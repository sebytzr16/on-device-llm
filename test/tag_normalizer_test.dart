import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

Future<String> run(ThinkingTagNormalizer n, List<String> pieces) =>
    Stream.fromIterable(pieces).transform(n).join();

void main() {
  test(
    'passes text through untouched when the model uses canonical tags',
    () async {
      final n = ThinkingTagNormalizer()
        ..configure(startTag: '<think>', endTags: ['</think>']);
      expect(await run(n, ['<thi', 'nk>a</think>b']), '<think>a</think>b');
    },
  );
  test('rewrites Gemma 4 channel markers at every split point', () async {
    const text =
        'x<|channel>thought\nplan<channel|>answer<|channel>thought\n<channel|>';
    for (var i = 1; i < text.length; i++) {
      final n = ThinkingTagNormalizer()
        ..configure(startTag: '<|channel>thought', endTags: ['<channel|>']);
      expect(
        await run(n, [text.substring(0, i), text.substring(i)]),
        'x<think>\nplan</think>answer<think>\n</think>',
        reason: 'split at $i',
      );
    }
  });
  test('flushes a held tail that never became a tag', () async {
    final n = ThinkingTagNormalizer()
      ..configure(startTag: '<|channel>thought', endTags: ['<channel|>']);
    expect(await run(n, ['hello <|chan']), 'hello <|chan');
  });

  test(
    'short reasoning and answer deltas arrive while input is open',
    () async {
      final source = StreamController<String>();
      final normalizer = ThinkingTagNormalizer()
        ..configure(startTag: '<|channel>thought', endTags: ['<channel|>']);
      final output = StreamIterator(source.stream.transform(normalizer));

      Future<void> checkDelta(String input, String expected) async {
        final next = output.moveNext();
        source.add(input);
        expect(await next.timeout(const Duration(seconds: 1)), isTrue);
        expect(output.current, expected);
      }

      try {
        await checkDelta('<|channel>thought', '<think>');
        await checkDelta('plan<chan', 'plan');
        await checkDelta('nel|>', '</think>');
        await checkDelta('🧠', '🧠');
        await checkDelta('yes', 'yes');
      } finally {
        await output.cancel();
        await source.close();
      }
    },
  );
}
