import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';

void main() {
  test(
    'same-default selection stays above model recommendations after save',
    () {
      final chosen = const InferenceSettings().copyWith(temperature: .7);
      final saved = InferenceSettings.fromJson(chosen.toJson());
      final r = SettingsResolver.resolve(
        global: saved,
        recommended: {'temperature': 1.0},
      );
      expect(r.effective.temperature, .7);
      expect(r.originOf('temperature'), SettingsLayer.idGlobal);
    },
  );
  test('registry edit records the explicitly selected keys', () {
    final chosen = SettingsResolver.editGlobal(const InferenceSettings(), {
      'temperature': .7,
    });
    expect(chosen.explicitOverrides, contains('temperature'));
  });
  test(
    'a legacy save keeps what the build that wrote it treated as chosen',
    () {
      // Pre-provenance saves wrote every field; only values unlike the
      // defaults were the user's, so defaults still follow the model.
      final legacy = const InferenceSettings(temperature: .3).toJson()
        ..remove('explicitOverrides');
      final saved = InferenceSettings.fromJson(legacy);
      final r = SettingsResolver.resolve(
        global: saved,
        recommended: {'temperature': 1.0, 'topP': .8},
      );
      expect(r.effective.temperature, .3);
      expect(r.originOf('temperature'), SettingsLayer.idGlobal);
      expect(r.effective.topP, .8);
      expect(r.originOf('topP'), SettingsLayer.idRecommended);
    },
  );
  test('migration preserves ambiguous legacy choices', () {
    const saved = InferenceSettings(contextSize: 4096, repetitionPenalty: 1.1);
    final next = migrateSamplingDefaults(
      saved,
      const InferenceSettings(contextSize: 8192),
    );
    expect(next.contextSize, 4096);
    expect(next.repetitionPenalty, 1.1);
  });
}
