enum EngineDistribution { bundled, signedPack }

enum EngineHelperMode { dedicated, sharedChat, unavailable }

/// Stable IDs of the GGUF engines. llama.cpp stays the default everywhere;
/// ik_llama.cpp is optional and only runs from its installed engine pack.
const llamaCppEngineId = 'llama.cpp';
const ikLlamaEngineId = 'ik_llama';

/// Capabilities of the app's adapter. Individual model files can support less.
class EngineCapabilities {
  const EngineCapabilities({
    required this.streaming,
    required this.cancel,
    required this.vision,
    required this.tools,
    required this.samplingKeys,
    required this.loadKeys,
    required this.helpers,
    required this.hosting,
    this.ggufMetadata = false,
    this.visionFromRuntime = false,
    this.optimize = false,
    this.benchmark = false,
    this.grammar = false,
    this.visibleSettingKeys,
  });

  final bool streaming, cancel, vision, tools, hosting;
  final Set<String> samplingKeys, loadKeys;
  final EngineHelperMode helpers;
  final bool ggufMetadata, visionFromRuntime, optimize, grammar;

  /// The Benchmark dialog needs the llama.cpp planner; separate from
  /// [optimize] so an engine can offer one without the other.
  final bool benchmark;

  /// Engine-controlled settings exposed in profiles and the inspector. Null
  /// keeps the full set of standard controls. App-only controls are separate.
  final Set<String>? visibleSettingKeys;
}

class EngineDescriptor {
  const EngineDescriptor({
    required this.id,
    required this.displayName,
    required this.platforms,
    required this.extensions,
    required this.distribution,
    required this.capabilities,
  });

  final String id, displayName;
  final Set<String> platforms, extensions;
  final EngineDistribution distribution;
  final EngineCapabilities capabilities;

  bool claims(String path) {
    final name = path.toLowerCase();
    return extensions.any(name.endsWith);
  }
}

const llamaCppEngine = EngineDescriptor(
  id: llamaCppEngineId,
  displayName: 'llama.cpp',
  platforms: {'android', 'windows', 'linux', 'macos', 'ios'},
  extensions: {'.gguf'},
  distribution: EngineDistribution.bundled,
  capabilities: EngineCapabilities(
    streaming: true,
    cancel: true,
    vision: true,
    tools: true,
    helpers: EngineHelperMode.dedicated,
    hosting: true,
    ggufMetadata: true,
    optimize: true,
    benchmark: true,
    grammar: true,
    samplingKeys: {
      'temperature',
      'topP',
      'topK',
      'minP',
      'typicalP',
      'repetitionPenalty',
      'presencePenalty',
      'frequencyPenalty',
      'repeatLastN',
      'maxTokens',
      'seed',
      'stopSequences',
      'samplerOrder',
      'xtcProbability',
      'xtcThreshold',
      'topNSigma',
      'dryMultiplier',
      'dryBase',
      'dryAllowedLength',
      'dryPenaltyLastN',
      'logitBias',
    },
    loadKeys: llamaLoadSettingKeys,
  ),
);

const _liteRtSampling = {'temperature', 'topP', 'topK', 'maxTokens'};
const _liteRtLoad = {'liteRtBackend', 'visionEnabled'};

const liteRtLmEngine = EngineDescriptor(
  id: 'litert-lm',
  displayName: 'LiteRT-LM',
  platforms: {'android'},
  extensions: {'.litertlm'},
  distribution: EngineDistribution.bundled,
  capabilities: EngineCapabilities(
    streaming: true,
    cancel: true,
    vision: true,
    tools: false,
    helpers: EngineHelperMode.sharedChat,
    hosting: false,
    visionFromRuntime: true,
    samplingKeys: _liteRtSampling,
    loadKeys: _liteRtLoad,
    visibleSettingKeys: {
      ..._liteRtSampling,
      ..._liteRtLoad,
      'knowledgeCollection',
      'thinkingModeEnabled',
      'thinkingBudgetTokens',
    },
  ),
);

/// What the same Windows bridge can do against an ik_llama.cpp checkout: no
/// projector (the fork has no libmtmd), no MTP/DFlash draft, no expert-cache
/// planner and no llama.cpp optimizer or hosting hand-off. The samplers below
/// are the ones both engines share; XTC, DRY, top-n-sigma and logit bias stay
/// llama.cpp-only.
const _ikSampling = {
  'temperature',
  'topP',
  'topK',
  'minP',
  'typicalP',
  'repetitionPenalty',
  'presencePenalty',
  'frequencyPenalty',
  'repeatLastN',
  'maxTokens',
  'seed',
  'stopSequences',
  'samplerOrder',
};

/// Load keys the ik bridge honours. GPU placement (`nGpuLayers`, `mainGpu`,
/// `splitMode`, `vramReserveMb`) and the projector device are deliberately
/// absent: the ik loader is CPU-only and reports `gpuLayers: 0`, so offering
/// them would only store settings it ignores.
const _ikLoad = {
  'chatTemplate',
  'contextSize',
  'contextAuto',
  'batchSize',
  'microBatchSize',
  'backend',
  'cpuVariant',
  'cpuThreads',
  'batchThreads',
  'promptStoreMb',
  'useMmap',
  'useMlock',
  'offloadKv',
  'flashAttention',
  'kvCacheType',
  'vCacheType',
  'ropeScaling',
  'ropeFreqBase',
  'ropeFreqScale',
  'yarnExtFactor',
  'yarnAttnFactor',
  'yarnBetaFast',
  'yarnBetaSlow',
  'yarnOrigCtx',
};

const ikLlamaCppEngine = EngineDescriptor(
  id: ikLlamaEngineId,
  displayName: 'ik_llama.cpp',
  platforms: {'windows'},
  extensions: {'.gguf'},
  distribution: EngineDistribution.signedPack,
  capabilities: EngineCapabilities(
    streaming: true,
    cancel: true,
    vision: false,
    tools: true,
    helpers: EngineHelperMode.unavailable,
    hosting: false,
    ggufMetadata: true,
    grammar: true,
    samplingKeys: _ikSampling,
    loadKeys: _ikLoad,
    visibleSettingKeys: {
      ..._ikSampling,
      ..._ikLoad,
      // App-side controls that still apply: context handling, chatting with
      // tools, and reasoning control. Vision, draft/MTP, expert cache and
      // helper controls stay hidden, so their defaults are the unused ones.
      'keepTokens',
      'contextOverflow',
      'toolsEnabled',
      'toolChoice',
      'toolCalculator',
      'toolWeb',
      'toolDocuments',
      'toolMemory',
      'toolActions',
      'thinkingModeEnabled',
      'thinkingBudgetTokens',
    },
  ),
);

const bundledTextEngines = [llamaCppEngine, liteRtLmEngine];

/// Every engine the app knows, in priority order: llama.cpp is the format
/// default and an optional pack never wins a format on its own.
const knownTextEngines = [llamaCppEngine, liteRtLmEngine, ikLlamaCppEngine];

/// The descriptor with [id], or null for an unknown engine.
EngineDescriptor? engineById(String id) {
  for (final engine in knownTextEngines) {
    if (engine.id == id) return engine;
  }
  return null;
}

const llamaLoadSettingKeys = {
  'chatTemplate',
  'contextSize',
  'contextAuto',
  'imageMaxTokens',
  'batchSize',
  'microBatchSize',
  'nGpuLayers',
  'backend',
  'cpuVariant',
  'projectorDevice',
  'cpuThreads',
  'batchThreads',
  'vramReserveMb',
  'draftMinP',
  'promptStoreMb',
  'useMmap',
  'visionEnabled',
  'useMlock',
  'mainGpu',
  'splitMode',
  'offloadKv',
  'swaFull',
  'nCpuMoe',
  'moeCacheSizeMb',
  'moeCacheCpuShare',
  'expertsUsed',
  'draftGpuLayers',

  'flashAttention',
  'mtp',
  'speculationMode',
  'kvCacheType',
  'vCacheType',
  'ropeScaling',
  'ropeFreqBase',
  'ropeFreqScale',
  'yarnExtFactor',
  'yarnAttnFactor',
  'yarnBetaFast',
  'yarnBetaSlow',
  'yarnOrigCtx',
  'draftModelId',
  'draftMaxTokens',
};
