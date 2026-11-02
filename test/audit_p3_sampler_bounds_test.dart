import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

void main() {
  const settings = InferenceSettings();
  test(
    'repeat penalty rejects zero, nonfinite values and values above two',
    () {
      for (final value in [0, -1, 2.001, double.infinity, double.nan, '1']) {
        expect(
          () => DeviceModelServer.samplingForRequest({
            'repeat_penalty': value,
          }, settings),
          throwsFormatException,
        );
      }
      for (final value in [0.01, 1.0, 2.0]) {
        expect(
          DeviceModelServer.samplingForRequest({
            'repeat_penalty': value,
          }, settings).repetitionPenalty,
          value,
        );
      }
    },
  );
  test('presence and frequency penalties retain their signed bounds', () {
    for (final key in ['presence_penalty', 'frequency_penalty']) {
      for (final value in [-2.001, 2.001, double.nan]) {
        expect(
          () => DeviceModelServer.samplingForRequest({key: value}, settings),
          throwsFormatException,
        );
      }
      for (final value in [-2.0, 0.0, 2.0]) {
        final result = DeviceModelServer.samplingForRequest({
          key: value,
        }, settings);
        expect(
          key == 'presence_penalty'
              ? result.presencePenalty
              : result.frequencyPenalty,
          value,
        );
      }
    }
  });
}
