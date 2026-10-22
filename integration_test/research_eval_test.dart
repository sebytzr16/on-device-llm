// Scored web-research evaluation on a real model with the live web
// (roadmap §7.8 / §11.4). Reads the question set pushed by
// scripts/test-android.ps1 -Eval eval/research_questions.json, runs every
// question through the real ChatNotifier pipeline and prints one EVAL: JSON
// line per question plus an EVAL_SUMMARY line. Nothing is asserted about
// correctness: the point is a number that can be compared across changes.
// scripts/summarize-eval.py turns the log into a table.
//
// With FROZEN_WEB=record|fill|replay and FROZEN_FILE=<path> every search,
// lookup and page read goes through a frozen web record (D1 benchmark,
// eval/d1_benchmark.json): one live pass records it, later passes replay it
// so configurations differ only in their decisions. FROZEN_LATENCY=false
// replays without the recorded network time.
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
import 'package:ondevice_llm/features/chat/domain/answer_shape.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/retrieval/domain/research_evaluation.dart';
import 'package:ondevice_llm/features/retrieval/semantic_rerank.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';

import 'support/frozen_web.dart';
import 'package:ondevice_llm/features/chat/domain/answer_checks.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _family = String.fromEnvironment('MODEL_FAMILY', defaultValue: 'qwen');
const _evalPath = String.fromEnvironment('EVAL_FILE');
const _mode = String.fromEnvironment('EVAL_MODE', defaultValue: 'always');
const _frozenMode = String.fromEnvironment('FROZEN_WEB');
const _frozenFile = String.fromEnvironment('FROZEN_FILE');
const _frozenLatency = bool.fromEnvironment(
  'FROZEN_LATENCY',
  defaultValue: true,
);
// Research settings under test; 0 keeps the app's default.
const _pages = int.fromEnvironment('EVAL_PAGES');
const _passages = int.fromEnvironment('EVAL_PASSAGES');
// Sentence-trimming experiment: the share of each passage's sentences kept.
const _trim = String.fromEnvironment('EVAL_TRIM');
// EmbeddingGemma 2 for the semantic web ranking, as the app uses it once
// downloaded: pushed by -AuxiliaryModels into files/, copied to the models
// folder on the first run.
const _eg2 = bool.fromEnvironment('EVAL_EG2');

final _model = ModelInfo(
  id: 'eval',
  displayName: 'Eval model',
  fileName: _modelPath.split('/').last,
  sizeBytes: 0,
  family: ModelFamily.values.byName(_family),
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: _modelPath,
);

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return InferenceSettings(
      backend: GpuBackend.values.byName(
        const String.fromEnvironment('SMOKE_BACKEND', defaultValue: 'cpu'),
      ),
      webMode: WebMode.values.byName(_mode),
      contextSize: 4096,
      maxTokens: 320,
      temperature: 0,
      thinkingModeEnabled: false,
      maxPagesRead: _pages > 0 ? _pages : 3,
      evidencePassages: _passages > 0 ? _passages : 6,
    );
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [_model], embeddingReady: _eg2);
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
  if (_trim.isNotEmpty) SemanticRerank.trimShare = double.parse(_trim);
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('scored live research evaluation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Research evaluation'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    expect(_evalPath, isNotEmpty, reason: 'Pass -Eval to test-android.ps1');
    final set =
        jsonDecode(await File(_evalPath).readAsString())
            as Map<String, dynamic>;
    final questions = (set['questions'] as List).cast<Map<String, dynamic>>();
    if (_eg2) {
      final pushed = File(
        '${(await getApplicationSupportDirectory()).path}/${embeddingModel.fileName}',
      );
      final target = await ModelStorage.modelFile(embeddingModel.fileName);
      expect(
        pushed.existsSync() || target.existsSync(),
        isTrue,
        reason: 'Pass -AuxiliaryModels test-assets/${embeddingModel.fileName}',
      );
      if (pushed.existsSync() &&
          (!target.existsSync() ||
              target.lengthSync() != pushed.lengthSync())) {
        await pushed.copy(target.path);
      }
    }
    final frozen = _frozenMode.isEmpty
        ? null
        : await FrozenWeb.open(
            _frozenFile,
            FrozenMode.values.byName(_frozenMode),
            latency: _frozenLatency,
          );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final engine = LlamaEngine(
      cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(_Settings.new),
        modelManagerProvider.overrideWith(_Models.new),
        ...?frozen?.overrides,
      ],
    );
    addTearDown(() async {
      container.dispose();
      engine.dispose();
      await db.close();
    });
    final totals = <String, int>{};
    final seconds = <double>[];
    void tally(String key, bool v) {
      if (v) totals[key] = (totals[key] ?? 0) + 1;
    }

    for (final item in questions) {
      final q = item['q'] as String;
      final expects = (item['expect'] as List? ?? const []).cast<String>();
      final unanswerable = item['unanswerable'] == true;
      SemanticRerank.lastTrim = null;
      final n = container.read(chatProvider.notifier);
      n.newChat();
      final before = {...?frozen?.calls};
      final clock = Stopwatch()..start();
      final ok = await n.send(q);
      clock.stop();
      final webCalls = {
        for (final e in (frozen?.calls ?? const <String, int>{}).entries)
          if (e.value - (before[e.key] ?? 0) > 0)
            e.key: e.value - (before[e.key] ?? 0),
      };
      await frozen?.save(_frozenFile);
      final s = container.read(chatProvider);
      final answer = s.messages.isNotEmpty ? s.messages.last : null;
      final text = answer?.content ?? '';
      final sources = answer == null
          ? const []
          : jsonDecode(answer.sourcesJson) as List;
      final pages = sources
          .where((x) => x['retrievalStatus'] == 'page_read')
          .length;
      final read = pages > 0;
      final cited = RegExp(r'\[\d+(?:\s*,\s*\d+)*\]').hasMatch(text);
      final grounding = sources.isEmpty
          ? null
          : AnswerChecks.groundingNotice(text, sources.length);
      final lower = text.toLowerCase();
      final score = ResearchEvaluation.score(
        answer: text,
        evidence: [
          for (final src in sources)
            '${src['title'] ?? ''}\n${src['excerpt'] ?? ''}',
        ],
        gold: item,
      );
      final correct = unanswerable
          ? score.appropriateAbstention
          : score.factualRulesPassed;
      // Did it go to the web for this question, and should it have?
      final searched =
          sources.isNotEmpty || webCalls.keys.any((k) => k != 'read');
      final wanted = item['web'] as bool?;
      final routerOk = wanted == null ? null : wanted == searched;
      final mechanicallyGrounded =
          sources.isNotEmpty &&
          score.hasCitations &&
          score.citationNumbersValid &&
          score.figuresSupported;
      final row = {
        'id': item['id'],
        'kind': item['kind'] ?? 'fact',
        'family': _family,
        'mode': _mode,
        'set': item['set'],
        'lang': item['lang'],
        'frozen': _frozenMode.isEmpty ? null : _frozenMode,
        'searched': searched,
        'webWanted': wanted,
        'routerOk': routerOk,
        'webCalls': webCalls,
        'accepted': ok,
        'error': s.error,
        'notice': s.notice,
        'seconds': clock.elapsed.inMilliseconds / 1000,
        'sources': sources.length,
        'pages': pages,
        'read': read,
        'cited': cited,
        'grounded': mechanicallyGrounded,
        'semanticSupportRequiresReview': true,
        'grounding': grounding,
        'correct': correct,
        if (SemanticRerank.lastTrim != null) 'trim': SemanticRerank.lastTrim,
        'quality': score.toJson(),
        'legacyKeywordMatch': expects.any(
          (e) => lower.contains(e.toLowerCase()),
        ),
        'requiresGoldReview': correct == null,
        'current': item['current'] == true,
        'backend': s.metrics['backend'],
        'stages': s.metrics['stages'],
        'promptTokens': s.metrics['promptTokens'],
        // Where the generation time goes: reading the prompt (first token)
        // or writing the answer (tokens at tokensPerSecond).
        'cachedPromptTokens': s.metrics['cachedPromptTokens'],
        'firstTokenMs': s.metrics['firstTokenMs'],
        'tokens': s.metrics['tokens'],
        'tokensPerSecond': s.metrics['tokensPerSecond'],
        'generationRounds': s.metrics['generationRounds'],
        'finishReason': s.metrics['finishReason'],
        'answer': text,
      };
      // ignore: avoid_print
      print('EVAL: ${jsonEncode(row)}');
      tally('retrieved', sources.isNotEmpty);
      tally('read', read);
      tally('cited', cited);
      tally('grounded', mechanicallyGrounded);
      tally('correct', correct == true);
      tally('scorable', correct != null);
      tally('errors', s.error != null);
      tally('searched', searched);
      tally('routerOk', routerOk == true);
      tally('routerScored', routerOk != null);
      seconds.add(clock.elapsed.inMilliseconds / 1000);
    }
    seconds.sort();
    // ignore: avoid_print
    print(
      'EVAL_SUMMARY: ${jsonEncode({'family': _family, 'mode': _mode, if (_pages > 0) 'pages': _pages, if (_passages > 0) 'passages': _passages, if (_trim.isNotEmpty) 'trim': _trim, if (_eg2) 'eg2': true, if (AnswerShapes.concise) 'concise': true, 'frozen': _frozenMode.isEmpty ? null : _frozenMode, 'questions': questions.length, ...totals, if (seconds.isNotEmpty) 'medianSeconds': seconds[seconds.length ~/ 2], if (frozen != null) 'webCalls': frozen.calls, if (frozen != null) 'frozenMisses': frozen.misses})}',
    );
  }, timeout: const Timeout(Duration(minutes: 90)));
}
