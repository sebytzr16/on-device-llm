import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/voice/conversation_screen.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_pipeline.dart';
import 'package:path/path.dart' as p;

void main() {
  test('speechEnvelope gives the loudness every 32 ms', () {
    // 0.1 s of silence, then 0.1 s at half scale, at 24 kHz.
    final pcm = Int16List(4800);
    for (var i = 2400; i < 4800; i++) {
      pcm[i] = i.isEven ? 16384 : -16384;
    }
    final env = speechEnvelope(SpeechAudio(pcm, 24000));
    expect(env.length, (4800 / 768).ceil());
    expect(env.first, 0);
    expect(env[4], closeTo(0.5, 0.001));
  });

  group('WhisperListener.heardAudio', () {
    Float32List frames(int n) => Float32List(512 * n);
    test('a finished sentence is read from what the microphone heard', () {
      final speech = [for (var i = 0; i < 40; i++) frames(1)];
      final heard = WhisperListener.heardAudio(frames(20), speech);
      expect(heard.length, 40 * 512);
    });
    test('a short blip keeps its own segment', () {
      final speech = [for (var i = 0; i < 40; i++) frames(1)];
      expect(WhisperListener.heardAudio(frames(5), speech).length, 5 * 512);
    });
    test('more than Whisper reads keeps the segment', () {
      final speech = [for (var i = 0; i < 920; i++) frames(1)];
      expect(WhisperListener.heardAudio(frames(20), speech).length, 20 * 512);
    });
  });

  group('KokoroSpeaker.sentences', () {
    test('splits at sentence ends and line breaks', () {
      expect(KokoroSpeaker.sentences('Hello there. How are you?\nFine!'), [
        'Hello there.',
        'How are you?',
        'Fine!',
      ]);
    });

    test('drops pieces with no letters or digits', () {
      expect(KokoroSpeaker.sentences('Ok. ... \n - \n'), ['Ok.']);
    });

    test('cuts long sentences without losing characters', () {
      final long = List.generate(60, (i) => 'word$i').join(' ');
      final parts = KokoroSpeaker.sentences(long, max: 50);
      expect(parts.every((s) => s.length <= 50), isTrue);
      expect(parts.join(' '), long);
    });

    test('prefers a comma for long cuts', () {
      final text = '${'a' * 30}, ${'b ' * 40}end';
      final parts = KokoroSpeaker.sentences(text, max: 60);
      expect(parts.first, '${'a' * 30},');
    });

    test('a cut does not end on a small word', () {
      final parts = KokoroSpeaker.sentences(
        'The sky looks blue because of a process called Rayleigh scattering.',
        max: 34,
      );
      expect(parts.first, 'The sky looks blue because');
      expect(parts.join(' '), startsWith('The sky looks blue because of a'));
    });

    test('a word longer than the limit is cut hard', () {
      final parts = KokoroSpeaker.sentences('x' * 130, max: 50);
      expect(parts.join(), 'x' * 130);
    });
  });

  group('SentenceStream', () {
    test('gives finished sentences of a growing answer once', () {
      final s = SentenceStream();
      expect(s.take('The capital'), '');
      expect(s.take('The capital is Paris. It'), 'The capital is Paris.');
      expect(s.take('The capital is Paris. It has 2 million'), '');
      expect(
        s.take(
          'The capital is Paris. It has 2 million people. And',
          flush: true,
        ),
        ' It has 2 million people. And',
      );
    });

    test('does not cut at a decimal point', () {
      final s = SentenceStream();
      expect(s.take('It costs 3.5 euros'), '');
    });

    test('starts over when the answer is replaced', () {
      final s = SentenceStream();
      expect(s.take('Let me look that up.\n'), 'Let me look that up.\n');
      expect(
        s.take('Paris has about two million people. Yes'),
        'Paris has about two million people.',
      );
    });

    test('the first clause goes at its comma, later ones wait', () {
      final s = SentenceStream();
      expect(s.take('Yes, I'), '');
      expect(s.take('The sky looks blue because air scatters'), '');
      expect(
        s.take('The sky looks blue because air scatters, mostly blue light'),
        'The sky looks blue because air scatters,',
      );
      expect(
        s.take(
          'The sky looks blue because air scatters, mostly blue '
          'light, the short waves. Red',
        ),
        ' mostly blue light, the short waves.',
      );
    });

    test('"U.S." followed by a lowercase word is not a sentence end', () {
      final s = SentenceStream();
      expect(s.take('It costs more in the U.S. '), '');
      expect(s.take('It costs more in the U.S. is what'), '');
      expect(
        s.take('It costs more in the U.S. is what they say. It'),
        'It costs more in the U.S. is what they say.',
      );
      expect(KokoroSpeaker.sentences('The price in the U.S. is high. Yes.'), [
        'The price in the U.S. is high.',
        'Yes.',
      ]);
    });

    test('reset forgets what was taken', () {
      final s = SentenceStream()..take('One. Two');
      s.reset();
      expect(s.take('One. Two'), 'One.');
    });
  });

  group('WhisperListener.cleanTranscript', () {
    test('removes sound tags and extra spaces', () {
      expect(
        WhisperListener.cleanTranscript(' [Music]  What is   the weather? '),
        'What is the weather?',
      );
    });

    test('drops known inventions on silence', () {
      for (final t in [
        'Thank you for watching!',
        'Sous-titres réalisés par la communauté d\'Amara.org',
        'Gracias por ver.',
        '...',
        '(applause)',
      ]) {
        expect(WhisperListener.cleanTranscript(t), '', reason: t);
      }
    });

    test('drops cut-off tags and runaway loops heard on the phone', () {
      expect(WhisperListener.cleanTranscript('[Music'), '');
      expect(WhisperListener.cleanTranscript('(laughs'), '');
      expect(
        WhisperListener.cleanTranscript(
          List.filled(17, 'okay,').join(' ').replaceFirst('o', 'O'),
        ),
        '',
      );
      expect(
        WhisperListener.cleanTranscript(
          'Set a timer for five minutes, five minutes, five minutes, five '
          'minutes, five minutes.',
        ),
        'Set a timer for five minutes.',
      );
      expect(WhisperListener.cleanTranscript('No, no, no.'), 'No, no, no.');
      expect(
        WhisperListener.cleanTranscript("Don't touch. Don't touch."),
        "Don't touch. Don't touch.",
      );
    });

    test('keeps ordinary speech', () {
      expect(
        WhisperListener.cleanTranscript('Quel temps fait-il à Lyon ?'),
        'Quel temps fait-il à Lyon ?',
      );
    });
  });

  group('voice models', () {
    test('archive files the app does not need are skipped', () {
      expect(VoiceModels.skipped('/dict/jieba.dict.utf8'), isTrue);
      expect(VoiceModels.skipped('/lexicon-zh.txt'), isTrue);
      expect(VoiceModels.skipped('/phone-zh.fst'), isTrue);
      expect(VoiceModels.skipped('/README.md'), isTrue);
      expect(VoiceModels.skipped('/model.int8.onnx'), isFalse);
      expect(VoiceModels.skipped('/espeak-ng-data/fr_dict'), isFalse);
      expect(VoiceModels.skipped('/lexicon-us-en.txt'), isFalse);
    });

    test(
      'unpackArchive strips the top folder and writes the marker last',
      () async {
        final dir = await Directory.systemTemp.createTemp('voice_unpack');
        addTearDown(() => dir.delete(recursive: true));
        final archive = Archive()
          ..addFile(ArchiveFile.string('kokoro/model.int8.onnx', 'model'))
          ..addFile(ArchiveFile.string('kokoro/espeak-ng-data/fr_dict', 'fr'))
          ..addFile(ArchiveFile.string('kokoro/dict/jieba.dict.utf8', 'zh'))
          ..addFile(ArchiveFile.string('kokoro/README.md', 'readme'));
        final tar = TarEncoder().encode(archive);
        final bz = BZip2Encoder().encode(tar);
        final path = p.join(dir.path, 'pack.tar.bz2');
        File(path).writeAsBytesSync(bz);
        final out = p.join(dir.path, 'out');
        VoiceModels.unpackArchive(path, out);
        expect(
          File(p.join(out, 'model.int8.onnx')).readAsStringSync(),
          'model',
        );
        expect(
          File(p.join(out, 'espeak-ng-data', 'fr_dict')).readAsStringSync(),
          'fr',
        );
        expect(Directory(p.join(out, 'dict')).existsSync(), isFalse);
        expect(File(p.join(out, 'README.md')).existsSync(), isFalse);
        expect(File(p.join(out, VoiceModels.readyMarker)).existsSync(), isTrue);
        // The intermediate tar is removed.
        expect(File('$path.tar').existsSync(), isFalse);
      },
    );

    test('packs are pinned with hashes and sizes', () {
      for (final pack in VoiceModels.all) {
        for (final f in pack.files) {
          expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.url);
          expect(f.sizeBytes, greaterThan(0));
          expect(f.url, startsWith('https://'));
        }
      }
      // Whisper and Parakeet are pinned to a revision, not "main".
      for (final pack in [VoiceModels.listening, VoiceModels.parakeet]) {
        expect(pack.files.first.url, isNot(contains('/resolve/main/')));
      }
      // Parakeet is optional: not in the voice pack's one download row,
      // and it brings the Silero detector it needs.
      expect(VoiceModels.packs, isNot(contains(VoiceModels.parakeet)));
      expect(
        VoiceModels.parakeet.files.map((f) => f.fileName),
        contains('silero_vad.onnx'),
      );
      // Its own file names never collide with Whisper's.
      final whisper = VoiceModels.listening.files.map((f) => f.fileName);
      expect(
        VoiceModels.parakeet.files
            .map((f) => f.fileName)
            .where((n) => n != 'silero_vad.onnx' && whisper.contains(n)),
        isEmpty,
      );
    });

    test('the listening model setting keeps Parakeet or Whisper only', () {
      const s = InferenceSettings(listeningModel: 'parakeet-v3');
      expect(
        InferenceSettings.fromJson(s.toJson()).listeningModel,
        'parakeet-v3',
      );
      expect(
        InferenceSettings.fromJson({
          ...s.toJson(),
          'listeningModel': 'other',
        }).listeningModel,
        '',
      );
      expect(const InferenceSettings().listeningModel, '');
      const parakeet = ListeningPaths(
        encoder: 'e',
        decoder: 'd',
        tokens: 't',
        vad: 'v',
        joiner: 'j',
      );
      expect(parakeet.parakeet, isTrue);
      expect(
        const ListeningPaths(
          encoder: 'e',
          decoder: 'd',
          tokens: 't',
          vad: 'v',
        ).parakeet,
        isFalse,
      );
    });

    test('voices exist for each app language and fall back', () {
      expect(KokoroVoice.forLanguage('fr').lang, 'fr');
      expect(KokoroVoice.forLanguage('es').sid, 28);
      expect(KokoroVoice.forLanguage('es', sid: 29).name, 'Alex');
      // A speaker of another language falls back to the language default.
      expect(KokoroVoice.forLanguage('fr', sid: 3).sid, 30);
      expect(KokoroVoice.forLanguage('de').lang, 'en-us');
    });

    test('English voices use a lexicon; others go through espeak', () {
      const paths = SpeakingPaths(
        model: 'm',
        voices: 'v',
        tokens: 't',
        dataDir: 'd',
        lexiconUs: 'us',
        lexiconGb: 'gb',
      );
      expect(paths.lexiconFor('en-us'), 'us');
      expect(paths.lexiconFor('en-gb'), 'gb');
      expect(paths.lexiconFor('fr'), '');
    });
  });

  group('voice settings', () {
    test('defaults and JSON round trip', () {
      const s = InferenceSettings();
      expect(s.naturalVoice, isTrue);
      expect(s.kokoroSid, -1);
      expect(s.talkOver, isFalse);
      final back = InferenceSettings.fromJson(
        s.copyWith(naturalVoice: false, kokoroSid: 21, talkOver: true).toJson(),
      );
      expect(back.naturalVoice, isFalse);
      expect(back.kokoroSid, 21);
      expect(back.talkOver, isTrue);
    });

    test('voiceLanguage keeps supported codes only', () {
      expect(voiceLanguage('fr'), 'fr');
      expect(voiceLanguage('es'), 'es');
      expect(voiceLanguage('de'), 'en');
    });
  });

  group('conversation echo', () {
    const said = ['The capital of Australia is Canberra.', 'Yes.'];

    test('the answer heard back through the mic is echo', () {
      expect(
        ConversationScreen.echoOf(
          'capital of Australia is Canberra',
          said,
          duringSpeech: true,
        ),
        isTrue,
      );
    });

    test('a short echoed word counts only while the answer plays', () {
      expect(
        ConversationScreen.echoOf('Yes', said, duringSpeech: true),
        isTrue,
      );
      expect(
        ConversationScreen.echoOf('Yes', said, duringSpeech: false),
        isFalse,
      );
    });

    test('a new question is not echo', () {
      expect(
        ConversationScreen.echoOf(
          'And what about New Zealand?',
          said,
          duringSpeech: true,
        ),
        isFalse,
      );
      expect(
        ConversationScreen.echoOf('Stop', said, duringSpeech: true),
        isFalse,
      );
      expect(
        ConversationScreen.echoOf(
          'Is it Canberra',
          const [],
          duringSpeech: true,
        ),
        isFalse,
      );
    });
  });

  test(
    'KokoroSpeaker synthesizes what is queued while a sentence plays',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final log = <String>[];
      final playing = <Completer<bool>>[];
      const channel = MethodChannel('ondevice_llm/voice_audio');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method != 'play') return null;
            final done = Completer<bool>();
            playing.add(done);
            return done.future;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final speaker = KokoroSpeaker(
        voice: _LoggingVoice(log),
        kokoro: KokoroVoice.byLanguage['en']!.first,
      )..onSentence = (s) => log.add('play $s');
      speaker.add('One.');
      await pumpEventQueue();
      expect(log, ['synth One.', 'play One.']);
      // Two more arrive while the first plays: both start now, not after it.
      speaker.add('Two. Three.');
      await pumpEventQueue();
      expect(log, ['synth One.', 'play One.', 'synth Two.', 'synth Three.']);
      // "Two." is already queued at the player; it starts when "One." ends.
      expect(playing, hasLength(2));
      playing.first.complete(true);
      await pumpEventQueue();
      expect(log.last, 'play Two.');
      await speaker.stop();
    },
  );
}

class _LoggingVoice extends SherpaVoice {
  final List<String> log;
  _LoggingVoice(this.log);

  @override
  Future<SpeechAudio?> synthesize(
    String text, {
    required KokoroVoice voice,
    double speed = 1.0,
  }) async {
    log.add('synth $text');
    return SpeechAudio(Int16List(240), 24000);
  }
}
