// Speech recognition on the tester's own voice: the phone shows a phrase,
// the tester reads it aloud, and the recording goes through each engine:
// Whisper base the old way (the detector's tight segment), Whisper base
// the new way (from just before the first word to the pause after the
// last), Whisper small and Parakeet TDT 0.6B v3 when their files are in
// files/media. Prints one ASR: JSON line per phrase and engine with the
// text, word error rate and time; saves each recording as asr-<n>.wav.
// Run through scripts/test-android.ps1 -Test integration_test/asr_probe_test.dart
// -VoicePack -Media <small-*.onnx, small-tokens.txt, encoder/decoder/joiner.int8.onnx, tokens.txt>.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const _phrases = [
  'Hi, how are you?',
  'Are you able to do online searches?',
  'What is the weather like in Rome today?',
  'Set a timer for five minutes.',
  'Tell me a joke about cats.',
  'Remind me to call my mother tomorrow at nine.',
];

/// Seconds the tester has to say each phrase.
const _window = 6;

void _report(Map<String, Object?> m) {
  // ignore: avoid_print
  print('ASR: ${jsonEncode(m)}');
}

List<String> _words(String s) => RegExp(
  r"[\p{L}\p{N}']+",
  unicode: true,
).allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();

/// Word error rate of [heard] against [said].
double _wer(String said, String heard) {
  final a = _words(said), b = _words(heard);
  final d = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final sub = d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      d[i][j] = [
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        sub,
      ].reduce((x, y) => x < y ? x : y);
    }
  }
  return a.isEmpty ? 0 : d[a.length][b.length] / a.length;
}

class _Engine {
  final String name;
  final sherpa.OfflineRecognizer recognizer;
  _Engine(this.name, this.recognizer);

  String run(Float32List samples) {
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('speech recognition on the tester\'s voice', (tester) async {
    final prompt = ValueNotifier<String>('Getting ready…');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ValueListenableBuilder<String>(
                valueListenable: prompt,
                builder: (_, text, _) => Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 34),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    sherpa.initBindings();
    final support = await getApplicationSupportDirectory();
    final files = support.parent.path; // files/ (support dir is files/…)
    String find(String dir, String name) {
      for (final d in [dir, '$files/$dir', '${support.path}/$dir']) {
        final f = File('$d/$name');
        if (f.existsSync()) return f.path;
      }
      return '';
    }

    final voice = find('voice', 'silero_vad.onnx').isNotEmpty
        ? File(find('voice', 'silero_vad.onnx')).parent.path
        : '';
    expect(voice, isNotEmpty, reason: 'Run with -VoicePack');
    final media = Directory('$files/media').existsSync()
        ? '$files/media'
        : '${support.path}/media';
    _report({'voice': voice, 'media': media});

    final engines = <_Engine>[];
    sherpa.OfflineRecognizer whisper(String enc, String dec, String tok) =>
        sherpa.OfflineRecognizer(
          sherpa.OfflineRecognizerConfig(
            model: sherpa.OfflineModelConfig(
              whisper: sherpa.OfflineWhisperModelConfig(
                encoder: enc,
                decoder: dec,
                language: 'en',
                task: 'transcribe',
              ),
              tokens: tok,
              numThreads: 4,
              debug: false,
            ),
          ),
        );
    engines.add(
      _Engine(
        'base',
        whisper(
          '$voice/whisper-base-encoder.int8.onnx',
          '$voice/whisper-base-decoder.int8.onnx',
          '$voice/whisper-base-tokens.txt',
        ),
      ),
    );
    if (File('$media/small-encoder.int8.onnx').existsSync()) {
      final clock = Stopwatch()..start();
      engines.add(
        _Engine(
          'small',
          whisper(
            '$media/small-encoder.int8.onnx',
            '$media/small-decoder.int8.onnx',
            '$media/small-tokens.txt',
          ),
        ),
      );
      _report({'load': 'small', 'ms': clock.elapsedMilliseconds});
    }
    if (File('$media/joiner.int8.onnx').existsSync()) {
      final clock = Stopwatch()..start();
      engines.add(
        _Engine(
          'parakeet',
          sherpa.OfflineRecognizer(
            sherpa.OfflineRecognizerConfig(
              model: sherpa.OfflineModelConfig(
                transducer: sherpa.OfflineTransducerModelConfig(
                  encoder: '$media/encoder.int8.onnx',
                  decoder: '$media/decoder.int8.onnx',
                  joiner: '$media/joiner.int8.onnx',
                ),
                tokens: '$media/tokens.txt',
                modelType: 'nemo_transducer',
                numThreads: 4,
                debug: false,
              ),
            ),
          ),
        ),
      );
      _report({'load': 'parakeet', 'ms': clock.elapsedMilliseconds});
    }
    // Warm each engine once (the first decode pays for allocations).
    for (final e in engines) {
      e.run(Float32List(16000));
    }

    sherpa.VoiceActivityDetector detector() => sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: '$voice/silero_vad.onnx',
          minSilenceDuration: 0.7,
          minSpeechDuration: 0.25,
          maxSpeechDuration: 28,
        ),
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 40,
    );

    final out = await getApplicationDocumentsDirectory();
    final totals = <String, List<double>>{};
    // Two rounds: the recognition microphone (new default), then the call
    // microphone with echo cancelling and noise suppression (talk over).
    for (final call in [false, true]) {
      final source = call ? 'call' : 'recognition';
      await VoiceAudioChannel.conversation(true, call: call);
      for (var p = 0; p < _phrases.length; p++) {
        final phrase = _phrases[p];
        final frames = <Float32List>[];
        final sub = VoiceAudioChannel.frames().listen(frames.add);
        prompt.value = 'Get ready to say:\n\n“$phrase”';
        await tester.pump();
        // For scripts/speak-asr-phrases.ps1, which says it from the
        // computer's speakers when nobody reads it: told now, its voice
        // reaches the phone about when the microphone opens (told after,
        // it arrived 3 s into the window and was cut off, 2026-10-20).
        _report({'say': p, 'source': source, 'phrase': phrase});
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        prompt.value = 'Say it now:\n\n“$phrase”';
        await tester.pump();
        frames.clear();
        if (!await VoiceAudioChannel.startMic()) {
          fail('Microphone refused');
        }
        await Future<void>.delayed(const Duration(seconds: _window));
        await VoiceAudioChannel.stopMic();
        await sub.cancel();
        prompt.value = 'Thanks…';
        await tester.pump();

        final all = Float32List(frames.length * 512);
        for (var i = 0; i < frames.length; i++) {
          all.setAll(i * 512, frames[i]);
        }
        File('${out.path}/asr-$source-$p.wav').writeAsBytesSync(_wav(all));
        // The detector, as in the app; a new one per phrase, so segment
        // starts count from this clip. One kept across phrases drifted:
        // clear() does not reset its count, the second phrase's segment
        // started 3.9 s before its clip, and the third crashed sherpa's
        // decoder (2026-10-18, again 2026-10-20).
        final vad = detector();
        final segments = <sherpa.SpeechSegment>[];
        for (final f in frames) {
          vad.acceptWaveform(f);
          while (!vad.isEmpty()) {
            segments.add(vad.front());
            vad.pop();
          }
        }
        vad.flush();
        while (!vad.isEmpty()) {
          segments.add(vad.front());
          vad.pop();
        }
        vad.free();
        if (segments.isEmpty) {
          _report({'source': source, 'phrase': phrase, 'heard': 'nothing'});
          continue;
        }
        final first = segments.first, last = segments.last;
        final tight = Float32List.fromList([
          for (final s in segments) ...s.samples,
        ]);
        // The new way: 0.5 s before the first word to 0.7 s after the last.
        final from = (first.start - 8000).clamp(0, all.length);
        final to = (last.start + last.samples.length + 11200).clamp(
          from,
          all.length,
        );
        final padded = Float32List.sublistView(all, from, to);
        if (padded.length < SherpaVoice.minSamples) {
          _report({'source': source, 'phrase': phrase, 'heard': 'nothing'});
          continue;
        }
        for (final e in engines) {
          final runs = e.name == 'base'
              ? {'base-tight': tight, 'base': padded}
              : {e.name: padded};
          for (final r in runs.entries) {
            final clock = Stopwatch()..start();
            final text = e.run(r.value);
            final ms = clock.elapsedMilliseconds;
            final wer = _wer(phrase, text);
            (totals['${r.key}/$source'] ??= []).add(wer);
            _report({
              'source': source,
              'engine': r.key,
              'phrase': phrase,
              'heard': text,
              'wer': double.parse(wer.toStringAsFixed(2)),
              'ms': ms,
              'audioS': r.value.length / 16000,
            });
          }
        }
      }
      await VoiceAudioChannel.conversation(false);
    }
    prompt.value = 'Done — thank you!';
    await tester.pump();
    _report({
      'summary': {
        for (final e in totals.entries)
          e.key: double.parse(
            (e.value.reduce((a, b) => a + b) / e.value.length).toStringAsFixed(
              2,
            ),
          ),
      },
    });
    for (final e in engines) {
      e.recognizer.free();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Uint8List _wav(Float32List samples) {
  final b = BytesBuilder();
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(
      i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  final h = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + data.lengthInBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, data.lengthInBytes, Endian.little);
  b
    ..add(h.buffer.asUint8List())
    ..add(data.buffer.asUint8List());
  return b.toBytes();
}
