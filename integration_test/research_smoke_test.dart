// End-to-end web research on a real model with the live web: DuckDuckGo
// discovery, page reads, passage ranking, token budgeting, generation and the
// grounding check — the whole ChatNotifier path, nothing mocked. Prints one
// RESEARCH: JSON line per question. Run through scripts/test-android.ps1
// -Model <gguf> -Family qwen|gemma -Test integration_test/research_smoke_test.dart
// on a phone with internet access.
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
import 'package:ondevice_llm/features/chat/domain/answer_checks.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _family = String.fromEnvironment('MODEL_FAMILY', defaultValue: 'qwen');

final _model = ModelInfo(
  id: 'research',
  displayName: 'Research model',
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
    return const InferenceSettings(
      webMode: WebMode.always,
      contextSize: 4096,
      maxTokens: 384,
      temperature: 0,
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
  testWidgets('live web research answers with citations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Research test'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    expect(await File(_modelPath).exists(), true);
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
    final questions = [
      // Discovery + body reading; the answer changes over time, so only the
      // mechanics are asserted, and the text is printed for review.
      'What is the latest stable version of the Flutter SDK and when was it released?',
      // Direct URL reading, no search.
      'Summarize the main points of https://en.wikipedia.org/wiki/Adreno in three sentences.',
    ];
    for (final q in questions) {
      final n = container.read(chatProvider.notifier);
      // Keep both turns in one conversation to exercise repeated retrieval,
      // SQLite writes and native prompt reuse after the first response.
      final clock = Stopwatch()..start();
      final ok = await n.send(q);
      clock.stop();
      final s = container.read(chatProvider);
      final answer = s.messages.last;
      final sources = jsonDecode(answer.sourcesJson) as List;
      final report = {
        'family': _family,
        'question': q,
        'accepted': ok,
        'error': s.error,
        'notice': s.notice,
        'seconds': clock.elapsed.inMilliseconds / 1000,
        'sources': [
          for (final src in sources)
            {
              'n': src['number'],
              'status': src['retrievalStatus'],
              'url': src['url'],
              'excerptChars': (src['excerpt'] as String?)?.length ?? 0,
            },
        ],
        'metrics': {
          'promptTokens': s.metrics['promptTokens'],
          'tokens': s.metrics['tokens'],
          'tokensPerSecond': s.metrics['tokensPerSecond'],
          'backend': s.metrics['backend'],
        },
        'answer': answer.content,
      };
      // ignore: avoid_print
      print('RESEARCH: ${jsonEncode(report)}');
      expect(ok, true);
      expect(s.error, isNull);
      expect(answer.role.name, 'assistant');
      expect(answer.content.trim(), isNotEmpty);
      expect(sources, isNotEmpty, reason: 'retrieval produced no sources');
      expect(
        sources.any((src) => src['retrievalStatus'] == 'page_read'),
        true,
        reason: 'no destination page was read',
      );
      expect(
        AnswerChecks.groundingNotice(answer.content, sources.length),
        isNot(contains('cannot browse')),
        reason: 'the model refused despite supplied sources',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
