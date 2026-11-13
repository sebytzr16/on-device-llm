// A27: the voice session now owns the spoken turn's rules and the screen
// forwards to it. These check the forwarding kept every public name and rule
// unchanged (the screen's other tests keep exercising the behaviour itself).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/conversation_screen.dart';
import 'package:ondevice_llm/features/voice/conversation_session.dart';

void main() {
  test('the screen forwards the spoken turn rules to the session', () {
    expect(ConversationScreen.spokenStyle, ConversationSession.spokenStyle);
    expect(
      ConversationScreen.spokenStyleRemote,
      ConversationSession.spokenStyleRemote,
    );
    expect(ConversationScreen.turnSettings, ConversationSession.turnSettings);
    expect(
      ConversationScreen.maxAnswerTokens,
      ConversationSession.maxAnswerTokens,
    );
    expect(ConversationScreen.maxHold, ConversationSession.maxHold);
    for (final most in [0, 2, 3, 6]) {
      expect(
        ConversationScreen.styled(ConversationScreen.spokenStyle, most),
        ConversationSession.styled(ConversationSession.spokenStyle, most),
      );
      expect(
        ConversationScreen.turnSettingsFor(most),
        ConversationSession.turnSettingsFor(most),
      );
    }
  });

  test('echo and hold decisions are the session decisions', () {
    const said = ['The timer is set for five minutes.'];
    for (final text in [
      'The timer is set for five minutes.',
      'No, set the timer for ten minutes.',
    ]) {
      for (final during in [false, true]) {
        expect(
          ConversationScreen.echoOf(text, said, duringSpeech: during),
          ConversationSession.echoOf(text, said, duringSpeech: during),
        );
      }
    }
    for (final held in [false, true]) {
      for (final hearing in [false, true]) {
        for (final seconds in [1, 10]) {
          final heldFor = Duration(seconds: seconds);
          expect(
            ConversationScreen.keepsHolding(
              holding: held,
              hearing: hearing,
              heldFor: heldFor,
            ),
            ConversationSession.keepsHolding(
              holding: held,
              hearing: hearing,
              heldFor: heldFor,
            ),
          );
        }
      }
    }
  });

  test('talk-over still needs the setting and, on Windows, verified AEC', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.iOS,
    ]) {
      for (final requested in [false, true]) {
        for (final active in [false, true]) {
          expect(
            ConversationScreen.canTalkOver(
              requested: requested,
              platform: platform,
              aecActive: active,
            ),
            ConversationSession.canTalkOver(
              requested: requested,
              platform: platform,
              aecActive: active,
            ),
          );
        }
      }
    }
  });

  test('the conversation phases keep their order and names', () {
    expect(ConversationPhase.values, [
      ConversationPhase.starting,
      ConversationPhase.idle,
      ConversationPhase.listening,
      ConversationPhase.thinking,
      ConversationPhase.speaking,
    ]);
  });
}
