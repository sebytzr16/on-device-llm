import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';

void main() {
  test(
    'same-default selection stays above model recommendations after save',
    () {
      final chosen = const InferenceSettings().copyWith(contextSize: 8192);
      final saved = InferenceSettings.fromJson(chosen.toJson());
      final r = SettingsResolver.resolve(
        global: saved,
        recommended: {'contextSize': 32768},
      );
      expect(r.effective.contextSize, 8192);
      expect(r.originOf('contextSize'), SettingsLayer.idGlobal);
    },
  );
  test(
    "app-wide sampling is ignored; answer limits remain a global default",
    () {
      final saved = SettingsResolver.editGlobal(const InferenceSettings(), {
        'temperature': .2,
        'maxTokens': 65536,
      });
      final r = SettingsResolver.resolve(
        global: saved,
        recommended: {'temperature': 1.0},
      );
      expect(r.effective.temperature, 1.0);
      expect(r.originOf('temperature'), SettingsLayer.idRecommended);
      expect(r.effective.maxTokens, 65536);
      final profiled = SettingsResolver.resolve(
        global: saved,
        recommended: {'temperature': 1.0},
        model: {'temperature': .4},
      );
      expect(profiled.effective.temperature, .4);
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
      final legacy = const InferenceSettings(contextSize: 6144).toJson()
        ..remove('explicitOverrides');
      final saved = InferenceSettings.fromJson(legacy);
      final r = SettingsResolver.resolve(
        global: saved,
        recommended: {'contextSize': 32768, 'batchSize': 256},
      );
      expect(r.effective.contextSize, 6144);
      expect(r.originOf('contextSize'), SettingsLayer.idGlobal);
      expect(r.effective.batchSize, 256);
      expect(r.originOf('batchSize'), SettingsLayer.idRecommended);
    },
  );
  test('legacy choices are preserved without migration', () {
    const saved = InferenceSettings(contextSize: 4096, repetitionPenalty: 1.1);
    // Without the migration function, the saved settings are used as-is.
    expect(saved.contextSize, 4096);
    expect(saved.repetitionPenalty, 1.1);
  });
}
