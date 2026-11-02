import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/model_config_card.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';

import 'model_config_card_test.dart' show qwen;

void main() {
  test(
    'exports explicit default values over model recommendations (P2-23)',
    () {
      const global = InferenceSettings(
        explicitOverrides: {
          'temperature',
          'topK',
          'systemPrompt',
          'contextSize',
        },
      );
      final card = ModelConfigCard.decode(
        ModelConfigCard.from(model: qwen, global: global).encode(),
      )!;
      expect(card.settings, {
        'temperature': global.temperature,
        'topK': global.topK,
        'systemPrompt': global.systemPrompt,
      });
      final resolved = SettingsResolver.resolve(
        global: const InferenceSettings(),
        recommended: {
          'temperature': 1.5,
          'topK': 3,
          'systemPrompt': 'Recommended',
        },
        model: card.settings,
      );
      expect(resolved.effective.temperature, global.temperature);
      expect(resolved.effective.topK, global.topK);
      expect(resolved.effective.systemPrompt, global.systemPrompt);
    },
  );
}
