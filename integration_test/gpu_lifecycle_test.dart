// Separates full-prefill repeatability from cached-batch differences. Run with
// -Backend opencl -NoPromptCache to exercise cancellation/reload even when the
// original cache-enabled smoke equality assertion fails. That assertion stays.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';

import 'native_smoke_test.dart' as smoke;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'GPU fresh repeats and cache positions are independently checked',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('GPU cache diagnostic'))),
      );
      const path = String.fromEnvironment('SMOKE_MODEL');
      const settings = InferenceSettings(
        backend: GpuBackend.opencl,
        contextSize: 2048,
        maxTokens: 64,
        temperature: 0,
        cpuThreads: 4,
      );
      final engine = LlamaEngine(
        cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
      );
      addTearDown(engine.dispose);
      await engine.loadModel(modelPath: path, settings: settings);
      const messages = [
        {'role': 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content': 'Say hello in one sentence.'},
      ];
      Future<String> ask(bool cache) => engine
          .generate(
            messages: messages,
            fallbackTemplate: '',
            settings: settings.copyWith(promptCache: cache),
          )
          .join();
      final first = await ask(false);
      expect(engine.metrics['cachedPromptTokens'], 0);
      final repeated = await ask(false);
      expect(engine.metrics['cachedPromptTokens'], 0);
      final cached = await ask(true);
      final reused = engine.metrics['cachedPromptTokens'];
      expect(reused, (engine.metrics['promptTokens'] as num).toInt() - 1);
      final cachedAgain = await ask(true);
      final freshAfter = await ask(false);
      expect(engine.metrics['cachedPromptTokens'], 0);
      // Record before assertions so a failing control still leaves evidence.
      // ignore: avoid_print
      print(
        'GPU_CACHE_DIAGNOSTIC: ${jsonEncode({'fresh': first, 'freshRepeat': repeated, 'cached': cached, 'cachedAgain': cachedAgain, 'freshAfter': freshAfter, 'reusedTokens': reused, 'freshRepeatMatches': first == repeated, 'freshAfterMatches': first == freshAfter, 'cachedMatchesFresh': first == cached})}',
      );
      expect(first.trim(), isNotEmpty);
      expect(repeated, first);
      expect(freshAfter, first);
      expect(cached.trim(), isNotEmpty);
      expect(cachedAgain.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  smoke.main();
}
