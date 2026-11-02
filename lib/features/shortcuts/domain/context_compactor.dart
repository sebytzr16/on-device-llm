import '../../../inference/engine/text_engine.dart';
import '../../settings/domain/entities/inference_settings.dart';

class ContextCompactor {
  const ContextCompactor();
  Future<String> summarize({
    required TextEngine engine,
    required InferenceSettings settings,
    required String source,
    required String instruction,
    required String fallbackTemplate,
    required String fitError,
  }) async {
    final options = settings.copyWith(
      maxTokens: 512,
      thinkingModeEnabled: false,
      toolsEnabled: false,
      responseFormat: ResponseFormat.text,
    );
    Future<String> reduce(String text) async {
      final messages = <Map<String, Object>>[
        {'role': 'system', 'content': instruction},
        {'role': 'user', 'content': text},
      ];
      final fit = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: fallbackTemplate,
        settings: options,
      );
      if (fit['fits'] != true) throw StateError(fitError);
      final result =
          (await engine
                  .generate(
                    messages: messages,
                    fallbackTemplate: fallbackTemplate,
                    settings: options,
                  )
                  .join())
              .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
              .trim();
      if (result.isEmpty) throw StateError(fitError);
      return result;
    }

    Future<List<String>> parts(String text) async {
      final pending = <String>[text];
      final summaries = <String>[];
      while (pending.isNotEmpty) {
        final chunk = pending.removeAt(0);
        final fit = await engine.previewPrompt(
          messages: [
            {'role': 'system', 'content': instruction},
            {'role': 'user', 'content': chunk},
          ],
          fallbackTemplate: fallbackTemplate,
          settings: options,
        );
        if (fit['fits'] == true) {
          summaries.add(await reduce(chunk));
          continue;
        }
        if (chunk.length < 512) throw StateError(fitError);
        final middle = chunk.length ~/ 2;
        pending.insertAll(0, [
          chunk.substring(0, middle),
          chunk.substring(middle),
        ]);
      }
      return summaries;
    }

    var text = source;
    for (var round = 0; round < 6; round++) {
      final summaries = await parts(text);
      final next = summaries.join('\n\n');
      if (summaries.length == 1 && next.length <= 6000) return next;
      if (next.length >= text.length) throw StateError(fitError);
      text = next;
    }
    throw StateError(fitError);
  }
}
