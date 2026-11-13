// Voice understanding: a spoken turn carries the utterance's own recording
// only when the loaded model can hear audio, the setting allows it and the
// answer comes from this device.
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/conversation_session.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

void main() {
  group('conversation audio attachment', () {
    final hearing = LlamaEngine()..metrics = {'supportsAudio': true};
    final deaf = LlamaEngine()..metrics = {'supportsAudio': false};

    bool sends({
      required LlamaEngine engine,
      bool enabled = true,
      bool remote = false,
      int samples = 16000,
    }) => ConversationSession.sendsUtterance(
      hearsAudio: engine.supportsAudio,
      enabled: enabled,
      remote: remote,
      samples: samples,
    );

    test('only a model that can hear, with the setting on, on this device', () {
      expect(sends(engine: hearing), isTrue);
      expect(sends(engine: deaf), isFalse);
      expect(sends(engine: hearing, enabled: false), isFalse);
      expect(sends(engine: hearing, remote: true), isFalse);
    });

    test('at most 30 s of audio; longer utterances stay text only', () {
      expect(
        sends(
          engine: hearing,
          samples: ConversationSession.maxUtteranceSamples,
        ),
        isTrue,
      );
      expect(
        sends(
          engine: hearing,
          samples: ConversationSession.maxUtteranceSamples + 1,
        ),
        isFalse,
      );
      expect(sends(engine: hearing, samples: 0), isFalse);
    });

    test('the instructions say to trust the audio over the transcript', () {
      expect(
        ConversationSession.heardAudioPrompt,
        contains('attached as audio'),
      );
      expect(ConversationSession.heardAudioPrompt, contains('trust the audio'));
    });
  });
}
