import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/engine/stream_parser.dart';

void main() {
  test('P3-05 plain text is not held back behind a possible tag', () async {
    final p = ThinkingStreamParser();
    final answer = <String>[];
    p.answerStream.listen(answer.add);
    p.add('Hello world');
    await Future<void>.delayed(Duration.zero);
    expect(answer.join(), 'Hello world');
    p.add(' <thi');
    await Future<void>.delayed(Duration.zero);
    expect(answer.join(), 'Hello world ');
    p.close();
  });

  test('P3-04 the normalizer never emits half a surrogate pair', () async {
    final n = ThinkingTagNormalizer()
      ..configure(startTag: '<|think|>', endTags: const ['<|/think|>']);
    final pieces = <String>[];
    final done = Completer<void>();
    Stream.fromIterable([
      'ab😀12345678',
    ]).transform(n).listen(pieces.add, onDone: done.complete);
    await done.future;
    for (final piece in pieces) {
      final last = piece.codeUnitAt(piece.length - 1);
      expect((last & 0xFC00) == 0xD800, isFalse, reason: piece);
    }
    expect(pieces.join(), 'ab😀12345678');
  });
}
