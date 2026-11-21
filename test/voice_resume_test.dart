import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_models_provider.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final InferenceSettings initial;
  @override
  InferenceSettings build() {
    ready = Future.value();
    return initial;
  }

  @override
  Future<void> update(
    InferenceSettings next, {
    bool requirePersistence = false,
  }) async {
    state = next;
  }
}

class _Packs extends VoiceModelsNotifier {
  _Packs(this.ready);
  final Set<String> ready;

  @override
  VoiceModelsState build() => VoiceModelsState({
    for (final p in VoiceModels.all)
      p.id: VoicePackState(
        ready.contains(p.id) ? VoicePackStatus.ready : VoicePackStatus.missing,
      ),
  });
}

/// Stands in for the sherpa worker: a null [audio] behaves like a missing pack
/// (Kokoro drops the answer silently), [error] like a failed synthesis.
class _FakeVoice extends SherpaVoice {
  final synthesized = <String>[];
  SpeechAudio? audio;
  Object? error;

  @override
  Future<SpeechAudio?> synthesize(
    String text, {
    required KokoroVoice voice,
    double speed = 1.0,
  }) async {
    synthesized.add(text);
    final failure = error;
    if (failure != null) throw failure;
    return audio;
  }
}

/// A pause and resume must restart the engine that read the answer (audit
/// 08b-10). Without a pack, resuming used to go through Kokoro, which has
/// nothing to synthesize: nothing was read at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('flutter_tts');
  const audioChannel = MethodChannel('ondevice_llm/voice_audio');
  late List<String> calls;
  late List<String> spoken;
  late List<Object?> plays;
  Completer<void>? speaking;
  Completer<void>? playing;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    calls = [];
    spoken = [];
    plays = [];
    speaking = null;
    playing = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'speak') {
        spoken.add(call.arguments as String);
        if (speaking != null) await speaking!.future;
      }
      if (call.method == 'stop' && speaking?.isCompleted == false) {
        speaking!.complete();
      }
      return 1;
    });
    messenger.setMockMethodCallHandler(audioChannel, (call) async {
      if (call.method == 'play') {
        plays.add(call.arguments);
        if (playing != null) await playing!.future;
        return true;
      }
      if (call.method == 'stopPlayback' && playing?.isCompleted == false) {
        playing!.complete();
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(audioChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('resuming reads the answer with the system voice again', () async {
    final fake = _FakeVoice();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          () => _Settings(const InferenceSettings(naturalVoice: false)),
        ),
        voiceModelsProvider.overrideWith(() => _Packs(const {})),
        sherpaVoiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(container.dispose);
    final voice = container.read(voiceProvider.notifier);
    speaking = Completer<void>();
    unawaited(voice.speak('A long answer to read out loud.', id: 'a'));
    await pumpEventQueue();
    expect(calls, contains('speak'));
    await voice.pauseSpeaking();
    expect(container.read(voiceProvider).paused, isTrue);
    calls.clear();
    await voice.resumeSpeaking();
    for (var i = 0; i < 20 && !calls.contains('speak'); i++) {
      await pumpEventQueue();
    }
    // The system voice reads on; Kokoro was never asked (no pack: it would
    // have dropped the answer silently).
    expect(calls, contains('speak'));
    expect(fake.synthesized, isEmpty);
  });

  test('a Kokoro answer resumes with Kokoro from where it stopped', () async {
    final fake = _FakeVoice()..audio = SpeechAudio(Int16List(160), 24000);
    final desktop = DesktopHost.active;
    DesktopHost.active = true;
    addTearDown(() => DesktopHost.active = desktop);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          () => _Settings(const InferenceSettings()),
        ),
        voiceModelsProvider.overrideWith(
          () => _Packs({VoiceModels.speaking.id}),
        ),
        sherpaVoiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(container.dispose);
    final voice = container.read(voiceProvider.notifier);
    playing = Completer<void>();
    unawaited(
      voice.speak('First sentence here. Second sentence follows.', id: 'k'),
    );
    for (var i = 0; i < 20 && plays.isEmpty; i++) {
      await pumpEventQueue();
    }
    // Kokoro reads it: the first sentence is playing, the system voice is not
    // involved.
    expect(plays, isNotEmpty);
    expect(fake.synthesized.first, 'First sentence here.');
    expect(calls, isNot(contains('speak')));
    await voice.pauseSpeaking();
    expect(container.read(voiceProvider).paused, isTrue);
    final before = fake.synthesized.length;
    final played = plays.length;
    await voice.resumeSpeaking();
    for (var i = 0; i < 20 && plays.length == played; i++) {
      await pumpEventQueue();
    }
    // Kokoro reads on from the sentence it stopped at.
    expect(plays.length, greaterThan(played));
    expect(fake.synthesized.skip(before), ['Second sentence follows.']);
    expect(calls, isNot(contains('speak')));
  });

  test('the Kokoro fallback reads the whole remaining answer', () async {
    final fake = _FakeVoice()..error = StateError('synthesis failed');
    final desktop = DesktopHost.active;
    DesktopHost.active = true;
    addTearDown(() => DesktopHost.active = desktop);
    final container = ProviderContainer(
      overrides: [
        // The first answer is read by the system voice.
        settingsProvider.overrideWith(
          () => _Settings(const InferenceSettings(naturalVoice: false)),
        ),
        voiceModelsProvider.overrideWith(
          () => _Packs({VoiceModels.speaking.id}),
        ),
        sherpaVoiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(container.dispose);
    final voice = container.read(voiceProvider.notifier);
    await voice.speak('First answer.', id: 'a');
    expect(spoken, ['First answer.']);
    // The natural voice is switched on: the next answer goes to Kokoro, whose
    // synthesis fails. The system voice takes over at the offset Kokoro
    // reported, not at the position of the answer before (audit 08b-11).
    await container
        .read(settingsProvider.notifier)
        .update(const InferenceSettings());
    calls.clear();
    spoken.clear();
    unawaited(voice.speak('Second answer to read out.', id: 'b'));
    for (var i = 0; i < 20 && spoken.isEmpty; i++) {
      await pumpEventQueue();
    }
    expect(fake.synthesized, ['Second answer to read out.']);
    expect(spoken, ['Second answer to read out.']);
  });
}
