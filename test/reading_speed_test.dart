import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

void main() {
  test('reading speed is saved and kept within the voice range', () {
    expect(const InferenceSettings().readingSpeed, 1.0);
    final s = const InferenceSettings().copyWith(readingSpeed: 1.3);
    expect(InferenceSettings.fromJson(s.toJson()).readingSpeed, 1.3);
    expect(InferenceSettings.fromJson({'readingSpeed': 5}).readingSpeed, 1.6);
    expect(InferenceSettings.fromJson({}).readingSpeed, 1.0);
  });
}
