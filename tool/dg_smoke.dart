import 'dart:io';
import 'package:ondevice_llm/inference/engine/diffusiongemma_engine.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

Future<void> main(List<String> args) async {
  final engine = DiffusionGemmaEngine(
    denoisingSteps: int.parse(Platform.environment['DG_STEPS'] ?? '48'),
    ubatch: int.parse(Platform.environment['DG_UBATCH'] ?? '512'),
    executable: File(
      'native/out/windows-x64/diffusiongemma/dg_host.exe',
    ).absolute.path,
  );
  final model = args.isEmpty
      ? 'build/dg-models/diffusiongemma-26B-A4B-it-Q4_K_M.gguf'
      : args.first;
  final load = Stopwatch()..start();
  try {
    await engine.loadModel(File(model).absolute.path);
    stdout.writeln('Load: ${load.elapsedMilliseconds} ms');
    final messages = <Map<String, Object>>[];
    for (final prompt in [
      'What is the capital of France? Answer in one sentence.',
      'Write two short paragraphs explaining why leaves change color in autumn.\n\nKeep it clear and factual.',
    ]) {
      messages.add({'role': 'user', 'content': prompt});
      stdout.writeln(
        'Prompt: ${await engine.previewPrompt(messages: messages, fallbackTemplate: '', settings: const InferenceSettings(maxTokens: 512, temperature: 0.8))}',
      );
      final answer = StringBuffer();
      await for (final text in engine.generate(
        messages: messages,
        fallbackTemplate: '',
        settings: const InferenceSettings(maxTokens: 512, temperature: 0.8),
      )) {
        stdout.write(text);
        answer.write(text);
      }
      stdout.writeln('\n${engine.metrics}');
      messages.add({'role': 'assistant', 'content': answer.toString()});
    }
    if (Platform.environment['DG_BLOCK_PROBE'] == '1') {
      final answer = await engine
          .generate(
            messages: [
              {
                'role': 'user',
                'content':
                    'Write a detailed 600-word explanation of how the water cycle works, in four paragraphs.',
              },
            ],
            fallbackTemplate: '',
            settings: const InferenceSettings(maxTokens: 384, temperature: 0.8),
          )
          .join();
      if ((engine.metrics['diffusionBlock'] as int? ?? 0) < 1) {
        throw StateError('Expected more than one canvas: ${engine.metrics}');
      }
      stdout.writeln('Multiple blocks: $answer\n${engine.metrics}');
    }
    if (Platform.environment['DG_CANCEL_PROBE'] == '1') {
      var requested = false;
      final subscription = engine.canvasChanges.listen((event) {
        if (!requested && event['event'] == 'progress') {
          requested = true;
          engine.cancel();
        }
      });
      try {
        await engine
            .generate(
              messages: [
                {
                  'role': 'user',
                  'content':
                      'Write a long essay about the history of astronomy.',
                },
              ],
              fallbackTemplate: '',
              settings: const InferenceSettings(
                maxTokens: 1024,
                temperature: 0.8,
              ),
            )
            .drain<void>();
      } finally {
        await subscription.cancel();
      }
      if (engine.metrics['finishReason'] != 'cancelled') {
        throw StateError('Cancellation failed: ${engine.metrics}');
      }
      stdout.writeln('Cancelled: ${engine.metrics}');
      final recovered = await engine
          .generate(
            messages: [
              {
                'role': 'user',
                'content':
                    'What is the capital of France? Answer in one sentence.',
              },
            ],
            fallbackTemplate: '',
            settings: const InferenceSettings(maxTokens: 256, temperature: 0.8),
          )
          .join();
      if (!recovered.contains('Paris')) {
        throw StateError('Recovery failed: $recovered');
      }
      stdout.writeln('After cancel: $recovered\n${engine.metrics}');
    }
  } finally {
    engine.dispose();
  }
}
