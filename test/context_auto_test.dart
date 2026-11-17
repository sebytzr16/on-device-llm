import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';

// Auto context (owner 2026-11-16): the recommended default; a length set by
// hand, now or before Auto existed, turns it off.
void main() {
  test('Auto is the default and survives a round trip', () {
    expect(const InferenceSettings().contextAuto, isTrue);
    expect(InferenceSettings.forDevice(12).contextAuto, isTrue);
    expect(InferenceSettings.fromJson(const {}).contextAuto, isTrue);
    final off = const InferenceSettings().copyWith(contextAuto: false);
    expect(InferenceSettings.fromJson(off.toJson()).contextAuto, isFalse);
  });

  test('setting a length by hand turns Auto off', () {
    final s = const InferenceSettings().copyWith(contextSize: 16384);
    expect(s.contextAuto, isFalse);
    expect(s.explicitOverrides, containsAll(['contextSize', 'contextAuto']));
    expect(s.copyWith(contextAuto: true).contextAuto, isTrue);
    // Other edits leave the choice alone.
    expect(s.copyWith(temperature: .5).contextAuto, isFalse);
  });

  test('device and model-card lengths keep Auto on', () {
    final r = SettingsResolver.resolve(
      global: const InferenceSettings(),
      deviceDefaults: InferenceSettings.forDevice(4),
      recommended: {'contextSize': 32768},
    );
    expect(r.effective.contextAuto, isTrue);
  });

  test('a saved model or chat length from before Auto turns it off', () {
    final model = SettingsResolver.resolve(
      global: const InferenceSettings(),
      model: {'contextSize': 16384},
    );
    expect(model.effective.contextAuto, isFalse);
    expect(model.effective.contextSize, 16384);
    expect(model.originOf('contextAuto'), SettingsLayer.idModel);

    final back = SettingsResolver.resolve(
      global: const InferenceSettings(),
      model: {'contextSize': 16384, 'contextAuto': true},
    );
    expect(back.effective.contextAuto, isTrue);

    final chat = SettingsResolver.resolve(
      global: const InferenceSettings(),
      model: {'contextAuto': true},
      chat: {'contextSize': 8192},
    );
    expect(chat.effective.contextAuto, isFalse);
  });

  test('only a global length the user chose turns Auto off', () {
    // An old saved global with the former default is not a choice.
    final old = InferenceSettings.fromJson(const {'contextSize': 4096});
    expect(SettingsResolver.resolve(global: old).effective.contextAuto, isTrue);
    final chosen = SettingsResolver.editGlobal(const InferenceSettings(), {
      'contextSize': 8192,
    });
    expect(
      SettingsResolver.resolve(global: chosen).effective.contextAuto,
      isFalse,
    );
  });

  test('the Dart Auto length mirrors the bridge ceiling', () {
    int auto(int? trained, int gb, {bool desktop = true}) =>
        InferenceSettings.autoContext(
          trained: trained,
          ramTotalMb: gb * 1024,
          desktop: desktop,
        );
    expect(auto(262144, 32), 32768);
    expect(auto(262144, 16), 16384);
    expect(auto(262144, 8), 8192);
    expect(auto(4096, 32), 4096);
    expect(auto(null, 32), 32768);
    expect(auto(131072, 12, desktop: false), 8192);
    expect(auto(131072, 16, desktop: false), 16384);
    expect(auto(131072, 6, desktop: false), 4096);
    expect(auto(131072, 4, desktop: false), 2048);
  });
}
