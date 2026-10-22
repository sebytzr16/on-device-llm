import 'entities/inference_settings.dart';
import 'setting_specs.dart';

/// One layer of the settings cascade (roadmap P1.4): defaults → device →
/// your settings → model profile → preset → chat → this turn. Each layer is
/// a partial JSON object of [InferenceSettings.toJson] keys.
class SettingsLayer {
  final String id;
  final String label;
  final Map<String, dynamic> values;
  const SettingsLayer(this.id, this.label, this.values);

  static const idDefault = 'default';
  static const idDevice = 'device';
  static const idRecommended = 'recommended';
  static const idGlobal = 'global';
  static const idModel = 'model';
  static const idPreset = 'preset';
  static const idChat = 'chat';
  static const idProject = 'project';
  static const idTurn = 'turn';
}

/// The effective settings plus, per key, which layer decided it.
class ResolvedSettings {
  final InferenceSettings effective;

  /// Setting key → layer id that supplied the effective value.
  final Map<String, String> origin;
  final List<SettingsLayer> layers;

  /// The value each layer requested for a key, in cascade order (only layers
  /// that mention it).
  final Map<String, List<(String, Object?)>> requested;
  const ResolvedSettings({
    required this.effective,
    required this.origin,
    required this.layers,
    required this.requested,
  });

  String originOf(String key) => origin[key] ?? SettingsLayer.idDefault;

  /// Keys whose effective value differs from the plain user settings, i.e.
  /// a model profile, preset, chat or turn changed something.
  List<String> get overriddenKeys => [
    for (final e in origin.entries)
      if (e.value != SettingsLayer.idDefault &&
          e.value != SettingsLayer.idDevice &&
          e.value != SettingsLayer.idRecommended &&
          e.value != SettingsLayer.idGlobal)
        e.key,
  ];

  /// Load-time keys overridden below the global layer: the next turn will
  /// reload the model if the loaded one used other values.
  List<String> get reloadKeys => [
    for (final k in overriddenKeys)
      if (InferenceSettings.loadTimeKeys.contains(k)) k,
  ];
}

class SettingsResolver {
  /// A registry edit changes inference keys only. Global privacy, appearance
  /// and credentials survive resetting or importing model-setting values.
  static InferenceSettings editGlobal(
    InferenceSettings current,
    Map<String, dynamic> values, {
    InferenceSettings? resetMissingTo,
  }) {
    final json = current.toJson();
    final reset = resetMissingTo?.toJson();
    if (reset != null) {
      for (final spec in SettingSpec.all) {
        json[spec.key] = reset[spec.key];
      }
    }
    json.addAll(sanitize(values));
    json['explicitOverrides'] = {
      if (reset == null) ...current.explicitOverrides,
      ...sanitize(values).keys,
    }.toList();
    return InferenceSettings.fromJson(
      json,
    ).copyWith(remoteApiKeys: current.remoteApiKeys);
  }

  /// Only keys the registry knows are honoured from profile/preset/chat/turn
  /// layers, so a stored override can never flip a privacy switch.
  static Map<String, dynamic> sanitize(Map<String, dynamic>? raw) {
    if (raw == null) return const {};
    final out = <String, dynamic>{};
    for (final e in raw.entries) {
      final spec = SettingSpec.byKey(e.key);
      if (spec == null) continue;
      final v = spec.coerce(e.value);
      if (v != null) out[e.key] = v;
    }
    return out;
  }

  static ResolvedSettings resolve({
    required InferenceSettings global,
    InferenceSettings? deviceDefaults,
    Map<String, dynamic> recommended = const {},
    Map<String, dynamic> recommendedThinking = const {},
    String recommendedLabel = "Model's recommended",
    Map<String, dynamic> model = const {},
    String modelLabel = 'Model profile',
    Map<String, dynamic> preset = const {},
    String presetLabel = 'Preset',
    Map<String, dynamic> project = const {},
    String projectLabel = 'Project',
    Map<String, dynamic> chat = const {},
    Map<String, dynamic> turn = const {},
  }) {
    const universal = InferenceSettings();
    final base = universal.toJson();
    final device = (deviceDefaults ?? universal).toJson();
    final globalJson = global.toJson();
    Map<String, dynamic> diff(Map<String, dynamic> a, Map<String, dynamic> b) =>
        {
          for (final e in b.entries)
            if (!_same(a[e.key], e.value)) e.key: e.value,
        };
    List<SettingsLayer> layersWith(Map<String, dynamic> rec) => [
      SettingsLayer(SettingsLayer.idDefault, 'App default', base),
      SettingsLayer(SettingsLayer.idDevice, 'This phone', diff(base, device)),
      // What the model's makers recommend (request 2026-10-04): above
      // the app's defaults, below anything the user chose.
      SettingsLayer(SettingsLayer.idRecommended, recommendedLabel, rec),
      SettingsLayer(SettingsLayer.idGlobal, 'Your settings', {
        ...diff(device, globalJson),
        for (final k in global.explicitOverrides)
          if (SettingSpec.byKey(k) != null) k: globalJson[k],
      }),
      SettingsLayer(SettingsLayer.idModel, modelLabel, sanitize(model)),
      SettingsLayer(SettingsLayer.idPreset, presetLabel, sanitize(preset)),
      SettingsLayer(SettingsLayer.idProject, projectLabel, sanitize(project)),
      SettingsLayer(SettingsLayer.idChat, 'This chat', sanitize(chat)),
      SettingsLayer(SettingsLayer.idTurn, 'This turn', sanitize(turn)),
    ];
    (
      Map<String, dynamic>,
      Map<String, String>,
      Map<String, List<(String, Object?)>>,
    )
    merge(List<SettingsLayer> layers) {
      final merged = Map<String, dynamic>.from(base);
      final origin = <String, String>{for (final k in base.keys) k: 'default'};
      final requested = <String, List<(String, Object?)>>{};
      for (final layer in layers.skip(1)) {
        for (final e in layer.values.entries) {
          if (!base.containsKey(e.key)) continue;
          merged[e.key] = e.value;
          origin[e.key] = layer.id;
          (requested[e.key] ??= []).add((layer.id, e.value));
        }
      }
      return (merged, origin, requested);
    }

    final rec = sanitize(recommended);
    var layers = layersWith(rec);
    var (merged, origin, requested) = merge(layers);
    // Thinking models recommend other sampling while they reason; whether
    // thinking is on is only known once every layer has spoken.
    final thinkingRec = sanitize(recommendedThinking);
    if (thinkingRec.isNotEmpty && merged['thinkingModeEnabled'] == true) {
      layers = layersWith({...rec, ...thinkingRec});
      (merged, origin, requested) = merge(layers);
    }
    // The API key is session-only and never part of the JSON round trip.
    final effective = InferenceSettings.fromJson(
      merged,
    ).copyWith(remoteApiKeys: global.remoteApiKeys);
    return ResolvedSettings(
      effective: effective,
      origin: origin,
      layers: layers,
      requested: requested,
    );
  }

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_same(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is num && b is num) return a == b;
    return a == b;
  }
}
