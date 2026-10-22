import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';

void main() {
  test(
    'long utterances preserve all text and do not split surrogate pairs',
    () {
      final text = 'Sentence with a 🙂 and some detail. ' * 400;
      final parts = VoiceNotifier.chunks(text, limit: 97);
      expect(parts.join(), text);
      expect(parts.every((part) => part.length <= 97), isTrue);
      expect(parts.length, greaterThan(2));
      expect(
        parts.every((part) => !RegExp(r'[\uD800-\uDBFF]$').hasMatch(part)),
        isTrue,
      );
      expect(VoiceNotifier.chunks(''), isEmpty);
    },
  );
  test('markdown becomes speakable text', () {
    const md = '''
## Result

The **latest** stable is `3.47.4` [1], see [the notes](https://x.y/z).

- first point
- second *point*

```dart
void main() {}
```
| a | b |
''';
    final s = VoiceNotifier.speakable(md);
    expect(s, isNot(contains('#')));
    expect(s, isNot(contains('**')));
    expect(s, isNot(contains('```')));
    expect(s, isNot(contains('[1]')));
    expect(s, isNot(contains('https://')));
    expect(s, contains('The latest stable is 3.47.4, see the notes.'));
    expect(s, contains('first point'));
    expect(s, contains('code omitted'));
    expect(s, contains(', a , b ,'));
  });

  test('emoji are not read aloud', () {
    expect(VoiceNotifier.speakable('Bonne journée! 😊'), 'Bonne journée!');
    expect(
      VoiceNotifier.speakable('¡Hola! Todo bien ☀️ gracias.'),
      '¡Hola! Todo bien gracias.',
    );
  });
}
