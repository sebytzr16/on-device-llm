import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real GGUF generates, repeats independently, cancels and reloads',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Native inference test'))),
      );
      const modelPath = String.fromEnvironment(
        'SMOKE_MODEL',
        defaultValue:
            '/data/user/0/app.ondevicellm.ondevice_llm/files/smollm2.gguf',
      );
      expect(
        await File(modelPath).exists(),
        true,
        reason: 'Run scripts/test-android.ps1 to provision the test model.',
      );
      final engine = LlamaEngine(
        cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
      );
      addTearDown(engine.dispose);
      // --dart-define=SMOKE_BACKEND=vulkan to exercise the GPU path.
      const backendName = String.fromEnvironment(
        'SMOKE_BACKEND',
        defaultValue: 'cpu',
      );
      final backend = GpuBackend.values.byName(backendName);
      const promptCache = bool.fromEnvironment(
        'SMOKE_PROMPT_CACHE',
        defaultValue: true,
      );
      final settings = InferenceSettings(
        backend: backend,
        contextSize: 2048,
        maxTokens: 64,
        temperature: 0,
        cpuThreads: 4,
        promptCache: promptCache,
      );
      // ignore: avoid_print
      print('NATIVE_SMOKE: loading model');
      await engine.loadModel(modelPath: modelPath, settings: settings);
      // ignore: avoid_print
      print('NATIVE_SMOKE: model loaded');
      expect(engine.isLoaded, true);
      final messages = [
        {'role': 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content': 'Say hello in one sentence.'},
      ];
      Future<String> generate() => engine
          .generate(
            messages: messages,
            fallbackTemplate: '',
            settings: settings,
          )
          .join();
      final preview = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: '',
        settings: settings,
      );
      expect(preview['fits'], true);
      expect(preview['reservedTokens'], 64);
      expect(preview['promptTokens'], greaterThan(0));
      expect(engine.metrics['abiVersion'], LlamaBindings.supportedAbi);
      // CPU-only releases retain optimized kernels without an OpenCL driver.
      // An explicit -Arch run deliberately tests the Gradle-built library.
      if (backend == GpuBackend.cpu) {
        const expectFast = bool.fromEnvironment('EXPECT_FAST_CPU');
        expect(
          engine.metrics['nativeLibrary'],
          expectFast && LlamaBindings.cpuHasI8mm()
              ? 'libondevice_llm_cpu_i8mm.so'
              : 'libondevice_llm.so',
        );
        expect(engine.metrics['nativeLibrarySkipped'], isNotEmpty);
      } else {
        expect(engine.metrics['nativeLibrary'], 'libondevice_llm_opencl.so');
        expect(engine.metrics['nativeLibrarySkipped'], isEmpty);
      }
      expect(engine.metrics['kernelCacheDir'], isNotEmpty);
      expect(engine.metrics['devices'], isNotEmpty);
      expect((engine.metrics['effectiveSettings'] as Map)['threads'], 4);
      final first = await generate();
      expect(engine.metrics['promptTokens'], preview['promptTokens']);
      expect(first.trim(), isNotEmpty);
      expect(first.contains('\uFFFD'), false);
      final oversized = await engine.previewPrompt(
        messages: [
          {'role': 'user', 'content': List.filled(6000, 'hello').join(' ')},
        ],
        fallbackTemplate: '',
        settings: settings,
      );
      expect(oversized['fits'], false);
      expect(oversized['availableTokens'], lessThan(0));
      final second = await generate();
      expect(
        second,
        first,
        reason: 'Greedy generation must not inherit stale KV state.',
      );
      // ignore: avoid_print
      print('NATIVE_SMOKE[$backendName]: $first | ${engine.metrics}');
      // An explicit GPU request must not silently land on the CPU; Auto may fall back but must say why.
      if (backend != GpuBackend.cpu && backend != GpuBackend.auto) {
        expect(engine.metrics['backend'], isNot(startsWith('CPU')));
      }
      if (backend == GpuBackend.auto) {
        expect(
          engine.metrics['backend'],
          isNot('CPU'),
          reason: 'Auto fell back without a reason',
        );
      }
      // CHAT-02 continuation: the prefix is part of the prompt and the
      // model resumes it instead of starting a new answer.
      final withPrefix = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: '',
        settings: settings,
        assistantPrefix: 'Hello! I am',
      );
      expect(withPrefix['promptTokens'], greaterThan(preview['promptTokens']));
      final continued = await engine
          .generate(
            messages: messages,
            fallbackTemplate: '',
            settings: settings,
            assistantPrefix: 'Hello! I am',
          )
          .join();
      expect(continued.trim(), isNotEmpty);
      expect(
        continued.startsWith('Hello'),
        false,
        reason: 'only new text streams',
      );
      var pieces = 0;
      await for (final _ in engine.generate(
        messages: messages,
        fallbackTemplate: '',
        settings: settings.copyWith(maxTokens: 500),
      )) {
        pieces++;
        engine.cancel();
      }
      expect(pieces, greaterThan(0));
      expect(engine.isBusy, false);
      // Cancel during native prefill, before there is a streamed token.
      final prefillTimer = Timer(
        const Duration(milliseconds: 20),
        engine.cancel,
      );
      try {
        await engine
            .generate(
              messages: [
                {
                  'role': 'user',
                  'content': List.filled(1400, 'hello').join(' '),
                },
              ],
              fallbackTemplate: '',
              settings: settings.copyWith(maxTokens: 256, promptCache: false),
            )
            .join()
            .timeout(const Duration(seconds: 10));
      } finally {
        prefillTimer.cancel();
      }
      expect(engine.metrics['finishReason'], 'cancelled');
      expect(engine.isBusy, false);
      final probes = await Future.wait([engine.probe(), engine.probe()]);
      expect(probes, hasLength(2));
      expect(
        await generate(),
        isNotEmpty,
        reason: 'Cancellation must not poison the next request.',
      );
      await engine.loadModel(
        modelPath: modelPath,
        settings: settings.copyWith(contextSize: 4096),
      );
      expect(engine.metrics['contextSize'], 4096);
      expect(await generate(), isNotEmpty);
      await expectLater(
        engine.loadModel(modelPath: '$modelPath.missing', settings: settings),
        throwsException,
      );
      expect(engine.isLoaded, false);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
