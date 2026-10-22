import 'dart:io';
import 'dart:math';

import '../../../../core/motion/motion_choice.dart';
import '../../../../inference/remote/remote_provider.dart';

export '../../../../core/motion/motion_choice.dart' show MotionChoice;

enum KvCacheType { fp16, q8_0, q4_0 }

/// Web retrieval policy (roadmap WEB-01). `auto` retrieves when the message
/// pastes a link, asks to search, or looks time-sensitive; `always` researches
/// every message.
enum WebMode { off, auto, always }

// Persisted by name; keep existing names stable. `qnn` is retained only so old
// preferences still parse — it is never offered and native load rejects it.
enum GpuBackend { auto, metal, vulkan, opencl, qnn, cpu }

/// Position-encoding stretch for contexts beyond what the model was trained
/// for. `model` keeps whatever the GGUF declares.
enum RopeScaling { model, none, linear, yarn }

/// Constrained decoding: free text, any JSON object, JSON matching a schema,
/// or a hand-written GBNF grammar.
enum ResponseFormat { text, json, jsonSchema, gbnf }

/// How the model uses the tools it is offered: it decides when to call
/// one, or it must call one before it may answer (first round only, so
/// the answer still comes).
enum ToolChoice { auto, required }

/// The Think pill's steps (review 2026-09-28): no reasoning, or
/// reasoning up to [budget] tokens on the phone. Remote providers get their
/// own effort setting of the same name instead of a token count.
enum ThinkingLevel {
  off(0),
  low(512),
  medium(2048),
  high(8192);

  final int budget;
  const ThinkingLevel(this.budget);

  /// The step after this one, as the pill cycles.
  ThinkingLevel get next => values[(index + 1) % values.length];

  /// The settings of this step, as chat overrides.
  Map<String, dynamic> get overrides => this == off
      ? const {'thinkingModeEnabled': false}
      : {'thinkingModeEnabled': true, 'thinkingBudgetTokens': budget};
}

/// Appearance (theme selection): follows the phone, or a fixed scheme.
enum ThemeChoice { system, dark, light }

/// The one saturated colour in the UI.
enum AccentChoice { amber, blue, green, rose, violet, teal }

class InferenceSettings {
  /// Bounds shared by the sliders, the JSON reader and the bridge clamps.
  static const minContext = 512, maxContext = 1 << 20;
  static const maxBatch = 4096;

  /// 64K since 2026-09-24 (request): hosted models answer that long;
  /// on the phone [responseReserve] keeps a large budget from starving the
  /// prompt.
  static const minResponseTokens = 64, maxResponseTokens = 65536;
  static const maxThinkingBudget = 65536;
  static const minResearchSeconds = 10, maxResearchSeconds = 180;
  static const minEvidencePassages = 2, maxEvidencePassages = 16;
  static const maxPagesReadLimit = 8;
  static const maxStopSequences = 8, maxStopSequenceLength = 64;
  static const maxToolRounds = 8;

  /// The response budget a prompt must leave free in a [window]-token
  /// context: [maxTokens], but at most half the window. The engines reserve
  /// the whole budget before the prompt is placed, so a 64K budget in an 8K
  /// phone context would otherwise leave no room for the question at all.
  int responseReserve(int window) => maxTokens.clamp(
    1,
    window < 2 * minResponseTokens ? max(1, window - 1) : window ~/ 2,
  );

  /// Where the thinking switch and budget fall among the Think pill's
  /// steps; an unlimited budget counts as High.
  ThinkingLevel get thinkingLevel {
    if (!thinkingModeEnabled) return ThinkingLevel.off;
    final b = thinkingBudgetTokens;
    if (b > 0 && b <= ThinkingLevel.low.budget) return ThinkingLevel.low;
    if (b > 0 && b <= ThinkingLevel.medium.budget) return ThinkingLevel.medium;
    return ThinkingLevel.high;
  }

  /// Most tokens a turn can generate: [maxTokens] counts the answer only
  /// (review 2026-09-28) and the reasoning budget comes on top.
  int get outputCeiling =>
      maxTokens + (thinkingModeEnabled ? thinkingBudgetTokens : 0);

  /// These settings with the answer and the reasoning together within
  /// [allowed] tokens (what a Goal's token budget has left); the reasoning
  /// takes at most half.
  InferenceSettings withinOutput(int allowed) {
    if (!thinkingModeEnabled) {
      return copyWith(maxTokens: max(1, min(maxTokens, allowed)));
    }
    final half = max(1, allowed ~/ 2);
    final think = thinkingBudgetTokens > 0
        ? min(thinkingBudgetTokens, half)
        : half;
    return copyWith(
      maxTokens: max(1, min(maxTokens, allowed - think)),
      thinkingBudgetTokens: think,
    );
  }

  static const maxDraftTokens = 16;

  /// llama.cpp's sampler names, in its default order. Every list the user
  /// saves is completed with the missing ones in this order.
  static const samplerNames = [
    'penalties',
    'dry',
    'top_n_sigma',
    'top_k',
    'typ_p',
    'top_p',
    'min_p',
    'xtc',
    'temperature',
  ];

  final int contextSize;

  /// Keys deliberately set by the tester, including values equal to defaults.
  final Set<String> explicitOverrides;
  final int imageMaxTokens;
  final int batchSize;

  /// Physical micro-batch (n_ubatch); 0 = auto. Never above the batch size.
  final int microBatchSize;
  final int nGpuLayers;
  final GpuBackend backend;
  final int cpuThreads;

  /// Threads for prompt evaluation; 0 = auto (every core). Decode keeps
  /// [cpuThreads]: on the S25+ 8 threads prefill fastest but decode slowest.
  final int batchThreads;
  final bool flashAttention;
  final double temperature;
  final double topP;
  final double minP;
  final int topK;
  final double repetitionPenalty;
  final int maxTokens;

  /// K cache precision. [vCacheType] null = same as K.
  final KvCacheType kvCacheType;
  final KvCacheType? vCacheType;

  /// Keep the evaluated conversation in the context between turns so only new
  /// text is prefilled (roadmap PERF-02). Off re-evaluates every turn.
  final bool promptCache;
  final bool thinkingModeEnabled;

  /// Reasoning tokens allowed before the block is closed for the model;
  /// 0 = unlimited.
  final int thinkingBudgetTokens;
  final WebMode webMode;
  final int maxSearchResults;

  /// Destination pages fetched and ranked per question.
  final int maxPagesRead;

  /// Let the model rewrite the question into search-engine queries first.
  final bool searchQueryPlanning;

  /// Web-research overhaul phase 2: for questions that would be searched,
  /// the model researches through its tools (search_web, read_url,
  /// find_in_page) instead of the fixed search-read-rank pipeline. Needs
  /// tool calling on with the web tools open; off until the phone
  /// comparison on the evaluation set favours it.
  final bool researchLoop;

  /// Wall-clock budget for all page reads of one question.
  final int researchTimeBudgetSeconds;

  /// Ranked passages handed to the model across all read pages.
  final int evidencePassages;

  /// After a grounded answer, flag numbers, versions and dates that appear in
  /// the answer but in none of the supplied passages.
  final bool figureCheck;

  /// No longer read: the Think chip decides for searched answers too
  /// (tester, 2026-10-08). Kept so saved settings and presets still load.
  final bool thinkOnSearch;

  /// When the pages read leave words of the question unanswered, one more
  /// search (the subject plus those words) and up to two more pages.
  final bool searchAgain;

  /// The Wikipedia article about the question's subject joins the search
  /// results (Wikipedia's free API; one request, no key).
  final bool wikipediaLookup;

  /// The model names a new chat after its first exchange (a few tokens);
  /// off keeps the first message as the title.
  final bool autoTitles;

  /// Remote servers and hosted APIs used instead of the local engine when
  /// enabled. Off by default: nothing leaves the phone unless the user
  /// configures a connection. [remoteProfiles] are the saved connections,
  /// [remoteProfileId] the active one.
  final bool remoteEnabled;
  final List<RemoteProfile> remoteProfiles;
  final String remoteProfileId;

  /// API keys by profile id. Session state: never serialised with the rest
  /// of the settings — the notifier keeps them in the platform keystore.
  final Map<String, String> remoteApiKeys;
  final bool remoteWebResearch;
  final bool remoteVision;
  final bool remoteDocuments;
  final int remoteIdleTimeoutSeconds;

  /// This request leaves sampling and answer length to the remote
  /// connection (its model's own defaults: Gemini's, LM Studio's loaded
  /// config…), decision 2026-10-18. Set per turn by the chat, never
  /// saved; any copy that sets [maxTokens], [temperature] or [topP] itself
  /// (a title, a judge, a Goal's budget) clears it, because such a call
  /// needs the app's own limits.
  final bool serverSampling;

  /// Learn durable facts about the user from chats and give them to the
  /// model as context (Settings > Memory). Off by default.
  final bool memoryEnabled;

  /// Battery saver: below [batterySaverLevel] % and not charging, or when
  /// the phone reports severe heat, local turns run lighter (no thinking,
  /// shorter answers, fewer pages and passages). Off by default.
  final bool batterySaver;
  final int batterySaverLevel;

  /// Voice (FX-01): keep dictation on the phone's own recognizer (fails if
  /// no offline language pack is installed) and read every answer aloud.
  final bool voiceOnDeviceOnly;
  final bool readAloud;

  /// On-device voice (2026-10-07): Kokoro speaks and Whisper listens when
  /// their files are installed; off keeps the system engines.
  /// [kokoroSid] is the chosen speaker (-1: the language's default).
  final bool naturalVoice;
  final int kokoroSid;

  /// Conversation: the answer plays on the phone-call path, whose echo
  /// canceller lets the user talk over it (it sounds like a call). Off:
  /// full-quality sound, the microphone rests while the answer plays.
  final bool talkOver;

  /// Conversation: the most sentences a spoken answer keeps (0: all of
  /// it). Lists are never cut (tester, 2026-10-19: the length is a choice).
  final int spokenSentences;

  /// The model Conversation loads (catalog id); '' is the fastest one,
  /// Qwen3.5 0.8B (tester, 2026-10-08: any downloaded model, Qwen default).
  final String conversationModelId;

  /// The on-device listening model: '' is Whisper base (in the voice
  /// pack), 'parakeet-v3' is Parakeet TDT 0.6B v3, an optional download
  /// that is more accurate in French and Spanish. Whisper is used while
  /// Parakeet is not downloaded.
  final String listeningModel;

  /// UI language (FX-15): '' follows the phone, else a supported code.
  final String localeCode;

  /// Where searches and news come from (a DuckDuckGo region such as
  /// `ca-en`); '' follows the app language and the phone's country. A phone
  /// set to English (United States) in Canada otherwise gets US news.
  final String searchRegion;

  /// The regions offered for [searchRegion].
  static const searchRegions = [
    'ca-en',
    'ca-fr',
    'us-en',
    'uk-en',
    'au-en',
    'nz-en',
    'ie-en',
    'in-en',
    'za-en',
    'fr-fr',
    'be-fr',
    'ch-fr',
    'de-de',
    'it-it',
    'es-es',
    'mx-es',
    'br-pt',
    'jp-jp',
    'wt-wt',
  ];

  /// Knowledge library collection consulted on every message (FX-02);
  /// '' = off.
  final String knowledgeCollection;
  final String systemPrompt;

  // ----- Sampling controls (ABI 6) -----

  /// 0 = a fresh random seed every answer; anything else reproduces.
  final int seed;

  /// Text that ends the answer when it appears; never shown.
  final List<String> stopSequences;

  /// OpenAI-style penalties: presence (once per token seen), frequency
  /// (per occurrence). 0 = off. [repeatLastN] tokens are considered.
  final double presencePenalty;
  final double frequencyPenalty;
  final int repeatLastN;

  /// Locally typical sampling; 1.0 = off.
  final double typicalP;

  /// Exclude-top-choices sampling: with [xtcProbability] the tokens above
  /// [xtcThreshold] except the least likely are removed. 0 = off.
  final double xtcProbability;
  final double xtcThreshold;

  /// Keep tokens within n standard deviations of the top logit; ≤0 = off.
  final double topNSigma;

  /// DRY repetition penalty; multiplier 0 = off.
  final double dryMultiplier;
  final double dryBase;
  final int dryAllowedLength;
  final int dryPenaltyLastN;

  /// Sampler chain order (names from [samplerNames]).
  final List<String> samplerOrder;

  // ----- RoPE / YaRN (load time) -----
  final RopeScaling ropeScaling;

  /// 0 = model value.
  final double ropeFreqBase;
  final double ropeFreqScale;

  /// YaRN parameters; ext -1 = model value, others 0 = model value.
  final double yarnExtFactor;
  final double yarnAttnFactor;
  final double yarnBetaFast;
  final double yarnBetaSlow;
  final int yarnOrigCtx;

  // ----- Structured output -----
  final ResponseFormat responseFormat;
  final String jsonSchema;
  final String grammar;

  // ----- Tools -----

  /// Let the model call typed tools (search_web, read_url, find_in_page,
  /// search_documents, calculator). Each tool stays behind its own host
  /// permission: web tools need web research on, document search needs a
  /// collection.
  final bool toolsEnabled;
  final ToolChoice toolChoice;
  final int toolMaxRounds;
  final bool toolCalculator;
  final bool toolWeb;
  final bool toolDocuments;

  // ----- Speculative decoding -----

  /// Catalog id of a smaller model with the same vocabulary that drafts
  /// tokens for the main one; '' = off.
  final String draftModelId;
  final int draftMaxTokens;

  // ----- Appearance -----
  final ThemeChoice themeChoice;
  final AccentChoice accent;

  /// Multiplies the phone's text size for the whole app (0.85 … 1.4).
  final double textScale;
  final bool compactBubbles;

  /// Springs, morphs and blur (Full), calmer motion (Subtle) or none.
  final MotionChoice motion;

  const InferenceSettings({
    this.explicitOverrides = const {},
    this.contextSize = 4096,
    this.imageMaxTokens = 1024,
    this.batchSize = 0,
    this.microBatchSize = 0,
    this.nGpuLayers = 999,
    this.backend = GpuBackend.auto,
    this.cpuThreads = 0,
    this.batchThreads = 0,
    this.flashAttention = true,
    this.temperature = 0.7,
    this.topP = 0.95,
    this.minP = 0.05,
    this.topK = 40,
    this.repetitionPenalty = 1.0,
    this.maxTokens = 1024,
    this.kvCacheType = KvCacheType.fp16,
    this.vCacheType,
    this.promptCache = true,
    this.thinkingModeEnabled = false,
    this.thinkingBudgetTokens = 0,
    this.webMode = WebMode.off,
    this.maxSearchResults = 5,
    this.maxPagesRead = 3,
    this.searchQueryPlanning = true,
    this.researchLoop = false,
    this.researchTimeBudgetSeconds = 25,
    this.evidencePassages = 6,
    this.figureCheck = true,
    this.thinkOnSearch = true,
    this.searchAgain = true,
    this.wikipediaLookup = true,
    this.autoTitles = true,
    this.remoteEnabled = false,
    this.remoteProfiles = const [],
    this.remoteProfileId = '',
    this.remoteApiKeys = const {},
    this.remoteWebResearch = true,
    this.remoteVision = true,
    this.remoteDocuments = true,
    this.serverSampling = false,
    this.remoteIdleTimeoutSeconds = 120,
    this.memoryEnabled = false,
    this.batterySaver = false,
    this.batterySaverLevel = 20,
    this.voiceOnDeviceOnly = true,
    this.readAloud = false,
    this.naturalVoice = true,
    this.kokoroSid = -1,
    this.talkOver = false,
    this.spokenSentences = 3,
    this.conversationModelId = '',
    this.listeningModel = '',
    this.localeCode = '',
    this.searchRegion = '',
    this.knowledgeCollection = '',
    this.systemPrompt = '',
    this.seed = 0,
    this.stopSequences = const [],
    this.presencePenalty = 0,
    this.frequencyPenalty = 0,
    this.repeatLastN = 64,
    this.typicalP = 1.0,
    this.xtcProbability = 0,
    this.xtcThreshold = 0.1,
    this.topNSigma = -1,
    this.dryMultiplier = 0,
    this.dryBase = 1.75,
    this.dryAllowedLength = 2,
    this.dryPenaltyLastN = -1,
    this.samplerOrder = samplerNames,
    this.ropeScaling = RopeScaling.model,
    this.ropeFreqBase = 0,
    this.ropeFreqScale = 0,
    this.yarnExtFactor = -1,
    this.yarnAttnFactor = 1,
    this.yarnBetaFast = 32,
    this.yarnBetaSlow = 1,
    this.yarnOrigCtx = 0,
    this.responseFormat = ResponseFormat.text,
    this.jsonSchema = '',
    this.grammar = '',
    this.toolsEnabled = false,
    this.toolChoice = ToolChoice.auto,
    this.toolMaxRounds = 4,
    this.toolCalculator = true,
    this.toolWeb = true,
    this.toolDocuments = true,
    this.draftModelId = '',
    this.draftMaxTokens = 6,
    this.themeChoice = ThemeChoice.dark,
    this.accent = AccentChoice.amber,
    this.textScale = 1.0,
    this.compactBubbles = false,
    this.motion = MotionChoice.full,
  });

  /// North Star §12 risk 1: shrink the default footprint on small phones.
  /// [totalRamGb] null means unknown; keep the universal defaults.
  factory InferenceSettings.forDevice(double? totalRamGb) {
    if (totalRamGb == null) return const InferenceSettings();
    // Phones with 10 GB or more start at 8K (request 2026-10-04:
    // ready at first launch, room for a few searched turns); the native
    // memory guard still trims it to what fits when a model loads.
    return InferenceSettings(
      contextSize: totalRamGb < 6
          ? 2048
          : totalRamGb < 10
          ? 4096
          : 8192,
      kvCacheType: totalRamGb < 8 ? KvCacheType.q8_0 : KvCacheType.fp16,
    );
  }

  /// Measured on Snapdragon 8 Elite with Qwen3.5 2B Q4_K_M: 2/4/6/8 threads
  /// decoded 26/32/36/21 tok/s, so 8-core phones get 6; smaller SoCs keep half
  /// their cores until measured (roadmap PERF-03 replaces this with a profile).
  /// With layers on a GPU the CPU threads only feed the driver and run what
  /// stayed behind, and they compete with the driver's own thread: 4 beat 6
  /// by a wide margin in the published Adreno 830 measurements (llama.cpp
  /// discussion #23736), so an explicit GPU backend gets 4 until our own
  /// sweep says otherwise. [backend] is the resolved one at load time.
  int get effectiveThreads {
    if (cpuThreads > 0) return cpuThreads;
    final cores = Platform.numberOfProcessors;
    final gpu =
        (backend == GpuBackend.opencl ||
            backend == GpuBackend.vulkan ||
            backend == GpuBackend.metal) &&
        nGpuLayers > 0;
    if (gpu) return cores >= 8 ? 4 : (cores ~/ 2).clamp(2, 4);
    return cores >= 8 ? 6 : (cores ~/ 2).clamp(2, 8);
  }

  /// Same sweep, 864-token prefill: 2/4/6/8 threads took 10.0/6.8/5.9/5.1 s,
  /// so prompt evaluation uses every core by default.
  int get effectiveBatchThreads => batchThreads > 0
      ? batchThreads
      : Platform.numberOfProcessors.clamp(effectiveThreads, 16);

  int get effectiveGpuLayers => backend == GpuBackend.cpu ? 0 : nGpuLayers;

  bool get webSearchEnabled => webMode != WebMode.off;

  /// The V cache type actually requested: explicit, else the K type.
  KvCacheType get effectiveVCacheType => vCacheType ?? kvCacheType;

  /// Constrained decoding is on for the answer.
  bool get structuredOutput => responseFormat != ResponseFormat.text;

  /// A usable remote configuration: enabled with an http(s) base URL.
  bool get usesRemote => remoteEnabled && remoteUri != null;

  /// The selected connection, or the first saved one when the selection is
  /// stale.
  RemoteProfile? get activeRemoteProfile =>
      remoteProfiles.where((p) => p.id == remoteProfileId).firstOrNull ??
      remoteProfiles.firstOrNull;

  RemoteProvider get remoteProvider =>
      activeRemoteProfile?.provider ?? RemoteProvider.custom;
  String get remoteBaseUrl => activeRemoteProfile?.baseUrl ?? '';
  String get remoteModel => activeRemoteProfile?.model ?? '';
  Uri? get remoteUri => activeRemoteProfile?.uri;

  /// The active profile's key (session-only, see [remoteApiKeys]).
  String get remoteApiKey => remoteApiKeys[activeRemoteProfile?.id ?? ''] ?? '';

  /// Measured on the S25+ with Qwen3.5 2B: batch/micro-batch 512 prefills
  /// ~10% faster on the CPU and ~12% faster on OpenCL than 256/128, with
  /// no decode change, so auto uses 512 for both.
  int get effectiveBatchSize => batchSize > 0 ? batchSize : 512;

  int get effectiveMicroBatchSize =>
      (microBatchSize > 0 ? microBatchSize : effectiveBatchSize).clamp(
        32,
        effectiveBatchSize,
      );

  /// Keys whose change only takes effect when the model is loaded again.
  static const maxProfiles = 32;

  /// Settings saved before connections existed had one URL and model; they
  /// become a single profile so nothing is lost on upgrade.
  static List<RemoteProfile> legacyRemoteProfile(Map<String, dynamic> j) {
    final url = j['remoteBaseUrl'];
    if (url is! String || url.trim().isEmpty) return const [];
    final profile = RemoteProfile(
      id: 'legacy',
      name: 'Remote server',
      providerId: RemoteProvider.guess(Uri.tryParse(url.trim())).id,
      baseUrl: url.substring(0, url.length.clamp(0, 2000)),
      model: j['remoteModel'] is String
          ? (j['remoteModel'] as String).substring(
              0,
              (j['remoteModel'] as String).length.clamp(0, 200),
            )
          : '',
    );
    return [profile];
  }

  static const loadTimeKeys = {
    'contextSize',
    'imageMaxTokens',
    'batchSize',
    'microBatchSize',
    'nGpuLayers',
    'backend',
    'cpuThreads',
    'batchThreads',
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
    'draftModelId',
    'draftMaxTokens',
  };

  InferenceSettings copyWith({
    Set<String>? explicitOverrides,
    int? contextSize,
    int? imageMaxTokens,
    int? batchSize,
    int? microBatchSize,
    int? nGpuLayers,
    GpuBackend? backend,
    int? cpuThreads,
    int? batchThreads,
    bool? flashAttention,
    double? temperature,
    double? topP,
    double? minP,
    int? topK,
    double? repetitionPenalty,
    int? maxTokens,
    KvCacheType? kvCacheType,
    KvCacheType? vCacheType,
    bool clearVCacheType = false,
    bool? promptCache,
    bool? thinkingModeEnabled,
    int? thinkingBudgetTokens,
    WebMode? webMode,
    int? maxSearchResults,
    int? maxPagesRead,
    bool? searchQueryPlanning,
    bool? researchLoop,
    int? researchTimeBudgetSeconds,
    int? evidencePassages,
    bool? figureCheck,
    bool? thinkOnSearch,
    bool? searchAgain,
    bool? wikipediaLookup,
    bool? autoTitles,
    bool? remoteEnabled,
    List<RemoteProfile>? remoteProfiles,
    String? remoteProfileId,
    Map<String, String>? remoteApiKeys,
    bool? remoteWebResearch,
    bool? remoteVision,
    bool? remoteDocuments,
    bool? serverSampling,
    int? remoteIdleTimeoutSeconds,
    bool? memoryEnabled,
    bool? batterySaver,
    int? batterySaverLevel,
    bool? voiceOnDeviceOnly,
    bool? readAloud,
    bool? naturalVoice,
    int? kokoroSid,
    bool? talkOver,
    int? spokenSentences,
    String? conversationModelId,
    String? listeningModel,
    String? localeCode,
    String? searchRegion,
    String? knowledgeCollection,
    String? systemPrompt,
    int? seed,
    List<String>? stopSequences,
    double? presencePenalty,
    double? frequencyPenalty,
    int? repeatLastN,
    double? typicalP,
    double? xtcProbability,
    double? xtcThreshold,
    double? topNSigma,
    double? dryMultiplier,
    double? dryBase,
    int? dryAllowedLength,
    int? dryPenaltyLastN,
    List<String>? samplerOrder,
    RopeScaling? ropeScaling,
    double? ropeFreqBase,
    double? ropeFreqScale,
    double? yarnExtFactor,
    double? yarnAttnFactor,
    double? yarnBetaFast,
    double? yarnBetaSlow,
    int? yarnOrigCtx,
    ResponseFormat? responseFormat,
    String? jsonSchema,
    String? grammar,
    bool? toolsEnabled,
    ToolChoice? toolChoice,
    int? toolMaxRounds,
    bool? toolCalculator,
    bool? toolWeb,
    bool? toolDocuments,
    String? draftModelId,
    int? draftMaxTokens,
    ThemeChoice? themeChoice,
    AccentChoice? accent,
    double? textScale,
    bool? compactBubbles,
    MotionChoice? motion,
  }) => InferenceSettings(
    explicitOverrides:
        explicitOverrides ??
        {
          ...this.explicitOverrides,
          if (contextSize != null) 'contextSize',
          if (imageMaxTokens != null) 'imageMaxTokens',
          if (batchSize != null) 'batchSize',
          if (microBatchSize != null) 'microBatchSize',
          if (nGpuLayers != null) 'nGpuLayers',
          if (backend != null) 'backend',
          if (cpuThreads != null) 'cpuThreads',
          if (batchThreads != null) 'batchThreads',
          if (flashAttention != null) 'flashAttention',
          if (temperature != null) 'temperature',
          if (topP != null) 'topP',
          if (minP != null) 'minP',
          if (topK != null) 'topK',
          if (repetitionPenalty != null) 'repetitionPenalty',
          if (maxTokens != null) 'maxTokens',
          if (kvCacheType != null) 'kvCacheType',
          if (vCacheType != null) 'vCacheType',
          if (promptCache != null) 'promptCache',
          if (thinkingModeEnabled != null) 'thinkingModeEnabled',
          if (thinkingBudgetTokens != null) 'thinkingBudgetTokens',
          if (webMode != null) 'webMode',
          if (maxSearchResults != null) 'maxSearchResults',
          if (maxPagesRead != null) 'maxPagesRead',
          if (searchQueryPlanning != null) 'searchQueryPlanning',
          if (researchLoop != null) 'researchLoop',
          if (researchTimeBudgetSeconds != null) 'researchTimeBudgetSeconds',
          if (evidencePassages != null) 'evidencePassages',
          if (figureCheck != null) 'figureCheck',
          if (thinkOnSearch != null) 'thinkOnSearch',
          if (searchAgain != null) 'searchAgain',
          if (wikipediaLookup != null) 'wikipediaLookup',
          if (autoTitles != null) 'autoTitles',
          if (remoteEnabled != null) 'remoteEnabled',
          if (remoteProfiles != null) 'remoteProfiles',
          if (remoteProfileId != null) 'remoteProfileId',
          if (remoteWebResearch != null) 'remoteWebResearch',
          if (remoteVision != null) 'remoteVision',
          if (remoteDocuments != null) 'remoteDocuments',
          if (remoteIdleTimeoutSeconds != null) 'remoteIdleTimeoutSeconds',
          if (memoryEnabled != null) 'memoryEnabled',
          if (batterySaver != null) 'batterySaver',
          if (batterySaverLevel != null) 'batterySaverLevel',
          if (voiceOnDeviceOnly != null) 'voiceOnDeviceOnly',
          if (readAloud != null) 'readAloud',
          if (naturalVoice != null) 'naturalVoice',
          if (kokoroSid != null) 'kokoroSid',
          if (talkOver != null) 'talkOver',
          if (spokenSentences != null) 'spokenSentences',
          if (conversationModelId != null) 'conversationModelId',
          if (listeningModel != null) 'listeningModel',
          if (localeCode != null) 'localeCode',
          if (searchRegion != null) 'searchRegion',
          if (knowledgeCollection != null) 'knowledgeCollection',
          if (systemPrompt != null) 'systemPrompt',
          if (seed != null) 'seed',
          if (stopSequences != null) 'stopSequences',
          if (presencePenalty != null) 'presencePenalty',
          if (frequencyPenalty != null) 'frequencyPenalty',
          if (repeatLastN != null) 'repeatLastN',
          if (typicalP != null) 'typicalP',
          if (xtcProbability != null) 'xtcProbability',
          if (xtcThreshold != null) 'xtcThreshold',
          if (topNSigma != null) 'topNSigma',
          if (dryMultiplier != null) 'dryMultiplier',
          if (dryBase != null) 'dryBase',
          if (dryAllowedLength != null) 'dryAllowedLength',
          if (dryPenaltyLastN != null) 'dryPenaltyLastN',
          if (samplerOrder != null) 'samplerOrder',
          if (ropeScaling != null) 'ropeScaling',
          if (ropeFreqBase != null) 'ropeFreqBase',
          if (ropeFreqScale != null) 'ropeFreqScale',
          if (yarnExtFactor != null) 'yarnExtFactor',
          if (yarnAttnFactor != null) 'yarnAttnFactor',
          if (yarnBetaFast != null) 'yarnBetaFast',
          if (yarnBetaSlow != null) 'yarnBetaSlow',
          if (yarnOrigCtx != null) 'yarnOrigCtx',
          if (responseFormat != null) 'responseFormat',
          if (jsonSchema != null) 'jsonSchema',
          if (grammar != null) 'grammar',
          if (toolsEnabled != null) 'toolsEnabled',
          if (toolChoice != null) 'toolChoice',
          if (toolMaxRounds != null) 'toolMaxRounds',
          if (toolCalculator != null) 'toolCalculator',
          if (toolWeb != null) 'toolWeb',
          if (toolDocuments != null) 'toolDocuments',
          if (draftModelId != null) 'draftModelId',
          if (draftMaxTokens != null) 'draftMaxTokens',
          if (themeChoice != null) 'themeChoice',
          if (accent != null) 'accent',
          if (textScale != null) 'textScale',
          if (compactBubbles != null) 'compactBubbles',
          if (motion != null) 'motion',
        },
    contextSize: contextSize ?? this.contextSize,
    imageMaxTokens: imageMaxTokens ?? this.imageMaxTokens,
    batchSize: batchSize ?? this.batchSize,
    microBatchSize: microBatchSize ?? this.microBatchSize,
    nGpuLayers: nGpuLayers ?? this.nGpuLayers,
    backend: backend ?? this.backend,
    cpuThreads: cpuThreads ?? this.cpuThreads,
    batchThreads: batchThreads ?? this.batchThreads,
    flashAttention: flashAttention ?? this.flashAttention,
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
    minP: minP ?? this.minP,
    topK: topK ?? this.topK,
    repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
    maxTokens: maxTokens ?? this.maxTokens,
    kvCacheType: kvCacheType ?? this.kvCacheType,
    vCacheType: clearVCacheType ? null : vCacheType ?? this.vCacheType,
    promptCache: promptCache ?? this.promptCache,
    thinkingModeEnabled: thinkingModeEnabled ?? this.thinkingModeEnabled,
    thinkingBudgetTokens: thinkingBudgetTokens ?? this.thinkingBudgetTokens,
    webMode: webMode ?? this.webMode,
    maxSearchResults: maxSearchResults ?? this.maxSearchResults,
    maxPagesRead: maxPagesRead ?? this.maxPagesRead,
    searchQueryPlanning: searchQueryPlanning ?? this.searchQueryPlanning,
    researchLoop: researchLoop ?? this.researchLoop,
    researchTimeBudgetSeconds:
        researchTimeBudgetSeconds ?? this.researchTimeBudgetSeconds,
    evidencePassages: evidencePassages ?? this.evidencePassages,
    figureCheck: figureCheck ?? this.figureCheck,
    thinkOnSearch: thinkOnSearch ?? this.thinkOnSearch,
    searchAgain: searchAgain ?? this.searchAgain,
    wikipediaLookup: wikipediaLookup ?? this.wikipediaLookup,
    autoTitles: autoTitles ?? this.autoTitles,
    remoteEnabled: remoteEnabled ?? this.remoteEnabled,
    remoteProfiles: remoteProfiles ?? this.remoteProfiles,
    remoteProfileId: remoteProfileId ?? this.remoteProfileId,
    remoteApiKeys: remoteApiKeys ?? this.remoteApiKeys,
    remoteWebResearch: remoteWebResearch ?? this.remoteWebResearch,
    remoteVision: remoteVision ?? this.remoteVision,
    remoteDocuments: remoteDocuments ?? this.remoteDocuments,
    serverSampling:
        serverSampling ??
        (maxTokens != null || temperature != null || topP != null
            ? false
            : this.serverSampling),
    remoteIdleTimeoutSeconds:
        remoteIdleTimeoutSeconds ?? this.remoteIdleTimeoutSeconds,
    memoryEnabled: memoryEnabled ?? this.memoryEnabled,
    batterySaver: batterySaver ?? this.batterySaver,
    batterySaverLevel: batterySaverLevel ?? this.batterySaverLevel,
    voiceOnDeviceOnly: voiceOnDeviceOnly ?? this.voiceOnDeviceOnly,
    readAloud: readAloud ?? this.readAloud,
    naturalVoice: naturalVoice ?? this.naturalVoice,
    kokoroSid: kokoroSid ?? this.kokoroSid,
    talkOver: talkOver ?? this.talkOver,
    spokenSentences: spokenSentences ?? this.spokenSentences,
    conversationModelId: conversationModelId ?? this.conversationModelId,
    listeningModel: listeningModel ?? this.listeningModel,
    localeCode: localeCode ?? this.localeCode,
    searchRegion: searchRegion ?? this.searchRegion,
    knowledgeCollection: knowledgeCollection ?? this.knowledgeCollection,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    seed: seed ?? this.seed,
    stopSequences: stopSequences ?? this.stopSequences,
    presencePenalty: presencePenalty ?? this.presencePenalty,
    frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
    repeatLastN: repeatLastN ?? this.repeatLastN,
    typicalP: typicalP ?? this.typicalP,
    xtcProbability: xtcProbability ?? this.xtcProbability,
    xtcThreshold: xtcThreshold ?? this.xtcThreshold,
    topNSigma: topNSigma ?? this.topNSigma,
    dryMultiplier: dryMultiplier ?? this.dryMultiplier,
    dryBase: dryBase ?? this.dryBase,
    dryAllowedLength: dryAllowedLength ?? this.dryAllowedLength,
    dryPenaltyLastN: dryPenaltyLastN ?? this.dryPenaltyLastN,
    samplerOrder: samplerOrder ?? this.samplerOrder,
    ropeScaling: ropeScaling ?? this.ropeScaling,
    ropeFreqBase: ropeFreqBase ?? this.ropeFreqBase,
    ropeFreqScale: ropeFreqScale ?? this.ropeFreqScale,
    yarnExtFactor: yarnExtFactor ?? this.yarnExtFactor,
    yarnAttnFactor: yarnAttnFactor ?? this.yarnAttnFactor,
    yarnBetaFast: yarnBetaFast ?? this.yarnBetaFast,
    yarnBetaSlow: yarnBetaSlow ?? this.yarnBetaSlow,
    yarnOrigCtx: yarnOrigCtx ?? this.yarnOrigCtx,
    responseFormat: responseFormat ?? this.responseFormat,
    jsonSchema: jsonSchema ?? this.jsonSchema,
    grammar: grammar ?? this.grammar,
    toolsEnabled: toolsEnabled ?? this.toolsEnabled,
    toolChoice: toolChoice ?? this.toolChoice,
    toolMaxRounds: toolMaxRounds ?? this.toolMaxRounds,
    toolCalculator: toolCalculator ?? this.toolCalculator,
    toolWeb: toolWeb ?? this.toolWeb,
    toolDocuments: toolDocuments ?? this.toolDocuments,
    draftModelId: draftModelId ?? this.draftModelId,
    draftMaxTokens: draftMaxTokens ?? this.draftMaxTokens,
    themeChoice: themeChoice ?? this.themeChoice,
    accent: accent ?? this.accent,
    textScale: textScale ?? this.textScale,
    compactBubbles: compactBubbles ?? this.compactBubbles,
    motion: motion ?? this.motion,
  );

  Map<String, dynamic> toJson() => {
    'explicitOverrides': explicitOverrides.toList()..sort(),
    'contextSize': contextSize,
    'imageMaxTokens': imageMaxTokens,
    'batchSize': batchSize,
    'microBatchSize': microBatchSize,
    'nGpuLayers': nGpuLayers,
    'backend': backend.name,
    'cpuThreads': cpuThreads,
    'batchThreads': batchThreads,
    'flashAttention': flashAttention,
    'temperature': temperature,
    'topP': topP,
    'minP': minP,
    'topK': topK,
    'repetitionPenalty': repetitionPenalty,
    'maxTokens': maxTokens,
    'kvCacheType': kvCacheType.name,
    'vCacheType': vCacheType?.name ?? '',
    'promptCache': promptCache,
    'thinkingModeEnabled': thinkingModeEnabled,
    'thinkingBudgetTokens': thinkingBudgetTokens,
    'webMode': webMode.name,
    'maxSearchResults': maxSearchResults,
    'maxPagesRead': maxPagesRead,
    'searchQueryPlanning': searchQueryPlanning,
    'researchLoop': researchLoop,
    'researchTimeBudgetSeconds': researchTimeBudgetSeconds,
    'evidencePassages': evidencePassages,
    'figureCheck': figureCheck,
    'thinkOnSearch': thinkOnSearch,
    'searchAgain': searchAgain,
    'wikipediaLookup': wikipediaLookup,
    'autoTitles': autoTitles,
    'remoteEnabled': remoteEnabled,
    'remoteProfiles': [for (final p in remoteProfiles) p.toJson()],
    'remoteProfileId': remoteProfileId,
    // Shown in turn records and exports; the active profile decides them.
    'remoteModel': remoteModel,
    'remoteProvider': remoteProvider.id,
    'remoteWebResearch': remoteWebResearch,
    'remoteVision': remoteVision,
    'remoteDocuments': remoteDocuments,
    'remoteIdleTimeoutSeconds': remoteIdleTimeoutSeconds,
    'memoryEnabled': memoryEnabled,
    'batterySaver': batterySaver,
    'batterySaverLevel': batterySaverLevel,
    'voiceOnDeviceOnly': voiceOnDeviceOnly,
    'readAloud': readAloud,
    'naturalVoice': naturalVoice,
    'kokoroSid': kokoroSid,
    'talkOver': talkOver,
    'spokenSentences': spokenSentences,
    'conversationModelId': conversationModelId,
    'listeningModel': listeningModel,
    'localeCode': localeCode,
    'searchRegion': searchRegion,
    'knowledgeCollection': knowledgeCollection,
    'systemPrompt': systemPrompt,
    'seed': seed,
    'stopSequences': stopSequences,
    'presencePenalty': presencePenalty,
    'frequencyPenalty': frequencyPenalty,
    'repeatLastN': repeatLastN,
    'typicalP': typicalP,
    'xtcProbability': xtcProbability,
    'xtcThreshold': xtcThreshold,
    'topNSigma': topNSigma,
    'dryMultiplier': dryMultiplier,
    'dryBase': dryBase,
    'dryAllowedLength': dryAllowedLength,
    'dryPenaltyLastN': dryPenaltyLastN,
    'samplerOrder': samplerOrder,
    'ropeScaling': ropeScaling.name,
    'ropeFreqBase': ropeFreqBase,
    'ropeFreqScale': ropeFreqScale,
    'yarnExtFactor': yarnExtFactor,
    'yarnAttnFactor': yarnAttnFactor,
    'yarnBetaFast': yarnBetaFast,
    'yarnBetaSlow': yarnBetaSlow,
    'yarnOrigCtx': yarnOrigCtx,
    // The bridge reads "text" | "json" | "json_schema" | "gbnf".
    'responseFormat': switch (responseFormat) {
      ResponseFormat.text => 'text',
      ResponseFormat.json => 'json',
      ResponseFormat.jsonSchema => 'json_schema',
      ResponseFormat.gbnf => 'gbnf',
    },
    'jsonSchema': jsonSchema,
    'grammar': grammar,
    'toolsEnabled': toolsEnabled,
    'toolChoice': toolChoice.name,
    'toolMaxRounds': toolMaxRounds,
    'toolCalculator': toolCalculator,
    'toolWeb': toolWeb,
    'toolDocuments': toolDocuments,
    'draftModelId': draftModelId,
    'draftMaxTokens': draftMaxTokens,
    'themeChoice': themeChoice.name,
    'accent': accent.name,
    'textScale': textScale,
    'compactBubbles': compactBubbles,
    'motion': motion.name,
  };

  static Set<String> _legacyExplicit(Map<String, dynamic> j) {
    final defaults = const InferenceSettings().toJson();
    bool same(Object? a, Object? b) => a is num && b is num
        ? a == b
        : a is List && b is List
        ? a.length == b.length &&
              [
                for (var i = 0; i < a.length; i++) same(a[i], b[i]),
              ].every((x) => x)
        : a == b;
    return {
      for (final e in j.entries.take(128))
        if (!defaults.containsKey(e.key) || !same(defaults[e.key], e.value))
          e.key,
    };
  }

  factory InferenceSettings.fromJson(Map<String, dynamic> j) {
    int integer(String key, int fallback, int low, int high) {
      final v = j[key];
      return v is num && v.isFinite ? v.toInt().clamp(low, high) : fallback;
    }

    double number(String key, double fallback, double low, double high) {
      final v = j[key];
      return v is num && v.isFinite ? v.toDouble().clamp(low, high) : fallback;
    }

    bool boolean(String key, bool fallback) =>
        j[key] is bool ? j[key] as bool : fallback;
    String text(String key, int limit) => j[key] is String
        ? (j[key] as String).substring(
            0,
            (j[key] as String).length.clamp(0, limit),
          )
        : '';
    List<String> strings(String key, {required int max, required int each}) =>
        j[key] is List
        ? [
            for (final e in (j[key] as List).take(max))
              if (e is String && e.isNotEmpty)
                e.substring(0, e.length.clamp(0, each)),
          ]
        : const [];
    T? named<T extends Enum>(List<T> values, String key) =>
        values.where((v) => v.name == j[key]).firstOrNull;
    final order = strings(
      'samplerOrder',
      max: 32,
      each: 16,
    ).where(samplerNames.contains).toSet().toList();
    final profiles = j['remoteProfiles'] is List
        ? [
            for (final raw in (j['remoteProfiles'] as List).take(maxProfiles))
              ?RemoteProfile.fromJson(raw),
          ]
        : legacyRemoteProfile(j);
    return InferenceSettings(
      explicitOverrides: j['explicitOverrides'] is List
          ? (j['explicitOverrides'] as List)
                .whereType<String>()
                .take(128)
                .toSet()
          // Older saves wrote every field and carry no provenance. The
          // build that wrote them treated only values unlike the defaults as
          // the user's, so the upgrade keeps exactly that behaviour.
          : _legacyExplicit(j),
      contextSize: integer('contextSize', 4096, minContext, maxContext),
      imageMaxTokens: integer('imageMaxTokens', 1024, 64, 16384),
      batchSize: integer('batchSize', 0, 0, maxBatch),
      microBatchSize: integer('microBatchSize', 0, 0, maxBatch),
      nGpuLayers: integer('nGpuLayers', 999, 0, 999),
      backend: named(GpuBackend.values, 'backend') ?? GpuBackend.auto,
      cpuThreads: integer('cpuThreads', 0, 0, 16),
      batchThreads: integer('batchThreads', 0, 0, 16),
      flashAttention: boolean('flashAttention', true),
      temperature: number('temperature', .7, 0, 2),
      topP: number('topP', .95, 0, 1),
      minP: number('minP', .05, 0, 1),
      topK: integer('topK', 40, 0, 200),
      repetitionPenalty: number('repetitionPenalty', 1.0, 1, 2),
      maxTokens: integer(
        'maxTokens',
        1024,
        minResponseTokens,
        maxResponseTokens,
      ),
      kvCacheType: named(KvCacheType.values, 'kvCacheType') ?? KvCacheType.fp16,
      vCacheType: named(KvCacheType.values, 'vCacheType'),
      promptCache: boolean('promptCache', true),
      thinkingModeEnabled: boolean('thinkingModeEnabled', false),
      thinkingBudgetTokens: integer(
        'thinkingBudgetTokens',
        0,
        0,
        maxThinkingBudget,
      ),
      // Older preferences stored a boolean; true meant today's `auto`.
      webMode:
          named(WebMode.values, 'webMode') ??
          (boolean('webSearchEnabled', false) ? WebMode.auto : WebMode.off),
      maxSearchResults: integer('maxSearchResults', 5, 1, 10),
      maxPagesRead: integer('maxPagesRead', 3, 1, maxPagesReadLimit),
      searchQueryPlanning: boolean('searchQueryPlanning', true),
      researchLoop: boolean('researchLoop', false),
      researchTimeBudgetSeconds: integer(
        'researchTimeBudgetSeconds',
        25,
        minResearchSeconds,
        maxResearchSeconds,
      ),
      evidencePassages: integer(
        'evidencePassages',
        6,
        minEvidencePassages,
        maxEvidencePassages,
      ),
      figureCheck: boolean('figureCheck', true),
      thinkOnSearch: boolean('thinkOnSearch', true),
      searchAgain: boolean('searchAgain', true),
      wikipediaLookup: boolean('wikipediaLookup', true),
      autoTitles: boolean('autoTitles', true),
      remoteEnabled: boolean('remoteEnabled', false),
      remoteProfiles: profiles,
      remoteProfileId: text('remoteProfileId', 64),
      remoteWebResearch: boolean('remoteWebResearch', true),
      remoteVision: boolean('remoteVision', true),
      remoteDocuments: boolean('remoteDocuments', true),
      remoteIdleTimeoutSeconds: integer(
        'remoteIdleTimeoutSeconds',
        120,
        15,
        600,
      ),
      memoryEnabled: boolean('memoryEnabled', false),
      batterySaver: boolean('batterySaver', false),
      batterySaverLevel: integer('batterySaverLevel', 20, 5, 80),
      voiceOnDeviceOnly: boolean('voiceOnDeviceOnly', true),
      readAloud: boolean('readAloud', false),
      naturalVoice: boolean('naturalVoice', true),
      kokoroSid: integer('kokoroSid', -1, -1, 53),
      talkOver: boolean('talkOver', false),
      spokenSentences: integer('spokenSentences', 3, 0, 20),
      conversationModelId: text('conversationModelId', 200),
      listeningModel: text('listeningModel', 32) == 'parakeet-v3'
          ? 'parakeet-v3'
          : '',
      localeCode: const {'en', 'fr', 'es'}.contains(text('localeCode', 8))
          ? text('localeCode', 8)
          : '',
      searchRegion: searchRegions.contains(text('searchRegion', 8))
          ? text('searchRegion', 8)
          : '',
      knowledgeCollection: text('knowledgeCollection', 200),
      systemPrompt: text('systemPrompt', 16000),
      seed: integer('seed', 0, 0, 0x7fffffff),
      stopSequences: strings(
        'stopSequences',
        max: maxStopSequences,
        each: maxStopSequenceLength,
      ),
      presencePenalty: number('presencePenalty', 0, -2, 2),
      frequencyPenalty: number('frequencyPenalty', 0, -2, 2),
      repeatLastN: integer('repeatLastN', 64, 0, 4096),
      typicalP: number('typicalP', 1, 0, 1),
      xtcProbability: number('xtcProbability', 0, 0, 1),
      xtcThreshold: number('xtcThreshold', .1, 0, .5),
      topNSigma: number('topNSigma', -1, -1, 10),
      dryMultiplier: number('dryMultiplier', 0, 0, 5),
      dryBase: number('dryBase', 1.75, 1, 4),
      dryAllowedLength: integer('dryAllowedLength', 2, 1, 32),
      dryPenaltyLastN: integer('dryPenaltyLastN', -1, -1, 8192),
      samplerOrder: order.isEmpty
          ? samplerNames
          : [...order, ...samplerNames.where((n) => !order.contains(n))],
      ropeScaling:
          named(RopeScaling.values, 'ropeScaling') ?? RopeScaling.model,
      ropeFreqBase: number('ropeFreqBase', 0, 0, 1e9),
      ropeFreqScale: number('ropeFreqScale', 0, 0, 1),
      yarnExtFactor: number('yarnExtFactor', -1, -1, 1),
      yarnAttnFactor: number('yarnAttnFactor', 1, 0, 8),
      yarnBetaFast: number('yarnBetaFast', 32, 0, 128),
      yarnBetaSlow: number('yarnBetaSlow', 1, 0, 128),
      yarnOrigCtx: integer('yarnOrigCtx', 0, 0, maxContext),
      responseFormat: switch (j['responseFormat']) {
        'json' => ResponseFormat.json,
        'json_schema' || 'jsonSchema' => ResponseFormat.jsonSchema,
        'gbnf' => ResponseFormat.gbnf,
        _ => ResponseFormat.text,
      },
      jsonSchema: text('jsonSchema', 32000),
      grammar: text('grammar', 32000),
      toolsEnabled: boolean('toolsEnabled', false),
      toolChoice: named(ToolChoice.values, 'toolChoice') ?? ToolChoice.auto,
      toolMaxRounds: integer('toolMaxRounds', 4, 1, maxToolRounds),
      toolCalculator: boolean('toolCalculator', true),
      toolWeb: boolean('toolWeb', true),
      toolDocuments: boolean('toolDocuments', true),
      draftModelId: text('draftModelId', 200),
      draftMaxTokens: integer('draftMaxTokens', 6, 1, maxDraftTokens),
      themeChoice: named(ThemeChoice.values, 'themeChoice') ?? ThemeChoice.dark,
      accent: named(AccentChoice.values, 'accent') ?? AccentChoice.amber,
      textScale: number('textScale', 1, .85, 1.4),
      compactBubbles: boolean('compactBubbles', false),
      motion: named(MotionChoice.values, 'motion') ?? MotionChoice.full,
    );
  }
}
