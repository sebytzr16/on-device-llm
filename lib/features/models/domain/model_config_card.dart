import 'dart:convert';

import '../../settings/domain/entities/inference_settings.dart';
import '../../settings/domain/setting_specs.dart';
import '../../settings/domain/settings_scope.dart';
import 'entities/model_info.dart';

/// Which model a configuration card was made for: enough to find the same
/// file on another phone (the SHA-256 first, then the catalog id, then the
/// file name) or to download it (the URL, when it came from the catalog).
class ModelRef {
  final String id, displayName, fileName;
  final String? sha256, downloadUrl;
  final String quantization;
  const ModelRef({
    required this.id,
    required this.displayName,
    required this.fileName,
    this.sha256,
    this.downloadUrl,
    this.quantization = '',
  });

  factory ModelRef.of(ModelInfo m) => ModelRef(
    id: m.id,
    displayName: m.displayName,
    fileName: m.fileName,
    sha256: m.sha256,
    downloadUrl: m.downloadUrl,
    quantization: m.quantization.name,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'fileName': fileName,
    if (sha256 != null) 'sha256': sha256,
    if (downloadUrl != null) 'downloadUrl': downloadUrl,
    if (quantization.isNotEmpty) 'quantization': quantization,
  };

  static String _s(Object? v, [int max = 300]) =>
      v is String ? (v.length > max ? v.substring(0, max) : v) : '';

  static ModelRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    final file = _s(raw['fileName']);
    if (id.isEmpty && file.isEmpty) return null;
    final sha = _s(raw['sha256'], 64).toLowerCase();
    final url = _s(raw['downloadUrl'], 2000);
    return ModelRef(
      id: id,
      displayName: _s(raw['displayName']).isEmpty
          ? (id.isEmpty ? file : id)
          : _s(raw['displayName']),
      fileName: file,
      sha256: RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null,
      // Only a https link is kept; the card never makes the app fetch
      // anything by itself, the user starts a download from Models.
      downloadUrl: url.startsWith('https://') ? url : null,
      quantization: _s(raw['quantization'], 40),
    );
  }

  /// The same model among [models], preferring an exact file hash.
  ModelInfo? matchIn(List<ModelInfo> models) {
    if (sha256 != null) {
      final bySha = models.where((m) => m.sha256?.toLowerCase() == sha256);
      if (bySha.isNotEmpty) return bySha.first;
    }
    return models.where((m) => m.id == id).firstOrNull ??
        models
            .where((m) => fileName.isNotEmpty && m.fileName == fileName)
            .firstOrNull;
  }
}

/// A shareable model configuration: the model it was tuned for and the
/// settings that make it (sampling, context, reasoning, output, tools,
/// system prompt). Web research and hardware settings are never part of a
/// card: a shared file must not turn on network access, and thread counts
/// or GPU layers belong to the phone, not to the model. API keys, remote
/// connections and headers are not settings and cannot appear.
class ModelConfigCard {
  static const kind = 'model-config';
  static const version = 1;
  static const fileExtension = '.odllm.json';
  static const excludedGroups = {
    SettingSpec.groupWeb,
    SettingSpec.groupHardware,
  };

  /// Kept out as well: the context size decides how much memory a load
  /// takes, which belongs to the phone like the hardware group (a 32K card
  /// imported on a smaller phone could fail to load the model).
  static const excludedKeys = {'contextSize'};

  final String name;
  final ModelRef model;
  final Map<String, dynamic> settings;

  /// Keys a received card carried that were left out (unknown, invalid, or
  /// in an excluded group), shown in the import preview.
  final List<String> dropped;
  const ModelConfigCard({
    required this.name,
    required this.model,
    required this.settings,
    this.dropped = const [],
  });

  /// What [model] runs with here: the user's changes from the app defaults
  /// with the model's own profile on top, in shareable groups only.
  factory ModelConfigCard.from({
    required ModelInfo model,
    required InferenceSettings global,
    Map<String, dynamic> profile = const {},
    String? name,
  }) {
    final defaults = const InferenceSettings().toJson();
    final changed = {
      for (final e in global.toJson().entries)
        if (jsonEncode(defaults[e.key]) != jsonEncode(e.value)) e.key: e.value,
    };
    final (settings, _) = _shareable({
      ...SettingsResolver.sanitize(changed),
      ...SettingsResolver.sanitize(profile),
    });
    return ModelConfigCard(
      name: name ?? '${model.displayName} configuration',
      model: ModelRef.of(model),
      settings: settings,
    );
  }

  static (Map<String, dynamic>, List<String>) _shareable(
    Map<String, dynamic> raw,
  ) {
    final clean = SettingsResolver.sanitize(raw);
    final out = <String, dynamic>{};
    final dropped = <String>[];
    for (final key in raw.keys) {
      final spec = SettingSpec.byKey(key);
      if (spec == null ||
          !clean.containsKey(key) ||
          excludedGroups.contains(spec.group) ||
          excludedKeys.contains(key)) {
        dropped.add(key);
      } else {
        out[key] = clean[key];
      }
    }
    return (out, dropped);
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'ondevice_llm': kind,
    'version': version,
    'name': name,
    'model': model.toJson(),
    'settings': settings,
  });

  /// The card in [text], or null when it is not one (any other JSON, a
  /// newer format, no model).
  static ModelConfigCard? decode(String text) {
    Object? raw;
    try {
      raw = jsonDecode(text.trim());
    } on FormatException {
      return null;
    }
    if (raw is! Map || raw['ondevice_llm'] != kind) return null;
    final v = raw['version'];
    if (v is! int || v < 1 || v > version) return null;
    final model = ModelRef.fromJson(raw['model']);
    if (model == null) return null;
    final settings = raw['settings'] is Map
        ? Map<String, dynamic>.from(raw['settings'] as Map)
        : <String, dynamic>{};
    final (kept, dropped) = _shareable(settings);
    final name = raw['name'] is String ? (raw['name'] as String).trim() : '';
    return ModelConfigCard(
      name: name.isEmpty
          ? '${model.displayName} configuration'
          : name.substring(0, name.length.clamp(0, 120)),
      model: model,
      settings: kept,
      dropped: dropped,
    );
  }

  /// "Temperature: 0.2" lines for the preview, in registry order. Values
  /// are shown whole (a received system prompt must not hide instructions
  /// past a cut), up to [maxShown] characters with the rest counted.
  List<(String, String)> describe([String Function(SettingSpec)? labelOf]) => [
    for (final spec in SettingSpec.all)
      if (settings.containsKey(spec.key))
        (labelOf?.call(spec) ?? spec.label, _value(settings[spec.key])),
  ];

  static const maxShown = 4000;

  static String _value(Object? v) {
    final s = v is String ? v : jsonEncode(v);
    return s.length > maxShown
        ? '${s.substring(0, maxShown)}… (+${s.length - maxShown} characters)'
        : s;
  }
}
