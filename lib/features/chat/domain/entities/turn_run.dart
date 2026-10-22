import 'dart:convert';

import '../../../models/domain/entities/model_info.dart';
import '../../../presets/domain/preset.dart';
import '../../../settings/domain/entities/inference_settings.dart';

/// What produced one answer (roadmap CHAT-04): the settings in force for
/// that turn (preset applied), the model, what the engine actually ran
/// with, its measurements and the evidence it was given. Stored with the
/// assistant row so comparisons are fair and bug reports reproducible.
class TurnRun {
  final Map<String, dynamic> settings;
  final Map<String, dynamic> engine, metrics;
  final String modelId, modelName, presetId, presetName;
  final int sources;
  final DateTime at;

  /// Setting key → cascade layer that decided it (model profile, preset,
  /// chat, turn); keys the global settings decided are omitted.
  final Map<String, String> origins;

  /// Tool calls the model made for this answer, with their results.
  final List<Map<String, dynamic>> toolTrace;
  const TurnRun({
    required this.settings,
    required this.engine,
    required this.metrics,
    required this.modelId,
    required this.modelName,
    required this.presetId,
    required this.presetName,
    required this.sources,
    required this.at,
    this.origins = const {},
    this.toolTrace = const [],
  });

  /// Settings keys worth keeping: sampling, context, retrieval and
  /// reasoning — never the remote API key.
  static const _settingKeys = {
    'contextSize',
    'batchSize',
    'microBatchSize',
    'nGpuLayers',
    'backend',
    'cpuThreads',
    'batchThreads',
    'flashAttention',
    'temperature',
    'topP',
    'minP',
    'topK',
    'repetitionPenalty',
    'maxTokens',
    'kvCacheType',
    'promptCache',
    'thinkingModeEnabled',
    'thinkingBudgetTokens',
    'webMode',
    'maxSearchResults',
    'maxPagesRead',
    'searchQueryPlanning',
    'evidencePassages',
    'figureCheck',
    'thinkOnSearch',
    'searchAgain',
    'wikipediaLookup',
    'autoTitles',
    'remoteEnabled',
    'remoteModel',
    'memoryEnabled',
    'knowledgeCollection',
  };
  static const _metricKeys = {
    'backend',
    'tokensPerSecond',
    'firstTokenMs',
    'promptTokens',
    'cachedPromptTokens',
    'tokens',
    'thinkingTokens',
    'mediaTokens',
    'contextUsed',
    'contextSize',
    'peakRssMb',
    'trimmedMessages',
    'contextAudit',
    'evidenceAudit',
    'memoryUsed',
    'generationRounds',
    'operationTokens',
    'nativeLibrary',
    'nativeLibrarySkipped',
    'stages',
    'lifecycle',
    'finishReason',
    'draftModel',
    'draftProposed',
    'draftAccepted',
    'draftAcceptRate',
    'draftRounds',
    'draftDisabled',
    'draftReplays',
    'draftSpeedup',
    'adapters',
    'warning',
  };

  factory TurnRun.capture({
    required InferenceSettings settings,
    required Preset preset,
    required ModelInfo model,
    required Map<String, dynamic> metrics,
    required int sources,
    Map<String, String> origins = const {},
    List<Map<String, dynamic>> toolTrace = const [],
  }) {
    final all = settings.toJson();
    return TurnRun(
      settings: {
        for (final k in _settingKeys)
          if (all[k] != null) k: all[k],
      },
      engine: metrics['effectiveSettings'] is Map
          ? Map<String, dynamic>.from(metrics['effectiveSettings'] as Map)
          : const {},
      metrics: {
        for (final k in _metricKeys)
          if (metrics[k] != null) k: metrics[k],
      },
      modelId: model.id,
      modelName: model.displayName,
      presetId: preset.id,
      presetName: preset.name,
      sources: sources,
      at: DateTime.now().toUtc(),
      origins: {
        for (final e in origins.entries)
          if (e.value == 'model' ||
              e.value == 'preset' ||
              e.value == 'project' ||
              e.value == 'chat' ||
              e.value == 'turn')
            e.key: e.value,
      },
      toolTrace: toolTrace,
    );
  }

  /// What the figure and claim checks doubted in this answer, if anything.
  String? get warning => metrics['warning'] as String?;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'at': at.toIso8601String(),
    'model': {'id': modelId, 'name': modelName},
    'preset': {'id': presetId, 'name': presetName},
    'settings': settings,
    'engine': engine,
    'metrics': metrics,
    'sources': sources,
    if (origins.isNotEmpty) 'origins': origins,
    if (toolTrace.isNotEmpty) 'tools': toolTrace,
  };
  String encode() => jsonEncode(toJson());

  static TurnRun? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final j = jsonDecode(json) as Map<String, dynamic>;
      Map<String, dynamic> map(String k) =>
          j[k] is Map ? Map<String, dynamic>.from(j[k] as Map) : const {};
      final model = map('model'), preset = map('preset');
      return TurnRun(
        settings: map('settings'),
        engine: map('engine'),
        metrics: map('metrics'),
        modelId: model['id']?.toString() ?? '',
        modelName: model['name']?.toString() ?? '',
        presetId: preset['id']?.toString() ?? '',
        presetName: preset['name']?.toString() ?? '',
        sources: (j['sources'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime(1970),
        origins: {
          for (final e in map('origins').entries) e.key: e.value.toString(),
        },
        toolTrace: [
          for (final t in (j['tools'] as List?) ?? const [])
            if (t is Map) Map<String, dynamic>.from(t),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// A report a person can paste into a bug ticket or compare side by side.
  String plainText() {
    final b = StringBuffer()
      ..writeln('Model: $modelName ($modelId)')
      ..writeln('Preset: $presetName')
      ..writeln('When: ${at.toLocal()}')
      ..writeln('Sources given: $sources');
    void section(String title, Map<String, dynamic> m) {
      if (m.isEmpty) return;
      b.writeln();
      b.writeln('$title:');
      final keys = m.keys.toList()..sort();
      for (final k in keys) {
        final v = m[k];
        if (v is Map) {
          b.writeln(
            '  $k: ${v.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
          );
        } else if (v is num && v != v.roundToDouble()) {
          b.writeln('  $k: ${v.toStringAsFixed(2)}');
        } else {
          b.writeln('  $k: $v');
        }
      }
    }

    section('Settings', settings);
    if (origins.isNotEmpty) {
      b.writeln();
      b.writeln('Overridden by:');
      final keys = origins.keys.toList()..sort();
      for (final k in keys) {
        b.writeln('  $k: ${origins[k]}');
      }
    }
    section('Engine', engine);
    section('Measured', metrics);
    if (toolTrace.isNotEmpty) {
      b.writeln();
      b.writeln('Tools:');
      for (final t in toolTrace) {
        final call = t['call'] is Map ? t['call'] as Map : const {};
        b.writeln(
          '  ${call['name']}(${call['arguments']}) → ${t['ok'] == true ? 'ok' : 'error'} in ${t['elapsedMs']} ms',
        );
      }
    }
    return b.toString();
  }
}
