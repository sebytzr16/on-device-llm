// Round 2 of the plan (2026-10-08): the audit's speech findings C1,
// C2, C3 and C5, as acceptance tests for the desired behavior (the audit's
// reproductions asserted the broken one).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/citation_match.dart';
import 'package:ondevice_llm/features/voice/conversation_screen.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('C1: the speech cursor', () {
    test('a citation added at the start does not repeat a sentence', () {
      final stream = SentenceStream();
      const answer = 'Paris has large parks. It is a large city.';
      expect(stream.take(answer), 'Paris has large parks.');
      final cited = CitationMatch.attach(answer, [
        'Paris has large parks and is a large city.',
      ], fill: true);
      expect(cited, isNot(answer));
      final rest = stream.take(cited, flush: true);
      expect(rest, isNot(contains('Paris')));
      expect(rest, contains('It is a large city.'));
    });

    test('citations later in the text do not move the cursor', () {
      final stream = SentenceStream();
      const answer =
          'The Eiffel Tower is 330 metres tall. '
          'The tower stands in central Paris. Its design is iconic.';
      final first = stream.take(answer);
      expect(first, endsWith('central Paris.'));
      final cited = CitationMatch.attach(answer, [
        'The Eiffel Tower is 330 metres tall. The tower stands in central '
            'Paris. Its design is iconic.',
      ], fill: true);
      final rest = stream.take(cited, flush: true);
      expect(rest.trim(), startsWith('Its design is iconic.'));
    });

    test('markdown cleanup and a corrected number keep the cursor', () {
      final stream = SentenceStream();
      const raw = 'It costs **12 euros** here. The shop opens at nine.';
      expect(stream.take(raw), 'It costs **12 euros** here.');
      // The saved answer was cleaned up and a figure corrected.
      const saved = 'It costs 12 euros here [1]. The shop opens at 9.';
      final rest = stream.take(saved, flush: true);
      expect(rest.trim(), 'The shop opens at 9.');
    });

    test('a replaced answer (a tool round) starts over', () {
      final stream = SentenceStream();
      expect(stream.take('Let me look. It is'), 'Let me look.');
      expect(
        stream.take('Today it is sunny in Paris.', flush: true),
        'Today it is sunny in Paris.',
      );
    });
  });

  group('C3: the first words go early', () {
    test('a finished sentence goes once the model pauses', () {
      final stream = SentenceStream();
      const answer = 'This is a complete answer.';
      expect(stream.take(answer), isEmpty);
      expect(stream.take(answer, settled: true), answer);
    });

    test('an abbreviation at the end still waits', () {
      final stream = SentenceStream();
      expect(stream.take('It is sold in the U.S.', settled: true), isEmpty);
      // "3." may be "3.14" still being written.
      expect(SentenceStream().take('Pi is about 3.', settled: true), isEmpty);
    });

    test('a long first clause without a stop goes after a wait', () {
      var now = DateTime(2026, 10, 8, 12);
      final stream = SentenceStream(clock: () => now);
      const text = 'The quickest way to get there from the station is the';
      expect(stream.take(text), isEmpty);
      now = now.add(SentenceStream.firstMaxWait);
      final first = stream.take(text);
      // Whole words, never ending on "the".
      expect(first, 'The quickest way to get there from the station');
      expect(stream.take('$text bus.', flush: true).trim(), 'is the bus.');
    });

    test('decimals and dates are not split', () {
      final stream = SentenceStream();
      expect(stream.take('Pi is about 3.14 and'), isEmpty);
      expect(stream.take('On 8.10.2026 it rained.', settled: true), isNotEmpty);
    });
  });

  group('C2: stopping synthesis', () {
    late _Player player;
    setUp(() => player = _Player()..install());
    tearDown(() => player.uninstall());

    test('only one piece is synthesized at a time, a stop drops the rest '
        'and the next answer still plays', () async {
      final voice = _PendingVoice();
      final speaker = KokoroSpeaker(
        voice: voice,
        kokoro: KokoroVoice.byLanguage['en']!.first,
      );
      speaker.add('One. Two. Three.');
      await pumpEventQueue();
      expect(voice.requests, ['One.']);
      await speaker.stop();
      speaker.add('New answer.');
      await pumpEventQueue();
      // The FFI call for "One." cannot be cancelled; it finishes unheard.
      voice.pending.first.complete(_audio());
      await pumpEventQueue();
      expect(voice.requests, ['One.', 'New answer.']);
      voice.pending.last.complete(_audio());
      await pumpEventQueue();
      expect(player.played, 1);
      player.finishAll();
      await pumpEventQueue();
      expect(speaker.busy, isFalse);
    });

    test('a stop while a piece plays lets the next answer start', () async {
      final voice = _PendingVoice();
      final idle = Completer<void>();
      final speaker = KokoroSpeaker(
        voice: voice,
        kokoro: KokoroVoice.byLanguage['en']!.first,
      )..onIdle = () => idle.isCompleted ? null : idle.complete();
      speaker.add('First answer. It goes on.');
      await pumpEventQueue();
      voice.pending[0].complete(_audio());
      await pumpEventQueue();
      expect(player.played, 1);
      await speaker.stop();
      speaker.add('Next.');
      await pumpEventQueue();
      for (final p in voice.pending.where((p) => !p.isCompleted)) {
        p.complete(_audio());
      }
      await pumpEventQueue();
      for (final p in voice.pending.where((p) => !p.isCompleted)) {
        p.complete(_audio());
      }
      await pumpEventQueue();
      expect(voice.requests.last, 'Next.');
      expect(player.played, 2);
      player.finishAll();
      await pumpEventQueue();
      expect(idle.isCompleted, isTrue);
    });

    test('the next piece is queued before the one playing ends', () async {
      final voice = _PendingVoice();
      final speaker = KokoroSpeaker(
        voice: voice,
        kokoro: KokoroVoice.byLanguage['en']!.first,
      );
      final sentences = <String>[];
      speaker.onSentence = sentences.add;
      speaker.add('First sentence here. Second one.');
      await pumpEventQueue();
      voice.pending[0].complete(_audio());
      await pumpEventQueue();
      voice.pending[1].complete(_audio());
      await pumpEventQueue();
      // Both are with the player; the first has not finished.
      expect(player.played, 2);
      expect(sentences, ['First sentence here.']);
      player.finishNext();
      await pumpEventQueue();
      expect(sentences, ['First sentence here.', 'Second one.']);
      player.finishAll();
      await pumpEventQueue();
      expect(speaker.busy, isFalse);
    });
  });

  group('C5: corrections are not echo', () {
    test('a correction after the answer is kept', () {
      expect(
        ConversationScreen.echoOf('No, set the timer for ten minutes.', [
          'The timer is set for five minutes.',
        ], duringSpeech: false),
        isFalse,
      );
      expect(
        ConversationScreen.echoOf('Non, mets le minuteur sur dix minutes.', [
          'Le minuteur est réglé sur cinq minutes.',
        ], duringSpeech: true),
        isFalse,
      );
      expect(
        ConversationScreen.echoOf('No, pon el temporizador en diez minutos.', [
          'El temporizador está puesto en cinco minutos.',
        ], duringSpeech: false),
        isFalse,
      );
    });

    test('a different number is a correction', () {
      expect(
        ConversationScreen.echoOf('The timer is set for 10 minutes.', [
          'The timer is set for 5 minutes.',
        ], duringSpeech: true),
        isFalse,
      );
    });

    test('the answer heard back is still echo', () {
      expect(
        ConversationScreen.echoOf('The timer is set for five minutes.', [
          'The timer is set for five minutes.',
        ], duringSpeech: true),
        isTrue,
      );
      expect(
        ConversationScreen.echoOf('set for five minutes', [
          'The timer is set for five minutes.',
        ], duringSpeech: false),
        isTrue,
      );
      expect(
        ConversationScreen.echoOf('Yes.', [
          'Yes. The timer is set.',
        ], duringSpeech: true),
        isTrue,
      );
    });
  });
}

SpeechAudio _audio() => SpeechAudio(Int16List(2400), 24000);

/// The native player: each `play` completes when the test says it was
/// heard, or false on `stopPlayback`.
class _Player {
  static const _channel = MethodChannel('ondevice_llm/voice_audio');
  final _playing = <Completer<bool>>[];
  var played = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'play':
              played++;
              final done = Completer<bool>();
              _playing.add(done);
              return done.future;
            case 'stopPlayback':
              for (final p in _playing) {
                if (!p.isCompleted) p.complete(false);
              }
              _playing.clear();
              return null;
          }
          return null;
        });
  }

  void finishNext() {
    final p = _playing.where((p) => !p.isCompleted).firstOrNull;
    p?.complete(true);
  }

  void finishAll() {
    for (final p in _playing) {
      if (!p.isCompleted) p.complete(true);
    }
  }

  void uninstall() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

class _PendingVoice extends SherpaVoice {
  final requests = <String>[];
  final pending = <Completer<SpeechAudio?>>[];
  @override
  Future<SpeechAudio?> synthesize(
    String text, {
    required KokoroVoice voice,
    double speed = 1,
  }) {
    requests.add(text);
    final p = Completer<SpeechAudio?>();
    pending.add(p);
    return p.future;
  }
}
