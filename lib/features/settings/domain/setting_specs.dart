import 'dart:convert';

import '../../../core/platform/cpu_cores.dart';
import '../../../core/platform/desktop_host.dart';
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
  bool get desktopOnly =>
      nativeKeys.contains(key) ||
      const {
        'cpuVariant',
        'vramReserveMb',
        'mtp',
        'speculationMode',
        'draftModelId',
        'chatTemplate',
      }.contains(key);
  bool get available => DesktopHost.active || !desktopOnly;

  /// Sampling belongs to each model. Answer length also has an app-wide
  /// default (owner 2026-11-08), overridden by model/preset/chat choices.
  bool get perModel => group == groupGeneration && key != 'maxTokens';

  static const groupGeneration = 'Generation';
  static const groupReasoning = 'Reasoning';
  static const groupWeb = 'Web research';
  static const groupTools = 'Tools';
  static const groupAgents = 'Agents';
  static const groupOutput = 'Structured output';
  static const groupContext = 'Context';
  static const groupHardware = 'Hardware';
  static const groupPrompt = 'Prompt';

  /// Settings offered by the current host, independent of stored profiles.
  static List<SettingSpec> get visible => [...all.where((s) => s.available)];

  static const nativeKeys = {
    'useMmap',
    'useMlock',
    'mainGpu',
    'splitMode',
    'offloadKv',
    'swaFull',
    'nCpuMoe',
    'moeCacheSizeMb',
    'moeCacheCpuShare',
    'expertsUsed',
    'projectorDevice',
    'draftGpuLayers',
    'keepTokens',
    'contextOverflow',
    'logitBias',
    'draftMinP',
    'promptStoreMb',
  };

  /// Inference overrides only; profiles cannot change privacy or credentials.
  static final all = <SettingSpec>[
    const SettingSpec(
      key: 'projectorDevice',
      label: 'Vision projector',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['auto', 'gpu', 'cpu'],
    ),
    const SettingSpec(
      key: 'visionEnabled',
      label: 'Vision (photos)',
      group: groupHardware,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'useMmap',
      label: 'Memory map model',
      group: groupHardware,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'useMlock',
      label: 'Lock model in memory',
      group: groupHardware,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'mainGpu',
      label: 'Main GPU index',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: 127,
    ),
    const SettingSpec(
      key: 'splitMode',
      label: 'GPU split mode',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['none', 'layer', 'row'],
    ),
    const SettingSpec(
      key: 'offloadKv',
      label: 'Offload KV operations',
      group: groupHardware,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'swaFull',
      label: 'Full sliding-window cache',
      group: groupHardware,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'nCpuMoe',
      label: 'CPU expert layers (-1 = auto)',
      group: groupHardware,
      kind: SettingKind.integer,
      min: -1,
      max: 4096,
    ),
    const SettingSpec(
      key: 'moeCacheSizeMb',
      label: 'MoE device cache (MiB, 0 = disabled)',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: 1 << 30,
    ),
    const SettingSpec(
      key: 'moeCacheCpuShare',
      label: 'MoE cache misses computed on CPU (0–1)',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    const SettingSpec(
      key: 'expertsUsed',
      label: 'Experts per token (-1 = model default)',
      group: groupHardware,
      kind: SettingKind.integer,
      min: -1,
      max: 256,
    ),
    const SettingSpec(
      key: 'keepTokens',
      label: 'Keep first tokens',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxContext,
    ),
    const SettingSpec(
      key: 'contextOverflow',
      label: 'Context overflow',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['trim', 'shift', 'stop'],
    ),
    const SettingSpec(
      key: 'logitBias',
      label: 'Token logit biases (JSON)',
      group: groupHardware,
      kind: SettingKind.text,
    ),

    const SettingSpec(
      key: 'batchSize',
      label: 'Batch size',
      group: groupContext,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxBatch,
    ),
    const SettingSpec(
      key: 'microBatchSize',
      label: 'Micro batch size',
      group: groupContext,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxBatch,
    ),
    const SettingSpec(
      key: 'maxSearchResults',
      label: 'Search results',
      group: groupWeb,
      kind: SettingKind.integer,
      min: 1,
      max: 10,
    ),
    const SettingSpec(
      key: 'searchQueryPlanning',
      label: 'Plan search queries',
      group: groupWeb,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'searchAgain',
      label: 'Search again when pages fall short',
      group: groupWeb,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'wikipediaLookup',
      label: 'Add the Wikipedia article',
      group: groupWeb,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'researchTimeBudgetSeconds',
      label: 'Research time (seconds)',
      group: groupWeb,
      kind: SettingKind.integer,
      min: InferenceSettings.minResearchSeconds,
      max: InferenceSettings.maxResearchSeconds,
    ),
    const SettingSpec(
      key: 'xtcProbability',
      label: 'XTC probability',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    const SettingSpec(
      key: 'xtcThreshold',
      label: 'XTC threshold',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 0.5,
    ),
    const SettingSpec(
      key: 'topNSigma',
      label: 'Top-n sigma (-1 = off)',
      group: groupGeneration,
      kind: SettingKind.number,
      min: -1,
      max: 10,
    ),
    const SettingSpec(
      key: 'dryMultiplier',
      label: 'DRY multiplier',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 5,
    ),
    const SettingSpec(
      key: 'dryBase',
      label: 'DRY base',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 1,
      max: 4,
    ),
    const SettingSpec(
      key: 'dryAllowedLength',
      label: 'DRY allowed length',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: 1,
      max: 32,
    ),
    const SettingSpec(
      key: 'dryPenaltyLastN',
      label: 'DRY penalty window (-1 = context)',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: -1,
      max: 8192,
    ),
    const SettingSpec(
      key: 'samplerOrder',
      label: 'Sampler order',
      group: groupGeneration,
      kind: SettingKind.stringList,
    ),
    const SettingSpec(
      key: 'ropeFreqBase',
      label: 'RoPE frequency base',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 1000000000,
    ),
    const SettingSpec(
      key: 'ropeFreqScale',
      label: 'RoPE frequency scale',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    const SettingSpec(
      key: 'yarnExtFactor',
      label: 'YaRN extension factor',
      group: groupHardware,
      kind: SettingKind.number,
      min: -1,
      max: 1,
    ),
    const SettingSpec(
      key: 'yarnAttnFactor',
      label: 'YaRN attention factor',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 8,
    ),
    const SettingSpec(
      key: 'yarnBetaFast',
      label: 'YaRN beta fast',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 128,
    ),
    const SettingSpec(
      key: 'yarnBetaSlow',
      label: 'YaRN beta slow',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 128,
    ),
    const SettingSpec(
      key: 'yarnOrigCtx',
      label: 'YaRN original context',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxContext,
    ),
    const SettingSpec(
      key: 'draftMaxTokens',
      label: 'Draft tokens',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 1,
      max: InferenceSettings.maxDraftTokens,
    ),
    const SettingSpec(
      key: 'draftGpuLayers',
      label: 'Draft model GPU layers (0 = CPU)',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: 999,
    ),
    const SettingSpec(
      key: 'draftMinP',
      label: 'Draft confidence floor',
      group: groupHardware,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    const SettingSpec(
      key: 'promptStoreMb',
      label: 'Saved prompts RAM (MB, -1 = auto)',
      group: groupContext,
      kind: SettingKind.integer,
      min: -1,
      max: 65536,
    ),
    const SettingSpec(
      key: 'imageMaxTokens',
      label: 'Photo token budget',
      group: groupContext,
      kind: SettingKind.integer,
      min: 64,
      max: 16384,
    ),
    const SettingSpec(
      key: 'systemPrompt',
      label: 'Custom instructions',
      group: groupPrompt,
      kind: SettingKind.text,
    ),
    const SettingSpec(
      key: 'temperature',
      label: 'Temperature',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 2,
    ),
    const SettingSpec(
      key: 'topP',
      label: 'Top-P',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    const SettingSpec(
      key: 'minP',
      label: 'Min-P',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    const SettingSpec(
      key: 'topK',
      label: 'Top-K',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: 0,
      max: 200,
    ),
    const SettingSpec(
      key: 'typicalP',
      label: 'Typical-P',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 0,
      max: 1,
    ),
    const SettingSpec(
      key: 'repetitionPenalty',
      label: 'Repetition penalty',
      group: groupGeneration,
      kind: SettingKind.number,
      min: 1,
      max: 2,
    ),
    const SettingSpec(
      key: 'presencePenalty',
      label: 'Presence penalty',
      group: groupGeneration,
      kind: SettingKind.number,
      min: -2,
      max: 2,
    ),
    const SettingSpec(
      key: 'frequencyPenalty',
      label: 'Frequency penalty',
      group: groupGeneration,
      kind: SettingKind.number,
      min: -2,
      max: 2,
    ),
    const SettingSpec(
      key: 'repeatLastN',
      label: 'Penalty window (tokens)',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: 0,
      max: 4096,
    ),
    const SettingSpec(
      key: 'maxTokens',
      label: 'Max tokens',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: InferenceSettings.minResponseTokens,
      max: InferenceSettings.maxResponseTokens,
    ),
    const SettingSpec(
      key: 'seed',
      label: 'Seed (0 = random)',
      group: groupGeneration,
      kind: SettingKind.integer,
      min: 0,
      max: 0x7fffffff,
    ),
    const SettingSpec(
      key: 'stopSequences',
      label: 'Stop sequences',
      group: groupGeneration,
      kind: SettingKind.stringList,
    ),
    const SettingSpec(
      key: 'thinkingModeEnabled',
      label: 'Thinking mode',
      group: groupReasoning,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'thinkingBudgetTokens',
      label: 'Thinking budget (0 = unlimited)',
      group: groupReasoning,
      kind: SettingKind.integer,
      min: 0,
      max: InferenceSettings.maxThinkingBudget,
    ),
    const SettingSpec(
      key: 'webMode',
      label: 'Web research',
      group: groupWeb,
      kind: SettingKind.choice,
      options: ['off', 'auto', 'always'],
    ),
    const SettingSpec(
      key: 'researchLoop',
      label: 'Model-driven research',
      group: groupWeb,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'maxPagesRead',
      label: 'Pages to read',
      group: groupWeb,
      kind: SettingKind.integer,
      min: 1,
      max: InferenceSettings.maxPagesReadLimit,
    ),
    const SettingSpec(
      key: 'evidencePassages',
      label: 'Passages given to the model',
      group: groupWeb,
      kind: SettingKind.integer,
      min: InferenceSettings.minEvidencePassages,
      max: InferenceSettings.maxEvidencePassages,
    ),
    const SettingSpec(
      key: 'knowledgeCollection',
      label: 'Knowledge collection',
      group: groupWeb,
      kind: SettingKind.text,
    ),
    const SettingSpec(
      key: 'toolsEnabled',
      label: 'Tool calling',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'toolChoice',
      label: 'Tool use',
      group: groupTools,
      kind: SettingKind.choice,
      options: ['auto', 'required'],
    ),
    const SettingSpec(
      key: 'toolCalculator',
      label: 'Calculator',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'toolWeb',
      label: 'Web tools',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'toolDocuments',
      label: 'Document tools',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'toolMemory',
      label: 'Memory recall',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'toolActions',
      label: 'Phone actions',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'toolHelper',
      label: 'Helper model',
      group: groupTools,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'helperModelId',
      label: 'Helper model id',
      group: groupTools,
      kind: SettingKind.text,
    ),

    const SettingSpec(
      key: 'agentMaxTokens',
      label: 'Max answer tokens',
      group: groupAgents,
      kind: SettingKind.integer,
      min: InferenceSettings.minResponseTokens,
      max: InferenceSettings.maxResponseTokens,
    ),
    const SettingSpec(
      key: 'agentTemperature',
      label: 'Temperature',
      group: groupAgents,
      kind: SettingKind.number,
      min: 0,
      max: 2,
    ),
    const SettingSpec(
      key: 'agentTopP',
      label: 'Top p (-1 = model)',
      group: groupAgents,
      kind: SettingKind.number,
      min: -1,
      max: 1,
    ),
    const SettingSpec(
      key: 'agentMinP',
      label: 'Min p (-1 = model)',
      group: groupAgents,
      kind: SettingKind.number,
      min: -1,
      max: 1,
    ),
    const SettingSpec(
      key: 'agentTopK',
      label: 'Top k (-1 = model)',
      group: groupAgents,
      kind: SettingKind.integer,
      min: -1,
      max: 1000,
    ),
    const SettingSpec(
      key: 'agentRepeatPenalty',
      label: 'Repeat penalty (-1 = model)',
      group: groupAgents,
      kind: SettingKind.number,
      min: -1,
      max: 2,
    ),
    const SettingSpec(
      key: 'agentContextSize',
      label: 'Context size',
      group: groupAgents,
      kind: SettingKind.integer,
      min: 512,
      max: 65536,
    ),
    const SettingSpec(
      key: 'agentMaxConcurrent',
      label: 'Max agents at once',
      group: groupAgents,
      kind: SettingKind.integer,
      min: 1,
      max: 4,
    ),
    const SettingSpec(
      key: 'agentTimeoutSeconds',
      label: 'Agent time limit (seconds)',
      group: groupAgents,
      kind: SettingKind.integer,
      min: 0,
      max: 86400,
      hint: '0 = unlimited',
    ),
    const SettingSpec(
      key: 'agentThinking',
      label: 'Thinking',
      group: groupAgents,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'agentToolRounds',
      label: 'Tool rounds',
      group: groupAgents,
      kind: SettingKind.integer,
      min: 1,
      max: 8,
    ),
    const SettingSpec(
      key: 'agentWebAccess',
      label: 'Agent web access',
      group: groupAgents,
      kind: SettingKind.choice,
      options: ['askOnce', 'alwaysAllow', 'never'],
    ),
    const SettingSpec(
      key: 'agentInstructions',
      label: 'Custom agent instructions',
      group: groupAgents,
      kind: SettingKind.text,
    ),
    const SettingSpec(
      key: 'agentInputBudget',
      label: 'Input budget',
      group: groupAgents,
      kind: SettingKind.integer,
      min: 256,
      max: 65536,
    ),
    const SettingSpec(
      key: 'toolMaxRounds',
      label: 'Tool rounds per answer',
      group: groupTools,
      kind: SettingKind.integer,
      min: 1,
      max: InferenceSettings.maxToolRounds,
    ),
    const SettingSpec(
      key: 'responseFormat',
      label: 'Response format',
      group: groupOutput,
      kind: SettingKind.choice,
      options: ['text', 'json', 'json_schema', 'gbnf'],
    ),
    const SettingSpec(
      key: 'jsonSchema',
      label: 'JSON schema',
      group: groupOutput,
      kind: SettingKind.text,
    ),
    const SettingSpec(
      key: 'grammar',
      label: 'GBNF grammar',
      group: groupOutput,
      kind: SettingKind.text,
    ),
    const SettingSpec(
      key: 'contextSize',
      label: 'Context size',
      group: groupContext,
      kind: SettingKind.integer,
      min: InferenceSettings.minContext,
      max: InferenceSettings.maxContext,
    ),
    const SettingSpec(
      key: 'promptCache',
      label: 'Keep conversation in context',
      group: groupContext,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'cpuVariant',
      label: 'CPU variant',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['auto', 'avx512', 'avx2', 'compat'],
    ),
    const SettingSpec(
      key: 'backend',
      label: 'Backend',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['auto', 'cpu', 'opencl', 'vulkan', 'metal', 'cuda'],
    ),
    const SettingSpec(
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
      // Follow the real core count instead of a fixed 16-thread ceiling.
      max: CpuCores.desktop,
    ),
    SettingSpec(
      key: 'batchThreads',
      label: 'CPU threads (prefill, 0 = auto)',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      // Follow the real core count instead of a fixed 16-thread ceiling.
      max: CpuCores.desktop,
    ),
    const SettingSpec(
      key: 'vramReserveMb',
      label: 'VRAM reserve (MB)',
      group: groupHardware,
      kind: SettingKind.integer,
      min: 0,
      max: 8192,
    ),
    const SettingSpec(
      key: 'flashAttention',
      label: 'Flash attention',
      group: groupHardware,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
      key: 'kvCacheType',
      label: 'K cache type',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['fp16', 'q8_0', 'q4_0', 'f8_e4m3'],
    ),
    const SettingSpec(
      key: 'vCacheType',
      label: 'V cache type (empty = same as K)',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['', 'fp16', 'q8_0', 'q4_0', 'f8_e4m3'],
    ),
    const SettingSpec(
      key: 'ropeScaling',
      label: 'RoPE scaling',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['model', 'none', 'linear', 'yarn'],
    ),
    const SettingSpec(
      key: 'chatTemplate',
      label: 'Prompt template',
      group: groupHardware,
      kind: SettingKind.text,
    ),
    const SettingSpec(
      key: 'speculationMode',
      label: 'Speculative decoding',
      group: groupHardware,
      kind: SettingKind.choice,
      options: ['auto', 'off', 'mtp', 'draft', 'dflash'],
    ),
    const SettingSpec(
      key: 'mtp',
      label: 'Multi-token prediction (MTP)',
      group: groupHardware,
      kind: SettingKind.boolean,
    ),
    const SettingSpec(
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
    if (key == 'logitBias') {
      try {
        final raw = value is String ? jsonDecode(value) : value;
        return raw is Map ? InferenceSettings.sanitizeLogitBias(raw) : null;
      } on FormatException {
        return null;
      }
    }
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
          'chatTemplate' => 128000,
          'draftModelId' => 1024,
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
