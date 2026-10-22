// Stage-separated benchmark on a real model (roadmap §6.1 / BASE-01, PERF-01).
// Run through scripts/test-android.ps1 -Model <gguf> -Backend cpu|opencl
// -Test integration_test/native_bench_test.dart. Prints one BENCH: JSON line per
// thread count and prompt in the same shape as the in-app benchmark
// (BenchmarkResult.toJson: one discarded warm-up, medians of three samples,
// native effective settings, thermal zones before/after), plus `prompt`,
// `loadMs` and a text `sample`. The warm-up on a GPU backend includes kernel
// compilation; `loadMs` is the cold load for that thread count.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/core/device/thermal.dart';
import 'package:ondevice_llm/features/benchmark/benchmark.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real model benchmark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Benchmark'))),
    );
    const modelPath = String.fromEnvironment('BENCH_MODEL');
    const backendName = String.fromEnvironment(
      'SMOKE_BACKEND',
      defaultValue: 'cpu',
    );
    expect(modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    expect(await File(modelPath).exists(), true);
    final engine = LlamaEngine(
      cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    );
    addTearDown(engine.dispose);
    // Comma-separated thread counts to sweep, e.g. --dart-define=BENCH_THREADS=4,6,8
    const threadList = String.fromEnvironment(
      'BENCH_THREADS',
      defaultValue: '4',
    );
    final threadCounts = threadList
        .split(',')
        .map((t) => int.parse(t.trim()))
        .toList();
    // Batch / micro-batch overrides (0 = the app's auto values).
    const batch = int.fromEnvironment('BENCH_BATCH');
    const ubatch = int.fromEnvironment('BENCH_UBATCH');
    final base = InferenceSettings(
      backend: GpuBackend.values.byName(backendName),
      contextSize: 4096,
      maxTokens: 128,
      temperature: 0,
      batchSize: batch,
      microBatchSize: ubatch,
      thinkingModeEnabled: false,
    );
    final longUser = List.generate(
      40,
      (i) =>
          'Paragraph ${i + 1}: The committee reviewed the quarterly figures and noted that shipping costs rose while retention improved.',
    ).join(' ');
    final prompts = {
      'short': 'Explain in three sentences why the sky is blue.',
      'long': '$longUser\n\nSummarize the above in two sentences.',
    };
    final fileName = modelPath.split('/').last;
    final model = ModelInfo(
      id: fileName,
      displayName: fileName,
      fileName: fileName,
      sizeBytes: await File(modelPath).length(),
      family: ModelFamily.other,
      quantization: ModelQuantization.unknown,
      localPath: modelPath,
    );
    for (final threads in threadCounts) {
      final settings = base.copyWith(cpuThreads: threads);
      final loadWatch = Stopwatch()..start();
      await engine.loadModel(modelPath: modelPath, settings: settings);
      final loadMs = loadWatch.elapsedMilliseconds;
      for (final entry in prompts.entries) {
        final messages = [
          {'role': 'system', 'content': 'You are a concise assistant.'},
          {'role': 'user', 'content': entry.value},
        ];
        final thermalBefore = ThermalState.read();
        final samples = <BenchmarkSample>[];
        var text = '';
        const total = BenchmarkResult.warmUps + BenchmarkResult.samplesPerRun;
        for (var i = 0; i < total; i++) {
          text = await engine
              .generate(
                messages: messages,
                fallbackTemplate: '',
                // Prompt cache off: every sample evaluates the whole prompt.
                settings: settings.copyWith(promptCache: false),
              )
              .join();
          if (i >= BenchmarkResult.warmUps) {
            samples.add(BenchmarkSample.fromMetrics(engine.metrics));
          }
        }
        final result = BenchmarkResult.fromSamples(
          engine.metrics,
          samples,
          model: model,
          threads: settings.effectiveThreads,
          batchThreads: settings.effectiveBatchThreads,
          thermalBefore: thermalBefore,
          thermalAfter: ThermalState.read(),
        );
        // ignore: avoid_print
        print(
          'BENCH: ${jsonEncode({...result.toJson(), 'prompt': entry.key, 'loadMs': loadMs, 'sample': text.length > 80 ? text.substring(0, 80) : text})}',
        );
        expect(text.trim(), isNotEmpty);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
