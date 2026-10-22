import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/features/settings/domain/battery_saver.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

void main() {
  const on = InferenceSettings(
    batterySaver: true,
    batterySaverLevel: 20,
    thinkingModeEnabled: true,
    maxTokens: 2048,
  );
  DevicePower p(int level, {bool charging = false, int heat = 0}) =>
      DevicePower(level: level, charging: charging, thermalStatus: heat);

  test('the saver starts below the level, unplugged, or when hot', () {
    expect(BatterySaver.reason(on, p(50)), isNull);
    expect(BatterySaver.reason(on, p(18)), 'battery 18%');
    expect(BatterySaver.reason(on, p(18, charging: true)), isNull);
    expect(BatterySaver.reason(on, p(90, heat: 3)), 'phone hot: severe');
    expect(BatterySaver.reason(on, p(90, heat: 2)), isNull);
    expect(BatterySaver.reason(on, null), isNull, reason: 'not Android');
    expect(
      BatterySaver.reason(const InferenceSettings(), p(5)),
      isNull,
      reason: 'off by default',
    );
  });

  test('a lighter turn, and nothing that would reload the model', () {
    final light = BatterySaver.apply(on);
    expect(light.thinkingModeEnabled, false);
    expect(light.maxTokens, BatterySaver.maxTokens);
    expect(light.maxPagesRead, lessThanOrEqualTo(BatterySaver.maxPages));
    expect(light.evidencePassages, lessThanOrEqualTo(BatterySaver.maxPassages));
    final a = on.toJson(), b = light.toJson();
    for (final key in InferenceSettings.loadTimeKeys) {
      expect(b[key], a[key], reason: '$key is load-time');
    }
    // Values already under the caps stay.
    expect(BatterySaver.apply(on.copyWith(maxTokens: 200)).maxTokens, 200);
  });

  test('the settings survive a save', () {
    final back = InferenceSettings.fromJson(
      on.copyWith(batterySaverLevel: 30).toJson(),
    );
    expect(back.batterySaver, true);
    expect(back.batterySaverLevel, 30);
    expect(
      InferenceSettings.fromJson({'batterySaverLevel': 99}).batterySaverLevel,
      80,
    );
  });
}
