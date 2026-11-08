import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'helper_jobs.dart';
import 'helper_tool_loop.dart';
import '../tools/tool_runner.dart';
import '../tools/domain/tool_markup.dart';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/platform/desktop_host.dart';
import '../../core/platform/device_info.dart';
import '../../core/providers/shared_providers.dart';
import '../../core/utils/priority_work_queue.dart';
import '../../inference/engine/llama_engine.dart';
import '../../inference/engine/text_engine.dart';
import '../../inference/remote/remote_engine.dart';
import '../models/domain/entities/model_info.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../models/presentation/providers/model_recommendations_provider.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../settings/presentation/providers/effective_settings_provider.dart';
import '../settings/presentation/providers/model_profiles_provider.dart';

final _log = Logger('agent');

/// What one hand-off returned.
class HelperReply {
  final String text;
  final Duration took;
  final String modelName;
  const HelperReply({
    required this.text,
    required this.took,
    required this.modelName,
  });
}

class HelperUnavailable implements Exception {
  final String reason;
  const HelperUnavailable(this.reason);

  @override
  String toString() => 'HelperUnavailable: $reason';
}

/// Keeps local agent weights resident and routes Same as chat to remote APIs.
class HelperRunner {
  final LlamaEngine engine;
  final LlamaEngine chatEngine;
  final LlamaEngine Function()? extraEngine;
  final int lanes;
  final bool shareChat;

  /// Desktop agent jobs on the helper's own model run as parallel sequences of one copy.
  final bool batchOwnModel;
  final _extra = <HelperRunner>[];
  int _pending = 0;
  final List<ModelInfo> Function() catalog;
  final String? Function() loadedModelId;
  final InferenceSettings Function(ModelInfo) settingsFor;
  final Future<DeviceMemory?> Function() memory;
  final bool Function() desktop;
  final bool Function() localChat;
  final InferenceSettings Function()? chatSettings;

  /// A job owns its client so cancellation never stops the chat or another job.
  final RemoteEngine Function()? remoteEngine;
  final _remoteQueues = List.generate(4, (_) => PriorityWorkQueue());
  final _remotePending = List.filled(4, 0);
  final Duration idle;
  final Duration timeout;
  final Duration loadTimeout;
  final _placements = <String, Future<InferenceSettings>>{};
  final void Function(HelperJob)? publish;
  final void Function()? loadedChanged;
  final _loaded = StreamController<Set<String>>.broadcast();
  static int _nextJob = 0;
  final _queue = PriorityWorkQueue();
  final PriorityWorkQueue _loads;
  final bool Function()? keepWarm;
  int _turns = 0;
  InferenceSettings? _residentSettings;
  Timer? _idleTimer;
  String? _modelId;
  bool _disposed = false;
  final _stops = <void Function()>{};

  HelperRunner({
    required this.engine,
    required this.chatEngine,
    required this.catalog,
    required this.loadedModelId,
    required this.settingsFor,
    this.publish,
    this.loadedChanged,
    PriorityWorkQueue? loadQueue,
    this.keepWarm,
    this.extraEngine,
    this.lanes = 1,
    this.shareChat = true,
    this.batchOwnModel = true,
    this.memory = DeviceMemory.read,
    this.desktop = _desktop,
    this.localChat = _localChat,
    this.chatSettings,
    this.remoteEngine,
    this.idle = const Duration(minutes: 3),
    this.timeout = const Duration(seconds: 90),
    this.loadTimeout = const Duration(seconds: 120),
  }) : _loads = loadQueue ?? PriorityWorkQueue();

  static bool _desktop() => DesktopHost.active;
  static bool _localChat() => true;

  HelperRunner _pick(int maximum) {
    if (_pending == 0 || extraEngine == null || _disposed) return this;
    final eligible = _extra
        .take((maximum.clamp(1, 4) - 1).clamp(0, _extra.length))
        .toList();
    for (final lane in eligible) {
      if (lane._pending == 0) return lane;
    }
    if (_extra.length + 1 < lanes && _extra.length + 1 < maximum) {
      final lane = HelperRunner(
        engine: extraEngine!(),
        chatEngine: chatEngine,
        shareChat: false,
        batchOwnModel: batchOwnModel,
        catalog: catalog,
        loadedModelId: loadedModelId,
        settingsFor: settingsFor,
        publish: publish,
        loadedChanged: _emitLoaded,
        loadQueue: _loads,
        keepWarm: () => _turns > 0,
        memory: memory,
        desktop: desktop,
        localChat: localChat,
        idle: idle,
        timeout: timeout,
        loadTimeout: loadTimeout,
      );
      _extra.add(lane);
      return lane;
    }
    return [
      this,
      ...eligible,
    ].reduce((a, b) => a._pending <= b._pending ? a : b);
  }

  Set<String> get loadedModelIds => {
    if (_modelId != null && engine.isLoaded) _modelId!,
    for (final lane in _extra) ...lane.loadedModelIds,
  };
  Stream<Set<String>> get loadedModels => _loaded.stream;

  void _emitLoaded() {
    if (_disposed) return;
    _loaded.add(Set.unmodifiable(loadedModelIds));
    loadedChanged?.call();
  }

  Future<void> unloadModel(String modelId) async {
    await Future.wait([
      _queue.submit(() async {
        if (_modelId == modelId) await _release();
      }),
      for (final lane in _extra) lane.unloadModel(modelId),
    ]);
  }

  void beginTurn() {
    if (_turns == 0) _placements.clear();
    _turns++;
    _idleTimer?.cancel();
    for (final lane in _extra) {
      lane._idleTimer?.cancel();
    }
  }

  void endTurn() {
    if (_turns > 0) _turns--;
    if (_turns == 0) unawaited(chatEngine.closeSide());
    _scheduleIdle();
    for (final lane in _extra) {
      lane._scheduleIdle();
    }
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    if (_disposed || _turns > 0 || (keepWarm?.call() ?? false)) return;
    _idleTimer = Timer(
      idle,
      () => unawaited(unload().catchError((Object _) {})),
    );
  }

  Future<InferenceSettings> _desktopSettings(
    File file,
    InferenceSettings settings,
  ) async {
    // Measure free VRAM with the chat resident; fill it first and spill the
    // remaining layers into RAM (owner, 2026-11-02 afternoon).
    final info = await engine.probe();
    final devices = (info['devices'] as List? ?? const []).whereType<Map>();
    final gpu = devices
        .where(
          (d) =>
              (d['gpu'] == true || d['type'] == 'gpu') &&
              const [
                'cuda',
                'vulkan',
              ].contains('${d['backend']}'.toLowerCase()),
        )
        .firstOrNull;
    if (gpu == null) return settings.copyWith(backend: GpuBackend.cpu);
    final backend = '${gpu['backend']}'.toLowerCase() == 'cuda'
        ? GpuBackend.cuda
        : GpuBackend.vulkan;
    final candidate = settings.copyWith(backend: backend, nGpuLayers: 999);
    try {
      final fit = await engine.estimate(
        modelPath: file.path,
        settings: candidate,
      );
      // The native fit already keeps vramReserveMb free for the chat and
      // moves layers (or MoE experts) that do not fit to the CPU.
      final offloaded = fit['gpuLayers'] as num?;
      if (offloaded != null && offloaded > 0) {
        _log.info(
          'Agent placement: ${backend.name}, ${fit['gpuLayers']}/${fit['layers']} layers on the GPU '
          '(VRAM need ${fit['vramNeedMb']} MB, free ${fit['vramFreeMb']} MB)',
        );
        return candidate;
      }
      _log.info('Agent placement: CPU, no layer fits in free VRAM ($fit)');
    } catch (error, stack) {
      // A failed admission must leave the main model running (owner, 2026-11-02).
      _log.warning('Agent placement estimate failed, using CPU', error, stack);
    }
    return settings.copyWith(backend: GpuBackend.cpu);
  }

  bool get _chatOnGpu {
    final layers =
        chatEngine.metrics['gpuLayers'] ??
        (chatEngine.metrics['effectiveSettings'] as Map?)?['gpuLayers'];
    final backend = '${chatEngine.metrics['backend']}'.toLowerCase();
    return localChat() &&
        chatEngine.isLoaded &&
        loadedModelId() != null &&
        layers is num &&
        layers > 0 &&
        (backend.contains('cuda') || backend.contains('vulkan'));
  }

  Future<InferenceSettings> _placement(
    String modelId,
    InferenceSettings? agentSettings,
  ) async {
    final model = catalog().where((m) => m.id == modelId).firstOrNull;
    if (model == null) return const InferenceSettings(backend: GpuBackend.cpu);
    final base = settingsFor(model);
    final settings =
        (agentSettings == null ? base : base.withAgentSettings(agentSettings))
            .forAgent();
    if (!desktop() ||
        model.localPath == null ||
        !await File(model.localPath!).exists()) {
      return settings.copyWith(backend: GpuBackend.cpu);
    }
    if (_modelId == modelId &&
        engine.isLoaded &&
        _residentSettings != null &&
        _residentSettings!.backend != GpuBackend.cpu &&
        _residentSettings!.contextSize == settings.contextSize) {
      return settings.copyWith(
        backend: _residentSettings!.backend,
        nGpuLayers: _residentSettings!.nGpuLayers,
      );
    }
    return _desktopSettings(File(model.localPath!), settings);
  }

  Future<InferenceSettings> _admit(
    String modelId,
    InferenceSettings? agentSettings,
  ) {
    final key = agentSettings == null
        ? modelId
        : '$modelId:${jsonEncode({for (final entry in agentSettings.toJson().entries)
            if (entry.key.startsWith("agent")) entry.key: entry.value})}';
    final pending = _placements[key];
    if (pending != null) return pending;
    late final Future<InferenceSettings> future;
    future = () async {
      try {
        return await _placement(modelId, agentSettings);
      } finally {
        if (_turns == 0 && identical(_placements[key], future)) {
          unawaited(_placements.remove(key));
        }
      }
    }();
    _placements[key] = future;
    return future;
  }

  /// The agent model setting that means the chat's selected local or remote model.
  static const sameAsChat = '@chat';

  String _remoteName(InferenceSettings settings) =>
      settings.remoteModel.trim().isEmpty
      ? 'server default'
      : settings.remoteModel.trim();

  InferenceSettings? _remoteSettings(
    String modelId,
    InferenceSettings? agentSettings,
  ) {
    final settings = agentSettings ?? chatSettings?.call();
    return modelId == sameAsChat && settings?.usesRemote == true
        ? settings
        : null;
  }

  String _resolve(String modelId) {
    if (modelId != sameAsChat) return modelId;
    final loaded = loadedModelId();
    if (loaded == null || !chatEngine.isLoaded) {
      throw const HelperUnavailable('no chat model is loaded');
    }
    return loaded;
  }

  String _modelName(String modelId, bool sideGpu, InferenceSettings placement) {
    final name =
        catalog().where((m) => m.id == modelId).firstOrNull?.displayName ??
        modelId;
    if (sideGpu) return '$name (shared GPU)';
    return desktop()
        ? '$name · ${placement.backend == GpuBackend.cpu ? 'CPU' : 'GPU'}'
        : name;
  }

  // The chosen agent model always runs; only the chat model itself batches
  // beside the chat on its GPU (owner, 2026-11-02).
  bool _usesSharedGpu(String modelId) =>
      desktop() &&
      loadedModelId() == modelId &&
      chatEngine.isLoaded &&
      _chatOnGpu;

  // Start acknowledgements use the same admission decision as execution (owner, 2026-11-02).
  Future<String> modelNameFor(
    String modelId, {
    InferenceSettings? agentSettings,
  }) async {
    final remote = _remoteSettings(modelId, agentSettings);
    if (remote != null) return _remoteName(remote);
    modelId = _resolve(modelId);
    final sideGpu = _usesSharedGpu(modelId);
    final placement = sideGpu
        ? const InferenceSettings()
        : await _admit(modelId, agentSettings);
    return _modelName(modelId, sideGpu, placement);
  }

  Future<HelperReply> run({
    required String modelId,
    required String task,
    String input = '',
    String? messageId,
    int? maxTokens,
    ToolRunner? webTools,
    Future<bool> Function(CancelToken)? approveWeb,
    InferenceSettings? agentSettings,
    CancelToken? cancel,
  }) async {
    if (_disposed) throw const HelperUnavailable('helper is disposed');
    final remote = _remoteSettings(modelId, agentSettings);
    if (remote != null) {
      final maximum = remote.agentMaxConcurrent.clamp(1, 4);
      var lane = 0;
      for (var i = 1; i < maximum; i++) {
        if (_remotePending[i] < _remotePending[lane]) lane = i;
      }
      _remotePending[lane]++;
      try {
        return await _runHere(
          remoteSettings: remote,
          workQueue: _remoteQueues[lane],
          sideGpu: false,
          placement: remote,
          modelId: modelId,
          task: task,
          input: input,
          messageId: messageId,
          maxTokens: maxTokens,
          jobTimeout: remote.agentTimeoutSeconds <= 0
              ? null
              : Duration(seconds: remote.agentTimeoutSeconds.clamp(1, 86400)),
          webTools: webTools,
          approveWeb: approveWeb,
          cancel: cancel,
        );
      } finally {
        _remotePending[lane]--;
      }
    }
    modelId = _resolve(modelId);
    final sideGpu = _usesSharedGpu(modelId);
    final reuse =
        !sideGpu &&
        shareChat &&
        loadedModelId() == modelId &&
        chatEngine.isLoaded;
    final placement = await _admit(modelId, agentSettings);
    // Desktop and CPU jobs share one resident copy; phone GPU lanes are admitted per turn (owner, 2026-11-02).
    final lane =
        sideGpu ||
            reuse ||
            (batchOwnModel && desktop()) ||
            placement.backend == GpuBackend.cpu
        ? this
        : _pick(placement.agentMaxConcurrent);
    lane._pending++;
    try {
      return await lane._runHere(
        sideGpu: sideGpu,
        placement: placement,
        modelId: modelId,
        task: task,
        input: input,
        messageId: messageId,
        maxTokens: maxTokens,
        jobTimeout: agentSettings == null
            ? timeout
            : agentSettings.agentTimeoutSeconds <= 0
            ? null
            : Duration(
                seconds: agentSettings.agentTimeoutSeconds.clamp(1, 86400),
              ),
        webTools: webTools,
        approveWeb: approveWeb,
        cancel: cancel,
      );
    } finally {
      lane._pending--;
    }
  }

  /// Jobs queue in arrival order. Cancellation also applies while queued.
  Future<HelperReply> _runHere({
    InferenceSettings? remoteSettings,
    PriorityWorkQueue? workQueue,
    required Duration? jobTimeout,
    required bool sideGpu,
    required InferenceSettings placement,
    required String modelId,
    required String task,
    String input = '',
    String? messageId,
    int? maxTokens,
    ToolRunner? webTools,
    Future<bool> Function(CancelToken)? approveWeb,
    CancelToken? cancel,
  }) {
    final jobCancel = CancelToken();
    final reply = Completer<HelperReply>();
    final id = 'helper-${++_nextJob}';
    final elapsed = Stopwatch()..start();
    var phase = HelperPhase.queued;
    final chatId = loadedModelId();
    final chatModel = catalog().where((m) => m.id == chatId).firstOrNull;
    final modelName = remoteSettings == null
        ? _modelName(modelId, sideGpu, placement)
        : _remoteName(remoteSettings);
    // A desktop agent model batches all its jobs on one resident copy, like the chat model's side batch (owner, 2026-11-02).
    final ownSide =
        remoteSettings == null &&
        batchOwnModel &&
        desktop() &&
        !sideGpu &&
        !(shareChat && loadedModelId() == modelId && chatEngine.isLoaded);
    final side = sideGpu || ownSide;
    LlamaEngine sideEngine() => sideGpu ? chatEngine : engine;
    final output = StringBuffer();
    Map<String, dynamic> metrics = {};
    String? activity;
    HelperToolLoop? loop;
    var loadMs = 0;
    Duration? firstToken, prefill;
    Stopwatch? generation;
    HelperReply? result;
    String? reason;
    var terminal = false;
    Timer? updates;
    void emit() {
      final raw = output.toString();
      final thinking = RegExp(
        r'<think>(.*?)(?:</think>|$)',
        dotAll: true,
        caseSensitive: false,
      ).allMatches(raw).map((m) => m.group(1)!).join('\n');
      final answer = ToolMarkup.visible(raw)
          .replaceAll(
            RegExp(
              r'<think>.*?(?:</think>|$)',
              dotAll: true,
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(RegExp(r'</think>|<[^>]*$', caseSensitive: false), '')
          .trim();
      publish?.call(
        HelperJob(
          id: id,
          task: task,
          inputPreview: input.length > 1200
              ? '${input.substring(0, 1200)}...'
              : input,
          modelName: modelName,
          messageId: messageId,
          phase: phase,
          output: answer,
          thinking: thinking,
          elapsed: elapsed.elapsed,
          firstToken: firstToken,
          prefill: prefill,
          metrics: Map.unmodifiable({
            ...metrics,
            'toolActivity': ?activity,
            if (loop != null)
              'toolCalls': [for (final r in loop!.trace) r.toJson()],
            if (!sideGpu) 'loadMs': loadMs,
            if (sideGpu) 'sharedGpu': true,
            if (sideGpu) 'chatModelId': chatId,
            if (sideGpu) 'sideStarted': generation != null,
            if (generation != null)
              'generationElapsedMs': generation!.elapsedMilliseconds,
          }),
          reason: reason,
          reply: result,
        ),
      );
    }

    void finish(HelperPhase end, [String? why]) {
      if (terminal) return;
      terminal = true;
      updates?.cancel();
      phase = end;
      reason = why;
      elapsed.stop();
      emit();
    }

    emit();
    bool? previousLiveMetrics;
    TextEngine? active;
    RemoteEngine? remoteClient;
    var finished = false;
    HelperUnavailable? stopped;
    void stop(String reason) {
      if (finished || terminal || stopped != null) return;
      stopped = HelperUnavailable(reason);
      jobCancel.cancel(reason);
      if (generation != null && active != null) {
        metrics = {
          ...(side ? sideEngine().sideMetrics[id] ?? metrics : active!.metrics),
        };
      }
      finish(
        reason.endsWith('timed out')
            ? HelperPhase.timedOut
            : HelperPhase.cancelled,
        reason,
      );
      final running = active;
      if (side) {
        sideEngine().cancelSide(id);
      } else {
        running?.cancel();
      }
      // On the chat's own engine the job answers only once it has settled:
      // the chat's next round would find it busy.
      if ((side || !identical(running, chatEngine)) && !reply.isCompleted) {
        reply.completeError(stopped!);
      }
    }

    void cancelJob() => stop('cancelled');
    _stops.add(cancelJob);
    updates = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (terminal) return;
      if (active != null) {
        metrics = {
          ...(side ? sideEngine().sideMetrics[id] ?? metrics : active!.metrics),
          if (sideGpu) 'sharedGpu': true,
          if (sideGpu)
            'backend':
                '${chatEngine.metrics['backend']} (shared with ${chatModel?.displayName ?? chatId})',
          if (!sideGpu && active is LlamaEngine)
            'loadProgress': ?(active as LlamaEngine).loadProgress,
          if (!sideGpu && active is LlamaEngine)
            'prefillProgress': ?(active as LlamaEngine).prefillProgress,
        };
      }
      emit();
    });
    if (cancel?.isCancelled == true) stop('cancelled');
    unawaited(cancel?.whenCancel.then((_) => stop('cancelled')));
    Future<void> execute() async {
      final watch = Stopwatch()..start();
      _log.info(
        '$id: started on $modelName '
        '(${sideGpu
            ? 'shared chat GPU'
            : ownSide
            ? 'batched'
            : 'own engine'}): $task',
      );
      Timer? timer;
      final activeTime = Stopwatch();
      void armDeadline() {
        timer?.cancel();
        if (jobTimeout == null) return;
        activeTime.start();
        final remaining = jobTimeout - activeTime.elapsed;
        if (remaining <= Duration.zero) {
          stop('timed out');
        } else {
          timer = Timer(remaining, () => stop('timed out'));
        }
      }

      bool Function()? previousLoadStop;
      var changedLoadStop = false;
      try {
        if (stopped != null) throw stopped!;
        if (_disposed) throw const HelperUnavailable('helper is disposed');
        _idleTimer?.cancel();
        // Side batches run on the chat's loaded weights, not a file.
        final model = catalog().where((m) => m.id == modelId).firstOrNull;
        if (remoteSettings == null &&
            (model == null ||
                (!sideGpu &&
                    (!model.isDownloaded ||
                        model.localPath == null ||
                        !await File(model.localPath!).exists())))) {
          throw const HelperUnavailable('model is not downloaded');
        }
        final file = File(model?.localPath ?? '');
        if (stopped != null) throw stopped!;
        final reuse =
            remoteSettings == null &&
            !sideGpu &&
            shareChat &&
            loadedModelId() == modelId &&
            chatEngine.isLoaded;
        if (remoteSettings != null) {
          remoteClient = remoteEngine?.call() ?? RemoteEngine();
        }
        final TextEngine target =
            remoteClient ?? (sideGpu || reuse ? chatEngine : engine);
        // A chat generation owns its context until the stream has ended.
        if (!side && target is LlamaEngine && target.isBusy) {
          throw const HelperUnavailable('model is busy');
        }
        var settings =
            (sideGpu && chatModel != null
                    ? settingsFor(chatModel).withAgentSettings(placement)
                    : placement)
                .forAgent(answerTokens: maxTokens);
        // Server defaults must not override the helper's bounded response.
        if (remoteSettings != null) {
          settings = settings.copyWith(serverSampling: false);
        }
        if (reuse && engine.isLoaded) {
          // The chat may have loaded a model the helper already held.
          await _release();
          if (loadedModelId() != modelId || !chatEngine.isLoaded) {
            throw const HelperUnavailable('chat model changed');
          }
          if (chatEngine.isBusy) {
            throw const HelperUnavailable('model is busy');
          }
        }
        Future<void> ensureLoaded() async {
          if (_modelId != modelId ||
              !engine.isLoaded ||
              _residentSettings?.backend != placement.backend ||
              _residentSettings?.contextSize != settings.contextSize) {
            await _release();
            if (!desktop()) {
              // Read now: the cached device facts predate the chat's load.
              final available = await memory();
              final fileBytes = await file.length();
              final bytes = model!.sizeBytes > fileBytes
                  ? model.sizeBytes
                  : fileBytes;
              if (available == null ||
                  available.lowMemory ||
                  available.availableBytes < bytes * 1.25) {
                throw const HelperUnavailable('not enough available memory');
              }
            }
            if (stopped != null) throw stopped!;
            active = target;
            previousLoadStop = engine.loadStop;
            changedLoadStop = true;
            engine.loadStop = () => stopped != null || _disposed;
            phase = HelperPhase.loadingModel;
            emit();
            final loading = Stopwatch()..start();
            await _loads.submit(() async {
              if (stopped != null) throw stopped!;
              timer = Timer(loadTimeout, () => stop('loading timed out'));
              if (stopped != null) throw stopped!;
              try {
                await engine.loadModel(
                  modelPath: file.path,
                  settings: settings,
                );
              } catch (error, stack) {
                _log.warning(
                  '$id: loading ${model!.displayName} failed',
                  error,
                  stack,
                );
                if (!desktop() ||
                    settings.backend == GpuBackend.cpu ||
                    stopped != null) {
                  rethrow;
                }
                await engine.unload();
                throw const HelperUnavailable('GPU helper admission changed');
              }
            });
            timer?.cancel();
            timer = null;
            loadMs = loading.elapsedMilliseconds;
            _log.info(
              '$id: loaded ${model!.displayName} in $loadMs ms '
              '(${engine.metrics['backend']}, ${(engine.metrics['effectiveSettings'] as Map?)?['gpuLayers']} GPU layers)',
            );
            _residentSettings = settings;
            _modelId = modelId;
            _emitLoaded();
          }
        }

        if (remoteSettings == null && !reuse && !sideGpu) {
          // Batched jobs run beside each other, so only their loads queue.
          await (ownSide ? _queue.submit(ensureLoaded) : ensureLoaded());
        }
        if (stopped != null) throw stopped!;
        if (_disposed) throw const HelperUnavailable('helper is disposed');
        if (remoteSettings == null &&
            !reuse &&
            !sideGpu &&
            _residentSettings != null) {
          settings = settings.copyWith(
            backend: _residentSettings!.backend,
            nGpuLayers: _residentSettings!.nGpuLayers,
          );
        }
        active = target;
        phase = side ? HelperPhase.queued : HelperPhase.prefill;
        if (!side && target is LlamaEngine) {
          // Previous job counters must not appear during fresh prefill (owner, 2026-11-02).
          target.metrics = {
            for (final e in target.metrics.entries)
              if (!const {
                'tokens',
                'tokensPerSecond',
                'promptTokens',
                'prefillMs',
                'firstTokenMs',
              }.contains(e.key))
                e.key: e.value,
          };
          previousLiveMetrics = target.reportLiveMetrics;
          target.reportLiveMetrics = true;
        }
        void started() {
          if (stopped != null) {
            sideEngine().cancelSide(id);
            return;
          }
          phase = HelperPhase.prefill;
          generation ??= Stopwatch()..start();
          armDeadline();
          emit();
        }

        if (!side) started();
        emit();
        loop = HelperToolLoop(
          tools: webTools,
          approve: approveWeb == null ? null : () => approveWeb(jobCancel),
          cancel: jobCancel,
          activity: (value) {
            activity = value;
            // Waiting for the user does not consume the inference deadline.
            if (value == 'approval') {
              timer?.cancel();
              activeTime.stop();
            } else {
              armDeadline();
            }
            emit();
          },
        );
        final answer = await loop!.run(
          task: task,
          input: input,
          settings: settings,
          generate: (messages) async {
            if (stopped != null) throw stopped!;
            output.clear();
            if (sideGpu &&
                (chatId != loadedModelId() || !chatEngine.isLoaded)) {
              throw const HelperUnavailable('chat model changed');
            }
            final stream = side
                ? sideEngine().generateSide(
                    jobId: id,
                    messages: messages,
                    fallbackTemplate: sideGpu
                        ? chatModel?.family.fallbackTemplate ?? ''
                        : model!.family.fallbackTemplate,
                    settings: settings,
                    onStarted: started,
                  )
                : target.generate(
                    messages: messages,
                    fallbackTemplate: model?.family.fallbackTemplate ?? '',
                    settings: settings,
                  );
            await for (final part in stream) {
              if (stopped != null) continue;
              firstToken ??= generation?.elapsed;
              prefill ??= generation!.elapsed;
              phase = HelperPhase.generating;
              output.write(part);
            }
            if (stopped != null) throw stopped!;
            return output.toString();
          },
        );
        activity = null;
        if (stopped != null) throw stopped!;
        metrics = {
          ...(side ? sideEngine().sideMetrics[id] ?? metrics : target.metrics),
          if (sideGpu) 'sharedGpu': true,
          if (sideGpu)
            'backend':
                '${chatEngine.metrics['backend']} (shared with ${chatModel?.displayName ?? chatId})',
        };
        var text = answer
            .replaceAll(
              RegExp(
                r'<think>.*?(?:</think>|$)',
                dotAll: true,
                caseSensitive: false,
              ),
              '',
            )
            .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
            .trim();

        final answerChars = settings.maxTokens * 4000 ~/ 512;
        if (text.length > answerChars) {
          text = text.substring(0, answerChars).trimRight();
        }
        if (!reply.isCompleted) {
          result = HelperReply(
            text: text,
            took: watch.elapsed,
            modelName: modelName,
          );
          _log.info(
            '$id: done in ${watch.elapsedMilliseconds} ms, ${metrics['tokens']} tokens, '
            '${(metrics['tokensPerSecond'] as num?)?.toStringAsFixed(1)} tok/s, ${metrics['backend']}',
          );
          finish(HelperPhase.done);
          reply.complete(result!);
        }
      } catch (error, stack) {
        // The card and the Logs page show the real cause: a bare "helper
        // inference failed" hid a stale native bridge (owner, 2026-11-02).
        final detail = '$error'
            .replaceFirst(RegExp(r'^(Bad state|Exception): '), '')
            .split('\n')
            .first;
        final unavailable = error is HelperUnavailable
            ? error
            : HelperUnavailable(
                '$error'.contains('chat model changed')
                    ? 'chat model changed'
                    : 'helper inference failed: ${detail.length > 160 ? '${detail.substring(0, 160)}…' : detail}',
              );
        if (stopped != null) {
          _log.info(
            '$id: stopped (${stopped!.reason}) after ${watch.elapsedMilliseconds} ms',
          );
        } else {
          _log.warning(
            '$id: failed after ${watch.elapsedMilliseconds} ms',
            error,
            stack,
          );
        }
        finish(
          _disposed ? HelperPhase.cancelled : HelperPhase.failed,
          unavailable.reason,
        );
        if (!reply.isCompleted) {
          reply.completeError(stopped ?? unavailable, stack);
        }
      } finally {
        // Keep queue ownership until native cancellation has settled.
        updates?.cancel();
        finished = true;
        if (previousLiveMetrics != null) {
          (active as LlamaEngine).reportLiveMetrics = previousLiveMetrics!;
        }
        remoteClient?.dispose();
        active = null;
        _stops.remove(cancelJob);
        if (side) sideEngine().sideMetrics.remove(id);
        timer?.cancel();
        if (changedLoadStop) engine.loadStop = previousLoadStop;
        _scheduleIdle();
      }
    }

    unawaited(side ? execute() : (workQueue ?? _queue).submit(execute));
    return reply.future;
  }

  Future<void> _release() async {
    _idleTimer?.cancel();
    if (engine.isLoaded) await engine.unload();
    _modelId = null;
    _residentSettings = null;
    _emitLoaded();
  }

  /// Releases only the helper's worker, including after a shared-engine job.
  Future<void> unload() async {
    await Future.wait([
      _queue.submit(_release),
      for (final lane in _extra) lane.unload(),
    ]);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_loaded.close());
    _idleTimer?.cancel();
    for (final stop in _stops.toList()) {
      stop();
    }
    for (final lane in _extra) {
      lane.dispose();
      // Native contexts must settle before their worker is disposed (owner, 2026-11-02).
      unawaited(
        lane
            .unload()
            .whenComplete(lane.engine.dispose)
            .catchError((Object _) {}),
      );
    }
    unawaited(unload().catchError((Object _) {}));
  }
}

final helperRunnerProvider = Provider<HelperRunner>((ref) {
  var alive = true;
  final jobs = ref.read(helperJobsProvider.notifier);
  final runner = HelperRunner(
    publish: (job) {
      if (alive) jobs.publish(job);
    },
    localChat: () => !ref.read(effectiveSettingsProvider).effective.usesRemote,
    chatSettings: () => ref.read(effectiveSettingsProvider).effective,
    remoteEngine: ref.watch(remoteHelperEngineFactoryProvider),
    engine: ref.watch(helperEngineProvider),
    extraEngine: createHelperEngine,
    lanes: 4,
    // Background helpers must not occupy the main model context (owner, 2026-11-02).
    shareChat: false,
    chatEngine: ref.watch(llamaEngineProvider),
    catalog: () => ref.read(modelManagerProvider).catalog,
    loadedModelId: () => ref.read(modelManagerProvider).loadedModelId,
    settingsFor: (model) {
      final recommendation = recommendationFor(
        model,
        ref.read(modelRecommendationsProvider),
      );
      final agent = ref.read(effectiveSettingsProvider).effective;
      return InferenceSettings.fromJson({
        ...recommendation.values,
        ...?ref.read(modelProfilesProvider)[model.id],
        for (final entry in agent.toJson().entries)
          if (entry.key.startsWith('agent')) entry.key: entry.value,
      });
    },
  );
  ref.onDispose(() {
    alive = false;
    runner.dispose();
  });
  return runner;
});

// Model cards observe every lane, including jobs launched from other screens (owner, 2026-11-02).
final helperLoadedModelsProvider = StreamProvider<Set<String>>((ref) async* {
  final runner = ref.watch(helperRunnerProvider);
  yield runner.loadedModelIds;
  yield* runner.loadedModels;
});

// Model cards follow published job state across chat surfaces (owner, 2026-11-02).
final helperStreamsProvider = Provider.family<int, String>((ref, modelId) {
  return ref
      .watch(helperJobsProvider)
      .jobs
      .where(
        (job) =>
            !job.terminal &&
            job.metrics['chatModelId'] == modelId &&
            job.metrics['sideStarted'] == true,
      )
      .length;
});
