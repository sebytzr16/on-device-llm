import 'dart:async';
import '../../core/utils/inference_admission.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../../core/errors/exceptions.dart';
import '../../core/platform/desktop_host.dart';
import '../../features/settings/domain/entities/inference_settings.dart';
import '../../features/tools/domain/tool_spec.dart';
import '../ffi/llama_bindings.dart';
import 'text_engine.dart';

class LlamaEngine implements TextEngine {
  /// Resolves the app's cache directory for compiled GPU kernels. Null keeps
  /// the backend's kernel cache off (every load recompiles).
  final Future<String?> Function()? cacheDirectory;

  /// The window that owns this engine's native models (Android): when it
  /// closes, the platform frees them although the process lives on. Null or
  /// 0 leaves them untagged.
  final Future<int> Function()? owner;

  /// Told which bridge library the worker opened, so the platform reaches
  /// the same copy when it frees them.
  final void Function(String library)? onLibrary;
  LlamaEngine({this.cacheDirectory, this.owner, this.onLibrary});
  SendPort? _commands;
  ReceivePort? _events;
  Future<void>? _starting;
  Completer<void>? _operation;
  Completer<Map<String, dynamic>>? _preview, _probe, _embed, _adapter;
  StreamController<List<int>>? _output;
  ThinkingTagNormalizer? _normalizer;
  String? _loadedPath, _loadSettings;
  bool _busy = false;
  void Function()? _replyAdmission;
  int _requestId = 0;
  int? _sessionId;
  LlamaBindings? _control;
  bool _cancelRequested = false;
  String? _library;
  int _loads = 0;
  Completer<void>? _idle;
  Future<void> _metadataTail = Future.value();
  Completer<void>? _priming;
  bool _primeIssuing = false, _primeCancelled = false;

  /// Background prefill gives up ownership before any foreground operation.
  void cancelPriming() {
    if (_priming == null) return;
    _primeCancelled = true;
    cancel();
  }

  Future<void> _stopPriming() async {
    if (_primeIssuing) return;
    final prime = _priming;
    if (prime == null) return;
    cancelPriming();
    await prime.future;
  }

  /// One discarded token is the cheapest generation supported by the bridge.
  /// Preview verifies that even templates which omit empty turns retain the
  /// entire prefix before a real user's text. Unsupported templates are skipped.
  Future<void> primePrompt({
    required String system,
    required String fallbackTemplate,
    required InferenceSettings settings,
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async {
    if (!isLoaded || isBusy || _priming != null) return;
    final done = _priming = Completer<void>();
    _primeCancelled = false;
    final previousMetrics = metrics;
    final limited = settings.copyWith(maxTokens: 1);
    List<Map<String, Object>> messages(String user) => [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
    Future<Map<String, dynamic>> preview(String user) {
      _primeIssuing = true;
      try {
        return previewPrompt(
          messages: messages(user),
          fallbackTemplate: fallbackTemplate,
          settings: limited,
          tools: tools,
        );
      } finally {
        _primeIssuing = false;
      }
    }

    try {
      const marker = 'prime_user_content_7f93';
      final rendered = (await preview(marker))['formattedPrompt'];
      if (_primeCancelled || rendered is! String) return;
      final start = rendered.indexOf(marker);
      if (start < 0) return;
      final prefix = rendered.substring(0, start);
      String? user;
      for (final candidate in ['', ' ']) {
        final prompt = (await preview(candidate))['formattedPrompt'];
        if (_primeCancelled) return;
        if (prompt is String && prompt.startsWith(prefix)) {
          user = candidate;
          break;
        }
      }
      if (user == null || _primeCancelled) return;
      _primeIssuing = true;
      late Stream<String> output;
      try {
        output = generate(
          messages: messages(user),
          fallbackTemplate: fallbackTemplate,
          settings: limited,
          tools: tools,
          toolChoice: toolChoice,
        );
      } finally {
        _primeIssuing = false;
      }
      await output.drain<void>();
    } finally {
      metrics = previousMetrics;
      _priming = null;
      done.complete();
    }
  }

  void _send(Map<String, Object?> command) {
    _cancelRequested = false;
    _commands!.send({...command, 'requestId': ++_requestId});
  }

  void _notifyIdle() {
    if (!_busy) {
      _replyAdmission?.call();
      _replyAdmission = null;
    }
    _idle?.complete();
    _idle = null;
  }

  Future<void> _waitIdle() async {
    while (_occupied) {
      _idle ??= Completer<void>();
      await _idle!.future;
    }
  }

  Future<T> _metadata<T>(Future<T> Function() action) {
    cancelPriming();
    final next = _metadataTail.then((_) async {
      await _stopPriming();
      await _waitIdle();
      return action();
    });
    _metadataTail = next.then((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Map<String, dynamic> metrics = {};

  /// Share of the prompt already read (0…1) while the model reads it, before
  /// it writes; null otherwise. Drives the send button's ring.
  double? get prefillProgress => _prefill;
  Stream<double?> get prefillChanges => _prefillChanges.stream;
  double? _prefill;
  final _prefillChanges = StreamController<double?>.broadcast();
  void _setPrefill(double? value) {
    if (value == _prefill) return;
    _prefill = value;
    _prefillChanges.add(value);
  }

  /// Share loaded by the bridge (0..1); null when idle or unsupported.
  double? get loadProgress => _loadProgress;
  Stream<double?> get loadProgressChanges => _loadProgressChanges.stream;
  double? _loadProgress;
  Timer? _loadProgressTimer;
  bool _loading = false;
  final _loadProgressChanges = StreamController<double?>.broadcast();

  void _setLoadProgress(double? value) {
    if (value == _loadProgress) return;
    _loadProgress = value;
    _loadProgressChanges.add(value);
  }

  void _pollLoadProgress() {
    final id = _sessionId;
    if (id == null) return;
    try {
      final value = _control?.loadProgress?.call(id);
      _setLoadProgress(
        value != null && value.isFinite && value >= 0
            ? value.clamp(0.0, 1.0)
            : null,
      );
    } catch (_) {
      _setLoadProgress(null);
    }
  }

  void _stopLoadProgress() {
    _loading = false;
    _loadProgressTimer?.cancel();
    _loadProgressTimer = null;
    _setLoadProgress(null);
  }

  Future<void> _load(String path, String config) async {
    final op = Completer<void>();
    _operation = op;
    _loading = true;
    _send({'type': 'load', 'path': path, 'settings': config});
    try {
      await op.future;
    } catch (e) {
      throw ModelLoadException(modelLoadErrorMessage(e));
    } finally {
      _stopLoadProgress();
    }
  }

  bool get isLoaded => _loadedPath != null;

  /// Loads completed so far. [loadModel] returns early when the same model
  /// and settings are already loaded; a change here means a fresh load.
  int get loadCount => _loads;

  /// Background priming is available to foreground callers, which preempt it.
  bool get isPriming => _priming != null;
  bool get isBusy => !isPriming && _occupied;
  bool get _occupied =>
      _busy ||
      _operation != null ||
      _preview != null ||
      _embed != null ||
      _probe != null ||
      _adapter != null;
  bool get _working =>
      _busy || _operation != null || _preview != null || _embed != null;
  String? get loadedPath => _loadedPath;
  Future<void> _start() => _starting ??= _spawn();
  Future<void> _spawn() async {
    final ready = Completer<void>();
    _events = ReceivePort();
    _events!.listen((dynamic event) {
      if (event is SendPort) {
        _commands = event;
        ready.complete();
        return;
      }
      if (event == null || event is List) {
        final error = StateError(
          'Native worker exited unexpectedly${event is List ? ': ${event.first}' : ''}',
        );
        if (!ready.isCompleted) ready.completeError(error);
        _preview?.completeError(error);
        _preview = null;
        _probe?.completeError(error);
        _probe = null;
        _embed?.completeError(error);
        _embed = null;
        _adapter?.completeError(error);
        _adapter = null;
        _operation?.completeError(error);
        _operation = null;
        _output?.addError(error);
        unawaited(_output?.close());
        _output = null;
        _setPrefill(null);
        _loadedPath = null;
        _busy = false;
        _starting = null;
        _notifyIdle();
        return;
      }
      final e = event as Map;
      if (e['type'] == 'session') {
        _sessionId = e['id'] as int?;
        final library = e['library'] as String?;
        if (library != null && library != _library) {
          _library = library;
          // Sessions live in one bridge DLL; cancel through the same one.
          _control = null;
          onLibrary?.call(library);
        }
        if (_cancelRequested) _cancelNative();
        if (_loading && _loadProgressTimer == null) {
          try {
            // The worker already opened this exact library. Avoid discovery
            // (including Android CPU probing), and bind before polling starts.
            _control ??= LlamaBindings(libraryPath: _library);
            _loadProgressTimer = Timer.periodic(
              const Duration(milliseconds: 200),
              (_) => _pollLoadProgress(),
            );
          } catch (_) {
            /* Progress is optional on older bridges. */
          }
        }
        return;
      }
      if (e['requestId'] != _requestId) return;
      switch (e['type']) {
        case 'preview':
          _preview?.complete(Map<String, dynamic>.from(e['result'] as Map));
          _preview = null;
        case 'loaded':
          metrics = Map<String, dynamic>.from(e['metrics'] as Map);
          _loads++;
          _operation?.complete();
          _operation = null;
        case 'unloaded':
          metrics = const {};
          _operation?.complete();
          _operation = null;
        case 'probed':
          _probe?.complete(Map<String, dynamic>.from(e['info'] as Map));
          _probe = null;
        case 'embedded':
          _embed?.complete(Map<String, dynamic>.from(e['result'] as Map));
          _embed = null;
        case 'adapter' || 'estimated':
          _adapter?.complete(Map<String, dynamic>.from(e['result'] as Map));
          _adapter = null;
        case 'begun':
          final info = Map<String, dynamic>.from(e['info'] as Map);
          metrics = {...metrics, ...info};
          _normalizer?.configure(
            startTag: info['thinkingStartTag'] as String? ?? '',
            endTags:
                (info['thinkingEndTags'] as List?)?.cast<String>() ?? const [],
          );
          // The template already opened the reasoning block inside the prompt;
          // re-emit the tag so the parser routes the first tokens correctly.
          if (info['thinkingForcedOpen'] == true) {
            _output?.add(utf8.encode(ThinkingTagNormalizer.openTag));
          }
          final total = (info['promptTokens'] as num?)?.toInt() ?? 0;
          final cached = (info['cachedPromptTokens'] as num?)?.toInt() ?? 0;
          _setPrefill(total > cached ? cached / total : null);
        case 'prefill':
          final total = e['total'] as int;
          _setPrefill(total > 0 ? (e['read'] as int) / total : null);
        case 'bytes':
          _setPrefill(null);
          _output?.add(e['data'] as Uint8List);
        case 'done':
          _setPrefill(null);
          metrics = Map<String, dynamic>.from(e['metrics'] as Map);
          unawaited(_output?.close());
          _output = null;
          _busy = false;
        case 'error':
          final error = e['load'] == true
              ? ModelLoadException(modelLoadErrorMessage(e['message']))
              : InferenceException(e['message'] as String);
          _preview?.completeError(error);
          _preview = null;
          _probe?.completeError(error);
          _probe = null;
          _embed?.completeError(error);
          _embed = null;
          _adapter?.completeError(error);
          _adapter = null;
          _operation?.completeError(error);
          _operation = null;
          _output?.addError(error);
          unawaited(_output?.close());
          _output = null;
          _busy = false;
          _setPrefill(null);
      }
      if (!_occupied) _notifyIdle();
    });
    String? cacheDir;
    try {
      cacheDir = await cacheDirectory?.call();
    } catch (_) {
      cacheDir = null;
    }
    var ownerId = 0;
    try {
      ownerId = await owner?.call() ?? 0;
    } catch (_) {
      ownerId = 0;
    }
    await Isolate.spawn(
      _worker,
      [_events!.sendPort, cacheDir, ownerId],
      onError: _events!.sendPort,
      onExit: _events!.sendPort,
    );
    await ready.future;
  }

  /// [adapters] are LoRA GGUF files with scales; [draftModelPath] enables
  /// speculative decoding with that smaller model (same vocabulary).
  Future<void> loadModel({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    // A header read (probe, adapter info) finishes on its own: wait for it
    // rather than refusing the load.
    if (_priming != null) await _stopPriming();
    if (_working) {
      throw const ModelLoadException(
        'Wait for the current operation to finish.',
      );
    }
    final config = loadConfig(
      settings: settings,
      mmprojPath: mmprojPath,
      adapters: adapters,
      draftModelPath: draftModelPath,
    );
    if (_loadedPath == modelPath && _loadSettings == config) return;
    await _start();
    while (_occupied) {
      await _waitIdle();
    }
    _loadedPath = null;
    await _load(modelPath, config);
    _loadedPath = modelPath;
    _loadSettings = config;
  }

  /// The settings JSON od_load and od_estimate read.
  static String loadConfig({
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) {
    return jsonEncode({
      'contextSize': settings.contextSize,
      'imageMaxTokens': settings.imageMaxTokens,
      'backend': settings.backend.name,
      'cpuVariant': settings.cpuVariant,
      'projectorDevice': settings.projectorDevice,
      'nGpuLayers': settings.nGpuLayers,
      'vramReserveMb': settings.vramReserveMb,
      'useMmap': settings.useMmap,
      'useMlock': settings.useMlock,
      'mainGpu': settings.mainGpu,
      'splitMode': settings.splitMode,
      'offloadKv': settings.offloadKv,
      'swaFull': settings.swaFull,
      'nCpuMoe': settings.nCpuMoe,
      'expertsUsed': settings.expertsUsed,
      'draftGpuLayers': settings.draftGpuLayers,

      'flashAttention': settings.flashAttention,
      'kvCacheType': settings.kvCacheType.name,
      'vCacheType': settings.vCacheType?.name ?? '',
      'effectiveThreads': settings.effectiveThreads,
      'threadsAuto': DesktopHost.active && settings.cpuThreads == 0,
      'effectiveBatchThreads': settings.effectiveBatchThreads,
      'effectiveBatchSize': settings.effectiveBatchSize,
      'effectiveMicroBatchSize': settings.effectiveMicroBatchSize,
      'ropeScaling': settings.ropeScaling.name,
      'ropeFreqBase': settings.ropeFreqBase,
      'ropeFreqScale': settings.ropeFreqScale,
      'yarnExtFactor': settings.yarnExtFactor,
      'yarnAttnFactor': settings.yarnAttnFactor,
      'yarnBetaFast': settings.yarnBetaFast,
      'yarnBetaSlow': settings.yarnBetaSlow,
      'yarnOrigCtx': settings.yarnOrigCtx,
      // Vision projector (mmproj) next to the weights, when the model has one.
      'mmproj': mmprojPath ?? '',
      'loraAdapters': [
        for (final a in adapters) {'path': a.path, 'scale': a.scale},
      ],
      'draftModel': draftModelPath ?? '',
      'draftMaxTokens': settings.draftMaxTokens,
      'draftMinP': settings.draftMinP,
      'mtp': settings.mtp,
      'chatTemplate': settings.chatTemplate,
    });
  }

  /// Loads an embedding GGUF (EmbeddingGemma, nomic, bge…) on the CPU with
  /// pooled outputs (FX-02). Such a runtime answers [embed] only. With
  /// [mmprojPath] (ABI 7, EmbeddingGemma 2) it also embeds photos and
  /// recordings into the same space as text.
  Future<void> loadEmbedder({
    required String modelPath,
    String? mmprojPath,
    int threads = 4,
    int contextSize = 2048,
  }) async {
    if (_priming != null) await _stopPriming();
    if (_occupied) {
      throw const ModelLoadException(
        'Wait for the current operation to finish.',
      );
    }
    final config = jsonEncode({
      'embedding': true,
      'backend': 'cpu',
      'contextSize': contextSize,
      'effectiveThreads': threads,
      'effectiveBatchThreads': threads,
      'effectiveBatchSize': contextSize,
      'effectiveMicroBatchSize': 512,
      'flashAttention': false,
      'kvCacheType': 'fp16',
      'mmproj': ?mmprojPath,
    });
    if (_loadedPath == modelPath && _loadSettings == config) return;
    await _start();
    while (_occupied) {
      await _waitIdle();
    }
    _loadedPath = null;
    await _load(modelPath, config);
    _loadedPath = modelPath;
    _loadSettings = config;
  }

  /// Whether the loaded embedder has a projector for photos and recordings.
  bool get embedsMedia =>
      _loadSettings != null &&
      (jsonDecode(_loadSettings!) as Map)['mmproj'] != null;

  /// One L2-normalised vector per item, in order. Requires [loadEmbedder].
  /// An item is a text, or an [EmbedItem] with photos/recordings (needs a
  /// projector). [dims] > 0 keeps that many leading dimensions (Matryoshka).
  Future<List<Float32List>> embed(List<Object> texts, {int dims = 0}) async {
    if (_priming != null) await _stopPriming();
    if (!isLoaded || _occupied) {
      throw const InferenceException(
        'Load an embedding model and wait for the current operation.',
      );
    }
    if (texts.isEmpty) return const [];
    final op = Completer<Map<String, dynamic>>();
    _embed = op;
    _send({
      'type': 'embed',
      'request': jsonEncode({
        'texts': [for (final t in texts) t is EmbedItem ? t.toJson() : t],
        'dims': ?(dims > 0 ? dims : null),
      }),
    });
    final result = await op.future;
    return [
      for (final v in result['vectors'] as List)
        Float32List.fromList([
          for (final x in v as List) (x as num).toDouble(),
        ]),
    ];
  }

  /// Exact token counts per text (special tokens included) and the most one
  /// input may hold before [embed] truncates it, without embedding anything.
  /// Null when the engine library predates counting.
  Future<({List<int> counts, int limit})?> embedTokenCounts(
    List<String> texts,
  ) async {
    if (_priming != null) await _stopPriming();
    if (!isLoaded || _occupied) {
      throw const InferenceException(
        'Load an embedding model and wait for the current operation.',
      );
    }
    final op = Completer<Map<String, dynamic>>();
    _embed = op;
    _send({
      'type': 'embed',
      'request': jsonEncode({'texts': texts, 'countOnly': true}),
    });
    final result = await op.future;
    final counts = result['counts'], limit = result['limit'];
    if (counts is! List || limit is! int) return null;
    return (counts: [for (final c in counts) c as int], limit: limit);
  }

  /// A reranker's raw classifier outputs per (query, document) pair, keyed
  /// by its labels (Qwen3-Reranker: `yes` and `no` logits). Requires
  /// [loadEmbedder] with a reranker GGUF (pooling RANK). [instruction]
  /// replaces the model's task line.
  Future<List<Map<String, double>>> score(
    List<({String query, String document})> pairs, {
    String? instruction,
  }) async {
    if (_priming != null) await _stopPriming();
    if (!isLoaded || _occupied) {
      throw const InferenceException(
        'Load a reranker and wait for the current operation.',
      );
    }
    if (pairs.isEmpty) return const [];
    final op = Completer<Map<String, dynamic>>();
    _embed = op;
    _send({
      'type': 'embed',
      'request': jsonEncode({
        'pairs': [
          for (final p in pairs) {'query': p.query, 'document': p.document},
        ],
        'instruction': ?instruction,
      }),
    });
    final result = await op.future;
    final labels = [for (final l in result['labels'] as List) '$l'];
    return [
      for (final row in result['scores'] as List)
        {
          for (var i = 0; i < (row as List).length; i++)
            (i < labels.length && labels[i].isNotEmpty ? labels[i] : '$i'):
                (row[i] as num).toDouble(),
        },
    ];
  }

  /// GGUF metadata of a LoRA adapter file: `{architecture, adapterType,
  /// name, alpha, tensors, keys}`. Works without a loaded model.
  Future<Map<String, dynamic>> adapterInfo(String path) => _metadata(() async {
    await _start();
    while (_occupied) {
      await _waitIdle();
    }
    final op = Completer<Map<String, dynamic>>();
    _adapter = op;
    _send({'type': 'adapter', 'path': path});
    return op.future;
  });

  /// What loading [modelPath] with [settings] would use, measured by the
  /// bridge without loading: `{contextSize, layers, gpuLayers, ramNeedMb,
  /// vramNeedMb, vramFreeMb, vramTotalMb, gpuFit, backend, devices,
  /// ramAvailableMb, ramTotalMb}`. An empty [modelPath] lists the devices.
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    String? draftModelPath,
  }) => _metadata(() async {
    await _start();
    while (_occupied) {
      await _waitIdle();
    }
    final op = Completer<Map<String, dynamic>>();
    _adapter = op;
    _send({
      'type': 'estimate',
      'path': modelPath,
      'settings': loadConfig(
        settings: settings,
        mmprojPath: mmprojPath,
        draftModelPath: draftModelPath,
      ),
    });
    return op.future;
  });

  /// Counts the fully rendered prompt with the loaded model's tokenizer.
  /// Includes the chat template and response reserve; does not trim history.
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    if (_priming != null && !_primeIssuing) await _stopPriming();
    if (!isLoaded || _occupied) {
      throw const InferenceException(
        'Load a model and wait for the current operation.',
      );
    }
    final op = Completer<Map<String, dynamic>>();
    _preview = op;
    _send({
      'type': 'preview',
      'request': jsonEncode({
        'messages': messages,
        'fallbackTemplate': fallbackTemplate,
        'settings': _native(settings),
        'assistantPrefix': assistantPrefix,
        'tools': [for (final t in tools) t.toJson()],
      }),
    });
    return op.future;
  }

  /// The settings as the bridge reads them, with the response budget
  /// capped at half the loaded context ([InferenceSettings.responseReserve]).
  Map<String, dynamic> _native(InferenceSettings settings) {
    final context = metrics['contextSize'];
    final window = context is int && context > 0
        ? context
        : settings.contextSize;
    return {
      ...settings.toJson(),
      'maxTokens': settings.responseReserve(window),
    };
  }

  /// [assistantPrefix] resumes a partial answer (CHAT-02): it is appended
  /// after the generation prompt and the stream yields only the new text.
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) {
    if (_priming != null && !_primeIssuing) {
      final stopped = _stopPriming();
      return (() async* {
        await stopped;
        yield* generate(
          messages: messages,
          fallbackTemplate: fallbackTemplate,
          settings: settings,
          assistantPrefix: assistantPrefix,
          tools: tools,
          toolChoice: toolChoice,
        );
      })();
    }
    if (!isLoaded || _occupied) {
      throw const InferenceException(
        'Load a model and wait for the current operation.',
      );
    }
    _busy = true;
    _replyAdmission = InferenceAdmission.shared.hold();
    final output = StreamController<List<int>>(onCancel: cancel);
    _output = output;
    final normalizer = ThinkingTagNormalizer();
    _normalizer = normalizer;
    _send({
      'type': 'generate',
      'request': jsonEncode({
        'messages': messages,
        'fallbackTemplate': fallbackTemplate,
        'settings': _native(settings),
        'assistantPrefix': assistantPrefix,
        'tools': [for (final t in tools) t.toJson()],
        'toolChoice': toolChoice,
      }),
    });
    return output.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(normalizer);
  }

  /// Backend devices and library variant without loading a model: what the
  /// runtime *could* use, so a backend policy can decide before the load.
  Future<Map<String, dynamic>> probe() => _metadata(() async {
    await _start();
    while (_occupied) {
      await _waitIdle();
    }
    final op = Completer<Map<String, dynamic>>();
    _probe = op;
    _send({'type': 'probe'});
    return op.future;
  });

  /// Frees the model and context but keeps the worker alive, so the next
  /// load is a plain reload (model residency, roadmap §5.2).
  Future<void> unload() async {
    if (_priming != null) await _stopPriming();
    if (!isLoaded || _commands == null) return;
    if (_occupied) {
      throw const InferenceException('Wait for the current operation.');
    }
    final op = Completer<void>();
    _operation = op;
    _send({'type': 'unload'});
    await op.future;
    _loadedPath = null;
    _loadSettings = null;
  }

  @override
  void cancel() {
    if (_priming != null) _primeCancelled = true;
    _cancelRequested = true;
    _cancelNative();
    _commands?.send({'type': 'cancel'});
  }

  void _cancelNative() {
    final id = _sessionId;
    if (id == null) return;
    try {
      (_control ??= LlamaBindings(
        libraryPath: _library,
      )).cancelSession?.call(id);
    } catch (_) {
      /* Older bridges still stop between steps. */
    }
  }

  void dispose() {
    _stopLoadProgress();
    cancel();
    _commands?.send({'type': 'dispose'});
    _preview?.completeError(StateError('Engine disposed.'));
    _preview = null;
    _probe?.completeError(StateError('Engine disposed.'));
    _probe = null;
    _embed?.completeError(StateError('Engine disposed.'));
    _embed = null;
    _adapter?.completeError(StateError('Engine disposed.'));
    _adapter = null;
    _operation?.completeError(StateError('Engine disposed.'));
    _operation = null;
    unawaited(_output?.close());
    _output = null;
    _busy = false;
    _events?.close();
    _events = null;
    _commands = null;
    _starting = null;
    _sessionId = null;
    _loadedPath = null;
    _loadSettings = null;
    _notifyIdle();
  }
}

/// Explicit Windows backend choice; each bridge carries one GPU backend.
String? _windowsGpuChoice(String settings) {
  if (!Platform.isWindows) return null;
  final backend = (jsonDecode(settings) as Map)['backend'];
  return const ['cpu', 'cuda', 'vulkan'].contains(backend)
      ? backend as String
      : null;
}

void _worker(List<Object?> args) {
  final events = args[0] as SendPort;
  final options = jsonEncode({
    'cacheDir': args[1] as String? ?? '',
    'owner': args[2] as int? ?? 0,
  });
  final commands = ReceivePort();
  events.send(commands.sendPort);
  LlamaBindings? api;
  String? bridgeChoice;
  Pointer<Void> handle = nullptr;
  bool running = false, cancelled = false, disposing = false;
  // Engine info plus which bridge library variant this process loaded (GPU-01).
  Map<String, dynamic> info() {
    final value =
        jsonDecode(api!.info(handle).toDartString()) as Map<String, dynamic>;
    final cpu = LlamaBindings.windowsCpuOf(api!.library);
    return {
      ...value,
      if (cpu != null) 'backend': '${value['backend']} / ${cpu.toUpperCase()}',
      'nativeLibrary': api!.library,
      'nativeLibrarySkipped': api!.skipped,
    };
  }

  void clean() {
    if (handle != nullptr) api!.destroy(handle);
    handle = nullptr;
    commands.close();
  }

  commands.listen((dynamic message) async {
    final m = message as Map;
    void send(Map<String, Object?> e) =>
        events.send({...e, 'requestId': m['requestId']});
    if (m['type'] == 'cancel') {
      cancelled = true;
      return;
    }
    if (m['type'] == 'dispose') {
      cancelled = true;
      disposing = true;
      if (!running) clean();
      return;
    }
    if (running) {
      send({'type': 'error', 'message': 'Native worker is busy.'});
      return;
    }
    if (m['type'] == 'probe') {
      try {
        api ??= LlamaBindings();
        if (handle == nullptr) {
          final opts = options.toNativeUtf8();
          try {
            handle = api!.create(opts);
          } finally {
            calloc.free(opts);
          }
        }
        send({'type': 'probed', 'info': info()});
      } catch (e) {
        send({
          'type': 'probed',
          'info': <String, dynamic>{'error': '$e'},
        });
      }
      return;
    }
    if (m['type'] == 'estimate') {
      try {
        api ??= LlamaBindings();
        final estimate = api!.estimate;
        if (estimate == null) {
          throw UnsupportedError('This native bridge cannot estimate memory.');
        }
        if (handle == nullptr) {
          final opts = options.toNativeUtf8();
          try {
            handle = api!.create(opts);
          } finally {
            calloc.free(opts);
          }
        }
        final path = (m['path'] as String).toNativeUtf8();
        final settings = (m['settings'] as String).toNativeUtf8();
        try {
          final result = estimate(handle, path, settings);
          if (result == nullptr) {
            throw StateError(api!.error(handle).toDartString());
          }
          send({
            'type': 'estimated',
            'result': jsonDecode(result.toDartString()),
          });
        } finally {
          calloc.free(path);
          calloc.free(settings);
        }
      } on StateError catch (e) {
        // The bridge's own words, without Dart's "Bad state:" prefix.
        send({'type': 'error', 'message': e.message});
      } catch (e) {
        send({'type': 'error', 'message': '$e'});
      }
      return;
    }
    if (m['type'] == 'adapter') {
      try {
        api ??= LlamaBindings();
        if (handle == nullptr) {
          final opts = options.toNativeUtf8();
          try {
            handle = api!.create(opts);
          } finally {
            calloc.free(opts);
          }
        }
        final path = (m['path'] as String).toNativeUtf8();
        try {
          final result = api!.adapterInfo(handle, path);
          if (result == nullptr) {
            throw StateError(api!.error(handle).toDartString());
          }
          send({
            'type': 'adapter',
            'result': jsonDecode(result.toDartString()),
          });
        } finally {
          calloc.free(path);
        }
      } catch (e) {
        send({'type': 'error', 'message': '$e'});
      }
      return;
    }
    if (m['type'] == 'unload') {
      // od_destroy frees model, context and sampler; the isolate and the
      // backend registry stay warm.
      if (handle != nullptr) api!.destroy(handle);
      handle = nullptr;
      send({'type': 'unloaded'});
      return;
    }
    try {
      final want = m['type'] == 'load'
          ? _windowsGpuChoice(m['settings'] as String)
          : null;
      final cpuVariant = m['type'] == 'load'
          ? ((jsonDecode(m['settings'] as String) as Map)['cpuVariant']
                    as String? ??
                'auto')
          : 'auto';
      final choice = '$want/$cpuVariant';
      if (m['type'] == 'load' && api != null && bridgeChoice != choice) {
        // Recreate the runtime when the backend or CPU variant changes.
        if (handle != nullptr) api!.destroy(handle);
        handle = nullptr;
        api = null;
      }
      api ??= LlamaBindings(windowsBackend: want, cpuVariant: cpuVariant);
      if (m['type'] == 'load') bridgeChoice = choice;
      if (handle == nullptr) {
        final opts = options.toNativeUtf8();
        try {
          handle = api!.create(opts);
        } finally {
          calloc.free(opts);
        }
      }
      if (handle == nullptr) {
        throw StateError('Native runtime initialization failed');
      }
      api!.resetCancel?.call(handle);
      events.send({
        'type': 'session',
        'id': api!.sessionId?.call(handle),
        'library': api!.library,
      });
      if (m['type'] == 'load') {
        final path = (m['path'] as String).toNativeUtf8();
        final config = (m['settings'] as String).toNativeUtf8();
        try {
          if (api!.load(handle, path, config) < 0) {
            throw ModelLoadException(api!.error(handle).toDartString());
          }
          send({'type': 'loaded', 'metrics': info()});
        } finally {
          calloc.free(path);
          calloc.free(config);
        }
      } else if (m['type'] == 'preview') {
        final request = (m['request'] as String).toNativeUtf8();
        try {
          final result = api!.preview(handle, request);
          if (result == nullptr) {
            throw StateError(api!.error(handle).toDartString());
          }
          send({
            'type': 'preview',
            'result': jsonDecode(result.toDartString()),
          });
        } finally {
          calloc.free(request);
        }
      } else if (m['type'] == 'embed') {
        final request = (m['request'] as String).toNativeUtf8();
        try {
          final result = api!.embed(handle, request);
          if (result == nullptr) {
            throw StateError(api!.error(handle).toDartString());
          }
          send({
            'type': 'embedded',
            'result': jsonDecode(result.toDartString()),
          });
        } finally {
          calloc.free(request);
        }
      } else if (m['type'] == 'generate') {
        running = true;
        cancelled = false;
        final request = (m['request'] as String).toNativeUtf8();
        final bytes = calloc<Uint8>(65536);
        final length = calloc<Int32>();
        try {
          if (api!.begin(handle, request) < 0) {
            throw StateError(api!.error(handle).toDartString());
          }
          final begun = info();
          send({'type': 'begun', 'info': begun});
          // od_step returns 0 once per batch of prompt tokens read, starting
          // after the cached prefix: enough to show how far reading got.
          final total = (begun['promptTokens'] as num?)?.toInt() ?? 0;
          var read = (begun['cachedPromptTokens'] as num?)?.toInt() ?? 0;
          final batch =
              ((begun['effectiveSettings'] as Map?)?['batchSize'] as num?)
                  ?.toInt() ??
              512;
          while (!cancelled) {
            final status = api!.step(handle, bytes, 65536, length);
            if (status < 0) throw StateError(api!.error(handle).toDartString());
            if (status == 2) break;
            if (status == 0 && read < total) {
              read = math.min(total, read + math.max(1, batch));
              send({'type': 'prefill', 'read': read, 'total': total});
            }
            if (status == 1 && length.value > 0) {
              send({
                'type': 'bytes',
                'data': Uint8List.fromList(bytes.asTypedList(length.value)),
              });
            }
            await Future<void>.delayed(Duration.zero);
          }
          send({
            'type': 'done',
            'metrics': {...info(), if (cancelled) 'finishReason': 'cancelled'},
          });
        } finally {
          running = false;
          calloc.free(request);
          calloc.free(bytes);
          calloc.free(length);
          if (disposing) clean();
        }
      }
    } catch (e) {
      if (handle != nullptr &&
          api?.cancelled?.call(handle) == 1 &&
          m['type'] == 'generate') {
        send({
          'type': 'done',
          'metrics': {...info(), 'finishReason': 'cancelled'},
        });
      } else {
        send({
          'type': 'error',
          'load': m['type'] == 'load',
          'message': m['type'] == 'load' ? modelLoadErrorMessage(e) : '$e',
        });
      }
    }
  });
}

/// Rewrites a model's own reasoning markers (Gemma 4: `<|channel>thought` …
/// `<channel|>`) to the canonical `<think>` … `</think>` pair the rest of the
/// app understands. Tags may arrive split across pieces, so a tail no longer
/// than the longest tag is held back until it cannot be a tag prefix.
/// One embedding input with photos or recordings (ABI 7): paths readable by
/// the native side (JPEG/PNG/BMP/GIF; 16 kHz WAV, MP3 or FLAC), plus an
/// optional text embedded jointly with them.
class EmbedItem {
  final String text;
  final List<String> media;
  const EmbedItem(this.media, {this.text = ''});
  Map<String, Object> toJson() => {'text': text, 'media': media};
}

class ThinkingTagNormalizer extends StreamTransformerBase<String, String> {
  static const openTag = '<think>';
  static const closeTag = '</think>';
  final _replacements = <String, String>{};
  int _hold = 0;

  void configure({required String startTag, required List<String> endTags}) {
    _replacements.clear();
    if (startTag.isNotEmpty && startTag != openTag) {
      _replacements[startTag] = openTag;
    }
    for (final end in endTags) {
      if (end.isNotEmpty && end != closeTag) _replacements[end] = closeTag;
    }
    _hold = _replacements.keys.fold(0, (m, k) => k.length > m ? k.length : m);
    if (_hold > 0) _hold -= 1;
  }

  @override
  Stream<String> bind(Stream<String> stream) {
    final buffer = StringBuffer();
    return stream.transform(
      StreamTransformer<String, String>.fromHandlers(
        handleData: (piece, sink) {
          if (_replacements.isEmpty) {
            sink.add(piece);
            return;
          }
          buffer.write(piece);
          var text = buffer.toString();
          buffer.clear();
          while (true) {
            String? tag;
            var at = -1;
            for (final key in _replacements.keys) {
              final i = text.indexOf(key);
              if (i != -1 && (at == -1 || i < at)) {
                at = i;
                tag = key;
              }
            }
            if (tag == null) break;
            sink.add(text.substring(0, at) + _replacements[tag]!);
            text = text.substring(at + tag.length);
          }
          if (text.length > _hold) {
            sink.add(text.substring(0, text.length - _hold));
            text = text.substring(text.length - _hold);
          }
          buffer.write(text);
        },
        handleDone: (sink) {
          if (buffer.isNotEmpty) sink.add(buffer.toString());
          sink.close();
        },
      ),
    );
  }
}
