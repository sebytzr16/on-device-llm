// Live probe of what web research actually hands the model and what the model
// makes of it: every source (URL, read status, excerpt size and opening), the
// chat notice, timings and the answer, one PROBE: JSON line per question.
// Nothing is mocked. Run through scripts/test-android.ps1 -Model <gguf>
// -Test integration_test/news_probe_test.dart [-EvalMode auto|always]; pass
// questions with -Eval <json> ({"questions":[{"q":"..."}]}) or use the
// built-in news set.
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _family = String.fromEnvironment('MODEL_FAMILY', defaultValue: 'qwen');
const _evalPath = String.fromEnvironment('EVAL_FILE');
const _mode = String.fromEnvironment('EVAL_MODE', defaultValue: 'auto');

final _model = ModelInfo(
  id: 'probe',
  displayName: 'Probe model',
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
      contextSize: 8192,
      maxTokens: 700,
      temperature: 0.2,
      thinkingModeEnabled: false,
    );
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [_model]);
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

/// Each entry is a new chat; later strings in an entry are follow-ups asked
/// in the same chat.
const _defaultQuestions = [
  ["What's the latest news?", 'Tell me more about the second story'],
  ['What is the latest news in Canada today?'],
  ['What is the latest news about the Toronto Blue Jays?'],
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('live news probe', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('News probe'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    final questions = _evalPath.isEmpty
        ? _defaultQuestions
        : [
            for (final q
                in (jsonDecode(await File(_evalPath).readAsString())
                        as Map)['questions']
                    as List)
              [
                (q as Map)['q'] as String,
                ...((q['followUps'] as List?) ?? const []).cast<String>(),
              ],
          ];
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
      ],
    );
    addTearDown(() async {
      container.dispose();
      engine.dispose();
      await db.close();
    });
    for (final chat in questions) {
      final n = container.read(chatProvider.notifier);
      n.newChat();
      for (final q in chat) {
        final notices = <String>[];
        final sub = container.listen(chatProvider, (_, next) {
          final notice = next.notice;
          if (notice != null &&
              notice.isNotEmpty &&
              (notices.isEmpty || notices.last != notice)) {
            notices.add(notice);
          }
        });
        final clock = Stopwatch()..start();
        final ok = await n.send(q);
        clock.stop();
        sub.close();
        final s = container.read(chatProvider);
        final answer = s.messages.isEmpty ? null : s.messages.last;
        final sources = answer == null
            ? const []
            : jsonDecode(answer.sourcesJson) as List;
        String head(Object? text, int n) {
          final t = '${text ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
          return t.length <= n ? t : '${t.substring(0, n)}…';
        }

        final report = {
          'question': q,
          'mode': _mode,
          'accepted': ok,
          'error': s.error,
          'notices': notices,
          'finalNotice': s.notice,
          'seconds': clock.elapsed.inMilliseconds / 1000,
          'stages': s.metrics['stages'],
          'promptTokens': s.metrics['promptTokens'],
          'tokens': s.metrics['tokens'],
          'sources': [
            for (final src in sources)
              {
                'n': src['number'],
                'status': src['retrievalStatus'],
                'title': head(src['title'], 90),
                'url': src['url'],
                'published': src['publishedAt'],
                'excerptChars': (src['excerpt'] as String?)?.length ?? 0,
                'excerpt': head(src['excerpt'] ?? src['snippet'], 400),
                'readError': head(src['readError'], 120),
              },
          ],
          'answer': answer?.content ?? '',
        };
        // ignore: avoid_print
        print('PROBE: ${jsonEncode(report)}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
