// The on-device voice on the phone: Silero VAD + Whisper on recorded voice
// notes, Kokoro → Whisper round trips, and the live microphone channel
// (the Conversation screen heard nothing on 2026-10-07 because every mic
// frame threw). Prints VOICE: JSON lines with timings and transcripts.
//
// Run through scripts/test-android.ps1 -Test integration_test/voice_probe_test.dart
// -Media test-assets/media/memo-dentist.wav,test-assets/media/memo-rent.wav
// -VoicePack (the installed app's voice pack: Whisper, Silero VAD, Kokoro;
// also grants the .smoke app RECORD_AUDIO)
// While "mic-start" is printed, speech played
// near the phone is recorded for MIC_SECONDS, saved as files/mic.wav in the
// external files dir and transcribed.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_pipeline.dart';
import 'package:path_provider/path_provider.dart';

const _micSeconds = int.fromEnvironment('MIC_SECONDS', defaultValue: 14);

void _report(String name, Map<String, Object?> data) =>
    debugPrint('VOICE: ${jsonEncode({'probe': name, ...data})}');

/// 16-bit PCM WAV → mono float samples and the rate.
(Float32List, int) _readWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var at = 12, rate = 16000, channels = 1;
  while (at + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(at, at + 4));
    final size = data.getUint32(at + 4, Endian.little);
    if (id == 'fmt ') {
      channels = data.getUint16(at + 10, Endian.little);
      rate = data.getUint32(at + 12, Endian.little);
    } else if (id == 'data') {
      final n = size ~/ (2 * channels);
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] =
            data.getInt16(at + 8 + 2 * i * channels, Endian.little) / 32768.0;
      }
      return (out, rate);
    }
    at += 8 + size + (size & 1);
  }
  throw const FormatException('no data chunk');
}

Uint8List _wav(Float32List samples, int rate) {
  final out = ByteData(44 + samples.length * 2);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + samples.length * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, rate, Endian.little);
  out.setUint32(28, rate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  out.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(
      44 + 2 * i,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return out.buffer.asUint8List();
}

/// Linear resampling (Kokoro speaks at 24 kHz, Whisper listens at 16).
Float32List _resample(Float32List x, int from, int to) {
  if (from == to) return x;
  final out = Float32List((x.length * to / from).floor());
  for (var i = 0; i < out.length; i++) {
    final t = i * from / to;
    final j = t.floor();
    final f = t - j;
    final a = x[math.min(j, x.length - 1)];
    final b = x[math.min(j + 1, x.length - 1)];
    out[i] = a + (b - a) * f;
  }
  return out;
}

double _rms(Float32List x) {
  if (x.isEmpty) return 0;
  var s = 0.0;
  for (final v in x) {
    s += v * v;
  }
  return math.sqrt(s / x.length);
}

/// Utterances the VAD finds in [samples], fed in 512-sample windows the way
/// the microphone delivers them, then a second of silence.
List<Float32List> _segments(String vadModel, Float32List samples) {
  final vad = SpeechDetector.create(vadModel);
  final out = <Float32List>[];
  final padded = Float32List(samples.length + 16000)..setAll(0, samples);
  for (var at = 0; at + 512 <= padded.length; at += 512) {
    out.addAll(vad.accept(Float32List.sublistView(padded, at, at + 512)));
  }
  vad.dispose();
  return out;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Whisper, Kokoro and the microphone work on the phone', (
    tester,
  ) async {
    // test-android.ps1 -VoicePack leaves the pack in files/voice; the app
    // looks for it next to the models.
    final pack = Directory(
      '${(await getApplicationSupportDirectory()).path}/voice',
    );
    if (pack.existsSync()) {
      final models = await ModelStorage.modelsDir();
      for (final e in pack.listSync(recursive: true).whereType<File>()) {
        final to = File(
          '${models.path}/${e.path.substring(pack.path.length + 1)}',
        );
        if (to.existsSync() && to.lengthSync() == e.lengthSync()) continue;
        to.parent.createSync(recursive: true);
        e.copySync(to.path);
      }
    }
    final listening = await VoiceModels.listeningPaths();
    final speaking = await VoiceModels.speakingPaths();
    _report('models', {
      'listening': listening != null,
      'speaking': speaking != null,
      'dir': (await getExternalStorageDirectory())?.path,
    });
    expect(listening, isNotNull, reason: 'copy the voice pack first');
    final voice = SherpaVoice();
    final clock = Stopwatch()..start();
    await voice.warmListening('en');
    _report('warm-whisper', {'ms': clock.elapsedMilliseconds});

    // ---- Voice notes from a file --------------------------------------
    final media = Directory(
      '${(await getApplicationSupportDirectory()).path}/media',
    );
    for (final name in ['memo-dentist.wav', 'memo-rent.wav']) {
      final file = File('${media.path}/$name');
      if (!file.existsSync()) {
        _report('file-missing', {'file': name});
        continue;
      }
      final (samples, rate) = _readWav(await file.readAsBytes());
      final pcm = _resample(samples, rate, 16000);
      clock.reset();
      final whole = await voice.transcribe(pcm, language: 'en');
      final wholeMs = clock.elapsedMilliseconds;
      final segments = _segments(listening!.vad, pcm);
      final heard = <String>[];
      clock.reset();
      for (final s in segments) {
        final h = await voice.transcribe(s, language: 'en');
        heard.add(WhisperListener.cleanTranscript(h?.text ?? ''));
      }
      _report('file', {
        'file': name,
        'seconds': (pcm.length / 16000).toStringAsFixed(1),
        'whole': whole?.text,
        'wholeMs': wholeMs,
        'segments': segments.length,
        'segmentText': heard,
        'segmentMs': clock.elapsedMilliseconds,
      });
      expect(segments, isNotEmpty, reason: 'VAD found no speech in $name');
      expect((whole?.text ?? '').trim(), isNotEmpty);
    }

    // ---- Kokoro → Whisper round trips ---------------------------------
    if (speaking != null) {
      const lines = {
        'en': 'Remind me to call the dentist tomorrow at nine.',
        'fr': 'Quelle est la capitale du Canada?',
        'es': '¿Qué tiempo hace hoy en Madrid?',
      };
      for (final e in lines.entries) {
        final kokoro = KokoroVoice.forLanguage(e.key);
        clock.reset();
        final audio = await voice.synthesize(e.value, voice: kokoro);
        final synthMs = clock.elapsedMilliseconds;
        if (audio == null) {
          _report('kokoro', {'lang': e.key, 'audio': null});
          continue;
        }
        final f = Float32List(audio.pcm.length);
        for (var i = 0; i < f.length; i++) {
          f[i] = audio.pcm[i] / 32768.0;
        }
        final pcm = _resample(f, audio.sampleRate, 16000);
        clock.reset();
        final back = await voice.transcribe(pcm, language: e.key);
        _report('kokoro', {
          'lang': e.key,
          'said': e.value,
          'seconds': (f.length / audio.sampleRate).toStringAsFixed(1),
          'synthMs': synthMs,
          'heard': back?.text,
          'transcribeMs': clock.elapsedMilliseconds,
          'segments': _segments(listening!.vad, pcm).length,
        });
        expect(audio.pcm.length, greaterThan(audio.sampleRate ~/ 2));
      }
    }

    // Warm speed (the round trips above include loading each language).
    if (speaking != null) {
      final en = KokoroVoice.forLanguage('en');
      for (final text in [
        'Remind me to call the dentist tomorrow at nine.',
        'Ottawa is the capital of Canada, and it sits on the Ottawa River, '
            'right across from Gatineau in the province of Quebec.',
      ]) {
        clock.reset();
        final audio = await voice.synthesize(text, voice: en);
        final ms = clock.elapsedMilliseconds;
        final seconds = audio!.pcm.length / audio.sampleRate;
        _report('kokoro-warm', {
          'chars': text.length,
          'ms': ms,
          'seconds': seconds.toStringAsFixed(1),
          'realTime': (ms / 1000 / seconds).toStringAsFixed(2),
        });
      }
    }

    // Kokoro is the slow half on a phone CPU, and threads do not help
    // (2, 6 and 8 all took ~7 s for 6.2 s of speech, 2026-10-07). The
    // full-precision model, when pushed as media/kokoro-fp32.onnx, is
    // timed in place of the int8 one.
    final fp32 = File('${media.path}/kokoro-fp32.onnx');
    if (speaking != null && fp32.existsSync()) {
      const text =
          'Ottawa is the capital of Canada, and it sits on the Ottawa River, '
          'right across from Gatineau in the province of Quebec.';
      final en = KokoroVoice.forLanguage('en');
      for (final provider in ['xnnpack', 'nnapi']) {
        try {
          final v = SherpaVoice(speakProvider: provider);
          clock.reset();
          await v.warmSpeaking(en);
          final loadMs = clock.elapsedMilliseconds;
          final times = <int>[];
          for (var i = 0; i < 2; i++) {
            clock.reset();
            await v.synthesize(text, voice: en);
            times.add(clock.elapsedMilliseconds);
          }
          v.dispose();
          _report('kokoro-int8', {
            'provider': provider,
            'loadMs': loadMs,
            'ms': times,
          });
        } catch (e) {
          _report('kokoro-int8', {'provider': provider, 'error': '$e'});
        }
      }
      final int8 = File(speaking.model);
      final aside = '${speaking.model}.aside';
      int8.renameSync(aside);
      try {
        fp32.copySync(speaking.model);
        for (final provider in ['cpu', 'xnnpack', 'nnapi']) {
          try {
            final v = SherpaVoice(speakProvider: provider);
            clock.reset();
            await v.warmSpeaking(en);
            final loadMs = clock.elapsedMilliseconds;
            final times = <int>[];
            double seconds = 0;
            for (var i = 0; i < 2; i++) {
              clock.reset();
              final audio = await v.synthesize(text, voice: en);
              times.add(clock.elapsedMilliseconds);
              seconds = audio!.pcm.length / audio.sampleRate;
            }
            v.dispose();
            _report('kokoro-fp32', {
              'provider': provider,
              'loadMs': loadMs,
              'ms': times,
              'seconds': seconds.toStringAsFixed(1),
            });
          } catch (e) {
            _report('kokoro-fp32', {'provider': provider, 'error': '$e'});
          }
        }
      } finally {
        File(speaking.model).deleteSync();
        File(aside).renameSync(speaking.model);
      }
    }

    // ---- The live microphone ------------------------------------------
    final frames = <Float32List>[];
    final errors = <String>[];
    final sub = VoiceAudioChannel.frames().listen(
      frames.add,
      onError: (Object e) => errors.add('$e'),
    );
    final started = await VoiceAudioChannel.startMic();
    _report('mic-start', {'ok': started, 'seconds': _micSeconds});
    if (started) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: _micSeconds)),
      );
    }
    await VoiceAudioChannel.stopMic();
    await sub.cancel();
    final joined = Float32List(frames.fold(0, (a, f) => a + f.length));
    var at = 0;
    for (final f in frames) {
      joined.setAll(at, f);
      at += f.length;
    }
    final levels = [
      for (var i = 0; i + 16000 <= joined.length; i += 16000)
        double.parse(
          _rms(
            Float32List.sublistView(joined, i, i + 16000),
          ).toStringAsFixed(4),
        ),
    ];
    final ext = await getExternalStorageDirectory();
    if (ext != null && joined.isNotEmpty) {
      await File('${ext.path}/mic.wav').writeAsBytes(_wav(joined, 16000));
    }
    final segments = joined.isEmpty
        ? const <Float32List>[]
        : _segments(listening!.vad, joined);
    final heard = <String>[];
    for (final s in segments) {
      final h = await voice.transcribe(s, language: 'en');
      heard.add('${h?.text}');
    }
    _report('mic', {
      'ok': started,
      'frames': frames.length,
      'frameSizes': frames.map((f) => f.length).toSet().toList(),
      'errors': errors.take(3).toList(),
      'rmsPerSecond': levels,
      'segments': segments.length,
      'heard': heard,
    });
    if (started) {
      expect(errors, isEmpty);
      expect(frames.length, greaterThan(_micSeconds * 20));
    }

    // ---- Echo: the answer heard by the microphone -----------------------
    // The call path is echo-cancelled but sounds like a phone call; the
    // media path is full quality. How much of each leaks into the mic,
    // and would it be taken for the user talking (VAD segments, Whisper)?
    if (started && speaking != null) {
      final answer = await voice.synthesize(
        'The capital of Canada is Ottawa. It sits on the Ottawa River, '
        'across from Gatineau in Quebec.',
        voice: KokoroVoice.forLanguage('en'),
      );
      for (final call in [true, false]) {
        await VoiceAudioChannel.conversation(true, call: call);
        final heardFrames = <Float32List>[];
        final s = VoiceAudioChannel.frames().listen(heardFrames.add);
        await VoiceAudioChannel.startMic();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await VoiceAudioChannel.play(answer!);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await VoiceAudioChannel.stopMic();
        await s.cancel();
        await VoiceAudioChannel.conversation(false);
        final all = Float32List(heardFrames.fold(0, (a, f) => a + f.length));
        var k = 0;
        for (final f in heardFrames) {
          all.setAll(k, f);
          k += f.length;
        }
        final name = call ? 'call' : 'media';
        if (ext != null) {
          await File(
            '${ext.path}/echo-$name.wav',
          ).writeAsBytes(_wav(all, 16000));
        }
        final segs = _segments(listening!.vad, all);
        final texts = <String>[];
        for (final seg in segs) {
          texts.add('${(await voice.transcribe(seg, language: 'en'))?.text}');
        }
        _report('echo', {
          'path': name,
          'seconds': (all.length / 16000).toStringAsFixed(1),
          'rms': double.parse(_rms(all).toStringAsFixed(4)),
          'peakRmsPerSecond': [
            for (var i = 0; i + 16000 <= all.length; i += 16000)
              double.parse(
                _rms(
                  Float32List.sublistView(all, i, i + 16000),
                ).toStringAsFixed(4),
              ),
          ],
          'segments': segs.length,
          'heard': texts,
        });
      }
    }
    voice.dispose();
  });
}
