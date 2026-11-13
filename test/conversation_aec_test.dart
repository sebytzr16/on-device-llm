import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/conversation_screen.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows talk-over requires the setting and verified active AEC', () {
    for (final requested in [false, true]) {
      for (final active in [false, true]) {
        expect(
          ConversationScreen.canTalkOver(
            requested: requested,
            platform: TargetPlatform.windows,
            aecActive: active,
          ),
          requested && active,
        );
      }
    }
  });

  test('Android preserves the existing talk-over setting behavior', () {
    for (final requested in [false, true]) {
      for (final active in [false, true]) {
        expect(
          ConversationScreen.canTalkOver(
            requested: requested,
            platform: TargetPlatform.android,
            aecActive: active,
          ),
          requested,
        );
      }
    }
  });

  const channel = MethodChannel('ondevice_llm/voice_audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'AEC status queries the current native stream, including loss',
    () async {
      var active = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'aecActive');
        return active;
      });
      expect(await VoiceAudioChannel.aecActive(), isTrue);
      active = false;
      expect(await VoiceAudioChannel.aecActive(), isFalse);
    },
  );

  test('null, missing and failed AEC status cannot enable talk-over', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await VoiceAudioChannel.aecActive(), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await VoiceAudioChannel.aecActive(), isFalse);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'capture_unavailable');
    });
    expect(await VoiceAudioChannel.aecActive(), isFalse);
  });
}
