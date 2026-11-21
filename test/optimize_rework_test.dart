import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/model_tune_section.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/optimize/model_speed_engine_provider.dart';
import 'package:ondevice_llm/features/optimize/optimize_controller.dart';
import 'package:ondevice_llm/features/optimize/optimize_setups.dart';
import 'package:ondevice_llm/features/optimize/optimized_models_provider.dart';
import 'package:ondevice_llm/features/optimize/tune_benchmark_run.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_pages_2_test.dart' show TestModels, TestSettings, testModel;

const _current = InferenceSettings(
  kvCacheType: KvCacheType.q8_0,
  nGpuLayers: 3,
  flashAttention: false,
  batchSize: 2048,
  cpuThreads: 12,
  temperature: 0.4,
  draftModelId: 'old-draft',
);

Map<String, dynamic> _estimate(InferenceSettings s) => {
  'layers': 24,
  'gpuLayers': s.nGpuLayers.clamp(0, 24),
  'ramNeedMb': 2048,
  'ramAvailableMb': 16384,
  'vramNeedMb': 1000 + s.nGpuLayers.clamp(0, 24) * 200,
  'vramFreeMb': 5000,
};

class _Estimator extends LlamaEngine {
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => _estimate(settings);
}

/// A bridge whose estimate always fails: Optimize must still measure.
class _BrokenEstimator extends LlamaEngine {
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => throw StateError('Estimator unavailable');
}

/// A working estimate that places every setup far over the machine's memory.
class _OverBudgetEstimator extends LlamaEngine {
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => {
    'layers': 24,
    'gpuLayers': settings.nGpuLayers.clamp(0, 24),
    'ramNeedMb': 64000,
    'ramAvailableMb': 8192,
    'ramTotalMb': 8192,
    'vramNeedMb': 9000,
    'vramFreeMb': 4000,
  };
}

/// An estimate that cancels the run while it answers the planning probes.
class _CancellingEstimator extends LlamaEngine {
  _CancellingEstimator(this.onEstimate);
  final void Function() onEstimate;

  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    onEstimate();
    return _estimate(settings);
  }
}

class _Models extends TestModels {
  final loads = <InferenceSettings>[];

  /// The model each load was for, in the same order as [loads].
  final loadIds = <String>[];
  int stopLoads = 0;
  void Function(InferenceSettings)? onLoad;

  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
    void Function()? onLoadStart,
    bool vision = false,
  }) async {
    final s = settings!;
    loads.add(s);
    loadIds.add(info.id);
    onLoad?.call(s);
  }

  @override
  void stopLoad() => stopLoads++;
}

const _otherModel = ModelInfo(
  id: 'other',
  displayName: 'Other Model',
  fileName: 'other.gguf',
  sizeBytes: 80,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: 'other.gguf',
);

/// The settings the other model was loaded with before the run.
const _otherSettings = InferenceSettings(
  contextSize: 4096,
  nGpuLayers: 9,
  kvCacheType: KvCacheType.fp16,
);

/// A manager that keeps its own loaded-model state in step with the loads and
/// unloads a run makes, so the restore path is checked against the runtime
/// rather than the run's record of its last load.
class _TrackingModels extends _Models {
  _TrackingModels({this.loaded = true, this.before, this.beforeSettings});

  /// Whether any model is loaded at all.
  final bool loaded;

  /// The loaded model when it is not [testModel] itself.
  final ModelInfo? before;
  final InferenceSettings? beforeSettings;

  @override
  ModelManagerState build() {
    // TestModels sets `ready`; a model the user never loaded starts unloaded.
    final base = super.build();
    final catalog = before == null ? base.catalog : [...base.catalog, before!];
    return ModelManagerState(
      catalog: catalog,
      loadedModelId: loaded ? before?.id ?? testModel.id : null,
    );
  }

  @override
  ChatLoad? get loadedConfig {
    final model = before;
    if (model == null) return null;
    return (
      modelId: model.id,
      modelPath: model.localPath!,
      settings: beforeSettings ?? const InferenceSettings(),
      mmprojPath: null,
      draftModelPath: null,
      adapters: const [],
    );
  }

  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
    void Function()? onLoadStart,
    bool vision = false,
  }) async {
    await super.loadModel(
      info,
      forChat: forChat,
      settings: settings,
      onLoadStart: onLoadStart,
      vision: vision,
    );
    state = state.copyWith(loadedModelId: info.id);
  }

  @override
  Future<void> unloadModel({bool ownsBusy = false}) async {
    state = state.copyWith(clearLoaded: true);
  }
}

class _Engine extends Fake implements TextEngine {
  Completer<void>? gate;
  bool changeOutput = false;
  int calls = 0;
  @override
  Map<String, dynamic> get metrics => {
    'contextSize': 32768,
    'promptTokens': 32,
    'tokens': 128,
    'firstTokenMs': 100,
    'tokensPerSecond': 200,
  };
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => {'promptTokens': 32, 'fits': true};
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    calls++;
    if (gate != null) await gate!.future;
    yield changeOutput && settings.nGpuLayers > 3
        ? 'changed answer'
        : 'A seed absorbs water and grows roots toward sunlight.';
  }

  @override
  void cancel() {
    if (gate?.isCompleted == false) gate!.complete();
  }
}

class _Settings extends TestSettings {
  @override
  InferenceSettings build() {
    super.build();
    return _current;
  }
}

ProviderContainer _container({
  bool mobile = false,
  bool generating = false,
  TextEngine? engine,
  LlamaEngine? estimator,
  Duration? budget,
  DateTime Function()? clock,
  _Models Function()? models,
}) {
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_Settings.new),
      modelManagerProvider.overrideWith(models ?? _Models.new),
      llamaEstimatorProvider.overrideWithValue(estimator ?? _Estimator()),
      modelSpeedEngineProvider.overrideWithValue(engine ?? _Engine()),
      optimizeGeneratingProvider.overrideWithValue(() => generating),
      optimizeMobileProvider.overrideWithValue(mobile),
      if (budget != null) optimizeRunBudgetProvider.overrideWithValue(budget),
      if (clock != null) optimizeClockProvider.overrideWithValue(clock),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 1. The start path answers with the reason it could not start.
  for (final (generating, busyReason) in [
    (true, OptimizeBusyReason.generating),
    (false, OptimizeBusyReason.otherRun),
  ]) {
    test(
      'a busy session reports why Optimize did not start: ${busyReason.name}',
      () async {
        final c = _container(generating: generating);
        c.read(sessionBusyProvider.notifier).state = true;
        final provider = optimizeControllerProvider(testModel.id);
        await c.read(provider.notifier).start(testModel, _current);
        final state = c.read(provider);
        expect(state.running, isFalse);
        expect(state.busy, busyReason);
        expect(
          (c.read(modelManagerProvider.notifier) as _Models).loads,
          isEmpty,
        );
        expect(c.read(sessionBusyProvider), isTrue);
      },
    );
  }

  test('a model without a local file reports that it is not loaded', () async {
    final c = _container();
    final provider = optimizeControllerProvider(testModel.id);
    const missing = ModelInfo(
      id: 'test',
      displayName: 'Test Model',
      fileName: 'test.gguf',
      sizeBytes: 100,
      family: ModelFamily.qwen,
      quantization: ModelQuantization.q4_k_m,
    );
    await c.read(provider.notifier).start(missing, _current);
    expect(c.read(provider).busy, OptimizeBusyReason.notLoaded);
  });

  testWidgets('the section explains a busy start and disables its entry', (
    tester,
  ) async {
    final c = _container(generating: true);
    c.read(sessionBusyProvider.notifier).state = true;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: ModelOptimizeSection(model: testModel, settings: _current),
          ),
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('desktop-optimize')),
    );
    expect(button.onPressed, isNull);
    await c
        .read(optimizeControllerProvider(testModel.id).notifier)
        .start(testModel, _current);
    await tester.pump();
    expect(find.byKey(const Key('desktop-optimize-busy')), findsOneWidget);
    expect(
      find.text(AppLocalizationsEn().optimizeBusyGenerating),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-start no longer bypasses the busy entry', (tester) async {
    final c = _container(generating: true);
    c.read(sessionBusyProvider.notifier).state = true;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: ModelOptimizeSection(
              model: testModel,
              settings: _current,
              autoStart: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect((c.read(modelManagerProvider.notifier) as _Models).loads, isEmpty);
    expect(find.byKey(const Key('desktop-optimize-busy')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 2. The plan never dies before a measurement.
  test('a missing layer estimate falls back to a safe setup', () async {
    final plan = await pcOptimizationPlan(
      current: _current,
      defaults: const InferenceSettings(),
      estimate: (_) async => <String, dynamic>{},
    );
    expect(plan.unfit, isNull);
    expect(plan.settings.nGpuLayers, 0);
    expect(plan.settings.batchSize, lessThanOrEqualTo(256));
    expect(plan.settings.effectiveMicroBatchSize, lessThanOrEqualTo(128));
  });

  test('a failing estimator does not stop the plan', () async {
    final plan = await pcOptimizationPlan(
      current: _current,
      defaults: const InferenceSettings(),
      estimate: (_) async => throw StateError('no bridge'),
    );
    expect(plan.unfit, isNull);
    expect(plan.settings.nGpuLayers, 0);
  });

  test(
    'nothing fitting reports the short memory but still returns a setup',
    () async {
      final plan = await pcOptimizationPlan(
        current: _current,
        defaults: const InferenceSettings(),
        estimate: (s) async => {
          'layers': 24,
          'gpuLayers': s.nGpuLayers.clamp(0, 24),
          'ramNeedMb': 64000,
          'ramAvailableMb': 8192,
          'ramTotalMb': 8192,
          'vramNeedMb': 9000,
          'vramFreeMb': 4000,
        },
      );
      expect(plan.unfit, OptimizeUnfit.ram);
      expect(plan.settings.nGpuLayers, 0);
      expect(plan.settings.kvCacheType, KvCacheType.q8_0);
    },
  );

  test('a run whose estimate is broken still measures', () async {
    final c = _container(estimator: _BrokenEstimator());
    final provider = optimizeControllerProvider(testModel.id);
    await c.read(provider.notifier).start(testModel, _current);
    final state = c.read(provider);
    expect(state.failed, isFalse);
    expect(state.saved || state.kept != null, isTrue);
    expect(
      (c.read(modelManagerProvider.notifier) as _Models).loads,
      isNotEmpty,
    );
  });

  test(
    'a real estimate that nothing fits loads only the user\'s own settings back',
    () async {
      final models = _TrackingModels();
      final c = _container(
        models: () => models,
        estimator: _OverBudgetEstimator(),
      );
      final provider = optimizeControllerProvider(testModel.id);
      await c.read(provider.notifier).start(testModel, _current);
      final state = c.read(provider);
      expect(state.failed, isFalse);
      expect(state.saved, isFalse);
      expect(state.unfit, OptimizeUnfit.ram);
      // Over-budget settings are not loaded to "measure anyway": the exhausted
      // estimate is a fact, and the load could end the process on a phone.
      // The planning estimates unloaded the model, so the only load is the
      // user's own settings put back, exactly once (review #6).
      expect(models.loads, hasLength(1));
      expect(models.loads.single.nGpuLayers, _current.nGpuLayers);
      expect(models.loads.single.kvCacheType, _current.kvCacheType);
      expect(models.loads.single.contextSize, _current.contextSize);
      expect(c.read(modelManagerProvider).loadedModelId, testModel.id);
      expect(c.read(sessionBusyProvider), isFalse);
    },
  );

  test('the plan stops estimating past the run deadline', () async {
    var calls = 0;
    final plan = await pcOptimizationPlan(
      current: _current,
      defaults: const InferenceSettings(),
      estimate: (s) async {
        calls++;
        return _estimate(s);
      },
      outOfTime: () => true,
    );
    expect(calls, 0);
    expect(plan.unfit, isNull);
  });

  // 3. One deadline for the whole run.
  test('a sample started after the deadline never loads', () async {
    var loads = 0;
    final run = TuneBenchmarkRun(
      engine: _Engine(),
      model: testModel,
      load: (_) async => loads++,
      estimate: (_) async => <String, dynamic>{},
      save: (_) async {},
      deadline: DateTime.utc(2026, 1, 1),
      now: () => DateTime.utc(2026, 1, 2),
    );
    await expectLater(
      run.benchmark(_current.toJson()),
      throwsA(isA<OptimizeBudgetExhausted>()),
    );
    expect(loads, 0);
  });

  test('the deadline covers screening too and writes no profile', () async {
    final c = _container(budget: Duration.zero);
    final provider = optimizeControllerProvider(testModel.id);
    await c.read(provider.notifier).start(testModel, _current);
    final state = c.read(provider);
    expect(state.failure, OptimizeFailure.measurement);
    expect(state.saved, isFalse);
    expect(c.read(modelProfilesProvider.notifier).of(testModel.id), isEmpty);
    expect(c.read(sessionBusyProvider), isFalse);
    expect(await c.read(optimizedModelsProvider.future), isEmpty);
  });

  test('progress follows the clock while a load runs', () async {
    final base = DateTime.utc(2026, 1, 1);
    var ticks = 0;
    final c = _container(
      engine: _Engine()..gate = Completer<void>(),
      budget: const Duration(minutes: 60),
      clock: () => base.add(Duration(minutes: ticks++)),
    );
    final provider = optimizeControllerProvider(testModel.id);
    final run = c.read(provider.notifier).start(testModel, _current);
    for (var i = 0; i < 500 && (c.read(provider).progress ?? 0) <= 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final running = c.read(provider);
    expect(running.running, isTrue);
    expect(running.progress, greaterThan(0));
    c.read(provider.notifier).cancel();
    await run;
    expect(c.read(provider).running, isFalse);
  });

  test('cancel during planning loads the pre-run model back once', () async {
    final models = _TrackingModels();
    OptimizeController? controller;
    final c = _container(
      models: () => models,
      estimator: _CancellingEstimator(() => controller?.cancel()),
    );
    final provider = optimizeControllerProvider(testModel.id);
    controller = c.read(provider.notifier);
    await controller!.start(testModel, _current);
    expect(models.stopLoads, greaterThanOrEqualTo(1));
    expect(c.read(provider).running, isFalse);
    expect(c.read(sessionBusyProvider), isFalse);
    // The planning estimates emptied the runtime before the run was
    // cancelled, so the model the chat had loaded is loaded back exactly
    // once, with its own settings (review #1, #6).
    expect(models.loads, hasLength(1));
    expect(models.loads.single.nGpuLayers, _current.nGpuLayers);
    expect(models.loads.single.contextSize, _current.contextSize);
    expect(c.read(modelManagerProvider).loadedModelId, testModel.id);
  });

  test(
    'a run that keeps the settings puts the user\'s settings back',
    () async {
      final models = _Models();
      final c = _container(
        engine: _Engine()..changeOutput = true,
        models: () => models,
      );
      final provider = optimizeControllerProvider(testModel.id);
      await c.read(provider.notifier).start(testModel, _current);
      final state = c.read(provider);
      expect(state.kept, OptimizeKeepReason.outputChanged);
      expect(state.saved, isFalse);
      // The last sample loaded a measured setup; the chat's model must not stay
      // on it just because nothing was saved.
      expect(models.loads.last.nGpuLayers, _current.nGpuLayers);
      expect(models.loads.last.kvCacheType, _current.kvCacheType);
      expect(models.loads.last.temperature, _current.temperature);
      expect(models.loads.last.promptCache, _current.promptCache);
      // One restore load, not two.
      expect(
        models.loads.where((s) => s.temperature == _current.temperature).length,
        1,
      );
    },
  );

  test('a cancelled run never leaves a measured setup loaded', () async {
    final models = _Models();
    final c = _container(models: () => models);
    final provider = optimizeControllerProvider(testModel.id);
    // Cancel as soon as a measured setup (not the user's own settings) is
    // loaded, as a user closing the page mid-run does.
    models.onLoad = (s) {
      if (s.nGpuLayers != _current.nGpuLayers) {
        c.read(provider.notifier).cancel();
      }
    };
    await c.read(provider.notifier).start(testModel, _current);
    expect(c.read(provider).running, isFalse);
    expect(c.read(provider).saved, isFalse);
    expect(models.loads.last.nGpuLayers, _current.nGpuLayers);
    expect(models.loads.last.temperature, _current.temperature);
  });

  test(
    'a run that stops before its first sample loads the model back',
    () async {
      final models = _TrackingModels();
      final c = _container(
        models: () => models,
        estimator: _OverBudgetEstimator(),
      );
      final provider = optimizeControllerProvider(testModel.id);
      await c.read(provider.notifier).start(testModel, _current);
      final state = c.read(provider);
      // The planning estimates unloaded the model, then the run stopped because
      // nothing fit: no benchmark ever loaded it again, so the runtime is empty
      // and the user's settings must be loaded back (review #1).
      expect(state.unfit, OptimizeUnfit.ram);
      expect(state.failed, isFalse);
      expect(models.loads, hasLength(1));
      expect(models.loads.single.nGpuLayers, _current.nGpuLayers);
      expect(models.loads.single.kvCacheType, _current.kvCacheType);
      expect(c.read(modelManagerProvider).loadedModelId, testModel.id);
    },
  );

  test('a run on a model that was not loaded leaves it unloaded', () async {
    final models = _TrackingModels(loaded: false);
    final c = _container(
      models: () => models,
      engine: _Engine()..changeOutput = true,
    );
    final provider = optimizeControllerProvider(testModel.id);
    await c.read(provider.notifier).start(testModel, _current);
    expect(c.read(provider).kept, OptimizeKeepReason.outputChanged);
    // The benchmark loaded the model for its last sample; the user never had
    // it loaded, so the run must free it again instead of holding RAM with
    // the measured setup (review #2).
    expect(models.loads, isNotEmpty);
    expect(c.read(modelManagerProvider).loadedModelId, isNull);
  });

  test(
    'a run on an unloaded model restores the model the chat had loaded',
    () async {
      final models = _TrackingModels(
        before: _otherModel,
        beforeSettings: _otherSettings,
      );
      final c = _container(
        models: () => models,
        engine: _Engine()..changeOutput = true,
      );
      final provider = optimizeControllerProvider(testModel.id);
      await c.read(provider.notifier).start(testModel, _current);
      expect(c.read(provider).kept, OptimizeKeepReason.outputChanged);
      // The benchmark measured testModel, but the chat's own model was the
      // loaded one: it is put back with its own settings, and testModel does
      // not stay loaded (review #1).
      expect(models.loadIds.where((id) => id == _otherModel.id), hasLength(1));
      expect(models.loadIds.last, _otherModel.id);
      expect(models.loads.last.contextSize, _otherSettings.contextSize);
      expect(models.loads.last.nGpuLayers, _otherSettings.nGpuLayers);
      expect(c.read(modelManagerProvider).loadedModelId, _otherModel.id);
    },
  );

  // 5. A save only claims the keys the platform keeps.
  test('the saved profile holds only the keys this platform stores', () {
    final winner = const InferenceSettings().copyWith(
      nGpuLayers: 12,
      kvCacheType: KvCacheType.q8_0,
      speculationMode: 'draft',
      draftModelId: 'draft',
      mtp: true,
      nCpuMoe: 2,
    );
    DesktopHost.active = false;
    addTearDown(() => DesktopHost.active = false);
    final phone = optimizeProfileChanges(winner);
    expect(phone['nGpuLayers'], 12);
    expect(phone['kvCacheType'], 'q8_0');
    // The effective V cache travels with the measured cache.
    expect(phone['vCacheType'], 'q8_0');
    for (final key in ['speculationMode', 'draftModelId', 'mtp', 'nCpuMoe']) {
      expect(phone.containsKey(key), isFalse, reason: key);
    }
    DesktopHost.active = true;
    expect(optimizeProfileChanges(winner)['speculationMode'], 'draft');
  });

  // 6. A run starts clean, releases the session and marks the model.
  test('a second run starts from a clean state', () async {
    final engine = _Engine()..changeOutput = true;
    final c = _container(engine: engine);
    final provider = optimizeControllerProvider(testModel.id);
    await c.read(provider.notifier).start(testModel, _current);
    final first = c.read(provider);
    expect(first.kept, OptimizeKeepReason.outputChanged);
    expect(await c.read(optimizedModelsProvider.future), {testModel.id});

    engine
      ..changeOutput = false
      ..gate = Completer<void>();
    final run = c.read(provider.notifier).start(testModel, _current);
    await Future<void>.delayed(Duration.zero);
    final second = c.read(provider);
    expect(second.running, isTrue);
    expect(second.kept, isNull);
    expect(second.changes, isNull);
    expect(second.saved, isFalse);
    expect(second.failure, isNull);
    c.read(provider.notifier).cancel();
    await run;
  });

  test('disposing a running notifier releases the session', () async {
    final c = _container(engine: _Engine()..gate = Completer<void>());
    final seen = <bool>[];
    final watch = c.listen(
      sessionBusyProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    addTearDown(watch.close);
    final provider = optimizeControllerProvider(testModel.id);
    final run = c.read(provider.notifier).start(testModel, _current);
    await Future<void>.delayed(Duration.zero);
    expect(seen.last, isTrue);
    // Disposing the notifier (a scope going away) while its run is in flight.
    c.invalidate(provider);
    await run;
    expect(seen.last, isFalse);
  });

  test(
    'disposing an idle notifier leaves another task\'s lock alone',
    () async {
      final c = _container();
      final provider = optimizeControllerProvider(testModel.id);
      final watch = c.listen(provider, (_, next) {});
      addTearDown(watch.close);
      // A chat turn holds the session; Optimize never took it.
      c.read(sessionBusyProvider.notifier).state = true;
      c.invalidate(provider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionBusyProvider), isTrue);
    },
  );
}
