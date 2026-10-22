// Conversation mode's turns on the real model (Gemma 4 E2B on the phone),
// without the microphone: what the user says by voice is sent the way the
// Conversation screen sends it (spoken style, phone's own model, no
// thinking). Prints one CONV: JSON line per turn with the time to the first
// spoken sentence, the total time, whether it searched and the answer.
// Run through scripts/test-android.ps1 -Model <gemma gguf> -Family gemma
// -Test integration_test/conversation_probe_test.dart on a phone online.
// With -VoicePack each line also has the time to the first words on screen,
// to the first clause the screen hands to the voice (with its 250 ms settle
// and 700 ms first-words wait), and to that clause's Kokoro audio, made
// while the model goes on writing (plan round 3, 2026-10-08).
// -ExtraDefines CONV_SET=memory runs the memory turns only (a fact said,
// a search, then the fact asked back); REMOTE_URL=<base>,REMOTE_MODEL=<id>
// sends the turns to that OpenAI-style server the way Conversation does
// with a remote connection (tester, 2026-10-18).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/chat/domain/entities/turn_run.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/voice/conversation_screen.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_pipeline.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:path_provider/path_provider.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _family = String.fromEnvironment('MODEL_FAMILY', defaultValue: 'gemma');

/// -EvalMode replay: only the tester's turns from the phone (2026-10-08,
/// Qwen 0.8B "got every answer wrong"), with the prompt, the search and
/// the sources of each turn printed.
const _mode = String.fromEnvironment('EVAL_MODE');

const _set = String.fromEnvironment('CONV_SET');
const _remoteUrl = String.fromEnvironment('REMOTE_URL');
const _remoteModel = String.fromEnvironment('REMOTE_MODEL');
bool get _remote => _remoteUrl.isNotEmpty;

/// The phone's settings with the remote connection on, as the tester set
/// up LM Studio on the laptop.
InferenceSettings _withRemote(InferenceSettings s) => s.copyWith(
  remoteEnabled: true,
  remoteProfiles: [
    const RemoteProfile(
      id: 'probe',
      name: 'LM Studio',
      providerId: 'lmstudio',
      baseUrl: _remoteUrl,
      model: _remoteModel,
    ),
  ],
  remoteProfileId: 'probe',
);

/// Prints every prompt the chat sends to the model (CONV-PROMPT lines).
class _LoggingEngine extends LlamaEngine {
  _LoggingEngine({required super.cacheDirectory});

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) {
    if (_mode == 'replay') {
      // ignore: avoid_print
      print(
        'CONV-PROMPT: ${jsonEncode({
          'tools': [for (final t in tools) t.name],
          'toolChoice': toolChoice,
          'messages': messages,
        })}',
      );
    }
    return super.generate(
      messages: messages,
      fallbackTemplate: fallbackTemplate,
      settings: settings,
      assistantPrefix: assistantPrefix,
      tools: tools,
      toolChoice: toolChoice,
    );
  }
}

final _model = ModelInfo(
  id: 'conversation',
  displayName: 'Conversation probe model',
  fileName: _modelPath.split('/').last,
  sizeBytes: 0,
  family: ModelFamily.values.byName(_family),
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: _modelPath,
);

/// Replay: the sampling the tester's phone used (Qwen3.5 card, text without
/// thinking, with the tester's presence 1.5) and its q8_0 KV cache.
const _ownerPhone = InferenceSettings(
  webMode: WebMode.auto,
  contextSize: 8192,
  maxTokens: 512,
  temperature: 1.0,
  topP: 1.0,
  topK: 20,
  minP: 0,
  presencePenalty: 1.5,
  kvCacheType: KvCacheType.q8_0,
);

InferenceSettings? _replaySettings;

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    if (_replaySettings != null) return _replaySettings!;
    // The tester's settings: web search on Auto.
    const phone = InferenceSettings(
      webMode: WebMode.auto,
      contextSize: 8192,
      maxTokens: 512,
    );
    return _remote ? _withRemote(phone) : phone;
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [_model], loadedModelId: null);
  }

  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
  }) async {
    await ref
        .read(llamaEngineProvider)
        .loadModel(
          modelPath: info.localPath!,
          settings: ref.read(settingsProvider),
        );
    state = state.copyWith(loadedModelId: info.id);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('conversation turns: speed, search choice, spoken answers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Conversation probe'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    if (_mode == 'replay') _replaySettings = _ownerPhone;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final engine = _LoggingEngine(
      cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(_Settings.new),
        modelManagerProvider.overrideWith(_Models.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      engine.dispose();
      await db.close();
    });
    final load = Stopwatch()..start();
    await container.read(modelManagerProvider.notifier).loadModel(_model);
    // ignore: avoid_print
    print(
      'CONV-LOAD: ${jsonEncode({'model': _modelPath.split('/').last, 'ms': load.elapsedMilliseconds})}',
    );
    // The voice pack copied by -VoicePack, where the app keeps it.
    SherpaVoice? voice;
    final pack = Directory(
      '${(await getApplicationSupportDirectory()).path}/voice',
    );
    if (pack.existsSync()) {
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
      voice = SherpaVoice();
      addTearDown(voice.dispose);
      for (final lang in ['en', 'fr', 'es']) {
        await voice.warmSpeaking(KokoroVoice.forLanguage(lang));
      }
    }
    final failures = <String>[];

    Future<void> turn(
      String probe,
      String q, {
      bool? search,
      String lang = 'en',
      List<Pattern> expectAny = const [],
    }) async {
      final n = container.read(chatProvider.notifier);
      final clock = Stopwatch()..start();
      int? firstText, firstSentence, firstAudio;
      String? firstClause;
      final stream = SentenceStream();
      var lastPartial = '';
      var lastChange = 0;
      Future<void>? speaking;
      void clause(String chunk) {
        if (firstSentence != null || chunk.trim().isEmpty) return;
        firstSentence = clock.elapsedMilliseconds;
        firstClause = chunk.trim();
        final v = voice;
        if (v == null) return;
        speaking = v
            .synthesize(
              VoiceNotifier.speakable(chunk),
              voice: KokoroVoice.forLanguage(lang),
            )
            .then((_) => firstAudio = clock.elapsedMilliseconds);
      }

      final sub = container.listen(chatProvider, (_, s) {
        if (!s.isGenerating || s.partialAnswer.trim().isEmpty) return;
        firstText ??= clock.elapsedMilliseconds;
        if (s.partialAnswer != lastPartial) {
          lastPartial = s.partialAnswer;
          lastChange = clock.elapsedMilliseconds;
        }
        if (firstSentence == null) clause(stream.take(s.partialAnswer));
      });
      // The screen's settle timer: when the words pause for 250 ms.
      final settle = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (firstSentence != null || lastPartial.trim().isEmpty) return;
        if (!container.read(chatProvider).isGenerating) return;
        if (clock.elapsedMilliseconds - lastChange < 250) return;
        clause(stream.take(lastPartial, settled: true));
      });
      final ok = await n.send(
        q,
        extraSystem: _remote
            ? ConversationScreen.spokenStyleRemote
            : ConversationScreen.spokenStyle,
        localOnly: !_remote,
        spoken: true,
        turnOverrides: ConversationScreen.turnSettings,
      );
      final doneMs = clock.elapsedMilliseconds;
      settle.cancel();
      sub.close();
      final s = container.read(chatProvider);
      // A short answer: its only sentence goes when it is saved.
      clause(stream.take(s.messages.last.content, flush: true));
      await speaking;
      clock.stop();
      final answer = s.messages.last;
      final sources = jsonDecode(answer.sourcesJson) as List;
      final run = TurnRun.decode(answer.runJson);
      final tools = [
        for (final t in run?.toolTrace ?? const <Map<String, dynamic>>[])
          t['call'] is Map
              ? '${(t['call'] as Map)['name']}${jsonEncode((t['call'] as Map)['arguments'])}'
              : '${t['name'] ?? t['tool'] ?? '?'}',
      ];
      // Pages read earlier in the chat and read again for a follow-up are
      // not a new search.
      final recalled =
          sources.isNotEmpty &&
          sources.every((x) => x is Map && x['remembered'] == true);
      final searched =
          (sources.isNotEmpty && !recalled) ||
          (s.notice != null && sources.isEmpty);
      final text = answer.content;
      final lower = text.toLowerCase();
      // What the voice says (citation numbers and list marks dropped).
      final said = VoiceNotifier.speakable(text);
      final sentences = KokoroSpeaker.sentences(said).length;
      final problems = [
        if (!ok || s.error != null) 'error: ${s.error}',
        if (search == false && searched) 'searched needlessly',
        if (search == true && !searched && !recalled) 'did not search',
        if (expectAny.isNotEmpty &&
            !expectAny.any(
              (p) => lower.contains(p is String ? p.toLowerCase() : p),
            ))
          'missing one of: ${expectAny.join(' / ')}',
        if (RegExp(r'[*#`|]|\[\d+\]').hasMatch(said)) 'markdown in speech',
        if (sentences > 5) 'too long to listen to ($sentences sentences)',
      ];
      if (problems.isNotEmpty) failures.add('$probe: ${problems.join('; ')}');
      // ignore: avoid_print
      print(
        'CONV: ${jsonEncode({
          'probe': probe,
          'remote': _remote,
          'question': q,
          'pass': problems.isEmpty,
          'problems': problems,
          'firstText': firstText == null ? null : firstText! / 1000,
          'firstSentence': firstSentence == null ? null : firstSentence! / 1000,
          'firstAudio': firstAudio == null ? null : firstAudio! / 1000,
          'firstClause': firstClause,
          'seconds': doneMs / 1000,
          'searched': searched,
          'notice': s.notice,
          'sentences': sentences,
          'tools': tools,
          'metrics': {for (final e in s.metrics.entries)
            if (e.value is num || e.value is String) e.key: e.value},
          'answer': text,
        })}',
      );
      if (_mode == 'replay') {
        // ignore: avoid_print
        print(
          'CONV-SOURCES: ${jsonEncode({'probe': probe, 'run': answer.runJson, 'sources': sources})}',
        );
      }
    }

    final n = container.read(chatProvider.notifier);
    if (_mode == 'replay') {
      // Answers from sources are capped at 0.7 / 0.8 since 2026-10-09:
      // the phone's settings are the case that matters.
      final configs = {'phone': _ownerPhone};
      for (final c in configs.entries) {
        await container.read(settingsProvider.notifier).update(c.value);
        for (var rep = 1; rep <= 3; rep++) {
          final tag = '${c.key}$rep';
          // The tester's conversation as Whisper heard it.
          n.newChat();
          await turn('$tag-greeting', 'Hi, how are you?', search: false);
          await turn(
            '$tag-misheard-1',
            'Can you please tell me what do I like today in Denver?',
          );
          await turn(
            '$tag-weather',
            'Can you please tell me what the weather like today in Denver?',
            search: true,
            expectAny: ['°', 'degrees'],
          );
          await turn(
            '$tag-misheard-2',
            'Can you please tell me what do I like today in Denver?',
          );
          // The question meant, on its own.
          n.newChat();
          await turn(
            '$tag-weather-fresh',
            "What's the weather like today in Denver?",
            search: true,
            expectAny: ['°', 'degrees'],
          );
          // The tester's Bieber turn (2026-10-09): the earlier answer was
          // repeated word for word.
          n.newChat();
          await turn('$tag-where', 'Hey, where are you?', search: false);
          await turn(
            '$tag-bieber',
            'Can you please tell me how old is Justin Bieber?',
            search: true,
            expectAny: ['32', '1994', 'thirty-two', 'thirty two'],
          );
        }
      }
      // ignore: avoid_print
      print('CONV-SUMMARY: ${jsonEncode({'failures': failures})}');
      return;
    }
    if (_set == 'memory') {
      // "It forgets things" (tester, 2026-10-18): what the user said must
      // survive a turn that searched the web.
      n.newChat();
      await turn(
        'mem-intro',
        'Hi, my name is Robin and I live in Denver.',
        search: false,
      );
      await turn(
        'mem-weather',
        "What's the weather like where I live today?",
        search: true,
        expectAny: ['°', 'degrees'],
      );
      await turn(
        'mem-name',
        "What's my name?",
        search: false,
        expectAny: ['robin'],
      );
      await turn(
        'mem-city',
        'Which city do I live in?',
        search: false,
        expectAny: ['toronto'],
      );
      n.newChat();
      await turn('mem-cats', 'I have two cats, Milo and Luna.', search: false);
      await turn(
        'mem-bieber',
        'How old is Justin Bieber?',
        search: true,
        expectAny: ['32', '1994', 'thirty-two', 'thirty two'],
      );
      await turn(
        'mem-cat-names',
        'What are my cats called?',
        search: false,
        expectAny: ['milo', 'luna'],
      );
      await turn(
        'mem-cat-count',
        'How many cats do I have?',
        search: false,
        expectAny: ['two', '2'],
      );
      n.newChat();
      await turn(
        'mem-capital',
        'What is the capital of Canada?',
        // The phone may check Wikipedia for a stable fact.
        search: _remote ? false : null,
        expectAny: ['ottawa'],
      );
      await turn(
        'mem-population',
        'And roughly how many people live there?',
        expectAny: ['million', '000', RegExp(r'\d,\d{3},\d{3}')],
      );
      await turn(
        'mem-which-city',
        'Which city were we just talking about?',
        search: false,
        expectAny: ['ottawa'],
      );
      n.newChat();
      await turn(
        'mem-sum',
        'What is fifteen plus twenty-seven?',
        search: false,
        expectAny: ['42', 'forty-two', 'forty two'],
      );
      await turn(
        'mem-double',
        'Now double that.',
        search: false,
        expectAny: ['84', 'eighty-four', 'eighty four'],
      );
      // ignore: avoid_print
      print('CONV-SUMMARY: ${jsonEncode({'failures': failures})}');
      return;
    }
    // One conversation, the way the tester talked to it.
    n.newChat();
    await turn('greeting', 'Hi, how are you?', search: false);
    await turn(
      'self-search',
      'Are you able to do online searches?',
      search: false,
      expectAny: ['yes', 'can', 'search'],
    );
    await turn('self-what', 'What can you do?', search: false);
    await turn('thanks', 'Thank you.', search: false);
    await turn('joke', 'Tell me a short joke.', search: false);
    await turn(
      'fact-static',
      'What is the capital of Australia?',
      search: _remote ? false : null,
      expectAny: ['canberra'],
    );
    // Follow-ups: the earlier turns must still be in view. (Gemma 4 E2B
    // does not know Canberra's river: it said "not on a major river".)
    await turn(
      'follow-up',
      'And which country is it in?',
      search: false,
      expectAny: ['australia'],
    );
    await turn('remember', 'My favourite colour is green, by the way.');
    await turn(
      'recall',
      'What is my favourite colour?',
      search: false,
      expectAny: ['green'],
    );
    // How-to questions search when web search is on (tester, 2026-10-19).
    await turn('advice', 'How do I boil an egg?', search: true);
    await turn('action', 'Set a timer for five minutes.', search: false);
    // The turn after an action keeps the cached conversation (the
    // phone actions stay offered; the clock is not in the system prompt).
    await turn(
      'after-action',
      'Thanks. What is two plus two?',
      search: false,
      expectAny: ['4', 'four'],
    );
    // Things that change: these should be looked up.
    n.newChat();
    await turn(
      'weather',
      'What is the weather like in Rome today?',
      search: true,
    );
    await turn(
      'weather-follow-up',
      'And what about tomorrow?',
      search: true,
      expectAny: ['tomorrow', 'rome'],
    );
    // The turn after a search keeps the cached conversation.
    await turn(
      'after-search',
      'Thanks, that helps. Any tip for a rainy day there?',
    );
    n.newChat();
    await turn(
      'news',
      'What is the latest news about the Mars missions?',
      search: true,
    );
    n.newChat();
    await turn(
      'price',
      'How much does a Nintendo Switch 2 cost?',
      search: true,
    );
    // Other languages.
    n.newChat();
    await turn('fr-greeting', 'Salut, ça va ?', search: false, lang: 'fr');
    await turn('es-greeting', 'Hola, ¿qué tal?', search: false, lang: 'es');

    // ignore: avoid_print
    print('CONV-SUMMARY: ${jsonEncode({'failures': failures})}');
    expect(
      failures.where((f) => f.contains('error:')),
      isEmpty,
      reason: failures.join('\n'),
    );
  }, timeout: const Timeout(Duration(minutes: 30)));
}
