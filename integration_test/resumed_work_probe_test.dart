import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/core/platform/build_identity.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/attachments/domain/scan_options.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_media.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_grounding.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/zim/zim_article_page.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'package:ondevice_llm/main.dart' as application;
import 'package:ondevice_llm/features/goals/goal_watch.dart';
import 'package:ondevice_llm/features/goals/goal_watch_store.dart';
import 'package:ondevice_llm/features/schedule/scheduled_prompt.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'eg2_probe_test.dart' as embedding;

Future<File> _tone(Directory dir, int rate, int channels, int seconds) async {
  final file = File('${dir.path}/tone-$rate-$channels-$seconds.wav');
  final frames = rate * seconds;
  final header = ByteData.sublistView(
    KnowledgeMedia.wavBytes(Uint8List(0), rate),
  );
  header.setUint32(4, 36 + frames * channels * 2, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(28, rate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint32(40, frames * channels * 2, Endian.little);
  final block = ByteData(rate * channels * 2);
  for (var i = 0; i < rate; i++) {
    for (var c = 0; c < channels; c++) {
      block.setInt16(
        (i * channels + c) * 2,
        (math.sin(2 * math.pi * 440 * i / rate) * (c == 0 ? .5 : .25) * 32767)
            .round(),
        Endian.little,
      );
    }
  }
  final out = await file.open(mode: FileMode.write);
  try {
    await out.writeFrom(header.buffer.asUint8List());
    for (var i = 0; i < seconds; i++) {
      await out.writeFrom(block.buffer.asUint8List());
    }
  } finally {
    await out.close();
  }
  return file;
}

const _actionModel = String.fromEnvironment('ACTION_MODEL');

class _ActionProbeSettings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(
      contextSize: 4096,
      cpuThreads: 4,
      maxTokens: 192,
      temperature: 0,
      thinkingModeEnabled: false,
      autoTitles: false,
      promptCache: true,
    );
  }
}

class _ActionProbeModels extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(
      loadedModelId: 'action-probe',
      catalog: [
        ModelInfo(
          id: 'action-probe',
          displayName: 'Qwen 0.8B probe',
          fileName: 'Qwen3.5-0.8B-IQ4_NL.gguf',
          localPath: _actionModel,
          family: ModelFamily.qwen,
          quantization: ModelQuantization.iq4_nl,
          sizeBytes: 0,
          isDownloaded: true,
        ),
      ],
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a headless Android watch persists its result with the UI closed', (
    tester,
  ) async {
    // Retain the production entry library in the integration-test kernel.
    expect(application.goalWatchBackgroundMain, isNotNull);
    final schedules = await ScheduleStore.list();
    final prefs = await SharedPreferences.getInstance();
    final previousSettings = prefs.getString('inference_settings_v1');
    final id = ScheduledPrompt.freshId(schedules);
    final before = DateTime.now().subtract(const Duration(days: 2));
    final watch = GoalWatch(
      id: id,
      objective: 'Nikon Z30 weight',
      query: 'Nikon Z30 weight',
      hour: 0,
      minute: 0,
      createdAt: before,
      last: GoalWatchSnapshot(before, const []),
      lastCheckedAt: before,
    );
    try {
      await prefs.setString(
        'inference_settings_v1',
        jsonEncode(const InferenceSettings(webMode: WebMode.auto).toJson()),
      );
      await ScheduleStore.save([
        ...schedules,
        ScheduledPrompt(
          id: id,
          prompt: watch.objective,
          kind: 'goal',
          hour: 0,
          minute: 0,
        ),
      ]);
      await GoalWatchStore.put(watch);
      // The harness operator presses Home during this window. No Activity
      // is launched by the job; afterward the operator restores the test UI.
      // ignore: avoid_print
      print('GOAL_WATCH_READY_FOR_HOME');
      await Future<void>.delayed(const Duration(seconds: 20));
      await GoalWatchStore.enqueue();
      GoalWatch? updated;
      final deadline = DateTime.now().add(const Duration(seconds: 75));
      while (DateTime.now().isBefore(deadline)) {
        updated = (await GoalWatchStore.list())
            .where((w) => w.id == id)
            .firstOrNull;
        if (updated?.lastCheckedAt?.isAfter(before) == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(updated?.lastCheckedAt?.isAfter(before), isTrue);
      // A network failure must still be persisted; useful live coverage is
      // checked separately. Neither failure nor unchanged results notify.
      // ignore: avoid_print
      print(
        'RESUME_WATCH_JOB: ${jsonEncode({'build': BuildIdentity.toJson(), 'checkedAt': updated!.lastCheckedAt!.toIso8601String(), 'error': updated.lastError, 'fresh': updated.lastChange?.fresh.length})}',
      );
      await Future<void>.delayed(const Duration(seconds: 8));
    } finally {
      await GoalWatchStore.remove(id);
      await ScheduleStore.save(schedules);
      if (previousSettings == null) {
        await prefs.remove('inference_settings_v1');
      } else {
        await prefs.setString('inference_settings_v1', previousSettings);
      }
    }
  });
  testWidgets('streamed audio preserves resampling and bounds cancellation', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('decode-probe-');
    addTearDown(() => dir.delete(recursive: true));
    final measurements = <Map<String, Object?>>[];
    for (final (rate, channels) in [(8000, 1), (22050, 1), (48000, 2)]) {
      final source = await _tone(dir, rate, channels, 2);
      final clock = Stopwatch()..start();
      final decoded = await KnowledgeMedia.decodeAudio(source);
      final samples = await KnowledgeMedia.transcriptionSamples(decoded.$1);
      expect(samples.length, 32000);
      var error = 0.0;
      final amplitude = channels == 1 ? .5 : .375;
      for (var i = 100; i < samples.length - 100; i++) {
        final difference =
            samples[i] - amplitude * math.sin(2 * math.pi * 440 * i / 16000);
        error += difference * difference;
      }
      final rms = math.sqrt(error / (samples.length - 200));
      expect(
        rms,
        lessThan(.015),
        reason: 'correct time axis, downmix and interpolation',
      );
      measurements.add({
        'sourceRate': rate,
        'channels': channels,
        'ms': clock.elapsedMilliseconds,
        'rms': rms,
      });
      await decoded.$1.delete();
      if (rate == 48000) {
        await expectLater(
          KnowledgeMedia.decodeAudio(source, maxSeconds: 1),
          throwsA(isA<FormatException>()),
        );
      }
    }
    final long = await _tone(dir, 48000, 2, 180);
    var cancelled = false;
    final clock = Stopwatch()..start();
    final result = KnowledgeMedia.decodeAudio(long, cancelled: () => cancelled);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    cancelled = true;
    final stopAt = clock.elapsedMilliseconds;
    await expectLater(result, throwsA(isA<ScanCancelled>()));
    final stopMs = clock.elapsedMilliseconds - stopAt;
    expect(stopMs, lessThan(1000));
    // ignore: avoid_print
    print(
      'RESUME_AUDIO: ${jsonEncode({'build': BuildIdentity.toJson(), 'tones': measurements, 'cancelMs': stopMs, 'inputSeconds': 180, 'inputBytes': await long.length(), 'rssMb': ProcessInfo.currentRss ~/ (1024 * 1024)})}',
    );
  });
  testWidgets(
    'Qwen reuses its prompt after a prepared phone action',
    (tester) async {
      final engine = LlamaEngine();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          llamaEngineProvider.overrideWithValue(engine),
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWith(_ActionProbeSettings.new),
          modelManagerProvider.overrideWith(_ActionProbeModels.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        engine.dispose();
        await db.close();
      });
      await engine.loadModel(
        modelPath: _actionModel,
        settings: container.read(settingsProvider),
      );
      final chat = container.read(chatProvider.notifier);
      await chat.send('Set a timer for five minutes', spoken: true);
      final first = container.read(chatProvider).messages.last;
      expect(first.content, isNotEmpty);
      final timer = Stopwatch()..start();
      await chat.send('Hello', spoken: true);
      final cached = engine.metrics['cachedPromptTokens'] as num? ?? 0;
      // Printed before the assertion so a failure still shows the boundary.
      // ignore: avoid_print
      print(
        'RESUME_ACTION_CACHE: ${jsonEncode({'build': BuildIdentity.toJson(), 'cachedPromptTokens': cached, 'promptTokens': engine.metrics['promptTokens'], 'firstTokenMs': engine.metrics['firstTokenMs'], 'totalMs': timer.elapsedMilliseconds, 'answer': container.read(chatProvider).messages.last.content})}',
      );
      expect(
        cached,
        greaterThan(100),
        reason: 'the native system/schema prefix survives the action',
      );
    },
    skip: _actionModel.isEmpty,
  );
  if (const String.fromEnvironment('BENCH_MODEL').isNotEmpty) embedding.main();
  const captionModel = String.fromEnvironment('CAPTION_MODEL');
  const captionProjector = String.fromEnvironment('CAPTION_MMPROJ');
  testWidgets(
    'a real vision caption grounds a fact absent from OCR and filename',
    (tester) async {
      final engine = LlamaEngine();
      addTearDown(engine.dispose);
      const settings = InferenceSettings(
        contextSize: 4096,
        cpuThreads: 4,
        thinkingModeEnabled: false,
        promptCache: false,
      );
      await engine.loadModel(
        modelPath: captionModel,
        mmprojPath: captionProjector,
        settings: settings,
      );
      final file = File(
        '${(await getApplicationSupportDirectory()).path}/media/dog-384.jpg',
      );
      final caption = await KnowledgeGrounding.caption(
        file,
        engine,
        ModelFamily.qwen,
        settings,
      );
      expect(caption, contains(RegExp(r'dog|puppy', caseSensitive: false)));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final store = KnowledgeStore(db);
      await store.import(
        collection: 'Photo probe',
        name: 'garden-photo.jpg',
        bytes: await file.readAsBytes(),
        ocr: (_) async => '',
        caption: (_) async => caption,
      );
      final source = (await store.search(
        'Photo probe',
        'what animal is in the garden photo',
      )).single;
      expect(source.pageText, contains('model generated'));
      final answer = StringBuffer();
      await for (final s in engine.generate(
        messages: [
          {
            'role': 'system',
            'content': 'Answer using only the supplied caption.',
          },
          {
            'role': 'user',
            'content': 'What animal is in the photo?\n${source.pageText}',
          },
        ],
        fallbackTemplate: 'chatml',
        settings: settings.copyWith(maxTokens: 64),
      )) {
        answer.write(s);
      }
      expect(
        answer.toString(),
        contains(RegExp(r'dog|puppy', caseSensitive: false)),
      );
      // ignore: avoid_print
      print(
        'RESUME_REAL_PHOTO_FACT: ${jsonEncode({'build': BuildIdentity.toJson(), 'caption': caption, 'answer': answer.toString()})}',
      );
    },
    skip: captionModel.isEmpty || captionProjector.isEmpty,
  );
  testWidgets('late-minute recording fact reaches a real local answer', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final pack = Directory('${support.path}/voice');
    expect(
      await pack.exists(),
      isTrue,
      reason:
          'provision -VoicePack for the real transcription acceptance check',
    );
    final modelDir = await ModelStorage.modelsDir();
    for (final file in pack.listSync(recursive: true).whereType<File>()) {
      final target = File(
        '${modelDir.path}/${file.path.substring(pack.path.length + 1)}',
      );
      target.parent.createSync(recursive: true);
      file.copySync(target.path);
    }
    final dir = await Directory.systemTemp.createTemp('real-note-');
    addTearDown(() => dir.delete(recursive: true));
    final voice = SherpaVoice();
    addTearDown(voice.dispose);
    // A known spoken amount, generated locally, avoids treating an ASR
    // guess about an undocumented old fixture as the expected truth.
    const spoken =
        'The monthly rent is one thousand four hundred and fifty dollars.';
    final speech = await voice.synthesize(
      spoken,
      voice: KokoroVoice.forLanguage('en'),
    );
    expect(speech, isNotNull);
    final reference = File('${dir.path}/reference.wav');
    await reference.writeAsBytes(
      KnowledgeMedia.wavBytes(
        Uint8List.view(
          speech!.pcm.buffer,
          speech.pcm.offsetInBytes,
          speech.pcm.lengthInBytes,
        ),
        speech.sampleRate,
      ),
    );
    final heard = await KnowledgeMedia.decodeAudio(reference);
    addTearDown(() => heard.$1.delete());
    final clip = KnowledgeMedia.wavPcm(await heard.$1.readAsBytes())!;
    final pcm = Uint8List(60 * 16000 * 2);
    pcm.setRange(
      52 * 16000 * 2,
      52 * 16000 * 2 + clip.$1.length.clamp(0, 8 * 16000 * 2),
      clip.$1,
    );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final store = KnowledgeStore(db, null, () async => dir);
    final clock = Stopwatch()..start();
    await store.import(
      collection: 'Probe',
      name: 'late-rent.wav',
      bytes: KnowledgeMedia.wavBytes(pcm, 16000),
      transcribeSegment: (f) =>
          KnowledgeGrounding.transcript(f, voice, language: 'en'),
    );
    final sources = await store.search('Probe', 'rent amount each month');
    expect(sources.single.pageText, contains(RegExp(r'1[,\s]?450')));
    final engine = LlamaEngine();
    addTearDown(engine.dispose);
    const settings = InferenceSettings(
      contextSize: 2048,
      cpuThreads: 4,
      thinkingModeEnabled: false,
      maxTokens: 100,
      promptCache: false,
    );
    await engine.loadModel(
      modelPath: _actionModel.isNotEmpty
          ? _actionModel
          : const String.fromEnvironment('SMOKE_MODEL'),
      settings: settings,
    );
    final answer = StringBuffer();
    await for (final s in engine.generate(
      messages: [
        {
          'role': 'system',
          'content':
              'Answer the question using only this transcript. Keep the amount exactly as written. If absent, say unknown.',
        },
        {
          'role': 'user',
          'content':
              'How much rent is due each month?\n${sources.single.pageText}',
        },
      ],
      fallbackTemplate: 'chatml',
      settings: settings,
    )) {
      answer.write(s);
    }
    expect(
      answer.toString(),
      // A sentence may end after the figure; an invented decimal may not.
      contains(RegExp(r'(?<![\d.,])1[,\s]?450(?:\.00)?(?!\d|[.,]\d)')),
    );
    // ignore: avoid_print
    print(
      'RESUME_REAL_AUDIO_FACT: ${jsonEncode({'build': BuildIdentity.toJson(), 'ms': clock.elapsedMilliseconds, 'spokenReference': spoken, 'transcript': sources.single.pageText, 'answer': answer.toString(), 'speechStartSeconds': 52, 'syntheticReference': true})}',
    );
  });
  testWidgets('a voice pack released mid-sentence frees Kokoro', (
    tester,
  ) async {
    final paths = await VoiceModels.speakingPaths();
    expect(paths, isNotNull, reason: 'run with -VoicePack');
    final modelBytes = File(paths!.model).lengthSync();
    final voice = SherpaVoice();
    addTearDown(voice.dispose);
    final en = KokoroVoice.forLanguage('en');
    final before = ProcessInfo.currentRss;
    await voice.warmSpeaking(en);
    final loaded = ProcessInfo.currentRss;
    // Several seconds of synthesis: longer than the old two-second kill,
    // which landed as the native call returned and skipped the free.
    final long = List.filled(
      6,
      'The quick brown fox jumps over the lazy dog near the river on a quiet morning.',
    ).join(' ');
    final pending = voice.synthesize(long, voice: en);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final clock = Stopwatch()..start();
    voice.releasePack(speaking: true);
    await expectLater(pending, throwsA(isA<StateError>()));
    var after = ProcessInfo.currentRss;
    while (clock.elapsed < const Duration(seconds: 30) &&
        loaded - after < modelBytes ~/ 2) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      after = ProcessInfo.currentRss;
    }
    const mb = 1024 * 1024;
    // ignore: avoid_print
    print(
      'RESUME_VOICE_RELEASE: ${jsonEncode({'build': BuildIdentity.toJson(), 'modelMb': modelBytes ~/ mb, 'rssBeforeMb': before ~/ mb, 'rssLoadedMb': loaded ~/ mb, 'rssAfterMb': after ~/ mb, 'freedAfterMs': clock.elapsedMilliseconds})}',
    );
    expect(loaded - after, greaterThan(modelBytes ~/ 2));
  });
  testWidgets('archive source and saved excerpt render in EN FR ES', (
    tester,
  ) async {
    final boundary = GlobalKey();
    const source = <String, dynamic>{
      'title': 'Nikon Z30',
      'url': 'zim://Nikon_Z30',
      'archiveDate': '2024-02-01',
      'archiveLanguage': 'en',
      'coverage': 'archive_snapshot',
      'retrievalStatus': 'page_read',
      'fetchedAt': '2026-10-11T00:00:00Z',
      'excerpt': 'The Nikon Z30 weighs 405 g with its battery and memory card.',
      'snippet': 'Nikon Z30 camera',
    };
    final output = await getApplicationSupportDirectory();
    for (final language in ['en', 'fr', 'es']) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [zimWikipediaProvider.overrideWith((ref) async => null)],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: AppTheme.dark,
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => showSourceSheet(context, source),
                      child: const Text('Source'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final compressed = File(
        '${(await getApplicationSupportDirectory()).path}/media/resume-long.m4a',
      );
      if (await compressed.exists()) {
        final baseRss = ProcessInfo.currentRss;
        var peakRss = baseRss;
        final monitor = Timer.periodic(const Duration(milliseconds: 50), (_) {
          peakRss = math.max(peakRss, ProcessInfo.currentRss);
        });
        final timer = Stopwatch()..start();
        try {
          final decoded = await KnowledgeMedia.decodeAudio(compressed);
          expect(decoded.$2, closeTo(600, .25));
          final segment = await KnowledgeMedia.wavSegment(decoded.$1, 9);
          expect(
            segment,
            isNotNull,
            reason:
                'the last minute is addressable without loading the whole WAV',
          );
          await segment!.delete();
          final delta = (peakRss - baseRss) / (1024 * 1024);
          expect(
            delta,
            lessThan(128),
            reason: 'PCM is streamed to disk, not held at source rate',
          );
          // ignore: avoid_print
          print(
            'RESUME_LONG_AUDIO: ${jsonEncode({'build': BuildIdentity.toJson(), 'seconds': decoded.$2, 'inputBytes': await compressed.length(), 'derivedBytes': await decoded.$1.length(), 'ms': timer.elapsedMilliseconds, 'peakDeltaMb': delta})}',
          );
          await decoded.$1.delete();
        } finally {
          monitor.cancel();
        }
      }
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2024-02-01'), findsOneWidget);
      final t = lookupAppLocalizations(Locale(language));
      expect(find.text(t.sourceOfflineLimitation), findsOneWidget);
      // An archive opens in the app; its address is not offered as a link.
      expect(find.text(t.sourceOpenArchived), findsOneWidget);
      expect(find.text(t.sourceCopyLink), findsNothing);
      expect(tester.takeException(), isNull);
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${output.path}/resume-source-$language.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [zimWikipediaProvider.overrideWith((ref) async => null)],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ZimArticlePage(
            url: 'zim://Nikon_Z30',
            title: 'Nikon Z30',
            archiveDate: '2024-02-01',
            excerpt:
                'The Nikon Z30 weighs 405 g with its battery and memory card.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('405 g'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
