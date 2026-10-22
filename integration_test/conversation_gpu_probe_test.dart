// Conversation speed with the model on the CPU or on the GPU (OpenCL), alone
// and while Kokoro speaks (tester, 2026-10-07: "let Kokoro use the GPU").
// Kokoro cannot: the shipped sherpa-onnx falls back to the CPU for NNAPI,
// QNN and WebGPU (kokoro_provider_probe_test). The model can, which leaves
// the CPU to Kokoro. Prints GPUCONV: JSON lines.
//
// Run through scripts/test-android.ps1 -Backend auto -Model <gemma gguf>
// -Family gemma -VoicePack -Test integration_test/conversation_gpu_probe_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');

void _report(Map<String, Object?> data) =>
    debugPrint('GPUCONV: ${jsonEncode(data)}');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'model on CPU or GPU while Kokoro speaks',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('GPU conversation probe'))),
      );
      expect(_modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
      final pack = Directory(
        '${(await getApplicationSupportDirectory()).path}/voice',
      );
      if (pack.existsSync()) {
        final models = await ModelStorage.modelsDir();
        for (final e in pack.listSync(recursive: true).whereType<File>()) {
          final to = File(
            '${models.path}/${e.path.substring(pack.path.length + 1)}',
          );
          if (to.existsSync() && to.lengthSync() == e.lengthSync()) continue;
          to.parent.createSync(recursive: true);
          e.copySync(to.path);
        }
      }
      final en = KokoroVoice.forLanguage('en');
      final voice = SherpaVoice();
      await voice.warmSpeaking(en);
      const sentence =
          'The sky looks blue because air scatters the short blue waves of '
          'sunlight more than the long red ones.';
      const messages = [
        {
          'role': 'system',
          'content':
              'You are a helpful assistant. Your answer is read aloud. Answer '
              'in three to five spoken sentences.',
        },
        {'role': 'user', 'content': 'How do airplanes stay in the air?'},
      ];

      for (final backend in [GpuBackend.cpu, GpuBackend.opencl]) {
        final settings = InferenceSettings(
          backend: backend,
          contextSize: 4096,
          maxTokens: 160,
          temperature: 0,
          promptCache: false,
        );
        final engine = LlamaEngine(
          cacheDirectory: () async =>
              (await getApplicationCacheDirectory()).path,
        );
        final load = Stopwatch()..start();
        await engine.loadModel(modelPath: _modelPath, settings: settings);
        final loadMs = load.elapsedMilliseconds;
        // Warm-up, then alone, then with Kokoro speaking without pause.
        await engine
            .generate(
              messages: messages,
              fallbackTemplate: '',
              settings: settings.copyWith(maxTokens: 8),
            )
            .join();
        for (final withVoice in [false, true]) {
          var speaking = withVoice;
          final synth = <int>[];
          final kokoro = () async {
            while (speaking) {
              final c = Stopwatch()..start();
              await voice.synthesize(sentence, voice: en);
              synth.add(c.elapsedMilliseconds);
            }
          }();
          final clock = Stopwatch()..start();
          int? firstMs;
          final out = StringBuffer();
          await for (final piece in engine.generate(
            messages: messages,
            fallbackTemplate: '',
            settings: settings,
          )) {
            firstMs ??= clock.elapsedMilliseconds;
            out.write(piece);
          }
          final totalMs = clock.elapsedMilliseconds;
          speaking = false;
          await kokoro;
          _report({
            'backend': backend.name,
            'kokoro': withVoice,
            'loadMs': loadMs,
            'firstMs': firstMs,
            'totalMs': totalMs,
            'chars': out.length,
            'charsPerSecond': (out.length * 1000 / (totalMs - (firstMs ?? 0)))
                .toStringAsFixed(1),
            'kokoroMs': synth,
            'metrics': {
              for (final e in engine.metrics.entries)
                if (e.value is num || e.value is String || e.value is bool)
                  e.key: e.value,
            },
          });
        }
        engine.dispose();
        // Let the worker release the model before the next load.
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      voice.dispose();
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
