import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/model_speed_results_provider.dart';
import 'package:ondevice_llm/desktop/model_speed_run.dart';
import 'package:ondevice_llm/desktop/model_speed_section.dart';
import 'package:ondevice_llm/desktop/model_tune_section.dart';
import 'package:ondevice_llm/desktop/benchmark_receipt.dart';
import 'package:ondevice_llm/desktop/tune_benchmark_run.dart';
import 'package:ondevice_llm/features/benchmark/benchmark.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'advanced_pages_2_test.dart' show TestModels, testModel;

class _Engine implements TextEngine {
  int calls = 0, tokens = 0;
  bool cancelled = false;
  Completer<void>? gate;
  final contexts = <int>[];
  @override
  Map<String, dynamic> get metrics => {
    'contextSize': 32768,
    'promptTokens': tokens,
    'tokens': 128,
    'firstTokenMs': 1000,
    'tokensPerSecond': 212,
    'backend': 'test backend',
    'nativeLibrary': 'libondevice_llm_test.so',
    'effectiveSettings': {'batchSize': 512, 'threads': 4},
    'draftAcceptRate': 0.75,
  };
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    tokens = (messages.first['content'] as String).split(' hello').length + 16;
    return {
      'promptTokens': tokens,
      'fits': tokens + settings.maxTokens < settings.contextSize,
    };
  }

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    expect(settings.promptCache, false);
    calls++;
    contexts.add(tokens);
    if (gate != null) await gate!.future;
    yield 'done';
  }

  @override
  void cancel() {
    cancelled = true;
    if (gate?.isCompleted == false) gate!.complete();
  }
}

const _sample = BenchmarkSample(
  prefillMs: 1000,
  decodeTps: 212,
  peakRssMb: 0,
  promptTokens: 512,
  generated: 128,
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'receipt measures three prompt classes, hashes output and captures effective settings',
    () async {
      final engine = _Engine();
      final receipts = <BenchmarkReceipt>[];
      final run = TuneBenchmarkRun(
        engine: engine,
        model: testModel,
        load: (_) async {},
        estimate: (_) async => {},
        save: (receipt) async {
          receipts.add(receipt);
        },
        draftFile: 'C:/models/mtp-head.gguf',
      );
      await run.benchmark(const InferenceSettings().toJson(), repetitions: 3);
      expect(engine.calls, 12);
      final receipt = receipts.single.json;
      expect(receipt['draftFile'], 'mtp-head.gguf');
      expect(receipt['sizeBytes'], testModel.sizeBytes);
      expect(receipt['sha256'], testModel.sha256);
      expect(receipt['quant'], 'Q4_K_M');
      expect(receipt['nativeLibrary'], 'libondevice_llm_test.so');
      expect(receipt['backend'], 'test backend');
      expect(receipt['effective'], {'batchSize': 512, 'threads': 4});
      final classes = receipt['promptClasses'] as Map;
      expect(classes.keys, ['short', 'longPrefill', 'code']);
      for (final stats in classes.values) {
        expect(stats['medianTokensPerSecond'], 212);
        expect(stats['spreadTokensPerSecond'], 0);
        expect(stats['medianTtftMs'], 1000);
        expect(stats['medianDraftAcceptance'], 0.75);
        expect(stats['rounds'], hasLength(3));
        expect(stats['rounds'][0]['outputHash'], benchmarkOutputHash('done'));
      }
      expect(
        (receipt['requested'] as Map).containsKey('remoteProfiles'),
        false,
      );
    },
  );
  testWidgets('receipts show measurements and a local JSON export action', (
    tester,
  ) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final receipts = c.read(benchmarkReceiptsProvider.notifier);
    await receipts.save(
      BenchmarkReceipt({
        'modelId': 'receipt-model',
        'timestamp': '2026-10-26',
        'modelFile': 'model.gguf',
        'backend': 'CPU',
        'promptClasses': {
          'short': BenchmarkReceipt.statistics([
            {'tokensPerSecond': 123, 'firstTokenMs': 200},
          ]),
        },
      }),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: BenchmarkReceiptSection(modelId: 'receipt-model'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Benchmark receipt · 2026-10-26'));
    await tester.pumpAndSettle();
    expect(find.text('Median tok/s'), findsOneWidget);
    expect(find.text('123.00'), findsOneWidget);
    expect(find.text('Export receipt to JSON'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'results save, reload and replace only the same model and load shape',
    () async {
      final c = ProviderContainer();
      final n = c.read(modelSpeedResultsProvider.notifier);
      await n.ready;
      final a = modelSpeedShape(const InferenceSettings());
      final b = modelSpeedShape(
        const InferenceSettings().copyWith(nGpuLayers: 3),
      );
      for (final (id, shape, day) in [
        ('a', a, 1),
        ('a', b, 2),
        ('b', a, 3),
        ('a', a, 4),
      ]) {
        await n.save(
          ModelSpeedResult(
            modelId: id,
            shape: shape,
            timestamp: DateTime(2026, 1, day),
            samples: const [_sample],
          ),
        );
      }
      expect(c.read(modelSpeedResultsProvider).length, 3);
      c.dispose();
      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      await restored.read(modelSpeedResultsProvider.notifier).ready;
      final values = restored.read(modelSpeedResultsProvider).values;
      expect(values.length, 3);
      expect(
        values
            .singleWhere((r) => r.modelId == 'a' && r.shape == a)
            .timestamp
            .day,
        4,
      );
      expect(values.first.samples.first.decodeTps, 212);
    },
  );
  test(
    'three fills use preview counts and cap below the loaded context',
    () async {
      for (final context in [1024, 32768]) {
        final engine = _Engine();
        final samples = await ModelSpeedRun(engine).run(
          settings: const InferenceSettings().copyWith(contextSize: context),
          template: '',
          progress: (_) {},
        );
        expect(engine.calls, 6);
        expect(samples.length, 3);
        expect(samples.first.promptTokens, closeTo(512, 8));
        expect(
          samples.last.promptTokens,
          closeTo(context == 1024 ? 880 : 16384, 8),
        );
        expect(engine.contexts.every((n) => n + 128 < context), true);
        expect(samples.last.prefillTps, samples.last.promptTokens);
      }
    },
  );
  testWidgets(
    'dialog speed section loads, shows progress, cancels and saves a complete run',
    (tester) async {
      final engine = _Engine()..gate = Completer<void>();
      var loads = 0;
      final c = ProviderContainer(
        overrides: [
          modelManagerProvider.overrideWith(TestModels.new),
          modelSpeedEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(c.dispose);
      await c.read(modelSpeedResultsProvider.notifier).ready;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Dialog(
                child: ModelSpeedSection(
                  model: testModel,
                  settings: const InferenceSettings(),
                  load: () async {
                    loads++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(c.read(sessionBusyProvider), true);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(engine.cancelled, true);
      expect(c.read(modelSpeedResultsProvider), isEmpty);
      expect(c.read(sessionBusyProvider), false);
      engine.gate = null;
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(c.read(modelSpeedResultsProvider).values.single.samples.length, 3);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('212 tok/s'), findsNWidgets(3));
      expect(c.read(sessionBusyProvider), false);
    },
  );
}
