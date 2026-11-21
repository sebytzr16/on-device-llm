import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/model_tune_section.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/optimize/benchmark_receipt.dart';
import 'package:ondevice_llm/features/optimize/model_speed_engine_provider.dart';
import 'package:ondevice_llm/features/optimize/model_tuner.dart';
import 'package:ondevice_llm/features/optimize/optimize_controller.dart';
import 'package:ondevice_llm/features/optimize/optimize_setups.dart';
import 'package:ondevice_llm/features/optimize/optimized_models_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'advanced_pages_2_test.dart' show TestModels, TestSettings, testModel;

final _stale = const InferenceSettings().copyWith(
  kvCacheType: KvCacheType.q8_0,
  vCacheType: KvCacheType.q4_0,
  nGpuLayers: 3,
  flashAttention: false,
  batchSize: 2048,
  cpuThreads: 12,
  temperature: 0.4,
  draftModelId: 'old-draft',
);

Map<String, dynamic> _estimate(InferenceSettings s) => {
  'layers': 24,
  'gpuLayers': s.nGpuLayers,
  'ramNeedMb': 2048,
  'ramAvailableMb': 16384,
  'vramNeedMb': 1000 + s.nGpuLayers * 200,
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

/// The current settings (an old draft model) no longer fit this PC.
class _UnfitEstimator extends _Estimator {
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => {
    ..._estimate(settings),
    if (settings.draftModelId == 'old-draft') 'ramNeedMb': 64000,
  };
}

class _IosEstimator extends _Estimator {
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
    'ramNeedMb': 2048,
    'ramAvailableMb': 0,
    'ramTotalMb': 0,
    'vramNeedMb': 0,
  };
}

class _FailReceipts extends BenchmarkReceipts {
  @override
  Future<void> save(BenchmarkReceipt receipt) async {
    throw StateError('Receipt disk unavailable');
  }
}

class _ProfileWriteStore extends InMemorySharedPreferencesStore {
  _ProfileWriteStore() : super.empty();

  bool failProfileWrite = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failProfileWrite && key == 'flutter.model_profiles_v1') return false;
    return super.setValue(valueType, key, value);
  }
}

class _Settings extends TestSettings {
  @override
  InferenceSettings build() {
    super.build();
    return _stale;
  }
}

class _Models extends TestModels {
  final loads = <InferenceSettings>[];
  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
    void Function()? onLoadStart,
    bool vision = false,
  }) async {
    loads.add(settings!);
  }
}

class _Engine extends Fake implements TextEngine {
  Completer<void>? gate;
  int calls = 0;
  InferenceSettings? measured;
  @override
  Map<String, dynamic> get metrics => {
    'contextSize': 32768,
    'promptTokens': 32,
    'tokens': 128,
    'firstTokenMs': 100,
    'tokensPerSecond': (measured?.nGpuLayers ?? 0) > 3 ? 200 : 100,
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
    measured = settings;
    if (gate != null) await gate!.future;
    yield output(settings);
  }

  String output(InferenceSettings settings) =>
      settings.kvCacheType == KvCacheType.q8_0
      ? 'A seed absorbs water and grows roots then leaves toward sunlight.'
      : 'A seed absorbs water and grows roots then leaves towards sunlight!';

  @override
  void cancel() {
    if (gate?.isCompleted == false) gate!.complete();
  }
}

/// Answers with different bytes once more GPU layers are used, like a setup
/// that changes sampling behavior instead of only speed.
class _ChangingEngine extends _Engine {
  @override
  String output(InferenceSettings settings) =>
      settings.nGpuLayers > 3 ? 'changed answer' : 'same answer';
}

/// Every generation fails: nothing can be measured, so the run reports a
/// measurement error instead of saving anything.
class _BrokenEngine extends _Engine {
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
    throw StateError('engine unavailable');
  }
}

class _RateRunner implements TuneRunner {
  final double rate;
  _RateRunner(this.rate);
  @override
  Future<bool> fits(TuneSettings settings) async => true;
  @override
  Future<TuneMeasurement> measure(TuneSettings settings) async =>
      TuneMeasurement(settings['setup'] == 0 ? 100 : rate, 'same');
  @override
  void cancel() {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'optimization resets hardware, keeps sampling and chooses maximum fitting F16 layers',
    () async {
      final result = await pcOptimizationDefaults(
        current: _stale,
        defaults: const InferenceSettings(),
        estimate: (s) async => _estimate(s),
      );
      final expected = ((5000 - 1000 - result.vramReserveMb) / 200).floor();
      expect(result.nGpuLayers, expected);
      expect(result.kvCacheType, KvCacheType.fp16);
      expect(result.flashAttention, isTrue);
      expect(result.draftModelId, isEmpty);
      expect(result.mtp, isFalse);
      expect(result.temperature, 0.4);
      expect(result.explicitOverrides, isNot(contains('kvCacheType')));
      expect(result.explicitOverrides, contains('temperature'));
    },
  );

  test(
    'a MoE whose fit moves experts to RAM keeps every layer asked for',
    () async {
      final result = await pcOptimizationDefaults(
        current: _stale,
        defaults: const InferenceSettings(),
        estimate: (s) async => s.nGpuLayers >= 999
            ? {..._estimate(s), 'gpuExpertsOnCpu': true, 'vramNeedMb': 3000}
            : _estimate(s),
      );
      expect(result.nGpuLayers, 999);
      expect(result.kvCacheType, KvCacheType.fp16);
    },
  );

  test(
    'every layer with a q8_0 cache wins over F16 with some layers (E4B)',
    () async {
      // Gemma 4 E4B on an 8 GB card: F16 fits 33 of 43 layers (16 tok/s),
      // q8_0 fits all 43 with the projector moved to RAM (101 tok/s).
      Map<String, dynamic> e4b(InferenceSettings s) {
        final f16 = s.kvCacheType == KvCacheType.fp16;
        final placed = s.nGpuLayers >= 999 ? (f16 ? 33 : 43) : s.nGpuLayers;
        return {
          'layers': 43,
          'gpuLayers': placed,
          'ramNeedMb': 2048,
          'ramAvailableMb': 16384,
          'vramNeedMb': 1000 + placed * (f16 ? 180 : 115),
          'vramFreeMb': 7100,
        };
      }

      final result = await pcOptimizationDefaults(
        current: _stale,
        defaults: const InferenceSettings(),
        estimate: (s) async => e4b(s),
      );
      expect(result.nGpuLayers, 999);
      expect(result.kvCacheType, KvCacheType.q8_0);
    },
  );

  test('setups try MTP off and a 3-token draft only with an MTP head', () {
    const best = InferenceSettings(batchSize: 512, cpuThreads: 8);
    final plain = pcOptimizationSetups(best);
    final mtp = pcOptimizationSetups(best, mtpHead: true);
    expect(mtp.length, plain.length + 2);
    expect(plain.map((s) => s.draftModelId), everyElement(best.draftModelId));
    expect(mtp.map((s) => s.draftModelId), contains('mtp:off'));
    expect(mtp.map((s) => s.draftMaxTokens), contains(3));
  });

  test(
    'optimization falls back when the estimate has no memory numbers',
    () async {
      final plan = await pcOptimizationPlan(
        current: _stale,
        defaults: const InferenceSettings(),
        estimate: (_) async => {'layers': 24},
      );
      expect(plan.unfit, isNull);
      expect(plan.settings.nGpuLayers, lessThanOrEqualTo(24));
      expect(plan.settings.temperature, _stale.temperature);
    },
  );

  test('optimization names the short memory when nothing fits', () async {
    final plan = await pcOptimizationPlan(
      current: _stale,
      defaults: const InferenceSettings(),
      estimate: (s) async => {
        ..._estimate(s),
        'ramNeedMb': 64000,
        'ramAvailableMb': 8192,
        'ramTotalMb': 8192,
      },
    );
    expect(plan.unfit, OptimizeUnfit.ram);
    expect(plan.settings.nGpuLayers, 0);
    expect(plan.settings.temperature, _stale.temperature);
  });

  test('Optimize accepts harmless divergence but rejects unrelated answers', () {
    const base = TuneMeasurement(
      100,
      'a',
      outputs: [
        'A seed absorbs water and grows roots then leaves toward sunlight.',
        'def fibonacci(n): return n if n < 2 else fibonacci(n-1) + fibonacci(n-2)',
      ],
    );
    const harmless = TuneMeasurement(
      110,
      'b',
      outputs: [
        'A seed absorbs water and grows roots then leaves towards sunlight!',
        'def fibonacci(n): return n if n < 2 else fibonacci(n-1) + fibonacci(n-2)',
      ],
    );
    expect(optimizeOutputAcceptable(base, harmless), isTrue);
    expect(
      optimizeOutputAcceptable(
        base,
        const TuneMeasurement(
          200,
          'c',
          outputs: ['Unrelated broken output', 'different code'],
        ),
      ),
      isFalse,
    );
    final settings = const InferenceSettings(kvCacheType: KvCacheType.fp16);
    expect(
      pickOptimizeWinner(
        reference: base.outputHash,
        baseline: base,
        runs: [(settings: settings, measurement: harmless)],
      )?.settings,
      settings,
    );
  });

  for (final rate in [102.0, 103.0, 104.0]) {
    test('Optimize requires more than 3% throughput gain: $rate', () async {
      final report = await ModelTuner(_RateRunner(rate), minimumGain: 0.03).run(
        initial: {'setup': 0},
        candidates: {
          'setup': [1],
        },
      );
      expect(report.changes.isNotEmpty, rate > 103);
    });
  }

  test(
    'pickOptimizeWinner only lets output-equivalent runs beat the baseline',
    () {
      const base = InferenceSettings(batchSize: 512);
      const draft = InferenceSettings(batchSize: 1024);
      TuneMeasurement m(String hash, double tok) => TuneMeasurement(tok, hash);
      final runs = [
        (settings: draft, measurement: m('candidate answer', 100)),
        (settings: base, measurement: m('original answer', 50)),
      ];
      // No baseline: a candidate cannot stand in for the original answers.
      expect(pickOptimizeWinner(reference: null, runs: runs), isNull);
      expect(pickOptimizeWinner(reference: '', runs: runs), isNull);
      // A baseline ('before') measurement: only runs matching its output can win,
      // even when they are slower.
      expect(
        pickOptimizeWinner(reference: 'original answer', runs: runs)?.settings,
        base,
      );
      expect(pickOptimizeWinner(reference: 'never', runs: runs), isNull);
      expect(pickOptimizeWinner(reference: null, runs: []), isNull);
    },
  );

  test('Q8 fallback is used only when F16 cannot fit even on CPU', () async {
    final result = await pcOptimizationDefaults(
      current: _stale,
      defaults: const InferenceSettings(),
      estimate: (s) async => {
        ..._estimate(s),
        'ramNeedMb': s.kvCacheType == KvCacheType.fp16 ? 20000 : 2048,
      },
    );
    expect(result.kvCacheType, KvCacheType.q8_0);
  });

  for (final enoughMemory in [true, false]) {
    test(
      'iOS Metal sweep uses the process budget (fits: $enoughMemory)',
      () async {
        final engine = _Engine();
        final c = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            modelManagerProvider.overrideWith(_Models.new),
            llamaEstimatorProvider.overrideWithValue(_IosEstimator()),
            modelSpeedEngineProvider.overrideWithValue(engine),
            optimizeIosProvider.overrideWithValue(true),
            optimizeDeviceMemoryProvider.overrideWithValue(
              () async => DeviceMemory(
                totalBytes: 8 << 30,
                availableBytes: (enoughMemory ? 3 : 2) << 30,
                lowMemory: false,
              ),
            ),
          ],
        );
        addTearDown(c.dispose);
        expect(c.read(optimizeMobileProvider), isTrue);
        final provider = optimizeControllerProvider(testModel.id);
        final original = _stale.copyWith(backend: GpuBackend.metal);
        await c.read(provider.notifier).start(testModel, original);
        final receipts = c.read(benchmarkReceiptsProvider);
        if (enoughMemory) {
          expect(c.read(provider).saved, isTrue);
          expect(engine.calls, greaterThan(0));
          expect(receipts.map((r) => r.json['modelId']).toSet(), {
            testModel.id,
          });
          final profile = c
              .read(modelProfilesProvider.notifier)
              .of(testModel.id);
          expect(profile['nGpuLayers'], 999);
          // Speculation is desktop-only: a phone profile never stores it.
          expect(profile.containsKey('speculationMode'), isFalse);
          expect(await c.read(optimizedModelsProvider.future), {testModel.id});
        } else {
          // A usable estimate that places every setup over budget is not
          // measured anyway: nothing is loaded over budget, and the section
          // names the short memory.
          final state = c.read(provider);
          expect(state.failed, isFalse);
          expect(state.unfit, OptimizeUnfit.ram);
          expect(state.saved, isFalse);
          expect(engine.calls, 0);
          expect(receipts, isEmpty);
        }
      },
    );
  }

  test(
    'Optimize reports receipt failure and logs the underlying error',
    () async {
      final logs = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(logs.add);
      addTearDown(subscription.cancel);
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          modelManagerProvider.overrideWith(_Models.new),
          llamaEstimatorProvider.overrideWithValue(_Estimator()),
          modelSpeedEngineProvider.overrideWithValue(_Engine()),
          benchmarkReceiptsProvider.overrideWith(_FailReceipts.new),
          optimizeMobileProvider.overrideWithValue(false),
        ],
      );
      addTearDown(c.dispose);
      final provider = optimizeControllerProvider(testModel.id);
      await c.read(provider.notifier).start(testModel, _stale);
      expect(c.read(provider).failure, OptimizeFailure.save);
      final log = logs.singleWhere((record) => record.loggerName == 'optimize');
      expect(log.error.toString(), contains('Receipt disk unavailable'));
      expect(log.stackTrace, isNotNull);
      expect(await c.read(optimizedModelsProvider.future), isEmpty);
    },
  );

  test(
    'a failed strict profile save keeps the profile and permits retry',
    () async {
      final previousStore = SharedPreferencesStorePlatform.instance;
      final store = _ProfileWriteStore();
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = previousStore,
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final profiles = c.read(modelProfilesProvider.notifier);
      await expectLater(
        profiles.set(testModel.id, {
          'nGpuLayers': 24,
        }, requirePersistence: true),
        throwsA(isA<ModelProfileSaveFailure>()),
      );
      expect(profiles.of(testModel.id), isEmpty);
      store.failProfileWrite = false;
      await profiles.set(testModel.id, {
        'nGpuLayers': 4,
      }, requirePersistence: true);
      expect(profiles.of(testModel.id), {'nGpuLayers': 4});
    },
  );

  testWidgets('iOS Optimize uses the phone label and description', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelManagerProvider.overrideWith(_Models.new),
          optimizeIosProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: ModelOptimizeSection(
              model: testModel,
              settings: InferenceSettings(),
            ),
          ),
        ),
      ),
    );
    final t = AppLocalizationsEn();
    expect(find.text(t.optimizeSettingsTitle), findsOneWidget);
    expect(
      find.text(t.optimizeSettingsHint(testModel.displayName)),
      findsOneWidget,
    );
    expect(find.text(t.desktopOptimize), findsNothing);
    expect(find.text(t.desktopOptimizeHint), findsNothing);
  });

  test(
    'Android controller uses the mobile sweep and records a kept run',
    () async {
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          modelManagerProvider.overrideWith(_Models.new),
          llamaEstimatorProvider.overrideWithValue(_Estimator()),
          modelSpeedEngineProvider.overrideWithValue(_Engine()),
          optimizeMobileProvider.overrideWithValue(true),
        ],
      );
      addTearDown(c.dispose);
      final provider = optimizeControllerProvider(testModel.id);
      final original = _stale.copyWith(backend: GpuBackend.cpu);
      c.read(sessionBusyProvider.notifier).state = true;
      await c.read(provider.notifier).start(testModel, original);
      expect(c.read(provider).running, isFalse);
      expect((c.read(modelManagerProvider.notifier) as _Models).loads, isEmpty);
      c.read(sessionBusyProvider.notifier).state = false;
      await c.read(provider.notifier).start(testModel, original);
      expect(c.read(provider).failed, isFalse);
      expect(c.read(provider).kept, isNotNull);
      expect(await c.read(optimizedModelsProvider.future), {testModel.id});
      final trials = (c.read(modelManagerProvider.notifier) as _Models).loads
          .where((s) => s.draftModelId != original.draftModelId);
      expect(trials, isNotEmpty);
      expect(
        trials.every(
          (s) =>
              s.nGpuLayers == 0 &&
              s.draftModelId.isEmpty &&
              s.nCpuMoe == -1 &&
              s.batchSize <= 512,
        ),
        isTrue,
      );
    },
  );

  for (final outcome in ['saved', 'kept', 'cancelled', 'failed']) {
    test('controller transitions and persistence: $outcome', () async {
      DesktopHost.active = true;
      addTearDown(() => DesktopHost.active = false);
      final engine = switch (outcome) {
        'kept' => _ChangingEngine(),
        'failed' => _BrokenEngine(),
        _ => _Engine(),
      };
      if (outcome == 'cancelled') engine.gate = Completer<void>();
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          modelManagerProvider.overrideWith(_Models.new),
          llamaEstimatorProvider.overrideWithValue(_Estimator()),
          modelSpeedEngineProvider.overrideWithValue(engine),
          optimizeMobileProvider.overrideWithValue(false),
        ],
      );
      addTearDown(c.dispose);
      final provider = optimizeControllerProvider(testModel.id);
      final states = <OptimizeState>[];
      final subscription = c.listen(
        provider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final controller = c.read(provider.notifier);
      final run = controller.start(testModel, _stale);
      expect(c.read(provider).running, isTrue);
      expect(c.read(sessionBusyProvider), isTrue);
      // A second start must not reset or duplicate an active run.
      await controller.start(testModel, _stale);
      if (outcome == 'cancelled') controller.cancel();
      await run;
      final result = c.read(provider);
      expect(result.running, isFalse);
      expect(result.progress, isNull);
      expect(result.step, isNull);
      expect(result.failed, outcome == 'failed');
      expect(result.saved, outcome == 'saved');
      expect(result.kept != null, outcome == 'kept');
      expect(c.read(sessionBusyProvider), isFalse);
      final loads = (c.read(modelManagerProvider.notifier) as _Models).loads;
      // A run cancelled before its first sample never loads the model: a
      // cancel must not start a multi-gigabyte load.
      if (outcome != 'cancelled') expect(loads, isNotEmpty);
      // Benchmarks force temperature 0 and no prompt cache; a load with the
      // user's own sampling is the restore of the chat's model. A kept or
      // failed run must not leave the last measured setup loaded, a saved run
      // keeps the winner (the new profile), and a cancel loaded nothing.
      final restores = loads
          .where((s) => s.promptCache && s.temperature == _stale.temperature)
          .toList();
      if (outcome == 'saved') {
        final profile = c.read(modelProfilesProvider.notifier).of(testModel.id);
        expect(loads.last.nGpuLayers, profile['nGpuLayers']);
        expect(loads.last.kvCacheType.name, profile['kvCacheType']);
      } else if (outcome == 'kept' || outcome == 'failed') {
        expect(restores, hasLength(1));
        expect(restores.single.nGpuLayers, _stale.nGpuLayers);
      } else {
        expect(loads, isEmpty);
      }
      expect(
        await c.read(optimizedModelsProvider.future),
        outcome == 'saved' || outcome == 'kept' ? {testModel.id} : isEmpty,
      );
      expect(states.first.running, isFalse);
      expect(states.any((s) => s.running), isTrue);
      expect(
        states
            .where((s) => s.progress != null)
            .every((s) => s.progress! >= 0 && s.progress! <= 1),
        isTrue,
      );
    });
  }

  for (final cancel in [false, true]) {
    testWidgets(
      'Optimize button ${cancel ? 'cancels without saving' : 'measures and applies safe defaults'}',
      (tester) async {
        // Draft and MTP choices are desktop-only settings.
        DesktopHost.active = true;
        addTearDown(() => DesktopHost.active = false);
        final engine = _Engine()..gate = Completer<void>();
        final c = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            modelManagerProvider.overrideWith(_Models.new),
            llamaEstimatorProvider.overrideWithValue(_Estimator()),
            modelSpeedEngineProvider.overrideWithValue(engine),
          ],
        );
        addTearDown(c.dispose);
        final profiles = c.read(modelProfilesProvider.notifier);
        await profiles.ready;
        await profiles.set('test', {'temperature': 0.25, 'nGpuLayers': 3});
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: DesktopTheme.of(AccentChoice.amber, dark: true),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ModelOptimizeSection(model: testModel, settings: _stale),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(engine.calls, 0);
        expect(c.read(settingsProvider).kvCacheType, KvCacheType.q8_0);
        await tester.tap(find.byKey(const Key('desktop-optimize')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(c.read(sessionBusyProvider), isTrue);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        if (cancel) {
          await tester.tap(find.text(AppLocalizationsEn().tuneCancel));
        } else {
          engine.gate!.complete();
        }
        await tester.pumpAndSettle();
        expect(c.read(sessionBusyProvider), isFalse);
        final model = profiles.of('test');
        expect(model['temperature'], 0.25);
        if (cancel) {
          expect(model['nGpuLayers'], 3);
          expect(c.read(settingsProvider).kvCacheType, KvCacheType.q8_0);
        } else {
          expect(model['nGpuLayers'], greaterThan(3));
          expect(model['kvCacheType'], 'fp16');
          expect(model['vCacheType'], 'fp16');
          expect(model['flashAttention'], isTrue);
          expect(model['draftModelId'], '');
          final loaded =
              (c.read(modelManagerProvider.notifier) as _Models).loads.last;
          expect(loaded.kvCacheType, KvCacheType.fp16);
          expect(loaded.nGpuLayers, model['nGpuLayers']);
          expect(
            find.textContaining('kvCacheType: q8_0 -> fp16'),
            findsOneWidget,
          );
          final global = c.read(settingsProvider);
          // The winner goes to this model's profile only: the app-wide
          // choices other models use are kept (audit P1-13).
          expect(global.explicitOverrides, contains('kvCacheType'));
          expect(global.kvCacheType, KvCacheType.q8_0);
          expect(global.vCacheType, KvCacheType.q4_0);
          expect(global.explicitOverrides, contains('temperature'));
          expect(find.textContaining('Before: 100.0'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Optimize keeps the current settings when no setup keeps their answer',
    (tester) async {
      final engine = _ChangingEngine();
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          modelManagerProvider.overrideWith(_Models.new),
          llamaEstimatorProvider.overrideWithValue(_Estimator()),
          modelSpeedEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(c.dispose);
      final profiles = c.read(modelProfilesProvider.notifier);
      await profiles.ready;
      await profiles.set('test', {'temperature': 0.25, 'nGpuLayers': 3});
      final before = Map<String, dynamic>.of(profiles.of('test'));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ModelOptimizeSection(model: testModel, settings: _stale),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('desktop-optimize')));
      await tester.pumpAndSettle();
      expect(c.read(sessionBusyProvider), isFalse);
      // The baseline matched no candidate, so nothing was saved.
      expect(profiles.of('test'), before);
      final reason = tester.widget<Text>(
        find.byKey(const Key('desktop-optimize-kept-reason')),
      );
      expect(reason.data, AppLocalizationsEn().desktopOptimizeKeptOutput);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Optimize saves the safe setup when the current settings do not fit',
    (tester) async {
      DesktopHost.active = true;
      addTearDown(() => DesktopHost.active = false);
      final engine = _Engine();
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          modelManagerProvider.overrideWith(_Models.new),
          llamaEstimatorProvider.overrideWithValue(_UnfitEstimator()),
          modelSpeedEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(c.dispose);
      final profiles = c.read(modelProfilesProvider.notifier);
      await profiles.ready;
      await profiles.set('test', {'temperature': 0.25, 'nGpuLayers': 3});
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ModelOptimizeSection(model: testModel, settings: _stale),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('desktop-optimize')));
      await tester.pumpAndSettle();
      expect(c.read(sessionBusyProvider), isFalse);
      final model = profiles.of('test');
      expect(model['temperature'], 0.25);
      expect(model['kvCacheType'], 'fp16');
      expect(model['draftModelId'], '');
      expect(model['nGpuLayers'], greaterThan(3));
      expect(
        find.byKey(const Key('desktop-optimize-kept-reason')),
        findsNothing,
      );
      final loaded =
          (c.read(modelManagerProvider.notifier) as _Models).loads.last;
      expect(loaded.draftModelId, '');
      expect(tester.takeException(), isNull);
    },
  );
}
