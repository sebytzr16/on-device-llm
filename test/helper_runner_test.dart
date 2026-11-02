import 'dart:async';
import 'dart:io';

import 'agent_web_test.dart' show FakeAgentTools;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/helper/helper_runner.dart';
import 'package:ondevice_llm/features/helper/helper_jobs.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/domain/model_recommendations.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_recommendations_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

class _Engine extends LlamaEngine {
  bool loaded = false;
  bool busy = false;
  int loads = 0, unloads = 0, cancels = 0;
  final prompts = <List<Map<String, Object>>>[];
  final settingsSeen = <InferenceSettings>[];
  List<String> output = ['result'];
  final rounds = <String>[];
  Duration partDelay = Duration.zero;
  Completer<void>? gate;
  Completer<void>? loadGate;
  bool settleOnCancel = true;

  Map<String, dynamic> estimateSeen = {};
  List<Map<String, Object>> devices = [];
  @override
  Future<Map<String, dynamic>> probe() async => {'devices': devices};
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    String? draftModelPath,
  }) async => estimateSeen;

  @override
  bool get isLoaded => loaded;
  @override
  bool get isBusy => busy;

  @override
  Future<void> loadModel({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    loads++;
    settingsSeen.add(settings);
    await loadGate?.future;
    loaded = true;
  }

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<dynamic> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    busy = true;
    prompts.add(messages);
    settingsSeen.add(settings);
    try {
      await gate?.future;
      metrics = {'promptTokens': 12, 'tokens': 0};
      for (final part in rounds.isEmpty ? output : [rounds.removeAt(0)]) {
        metrics = {...metrics, 'tokens': (metrics['tokens'] as int) + 1};
        yield part;
        if (partDelay != Duration.zero) await Future<void>.delayed(partDelay);
      }
    } finally {
      busy = false;
    }
  }

  @override
  void cancel() {
    cancels++;
    if (settleOnCancel && gate?.isCompleted == false) gate!.complete();
  }

  @override
  Future<void> unload() async {
    expect(busy, isFalse, reason: 'Never unload an active generation');
    unloads++;
    loaded = false;
  }
}

void _admitGpu(_Engine engine) {
  engine.devices = [
    {'gpu': true, 'backend': 'CUDA'},
  ];
  engine.estimateSeen = {
    'vramNeedMb': 100,
    'vramFreeMb': 4000,
    'layers': 25,
    'gpuLayers': 25,
  };
}

class _SideEngine extends _Engine {
  final sideGate = Completer<void>();
  final sidePrompts = <List<Map<String, Object>>>[];
  int activeSide = 0, peakSide = 0;
  bool changed = false;
  @override
  Stream<String> generateSide({
    required String jobId,
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    void Function()? onStarted,
  }) async* {
    sidePrompts.add(messages);
    activeSide++;
    if (activeSide > peakSide) peakSide = activeSide;
    onStarted?.call();
    try {
      await sideGate.future;
      if (changed) throw StateError('chat model changed');
      sideMetrics[jobId] = {
        'tokens': 3,
        'promptTokens': 20,
        'tokensPerSecond': 50.0,
      };
      yield rounds.isEmpty
          ? 'reply ${messages.last['content']}'
          : rounds.removeAt(0);
    } finally {
      activeSide--;
    }
  }

  @override
  Future<void> closeSide() async {
    changed = true;
    if (!sideGate.isCompleted) sideGate.complete();
  }

  @override
  Future<void> unload() async {
    await closeSide();
    loaded = false;
  }
}

class _Recommendations extends ModelRecommendationsNotifier {
  @override
  Map<String, ModelRecommendation> build() => {};
}

class _Manager extends ModelManagerNotifier {
  final ModelInfo model;
  _Manager(this.model);

  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [model], loadedModelId: model.id);
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(done(), isTrue);
}

void main() {
  late Directory directory;
  late ModelInfo model;
  late _Engine engine, chat;
  late HelperRunner runner;
  late ProviderContainer jobs;
  final phases = <HelperPhase>[];

  HelperRunner create({
    List<ModelInfo>? catalog,
    String? loadedId,
    bool desktop = true,
    DeviceMemory? memory,
    LlamaEngine Function()? extraEngine,
    int lanes = 1,
    Duration idle = const Duration(minutes: 3),
    Duration timeout = const Duration(seconds: 90),
    Duration loadTimeout = const Duration(seconds: 120),
    bool shareChat = true,
    bool localChat = true,
    bool batchOwnModel = false,
  }) => HelperRunner(
    batchOwnModel: batchOwnModel,
    publish: (job) {
      phases.add(job.phase);
      jobs.read(helperJobsProvider.notifier).publish(job);
    },
    engine: engine,
    chatEngine: chat,
    extraEngine: extraEngine,
    lanes: lanes,
    catalog: () => catalog ?? [model],
    loadedModelId: () => loadedId,
    settingsFor: (_) => const InferenceSettings(topK: 17),
    desktop: () => desktop,
    memory: () async => memory,
    idle: idle,
    timeout: timeout,
    loadTimeout: loadTimeout,
    shareChat: shareChat,
    localChat: () => localChat,
  );

  setUp(() async {
    jobs = ProviderContainer();
    phases.clear();
    directory = await Directory.systemTemp.createTemp('helper_runner_');
    final file = await File(
      '${directory.path}/helper.gguf',
    ).writeAsString('gguf');
    model = ModelInfo(
      id: 'helper',
      displayName: 'Helper model',
      fileName: 'helper.gguf',
      sizeBytes: 100,
      family: ModelFamily.qwen,
      quantization: ModelQuantization.q8_0,
      isDownloaded: true,
      localPath: file.path,
    );
    engine = _Engine();
    chat = _Engine();
    runner = create();
  });

  tearDown(() async {
    runner.dispose();
    await runner.unload();
    jobs.dispose();
    await directory.delete(recursive: true);
  });

  for (final side in [false, true]) {
    test('agent web tool loop runs on side batch=$side', () async {
      final tools = FakeAgentTools();
      final target = side ? _SideEngine() : engine;
      if (side) {
        runner.dispose();
        chat = target;
        chat.loaded = true;
        chat.metrics = {'backend': 'CUDA', 'gpuLayers': 25};
        (target as _SideEngine).sideGate.complete();
        runner = create(loadedId: model.id);
      }
      target.rounds.addAll([
        '```tool\n{"name":"search_web","arguments":{"query":"release"}}\n```',
        'Verified answer',
      ]);
      var approvals = 0;
      final result = await runner.run(
        modelId: model.id,
        task: 'Check release',
        webTools: tools,
        approveWeb: (_) async {
          approvals++;
          return true;
        },
      );
      expect(result.text, 'Verified answer');
      expect(tools.calls.single.name, 'search_web');
      expect(approvals, 1);
      final job = jobs.read(helperJobsProvider).jobs.last;
      expect((job.metrics['toolCalls'] as List).length, 1);
      if (side) {
        expect((target as _SideEngine).sidePrompts.length, 2);
      } else {
        expect(target.prompts.length, 2);
      }
    });
  }

  test('agent settings update a resident GPU context and sampling', () async {
    _admitGpu(engine);
    await runner.run(modelId: model.id, task: 'first');
    await runner.run(
      modelId: model.id,
      task: 'second',
      agentSettings: const InferenceSettings(
        agentContextSize: 8192,
        agentMaxTokens: 2048,
        agentTemperature: .8,
        agentTopK: 9,
        agentThinking: true,
        agentInstructions: 'Use bullet points.',
      ),
    );
    expect(engine.loads, 2);
    final settings = engine.settingsSeen.last;
    expect(settings.contextSize, 8192);
    expect(settings.maxTokens, 2048);
    expect(settings.temperature, .8);
    expect(settings.topK, 9);
    expect(settings.thinkingModeEnabled, true);
    expect(
      engine.prompts.last.first['content'],
      contains('Use bullet points.'),
    );
  });

  test('turn cancellation removes an agent waiting for web approval', () async {
    engine.rounds.add(
      '```tool\n{"name":"search_web","arguments":{"query":"x"}}\n```',
    );
    final cancel = CancelToken();
    final tools = FakeAgentTools();
    final waiting = Completer<void>();
    final reply = runner.run(
      modelId: model.id,
      task: 'Check',
      webTools: tools,
      cancel: cancel,
      approveWeb: (jobCancel) async {
        waiting.complete();
        await jobCancel.whenCancel;
        throw jobCancel.cancelError!;
      },
    );
    final error = expectLater(reply, throwsA(isA<HelperUnavailable>()));
    await waiting.future;
    cancel.cancel();
    await error;
    await runner.unload();
    expect(tools.calls, isEmpty);
    expect(
      jobs.read(helperJobsProvider).jobs.single.phase,
      HelperPhase.cancelled,
    );
  });

  test('generation deadline starts after a slow load', () async {
    runner.dispose();
    runner = create(timeout: const Duration(milliseconds: 30));
    engine.loadGate = Completer<void>();
    final job = runner.run(modelId: model.id, task: 'title');
    await _until(() => engine.loads == 1);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(
      jobs.read(helperJobsProvider).jobs.single.phase,
      HelperPhase.loadingModel,
    );
    expect(engine.cancels, 0);
    engine.loadGate!.complete();
    expect((await job).text, 'result');
  });

  for (final phone in [false, true]) {
    test('remote or phone chat uses one CPU helper (phone=$phone)', () async {
      runner.dispose();
      chat.loaded = true;
      chat.metrics = {'backend': 'CUDA', 'gpuLayers': 43};
      final extra = _Engine();
      runner = create(
        loadedId: 'main',
        desktop: !phone,
        localChat: phone,
        memory: const DeviceMemory(
          totalBytes: 1000000,
          availableBytes: 1000000,
          lowMemory: false,
        ),
        extraEngine: () => extra,
        lanes: 3,
      );
      engine.gate = Completer<void>();
      final first = runner.run(modelId: model.id, task: 'one');
      final second = runner.run(modelId: model.id, task: 'two');
      await _until(() => engine.busy);
      expect(engine.settingsSeen.first.backend, GpuBackend.cpu);
      expect(extra.loads, 0);
      engine.gate!.complete();
      await Future.wait([first, second]);
      expect(engine.loads, 1);
    });
  }

  test(
    'CPU fallback keeps one copy and queued jobs have no generation deadline',
    () async {
      runner.dispose();
      final extra = _Engine();
      runner = create(extraEngine: () => extra, lanes: 3);
      engine.gate = Completer<void>();
      final first = runner.run(modelId: model.id, task: 'one');
      final second = runner.run(modelId: model.id, task: 'two');
      final third = runner.run(modelId: model.id, task: 'three');
      await _until(() => engine.busy);
      expect(extra.loads, 0);
      expect(engine.loads, 1);
      engine.gate!.complete();
      await Future.wait([first, second, third]);
      expect(engine.prompts.length, 3);
    },
  );

  for (final unload in [false, true]) {
    test(
      'GPU chat shares concurrent side sequences and cleanly handles unload=$unload',
      () async {
        runner.dispose();
        final side = _SideEngine()..loaded = true;
        side.metrics = {'backend': 'CUDA', 'gpuLayers': 43};
        chat = side;
        runner = create(
          loadedId: model.id,
          shareChat: false,
          lanes: 3,
          extraEngine: _Engine.new,
        );
        runner.beginTurn();
        final replies = [
          for (var i = 0; i < 3; ++i)
            runner.run(modelId: model.id, task: 'section $i'),
        ];
        final result = Future.wait(replies);
        final expectation = unload
            ? expectLater(
                result,
                throwsA(
                  isA<HelperUnavailable>().having(
                    (e) => e.reason,
                    'reason',
                    'chat model changed',
                  ),
                ),
              )
            : null;
        await _until(() => side.activeSide == 3);
        expect(engine.loads, 0);
        expect(side.peakSide, 3);
        await _until(() => jobs.read(helperStreamsProvider(model.id)) == 3);
        expect(side.prompts, isEmpty);
        expect(
          jobs
              .read(helperJobsProvider)
              .jobs
              .every((j) => j.modelName.contains('shared GPU')),
          isTrue,
        );
        if (unload) {
          await side.unload();
          await expectation;
        } else {
          side.sideGate.complete();
          expect((await result).map((r) => r.text), [
            'reply section 0',
            'reply section 1',
            'reply section 2',
          ]);
        }
        expect(jobs.read(helperStreamsProvider('main')), 0);
        runner.endTurn();
      },
    );
  }

  test('unknown, undownloaded and missing files are unavailable', () async {
    for (final catalog in [
      <ModelInfo>[],
      [model.copyWith(isDownloaded: false)],
      [model.copyWith(localPath: '${directory.path}/missing.gguf')],
    ]) {
      runner.dispose();
      runner = create(catalog: catalog);
      await expectLater(
        runner.run(modelId: model.id, task: 'title'),
        throwsA(
          isA<HelperUnavailable>().having(
            (e) => e.reason,
            'reason',
            'model is not downloaded',
          ),
        ),
      );
    }
    expect(engine.loads, 0);
    expect(
      jobs
          .read(helperJobsProvider)
          .jobs
          .every(
            (j) =>
                j.phase == HelperPhase.failed &&
                j.reason == 'model is not downloaded',
          ),
      isTrue,
    );
  });

  test(
    'a chosen agent model is never swapped for the GPU chat model',
    () async {
      runner.dispose();
      final side = _SideEngine()..loaded = true;
      side.metrics = {'backend': 'CUDA', 'gpuLayers': 43};
      side.sideGate.complete();
      chat = side;
      runner = create(loadedId: 'main');
      final result = await runner.run(modelId: model.id, task: 'title');
      expect(result.modelName, isNot(contains('shared GPU')));
      expect(result.modelName, startsWith(model.displayName));
      expect(engine.loads, 1);
    },
  );

  test('desktop agent jobs batch on one copy of the chosen model', () async {
    runner.dispose();
    final own = _SideEngine();
    engine = own;
    runner = create(loadedId: 'main', batchOwnModel: true);
    final first = runner.run(modelId: model.id, task: 'one');
    final second = runner.run(modelId: model.id, task: 'two');
    final third = runner.run(modelId: model.id, task: 'three');
    await pumpEventQueue();
    expect(own.peakSide, 3);
    expect(own.loads, 1);
    own.sideGate.complete();
    final replies = await Future.wait([first, second, third]);
    expect(
      replies.map((r) => r.modelName),
      everyElement(startsWith(model.displayName)),
    );
    expect(own.prompts, isEmpty);
  });

  test('strips split think tags, trims and caps the reply', () async {
    engine.output = [' <thi', 'nk>private\nreason</think>  Title  '];
    final result = await runner.run(modelId: model.id, task: 'title');
    expect(result.text, 'Title');
    expect(result.modelName, startsWith(model.displayName));
    expect(result.took, greaterThanOrEqualTo(Duration.zero));
    engine.output = ['<think>hidden</think>${'x' * 4500}'];
    expect(
      (await runner.run(modelId: model.id, task: 'title')).text.length,
      4000,
    );
    engine.output = ['visible<think>unfinished'];
    expect(
      (await runner.run(modelId: model.id, task: 'title')).text,
      'visible',
    );
    expect(engine.loads, 1);
  });

  test('caps combined helper content and disables thinking', () async {
    await runner.run(
      modelId: model.id,
      task: 'Summarise',
      input: '${'a' * 12000}discard',
      maxTokens: 123,
    );
    final content = engine.prompts.single.last['content'] as String;
    expect(content.length, lessThanOrEqualTo(4800));
    expect(content, startsWith('Summarise\n\n---\n'));
    expect(content, contains('[Excerpt cut to helper budget]'));
    expect(engine.prompts.single.first['role'], 'system');
    final settings = engine.settingsSeen.last;
    expect(settings.contextSize, 4096);
    expect(settings.temperature, 0.3);
    expect(settings.thinkingModeEnabled, isFalse);
    expect(settings.maxTokens, 123);
    expect(settings.topK, 17);
    await runner.run(modelId: model.id, task: 'Title');
    expect(engine.prompts.last.last['content'], 'Title');
  });

  test('serializes jobs and unload waits for the active job', () async {
    engine.gate = Completer<void>();
    final first = runner.run(modelId: model.id, task: 'first');
    await _until(() => engine.prompts.length == 1);
    final second = runner.run(modelId: model.id, task: 'second');
    final unload = runner.unload();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(engine.prompts.length, 1);
    expect(engine.unloads, 0);
    engine.gate!.complete();
    await Future.wait([first, second]);
    await unload;
    expect(engine.prompts.map((p) => p.last['content']), ['first', 'second']);
    expect(engine.unloads, 1);
  });

  test('two lanes overlap and the third call queues on the first', () async {
    runner.dispose();
    final extra = _Engine()..gate = Completer<void>();
    _admitGpu(engine);
    engine.gate = Completer<void>();
    runner = create(extraEngine: () => extra, lanes: 2);
    final first = runner.run(modelId: model.id, task: 'first');
    final second = runner.run(modelId: model.id, task: 'second');
    final third = runner.run(modelId: model.id, task: 'third');
    await _until(() => engine.busy && extra.busy);
    expect(engine.prompts.length, 1);
    expect(extra.prompts.length, 1);
    extra.gate!.complete();
    await second;
    expect(engine.prompts.length, 1);
    engine.gate!.complete();
    await Future.wait([first, third]);
    expect(engine.prompts.map((p) => p.last['content']), ['first', 'third']);
    await runner.unload();
    expect(extra.unloads, 1);
  });

  test('reused chat queues without loading another CPU copy', () async {
    runner.dispose();
    chat.loaded = true;
    chat.gate = Completer<void>();
    final extra = _Engine();
    runner = create(loadedId: model.id, extraEngine: () => extra, lanes: 2);
    final first = runner.run(modelId: model.id, task: 'first');
    final second = runner.run(modelId: model.id, task: 'second');
    await _until(() => chat.busy);
    expect(extra.loads, 0);
    chat.gate!.complete();
    await Future.wait([first, second]);
    expect(chat.prompts.length, 2);
  });

  for (final lowMemory in [false, true]) {
    test(
      'phone queues an extra job without memory room (lowMemory=$lowMemory)',
      () async {
        runner.dispose();
        engine.loaded = true;
        engine.gate = Completer<void>();
        final extra = _Engine();
        runner = create(
          desktop: false,
          memory: DeviceMemory(
            totalBytes: 1000000,
            availableBytes: lowMemory ? 1000000 : 124,
            lowMemory: lowMemory,
          ),
          loadedId: model.id,
          extraEngine: () => extra,
          lanes: 2,
        );
        // Sharing the chat leaves no room for a separate phone worker (owner, 2026-11-02).
        chat.loaded = true;
        chat.gate = Completer<void>();
        final first = runner.run(modelId: model.id, task: 'first');
        final second = runner.run(modelId: model.id, task: 'second');
        await _until(() => jobs.read(helperJobsProvider).jobs.length == 2);
        expect(chat.prompts.length, 1);
        expect(extra.loads, 0);
        expect(extra.prompts, isEmpty);
        expect(
          jobs.read(helperJobsProvider).jobs.last.phase,
          HelperPhase.queued,
        );
        chat.gate!.complete();
        await Future.wait([first, second]);
        expect(chat.prompts.length, 2);
      },
    );
  }

  test('same-id uses the loaded chat engine and never unloads it', () async {
    runner.dispose();
    chat.loaded = true;
    runner = create(loadedId: model.id);
    await runner.run(modelId: model.id, task: 'title');
    await runner.unload();
    expect(chat.prompts.length, 1);
    expect(chat.loads, 0);
    expect(chat.unloads, 0);
    expect(engine.loads, 0);
    chat.busy = true;
    await expectLater(
      runner.run(modelId: model.id, task: 'title'),
      throwsA(isA<HelperUnavailable>()),
    );
    expect(chat.cancels, 0);
    chat.busy = false;
  });

  test(
    'same-id frees an earlier helper copy and bypasses phone memory guard',
    () async {
      runner.dispose();
      await runner.unload();
      engine.loaded = true;
      chat.loaded = true;
      runner = create(loadedId: model.id, desktop: false);
      await runner.run(modelId: model.id, task: 'title');
      expect(engine.unloads, 1);
      expect(chat.prompts.length, 1);
      expect(chat.unloads, 0);
    },
  );

  test(
    'phone checks current available memory; desktop allows the job',
    () async {
      runner.dispose();
      runner = create(
        desktop: false,
        memory: const DeviceMemory(
          totalBytes: 1000000,
          availableBytes: 124,
          lowMemory: false,
        ),
      );
      await expectLater(
        runner.run(modelId: model.id, task: 'title'),
        throwsA(isA<HelperUnavailable>()),
      );
      expect(engine.loads, 0);
      runner.dispose();
      runner = create(
        desktop: false,
        memory: const DeviceMemory(
          totalBytes: 1000000,
          availableBytes: 125,
          lowMemory: false,
        ),
      );
      await runner.run(modelId: model.id, task: 'title');
      expect(engine.settingsSeen.first.backend, GpuBackend.cpu);
    },
  );

  test('cancellation stops generation and cancels queued work', () async {
    engine.gate = Completer<void>();
    final cancel = CancelToken();
    final first = runner.run(modelId: model.id, task: 'first', cancel: cancel);
    final firstError = expectLater(first, throwsA(isA<HelperUnavailable>()));
    await _until(() => engine.busy);
    final queuedCancel = CancelToken();
    final second = runner.run(
      modelId: model.id,
      task: 'second',
      cancel: queuedCancel,
    );
    final secondError = expectLater(second, throwsA(isA<HelperUnavailable>()));
    queuedCancel.cancel();
    cancel.cancel();
    await Future.wait([firstError, secondError]);
    await runner.unload();
    expect(engine.cancels, 1);
    expect(engine.prompts.length, 1);
    expect(jobs.read(helperJobsProvider).jobs.map((j) => j.phase), [
      HelperPhase.cancelled,
      HelperPhase.cancelled,
    ]);
  });

  test(
    'timeout returns promptly but keeps queue ownership until settled',
    () async {
      runner.dispose();
      runner = create(timeout: const Duration(milliseconds: 40));
      engine.gate = Completer<void>();
      engine.settleOnCancel = false;
      await expectLater(
        runner.run(modelId: model.id, task: 'first'),
        throwsA(
          isA<HelperUnavailable>().having(
            (e) => e.reason,
            'reason',
            'timed out',
          ),
        ),
      );
      expect(
        jobs.read(helperJobsProvider).jobs.single.phase,
        HelperPhase.timedOut,
      );
      expect(jobs.read(helperJobsProvider).jobs.single.reason, 'timed out');
      final second = runner.run(modelId: model.id, task: 'second');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(engine.prompts.length, 1);
      expect(engine.cancels, 1);
      engine.gate!.complete();
      await second;
      expect(engine.prompts.length, 2);
    },
  );

  test('shared chat timeout waits until the engine settles', () async {
    runner.dispose();
    chat.loaded = true;
    chat.gate = Completer<void>();
    chat.settleOnCancel = false;
    runner = create(
      loadedId: model.id,
      timeout: const Duration(milliseconds: 40),
    );
    var answered = false;
    final reply = runner.run(modelId: model.id, task: 'title');
    final checked = expectLater(
      reply.whenComplete(() => answered = true),
      throwsA(
        isA<HelperUnavailable>().having((e) => e.reason, 'reason', 'timed out'),
      ),
    );
    await _until(() => chat.cancels == 1);
    expect(chat.busy, isTrue);
    expect(answered, isFalse);
    chat.gate!.complete();
    await checked;
    expect(chat.busy, isFalse);
    expect(chat.unloads, 0);
  });

  test(
    'loading has its own deadline and skips generation after a late load',
    () async {
      runner.dispose();
      runner = create(loadTimeout: const Duration(milliseconds: 30));
      engine.loadGate = Completer<void>();
      await expectLater(
        runner.run(modelId: model.id, task: 'title'),
        throwsA(
          isA<HelperUnavailable>().having(
            (e) => e.reason,
            'reason',
            'loading timed out',
          ),
        ),
      );
      expect(engine.loadStop?.call(), isTrue);
      engine.loadGate!.complete();
      await runner.unload();
      expect(engine.prompts, isEmpty);
      expect(engine.loadStop, isNull);
    },
  );

  for (final fits in [true, false]) {
    test(
      // VRAM first, then RAM: any layer that fits beside the chat goes on
      // the card; only an agent with no room at all runs on the CPU.
      'desktop helper uses CUDA whenever a layer fits beside the resident chat (fits=$fits)',
      () async {
        chat.loaded = true;
        engine.devices = [
          {'gpu': true, 'backend': 'CUDA'},
        ];
        engine.estimateSeen = {
          'vramNeedMb': 800,
          'vramFreeMb': fits ? 2000 : 100,
          'layers': 25,
          'gpuLayers': fits ? 12 : 0,
        };
        await runner.run(modelId: model.id, task: 'title');
        expect(
          engine.settingsSeen.first.backend,
          fits ? GpuBackend.cuda : GpuBackend.cpu,
        );
        expect(engine.settingsSeen.first.contextSize, 4096);
        expect(
          jobs.read(helperJobsProvider).jobs.single.metrics['loadMs'],
          isA<int>(),
        );
        expect(chat.unloads, 0);
        await runner.run(modelId: model.id, task: 'again');
        expect(engine.loads, 1);
        expect(jobs.read(helperJobsProvider).jobs.last.metrics['loadMs'], 0);
      },
    );
  }

  test(
    'a new turn re-admits a resident CPU helper when GPU room returns',
    () async {
      runner.beginTurn();
      await runner.run(modelId: model.id, task: 'first');
      runner.endTurn();
      expect(engine.settingsSeen.first.backend, GpuBackend.cpu);
      _admitGpu(engine);
      runner.beginTurn();
      await runner.run(modelId: model.id, task: 'second');
      runner.endTurn();
      expect(engine.loads, 2);
      expect(engine.unloads, 1);
      expect(engine.settingsSeen[2].backend, GpuBackend.cuda);
    },
  );

  test('a turn keeps idle helper lanes resident until the turn ends', () async {
    runner.dispose();
    runner = create(idle: const Duration(milliseconds: 20));
    runner.beginTurn();
    await runner.run(modelId: model.id, task: 'title');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.unloads, 0);
    await runner.run(modelId: model.id, task: 'again');
    expect(engine.loads, 1);
    runner.endTurn();
    await _until(() => engine.unloads == 1);
  });

  test('idle releases weights and the next job reloads', () async {
    runner.dispose();
    runner = create(idle: const Duration(milliseconds: 20));
    await runner.run(modelId: model.id, task: 'title');
    await _until(() => engine.unloads == 1);
    await runner.run(modelId: model.id, task: 'title');
    expect(engine.loads, 2);
  });

  test('switching helper models releases the previous weights', () async {
    runner.dispose();
    final other = ModelInfo(
      id: 'other',
      displayName: 'Other',
      fileName: model.fileName,
      sizeBytes: model.sizeBytes,
      family: model.family,
      quantization: model.quantization,
      isDownloaded: true,
      localPath: model.localPath,
    );
    runner = create(catalog: [model, other]);
    await runner.run(modelId: model.id, task: 'title');
    await runner.run(modelId: other.id, task: 'title');
    expect(engine.loads, 2);
    expect(engine.unloads, 1);
  });

  test(
    'loaded-model stream includes extra lanes and targeted eject unloads every matching lane',
    () async {
      runner.dispose();
      final other = model.copyWith(localPath: model.localPath);
      final second = _Engine()..gate = Completer<void>();
      _admitGpu(engine);
      engine.gate = Completer<void>();
      runner = create(catalog: [other], lanes: 2, extraEngine: () => second);
      final container = ProviderContainer(
        overrides: [helperRunnerProvider.overrideWithValue(runner)],
      );
      final sub = container.listen(helperLoadedModelsProvider, (_, _) {});
      final firstJob = runner.run(modelId: model.id, task: 'first');
      final secondJob = runner.run(modelId: model.id, task: 'second');
      await _until(() => engine.busy && second.busy);
      await _until(
        () =>
            container
                .read(helperLoadedModelsProvider)
                .value
                ?.contains(model.id) ==
            true,
      );
      expect(runner.loadedModelIds, {model.id});
      engine.gate!.complete();
      second.gate!.complete();
      await Future.wait([firstJob, secondJob]);
      await runner.unloadModel(model.id);
      await _until(
        () => container.read(helperLoadedModelsProvider).value?.isEmpty == true,
      );
      expect(engine.unloads, 1);
      expect(second.unloads, 1);
      expect(chat.unloads, 0);
      sub.close();
      container.dispose();
    },
  );

  test('free-memory path unloads both workers', () async {
    engine.loaded = true;
    chat.loaded = true;
    final container = ProviderContainer(
      overrides: [
        helperEngineProvider.overrideWithValue(engine),
        llamaEngineProvider.overrideWithValue(chat),
        modelManagerProvider.overrideWith(() => _Manager(model)),
      ],
    );
    try {
      await container.read(modelManagerProvider.notifier).unloadModel();
      expect(engine.unloads, 1);
      expect(chat.unloads, 1);
      expect(container.read(modelManagerProvider).loadedModelId, isNull);
    } finally {
      container.dispose();
    }
  });

  test(
    'publishes queued, loading, prefill, live text and final measurements',
    () async {
      engine.output = ['<thi', 'nk>working</think>', 'result'];
      engine.partDelay = const Duration(milliseconds: 45);
      final future = runner.run(
        modelId: model.id,
        task: 'Summarise',
        input: 'x' * 1500,
        messageId: 'answer',
      );
      await _until(() => jobs.read(helperJobsProvider).jobs.isNotEmpty);
      expect(phases, contains(HelperPhase.queued));
      await _until(
        () => jobs.read(helperJobsProvider).jobs.single.thinking == 'working',
      );
      final live = jobs.read(helperJobsProvider).jobs.single;
      expect(live.phase, HelperPhase.generating);
      expect(live.reply, isNull);
      expect(live.output, isNot(contains('<thi')));
      expect(live.tokens, greaterThan(0));
      final reply = await future;
      final done = jobs.read(helperJobsProvider).jobs.single;
      expect(
        phases,
        containsAllInOrder([
          HelperPhase.queued,
          HelperPhase.loadingModel,
          HelperPhase.prefill,
          HelperPhase.generating,
          HelperPhase.done,
        ]),
      );
      expect(done.reply, same(reply));
      expect(done.output, 'result');
      expect(done.thinking, 'working');
      expect(done.messageId, 'answer');
      expect(done.inputPreview.length, lessThan(1500));
      expect(done.tokens, 3);
      expect(done.promptTokens, 12);
      expect(done.prefill, isNotNull);
      expect(done.firstToken, isNotNull);
      expect(done.elapsed, greaterThanOrEqualTo(done.firstToken!));
      expect(engine.reportLiveMetrics, isFalse);
    },
  );

  test(
    'keeps two job identities while the second waits and retains dismissed results',
    () async {
      engine.gate = Completer<void>();
      final first = runner.run(
        modelId: model.id,
        task: 'first',
        messageId: 'a',
      );
      await _until(() => engine.busy);
      final second = runner.run(
        modelId: model.id,
        task: 'second',
        messageId: 'a',
      );
      await _until(() => jobs.read(helperJobsProvider).jobs.length == 2);
      final queued = jobs.read(helperJobsProvider);
      expect(queued.jobs.length, 2);
      expect(queued.jobs.map((j) => j.id).toSet().length, 2);
      expect(queued.jobs.last.phase, HelperPhase.queued);
      expect(queued.visible.length, 2);
      engine.gate!.complete();
      await Future.wait([first, second]);
      final notifier = jobs.read(helperJobsProvider.notifier);
      notifier.dismiss();
      expect(jobs.read(helperJobsProvider).visible, isEmpty);
      expect(
        jobs
            .read(helperJobsProvider)
            .jobs
            .every((j) => j.phase == HelperPhase.done),
        isTrue,
      );
      notifier.reopen(queued.visible);
      expect(jobs.read(helperJobsProvider).visible.length, 2);
      expect(jobs.read(helperJobsProvider).expanded, isTrue);
    },
  );

  test(
    'disposal cancels queued jobs and no terminal state is overwritten',
    () async {
      engine.gate = Completer<void>();
      final cancel = CancelToken();
      final first = runner.run(
        modelId: model.id,
        task: 'first',
        cancel: cancel,
      );
      final firstError = expectLater(first, throwsA(isA<HelperUnavailable>()));
      await _until(() => engine.busy);
      final second = runner.run(modelId: model.id, task: 'second');
      final secondError = expectLater(
        second,
        throwsA(isA<HelperUnavailable>()),
      );
      runner.dispose();
      await Future.wait([firstError, secondError]);
      await runner.unload();
      expect(jobs.read(helperJobsProvider).jobs.map((j) => j.phase), [
        HelperPhase.cancelled,
        HelperPhase.cancelled,
      ]);
      cancel.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        jobs
            .read(helperJobsProvider)
            .jobs
            .every((j) => j.phase == HelperPhase.cancelled),
        isTrue,
      );
    },
  );

  test(
    'provider keeps helper work off the chat context and unloads on disposal',
    () async {
      final wasDesktop = DesktopHost.active;
      DesktopHost.active = true;
      addTearDown(() => DesktopHost.active = wasDesktop);
      chat.loaded = true;
      // The app batches desktop agent jobs on the helper's own copy.
      final own = _SideEngine()..sideGate.complete();
      engine = own;
      final container = ProviderContainer(
        overrides: [
          helperEngineProvider.overrideWithValue(engine),
          llamaEngineProvider.overrideWithValue(chat),
          modelManagerProvider.overrideWith(() => _Manager(model)),
          modelRecommendationsProvider.overrideWith(_Recommendations.new),
        ],
      );
      await container
          .read(helperRunnerProvider)
          .run(modelId: model.id, task: 'title');
      expect(chat.prompts, isEmpty);
      expect(engine.loads, 1);
      // A helper left resident by an earlier job still belongs to the runner.
      engine.loaded = true;
      container.dispose();
      await _until(() => !engine.loaded);
      expect(chat.unloads, 0);
    },
  );
}
