import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/engine/diffusiongemma_engine.dart';

void main() {
  test(
    'JSONL survives byte chunks, UTF-8, multiline text and adjacent events',
    () async {
      final events = [
        {'ready': true, 'loadMs': 123},
        {'event': 'progress', 'canvas': 'Café\n\nA "quoted" paragraph.'},
        {'event': 'block', 'text': 'Paris.\n\nFrance.'},
        {
          'done': true,
          'text': 'Paris.\n\nFrance.',
          'stats': {'answerTokens': 8},
        },
      ];
      final bytes = utf8.encode('${events.map(jsonEncode).join('\r\n')}\n');
      final parsed = await diffusionJsonLines(
        Stream.fromIterable([
          for (final byte in bytes) [byte],
        ]),
      ).toList();
      expect(parsed, events);
    },
  );

  test('invalid protocol surfaces an error', () async {
    await expectLater(
      diffusionJsonLines(Stream.value(utf8.encode('not-json\n'))),
      emitsError(isA<FormatException>()),
    );
  });
}
