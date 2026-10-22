// Audit-only phone probe. Uses the real native model and Kokoro, with silent
// PCM of the same duration for AudioTrack timing; it never starts the mic.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/voice/conversation_screen.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_pipeline.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';

const _model = String.fromEnvironment('BENCH_MODEL');

void _report(Map<String, Object?> data) =>
    debugPrint('AUDIT_PHONE: ${jsonEncode(data)}');

Future<int?> _rssKb() async {
  final status = await File('/proc/self/status').readAsString();
  final match = RegExp(r'^VmRSS:\s+(\d+)', multiLine: true).firstMatch(status);
  return match == null ? null : int.parse(match[1]!);
}

class _SilentVoice extends SherpaVoice {
  final SherpaVoice real;
  final Stopwatch clock;
  final List<Map<String, Object?>> events;
  _SilentVoice(this.real, this.clock, this.events);

  @override
  Future<SpeechAudio?> synthesize(
    String text, {
    required KokoroVoice voice,
    double speed = 1,
  }) async {
    final requested = clock.elapsedMilliseconds;
    final audio = await real.synthesize(text, voice: voice, speed: speed);
    final ready = clock.elapsedMilliseconds;
    events.add({
      'kind': 'synthesis',
      'text': text,
      'requestedMs': requested,
      'readyMs': ready,
      'durationMs': audio == null
          ? 0
          : audio.pcm.length * 1000 ~/ audio.sampleRate,
    });
    return audio == null
        ? null
        : SpeechAudio(Int16List(audio.pcm.length), audio.sampleRate);
  }
}

Future<Map<String, Object?>> _generate(
  LlamaEngine engine,
  InferenceSettings settings, {
  SherpaVoice? voice,
  String question =
      'Why does the sky look blue? Explain in three short sentences.',
}) async {
  final clock = Stopwatch()..start();
  final stream = SentenceStream();
  final events = <Map<String, Object?>>[];
  int? firstText, firstClause, firstAudio;
  final speaker = voice == null
      ? null
      : KokoroSpeaker(
          voice: _SilentVoice(voice, clock, events),
          kokoro: KokoroVoice.forLanguage('en'),
        );
  if (speaker != null) {
    speaker.onAudio = (audio) {
      firstAudio ??= clock.elapsedMilliseconds;
    };
    speaker.onPlaying = (playing) => events.add({
      'kind': playing ? 'play_start' : 'play_end',
      'ms': clock.elapsedMilliseconds,
    });
    speaker.onError = (error) =>
        events.add({'kind': 'error', 'error': '$error'});
  }
  final answer = StringBuffer();
  await for (final piece in engine.generate(
    messages: [
      {'role': 'system', 'content': ConversationScreen.spokenStyle},
      {'role': 'user', 'content': question},
    ],
    fallbackTemplate: '',
    settings: settings,
  )) {
    firstText ??= clock.elapsedMilliseconds;
    answer.write(piece);
    final clause = stream.take(answer.toString());
    if (clause.trim().isNotEmpty) {
      firstClause ??= clock.elapsedMilliseconds;
      speaker?.add(clause);
    }
  }
  final doneText = clock.elapsedMilliseconds;
  final tail = stream.take(answer.toString(), flush: true);
  if (tail.trim().isNotEmpty) {
    firstClause ??= clock.elapsedMilliseconds;
    speaker?.add(tail);
  }
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (speaker?.busy == true && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final stalled = speaker?.busy == true;
  await speaker?.stop();
  return {
    'threads': settings.cpuThreads,
    'withSpeech': voice != null,
    'firstTextMs': firstText,
    'firstClauseMs': firstClause,
    'firstAudioReadyMs': firstAudio,
    'textDoneMs': doneText,
    'playbackDoneMs': clock.elapsedMilliseconds,
    'stalled': stalled,
    'answer': answer.toString(),
    'events': events,
    'rssKb': await _rssKb(),
    'metrics': {
      for (final e in engine.metrics.entries)
        if (e.value is num || e.value is String || e.value is bool)
          e.key: e.value,
    },
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('audit speech latency and CPU contention', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Audit: silent speech latency probe')),
      ),
    );
    expect(_model, isNotEmpty);
    final pack = Directory(
      '${(await getApplicationSupportDirectory()).path}/voice',
    );
    final modelDir = await ModelStorage.modelsDir();
    for (final file in pack.listSync(recursive: true).whereType<File>()) {
      final target = File(
        '${modelDir.path}/${file.path.substring(pack.path.length + 1)}',
      );
      if (target.existsSync() && target.lengthSync() == file.lengthSync()) {
        continue;
      }
      target.parent.createSync(recursive: true);
      file.copySync(target.path);
    }
    final voice = SherpaVoice(speakThreads: 2);
    addTearDown(voice.dispose);
    final kokoro = KokoroVoice.forLanguage('en');
    final loadClock = Stopwatch()..start();
    await voice.warmSpeaking(kokoro);
    _report({
      'kind': 'voice_load',
      'ms': loadClock.elapsedMilliseconds,
      'rssKb': await _rssKb(),
    });
    for (final text in [
      'Hello there.',
      'The sky looks blue because air scatters light.',
      'The sky looks blue because air scatters the short blue waves of sunlight more than the long red ones.',
    ]) {
      for (var sample = 0; sample < 3; sample++) {
        final clock = Stopwatch()..start();
        final audio = await voice.synthesize(text, voice: kokoro);
        expect(audio, isNotNull);
        _report({
          'kind': 'tts_alone',
          'text': text,
          'sample': sample,
          'synthMs': clock.elapsedMilliseconds,
          'audioMs': audio!.pcm.length * 1000 ~/ audio.sampleRate,
          'rssKb': await _rssKb(),
        });
      }
    }
    for (final threads in [2, 4, 6]) {
      final engine = LlamaEngine(
        cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
      );
      final settings = InferenceSettings(
        backend: GpuBackend.cpu,
        cpuThreads: threads,
        contextSize: 4096,
        maxTokens: 96,
        temperature: 0,
        thinkingModeEnabled: false,
        promptCache: false,
      );
      final load = Stopwatch()..start();
      await engine.loadModel(modelPath: _model, settings: settings);
      _report({
        'kind': 'model_load',
        'threads': threads,
        'ms': load.elapsedMilliseconds,
      });
      await _generate(engine, settings.copyWith(maxTokens: 8));
      for (var sample = 0; sample < 3; sample++) {
        _report({
          'kind': 'llm_alone',
          'sample': sample,
          ...await _generate(engine, settings),
        });
      }
      _report({
        'kind': 'llm_with_speech',
        ...await _generate(engine, settings, voice: voice),
      });
      engine.dispose();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
