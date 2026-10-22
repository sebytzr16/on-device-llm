import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/constants/app_constants.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/benchmark/benchmark.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart'
    show TestEngine, TestModels, TestSettings, ToolTestSettings, testModel;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a run folds the engine metrics into a persisted, shareable card',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = TestEngine();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      // Every generation reports slightly different numbers; the warm-up
      // (first) is the slowest and must not count.
      var generation = 0;
      // What each generation was asked (the engine keeps the last one).
      final asked = <List<Map<String, Object>>?>[];
      engine.beforeGenerate = () {
        asked.add(engine.receivedMessages);
        generation++;
        engine.metrics = {
          'backend': 'CPU (OpenCL available, not auto-selected)',
          'nativeLibrary': 'libondevice_llm_opencl.so',
          'contextSize': 4096,
          'promptTokens': 310,
          'tokens': 128,
          'firstTokenMs': generation == 1 ? 9000.0 : 2000.0 + generation * 100,
          'tokensPerSecond': generation == 1 ? 12.0 : 30.0 + generation,
          'peakRssMb': 2000.0 + generation,
          'effectiveSettings': {
            'threads': 6,
            'batchThreads': 8,
            'batchSize': 512,
            'microBatchSize': 512,
            'kvCacheType': 'f16',
            'vCacheType': 'f16',
            'flashAttentionPolicy': 'auto',
            'requestedGpuLayers': 0,
          },
        };
      };
      final result = await container
          .read(benchmarkProvider.notifier)
          .run(testModel);
      expect(result, isNotNull);
      asked
        ..removeAt(0)
        ..add(engine.receivedMessages);
      // The run asked for the fixed prompt with the prompt cache off.
      for (final messages in asked.take(4)) {
        expect(messages!.single['content'], BenchmarkNotifier.prompt);
      }
      // One warm-up plus three measured samples; medians, taken separately.
      // Then the chat row (tools are off in these settings).
      expect(generation, 5);
      final chat = asked.last!;
      expect(chat.first['role'], 'system');
      expect(
        chat.first['content'] as String,
        startsWith(AppConstants.defaultSystemPrompt),
      );
      expect(chat.last['content'], BenchmarkNotifier.chatQuestion);
      expect(result!.chat!.prefillMs, 2500.0);
      expect(result.chat!.decodeTps, 35.0);
      expect(result.chatTools, isNull);
      expect(result.samples, hasLength(3));
      expect(result.prefillMs, 2300.0);
      expect(result.decodeTps, 33.0);
      expect(result.peakRssMb, 2004.0);
      expect(result.library, 'ondevice_llm_opencl');
      expect(result.engine['threads'], 6);
      expect(
        result.engineSummary,
        'threads 6/8 · batch 512/512 · kv f16 · fa auto · gpu layers 0',
      );
      expect(container.read(benchmarkProvider).results['test'], isNotNull);
      expect(container.read(sessionBusyProvider), false);
      final card = result.card(device: 'Test phone');
      expect(card, contains('Model: Test'));
      expect(card, contains('Device: Test phone'));
      expect(card, contains('Engine: threads 6/8'));
      expect(
        card,
        contains(
          'Decode: 33.0 tok/s over 128 tokens (median of 3, first run discarded)',
        ),
      );
      expect(card, contains('Samples: 141/32.0, 135/33.0, 129/34.0 tok/s'));
      expect(card, contains('Chat: 310 tok · first token 2.50 s · 35.0 tok/s'));
      // Persisted for the next launch.
      final again = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
        ],
      );
      await again.read(benchmarkProvider.notifier).ready;
      expect(again.read(benchmarkProvider).results.keys, ['test']);
      final restored = again.read(benchmarkProvider).results['test']!;
      expect(restored.samples, hasLength(3));
      expect(restored.engine['kvCacheType'], 'f16');
      expect(restored.chat!.prefillMs, 2500.0);
      expect(restored.chatTools, isNull);
      again.dispose();
    },
  );

  test('with tools on, a second chat row adds the tool descriptions', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final engine = TestEngine();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(ToolTestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    var generation = 0;
    engine.beforeGenerate = () {
      generation++;
      engine.metrics = {
        'promptTokens': generation == 6 ? 944 : 310,
        'tokens': 128,
        'firstTokenMs': generation == 6 ? 4850.0 : 2000.0,
        'tokensPerSecond': 27.6,
      };
    };
    final result = await container
        .read(benchmarkProvider.notifier)
        .run(testModel);
    expect(generation, 6);
    final system = engine.receivedMessages!.first['content'] as String;
    // This engine takes no tool definitions: the text protocol and the
    // policy go into the system prompt, as in a chat.
    expect(system, startsWith(AppConstants.defaultSystemPrompt));
    expect(system, contains('search_web'));
    expect(system, contains('Use a tool whenever'));
    expect(engine.receivedTools, isEmpty);
    expect(result!.chatTools!.promptTokens, 944);
    expect(
      result.card(),
      contains('Chat + tools: 944 tok · first token 4.85 s · 27.6 tok/s'),
    );
  });

  test('median and thermal summary', () {
    expect(median([]), 0);
    expect(median([3, 1, 2]), 2);
    expect(median([4, 1, 3, 2]), 2.5);
    final r = BenchmarkResult.fromSamples(
      const {'backend': 'CPU'},
      const [
        BenchmarkSample(
          prefillMs: 100,
          decodeTps: 10,
          peakRssMb: 1,
          promptTokens: 10,
          generated: 5,
        ),
      ],
      model: testModel,
      threads: 4,
      batchThreads: 4,
      thermalBefore: const {'cpu-0-0': 38.5, 'battery': 31.0},
      thermalAfter: const {'cpu-0-0': 47.2, 'battery': 32.0},
    );
    expect(r.thermalSummary, 'cpu-0-0 38.5 → 47.2°C');
    expect(r.card(), contains('Thermal: cpu-0-0 38.5 → 47.2°C'));
    expect(r.card(), isNot(contains('median of')));
    final back = BenchmarkResult.fromJson(r.toJson());
    expect(back.thermalAfter, {'cpu-0-0': 47.2, 'battery': 32.0});
    expect(back.toJson(), r.toJson());
  });

  test('metrics without numbers still produce a result', () {
    final r = BenchmarkResult.fromMetrics(
      const {'backend': 'CPU (OpenCL available, not auto-selected)'},
      model: testModel,
      threads: 6,
      batchThreads: 8,
    );
    expect(r.backend, 'CPU');
    expect(r.prefillTps, 0);
    expect(BenchmarkResult.fromJson(r.toJson()).toJson(), r.toJson());
  });
}
