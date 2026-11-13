import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

void main() {
  test(
    'existing settings keep Kokoro until the user chooses another engine',
    () {
      expect(const InferenceSettings().readingVoice, 'kokoro');
      expect(InferenceSettings.fromJson({}).readingVoice, 'kokoro');
      expect(
        InferenceSettings.fromJson({'readingVoice': 'unknown'}).readingVoice,
        'kokoro',
      );
    },
  );

  test('reading engine and speed survive the saved settings format', () {
    final chosen = const InferenceSettings().copyWith(
      readingVoice: 'supertonic-3',
      readingSpeed: 1.3,
    );
    final restored = InferenceSettings.fromJson(
      jsonDecode(jsonEncode(chosen.toJson())) as Map<String, dynamic>,
    );
    expect(restored.readingVoice, 'supertonic-3');
    expect(restored.readingSpeed, 1.3);
    expect(restored.copyWith(talkOver: true).readingVoice, 'supertonic-3');
  });

  test('a saved Supertonic 2 preference selects Supertonic 3', () {
    expect(
      InferenceSettings.fromJson({'readingVoice': 'supertonic-2'}).readingVoice,
      'supertonic-3',
    );
    expect(
      const InferenceSettings()
          .copyWith(readingVoice: 'supertonic-2')
          .readingVoice,
      'supertonic-3',
    );
  });
}
