import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/desktop_voice_policy.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/l10n/app_localizations_en.dart';
import 'package:ondevice_llm/l10n/app_localizations_fr.dart';
import 'package:ondevice_llm/l10n/app_localizations_es.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows offline gate and model fallback', () {
    expect(
      offlineVoiceReady(
        platform: TargetPlatform.windows,
        desktop: true,
        enabled: true,
        installed: true,
      ),
      isTrue,
    );
    for (final installed in [false, true]) {
      expect(
        offlineVoiceReady(
          platform: TargetPlatform.windows,
          desktop: true,
          enabled: false,
          installed: installed,
        ),
        isFalse,
      );
    }
    expect(
      offlineVoiceReady(
        platform: TargetPlatform.windows,
        desktop: true,
        enabled: true,
        installed: false,
      ),
      isFalse,
    );
    expect(
      offlineVoiceReady(
        platform: TargetPlatform.android,
        desktop: false,
        enabled: true,
        installed: true,
      ),
      isTrue,
    );
    expect(
      offlineVoiceReady(
        platform: TargetPlatform.iOS,
        desktop: false,
        enabled: true,
        installed: true,
      ),
      isFalse,
    );
  });

  test('Windows privacy message names the setting in each language', () {
    expect(
      AppLocalizationsEn().desktopVoiceMicPrivacy,
      contains('allow desktop apps'),
    );
    expect(
      AppLocalizationsFr().desktopVoiceMicPrivacy,
      contains('applications de bureau'),
    );
    expect(
      AppLocalizationsEs().desktopVoiceMicPrivacy,
      contains('aplicaciones de escritorio'),
    );
  });

  test('mic channel converts little endian PCM frames', () async {
    const name = 'ondevice_llm/voice_audio/mic';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    messenger.setMockMethodCallHandler(
      const MethodChannel(name),
      (call) async => null,
    );
    final frames = VoiceAudioChannel.frames();
    final first = frames.first;
    await Future<void>.delayed(Duration.zero);
    final bytes = Uint8List(1024);
    final pcm = ByteData.sublistView(bytes);
    pcm.setInt16(0, 16384, Endian.little);
    pcm.setInt16(2, -16384, Endian.little);
    await messenger.handlePlatformMessage(
      name,
      codec.encodeSuccessEnvelope(bytes),
      (_) {},
    );
    final frame = await first.timeout(const Duration(seconds: 2));
    expect(frame.length, 512);
    expect(frame[0], 0.5);
    expect(frame[1], -0.5);
    messenger.setMockMethodCallHandler(const MethodChannel(name), null);
  });

  test('Windows microphone privacy query uses the runner channel', () async {
    const channel = MethodChannel('ondevice_llm/voice_audio');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'micPrivacyDenied');
      return true;
    });
    expect(await VoiceAudioChannel.micPrivacyDenied(), isTrue);
    messenger.setMockMethodCallHandler(channel, null);
  });
}
