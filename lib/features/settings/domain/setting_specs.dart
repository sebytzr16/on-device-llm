import 'entities/inference_settings.dart';

/// How a setting is edited and displayed when a scope overrides it.
enum SettingKind { integer, number, boolean, choice, text, stringList }

/// One overridable setting: its JSON key (as in [InferenceSettings.toJson]),
/// how it is edited, its bounds, and whether changing it needs a reload.
class SettingSpec {
  final String key;
  final String label;
  final String group;
  final SettingKind kind;
  final num? min, max;

  /// Choice values (enum names) for [SettingKind.choice].
  final List<String> options;
  final String hint;
  const SettingSpec({
    required this.key,
    required this.label,
    required this.group,
    required this.kind,
    this.min,
    this.max,
    this.options = const [],
    this.hint = '',
  });

  bool get reloadRequired => InferenceSettings.loadTimeKeys.contains(key);

  static const groupGeneration = 'Generation';
  static const groupReasoning = 'Reasoning';
  static const groupWeb = 'Web research';
  static const groupTools = 'Tools';
  static const groupOutput = 'Structured output';
  static const groupContext = 'Context';
  static const groupHardware = 'Hardware';
  static const groupPrompt = 'Prompt';

  /// The settings a profile, preset or chat may override. Appearance,
  /// remote-server credentials, voice and privacy switches are deliberately
  /// not here: a model or a chat must never flip them.
  static const all = <SettingSpec>[
    SettingSpec(
      key: 'batchSize',
      label: 'Batch size',
      group: groupContext,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxBatch,
    ),
    SettingSpec(
      key: 'microBatchSize',
      label: 'Micro batch size',
      group: groupContext,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxBatch,
    ),
    SettingSpec(
      key: 'maxSearchResults',
      label: 'Search results',
      group: groupWeb,
      kind: SettingKind.integer,
      min: 1,
      max: 10,
    ),
    SettingSpec(
      key: 'searchQueryPlanning',
      label: 'Plan search queries',
      group: groupWeb,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'searchAgain',
      label: 'Search again when pages fall short',
      group: groupWeb,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'wikipediaLookup',
      label: 'Add the Wikipedia article',
      group: groupWeb,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'researchTimeBudgetSeconds',
      label: 'Research time (seconds)',
      group: groupWeb,
      kind: SettingKind.integer,
      min: InferenceSettings.minResearchSeconds,
      max: InferenceSettings.maxResearchSeconds,
    ),
    SettingSpec(
      key: 'xtcProbability',
      label: 'XTC probability',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    SettingSpec(
      key: 'xtcThreshold',
      label: 'XTC threshold',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 0.5,
    ),
    SettingSpec(
      key: 'topNSigma',
      label: 'Top-n sigma (-1 = off)',
      group: groupGeneration,
      kind: SettingKind.number,
      min: -1,
      max: 10,
    ),
    SettingSpec(
      key: 'dryMultiplier',
      label: 'DRY multiplier',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 5,
    ),
    SettingSpec(
      key: 'dryBase',
      label: 'DRY base',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 1,
      max: 4,
    ),
    SettingSpec(
      key: 'dryAllowedLength',
      label: 'DRY allowed length',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: 1,
      max: 32,
    ),
    SettingSpec(
      key: 'dryPenaltyLastN',
      label: 'DRY penalty window (-1 = context)',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: -1,
      max: 8192,
    ),
    SettingSpec(
      key: 'samplerOrder',
      label: 'Sampler order',
      group: groupGeneration,
      kind: SettingKind.stringList,
    ),
    SettingSpec(
      key: 'ropeFreqBase',
      label: 'RoPE frequency base',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 1000000000,
    ),
    SettingSpec(
      key: 'ropeFreqScale',
      label: 'RoPE frequency scale',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    SettingSpec(
      key: 'yarnExtFactor',
      label: 'YaRN extension factor',
      group: groupHardware,
      kind: SettingKind.number,
      min: -1,
      max: 1,
    ),
    SettingSpec(
      key: 'yarnAttnFactor',
      label: 'YaRN attention factor',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 8,
    ),
    SettingSpec(
      key: 'yarnBetaFast',
      label: 'YaRN beta fast',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 128,
    ),
    SettingSpec(
      key: 'yarnBetaSlow',
      label: 'YaRN beta slow',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 128,
    ),
    SettingSpec(
      key: 'yarnOrigCtx',
      label: 'YaRN original context',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxContext,
    ),
    SettingSpec(
      key: 'draftMaxTokens',
      label: 'Draft tokens',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 1,
      max: InferenceSettings.maxDraftTokens,
    ),
    SettingSpec(
      key: 'imageMaxTokens',
      label: 'Photo token budget',
      group: groupContext,
      kind: SettingKind.integer,
      min: 64,
      max: 16384,
    ),
    SettingSpec(
      key: 'systemPrompt',
      label: 'Custom instructions',
      group: groupPrompt,
      kind: SettingKind.text,
    ),
    SettingSpec(
      key: 'temperature',
      label: 'Temperature',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 2,
    ),
    SettingSpec(
      key: 'topP',
      label: 'Top-P',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    SettingSpec(
      key: 'minP',
      label: 'Min-P',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    SettingSpec(
      key: 'topK',
      label: 'Top-K',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: 0,
      max: 200,
    ),
    SettingSpec(
      key: 'typicalP',
      label: 'Typical-P',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    SettingSpec(
      key: 'repetitionPenalty',
      label: 'Repetition penalty',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 1,
      max: 2,
    ),
    SettingSpec(
      key: 'presencePenalty',
      label: 'Presence penalty',
      group: groupGeneration,
      kind: SettingKind.number,
      min: -2,
      max: 2,
    ),
    SettingSpec(
      key: 'frequencyPenalty',
      label: 'Frequency penalty',
      group: groupGeneration,
      kind: SettingKind.number,
      min: -2,
      max: 2,
    ),
    SettingSpec(
      key: 'repeatLastN',
      label: 'Penalty window (tokens)',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: 0,
      max: 4096,
    ),
    SettingSpec(
      key: 'maxTokens',
      label: 'Max tokens',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: InferenceSettings.minResponseTokens,
      max: InferenceSettings.maxResponseTokens,
    ),
    SettingSpec(
      key: 'seed',
      label: 'Seed (0 = random)',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: 0,
      max: 0x7fffffff,
    ),
    SettingSpec(
      key: 'stopSequences',
      label: 'Stop sequences',
      group: groupGeneration,
      kind: SettingKind.stringList,
    ),
    SettingSpec(
      key: 'thinkingModeEnabled',
      label: 'Thinking mode',
      group: groupReasoning,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'thinkingBudgetTokens',
      label: 'Thinking budget (0 = unlimited)',
      group: groupReasoning,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxThinkingBudget,
    ),
    SettingSpec(
      key: 'webMode',
      label: 'Web research',
      group: groupWeb,
      kind: SettingKind.choice,
      options: ['off', 'auto', 'always'],
    ),
    SettingSpec(
      key: 'researchLoop',
      label: 'Model-driven research',
      group: groupWeb,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'maxPagesRead',
      label: 'Pages to read',
      group: groupWeb,
      kind: SettingKind.integer,
      min: 1,
      max: InferenceSettings.maxPagesReadLimit,
    ),
    SettingSpec(
      key: 'evidencePassages',
      label: 'Passages given to the model',
      group: groupWeb,
      kind: SettingKind.integer,
      min: InferenceSettings.minEvidencePassages,
      max: InferenceSettings.maxEvidencePassages,
    ),
    SettingSpec(
      key: 'knowledgeCollection',
      label: 'Knowledge collection',
      group: groupWeb,
      kind: SettingKind.text,
    ),
    SettingSpec(
      key: 'toolsEnabled',
      label: 'Tool calling',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'toolChoice',
      label: 'Tool use',
      group: groupTools,
      kind: SettingKind.choice,
      options: ['auto', 'required'],
    ),
    SettingSpec(
      key: 'toolCalculator',
      label: 'Calculator',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'toolWeb',
      label: 'Web tools',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'toolDocuments',
      label: 'Document tools',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'toolMaxRounds',
      label: 'Tool rounds per answer',
      group: groupTools,
      kind: SettingKind.integer,
      min: 1,
      max: InferenceSettings.maxToolRounds,
    ),
    SettingSpec(
      key: 'responseFormat',
      label: 'Response format',
      group: groupOutput,
      kind: SettingKind.choice,
      options: ['text', 'json', 'json_schema', 'gbnf'],
    ),
    SettingSpec(
      key: 'jsonSchema',
      label: 'JSON schema',
      group: groupOutput,
      kind: SettingKind.text,
    ),
    SettingSpec(
      key: 'grammar',
      label: 'GBNF grammar',
      group: groupOutput,
      kind: SettingKind.text,
    ),
    SettingSpec(
      key: 'contextSize',
      label: 'Context size',
      group: groupContext,
      kind: SettingKind.integer,
      min: InferenceSettings.minContext,
      max: InferenceSettings.maxContext,
    ),
    SettingSpec(
      key: 'promptCache',
      label: 'Keep conversation in context',
      group: groupContext,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'backend',
      label: 'Backend',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['auto', 'cpu', 'opencl', 'vulkan', 'metal'],
    ),
    SettingSpec(
      key: 'nGpuLayers',
      label: 'GPU layers',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: 999,
    ),
    SettingSpec(
      key: 'cpuThreads',
      label: 'CPU threads (decode, 0 = auto)',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: 16,
    ),
    SettingSpec(
      key: 'batchThreads',
      label: 'CPU threads (prefill, 0 = auto)',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: 16,
    ),
    SettingSpec(
      key: 'flashAttention',
      label: 'Flash attention',
      group: groupHardware,
      kind: SettingKind.boolean,
    ),
    SettingSpec(
      key: 'kvCacheType',
      label: 'K cache type',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['fp16', 'q8_0', 'q4_0'],
    ),
    SettingSpec(
      key: 'vCacheType',
      label: 'V cache type (empty = same as K)',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['', 'fp16', 'q8_0', 'q4_0'],
    ),
    SettingSpec(
      key: 'ropeScaling',
      label: 'RoPE scaling',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['model', 'none', 'linear', 'yarn'],
    ),
    SettingSpec(
      key: 'draftModelId',
      label: 'Draft model (speculative decoding)',
      group: groupHardware,
      kind: SettingKind.text,
    ),
  ];

  static SettingSpec? byKey(String key) =>
      all.where((s) => s.key == key).firstOrNull;

  /// Group names in declaration order.
  static List<String> get groups {
    final out = <String>[];
    for (final s in all) {
      if (!out.contains(s.group)) out.add(s.group);
    }
    return out;
  }

  /// Human display of a JSON value for this setting.
  String display(Object? value) {
    if (value == null) return '—';
    if (value is List) return value.isEmpty ? 'none' : value.join(' · ');
    if (value is double) {
      return value == value.roundToDouble() && kind == SettingKind.integer
          ? value.toInt().toString()
          : value.toStringAsFixed(2);
    }
    if (value is String && value.isEmpty) {
      return kind == SettingKind.choice ? 'same as K' : 'none';
    }
    if (value is String && value.length > 60) {
      return '${value.substring(0, 57)}…';
    }
    return value.toString();
  }

  /// Coerces a raw override into the value shape [InferenceSettings.fromJson]
  /// expects; null means "not a valid override, drop it".
  Object? coerce(Object? value) {
    switch (kind) {
      case SettingKind.integer:
        if (value is num && !value.isFinite) return null;
        final v = value is num ? value.toInt() : int.tryParse('$value');
        if (v == null) return null;
        return v.clamp(min?.toInt() ?? v, max?.toInt() ?? v);
      case SettingKind.number:
        final v = value is num ? value.toDouble() : double.tryParse('$value');
        if (v == null || !v.isFinite) return null;
        return v.clamp(min?.toDouble() ?? v, max?.toDouble() ?? v);
      case SettingKind.boolean:
        return value is bool ? value : null;
      case SettingKind.choice:
        return value is String && options.contains(value) ? value : null;
      case SettingKind.text:
        if (value is! String) return null;
        final limit = switch (key) {
          'systemPrompt' => 16000,
          'jsonSchema' || 'grammar' => 32000,
          _ => 200,
        };
        return value.substring(0, value.length.clamp(0, limit));
      case SettingKind.stringList:
        if (value is! List) return null;
        if (key == 'samplerOrder') {
          return {
            for (final e in value)
              if (e is String && InferenceSettings.samplerNames.contains(e)) e,
          }.toList();
        }
        return [
          for (final e in value.whereType<String>().take(
            InferenceSettings.maxStopSequences,
          ))
            e.substring(
              0,
              e.length.clamp(0, InferenceSettings.maxStopSequenceLength),
            ),
        ];
    }
  }
}
