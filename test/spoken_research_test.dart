import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';

void main() {
  group('VoiceNotifier speakable methods', () {
    test('speakable keeps citation markers for UI', () {
      const input = 'This is a test [1]. Another sentence [2, 3].';
      final result = VoiceNotifier.speakable(input);
      // Citations should be kept for UI display
      expect(result, contains('[1]'));
      expect(result, contains('[2, 3]'));
    });

    test('speakableForTts strips citation markers for speech', () {
      const input = 'This is a test [1]. Another sentence [2, 3].';
      final result = VoiceNotifier.speakableForTts(input);
      // Citations should be stripped for TTS
      expect(result, isNot(contains('[1]')));
      expect(result, isNot(contains('[2, 3]')));
      expect(result, 'This is a test. Another sentence.');
    });

    test('speakable handles markdown formatting', () {
      const input = '**Bold** and *italic* with `code` and [link](url).';
      final result = VoiceNotifier.speakable(input);
      expect(result, 'Bold and italic with code and link.');
    });

    test('speakableForTts handles markdown and strips citations', () {
      const input = '**Bold** [1] with *italic* [2].';
      final result = VoiceNotifier.speakableForTts(input);
      expect(result, 'Bold with italic.');
    });

    test('speakable removes emoji', () {
      const input = 'Hello 😊 world 🎉';
      final result = VoiceNotifier.speakable(input);
      expect(result, 'Hello world');
    });

    test('speakable removes code fences', () {
      const input = '```dart\ncode\n```';
      final result = VoiceNotifier.speakable(input);
      expect(result, 'code omitted.');
    });
  });
}
