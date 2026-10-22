// Independent gold-set evaluation through the release ChatNotifier pipeline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/retrieval/domain/research_evaluation.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'quality_smoke.dart' show QualitySettings, QualityModels;

const _evalPath = String.fromEnvironment('EVAL_FILE');
void _log(String marker, Object value) {
  // ignore: avoid_print
  print('$marker ${jsonEncode(value)}');
}

Future<void> _run() async {
  final set = jsonDecode(await File(_evalPath).readAsString()) as Map;
  final questions = (set['questions'] as List).cast<Map<String, dynamic>>();
  final external = (await getExternalStorageDirectory())!;
  final output = File('${external.path}/research-recipes-results.json');
  final rows = <Map<String, dynamic>>[];
  Future<void> save() => output.writeAsString(
    jsonEncode({
      'evaluatedAt': DateTime.now().toUtc().toIso8601String(),
      'model': const String.fromEnvironment('BENCH_MODEL'),
      'goldSourcesCheckedAt': set['sourcesCheckedAt'],
      'semanticSupportRequiresReview': true,
      'questions': rows,
    }),
    flush: true,
  );
  final db = AppDatabase();
  final engine = LlamaEngine(
    cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
  );
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      llamaEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(QualitySettings.new),
      modelManagerProvider.overrideWith(QualityModels.new),
    ],
  );
  try {
    for (final item in questions) {
      final chat = container.read(chatProvider.notifier);
      chat.newChat();
      final clock = Stopwatch()..start();
      _log('QUALITY_PROGRESS', {'question': item['id'], 'stage': 'start'});
      final accepted = await chat.send(item['q'] as String);
      clock.stop();
      final state = container.read(chatProvider);
      final answer = state.messages.lastOrNull;
      final text = answer?.role.name == 'assistant' ? answer!.content : '';
      final sources = answer?.role.name == 'assistant'
          ? (jsonDecode(answer!.sourcesJson) as List)
          : const [];
      final score = ResearchEvaluation.score(
        answer: text,
        evidence: [
          for (final src in sources)
            '${src['title'] ?? ''}\n${src['excerpt'] ?? ''}',
        ],
        gold: item,
      );
      rows.add({
        'id': item['id'],
        'recipe': item['recipe'],
        'question': item['q'],
        'answer': text,
        'sources': sources,
        'accepted': accepted,
        'error': state.error,
        'notice': state.notice,
        'metrics': state.metrics,
        'seconds': clock.elapsedMilliseconds / 1000,
        'referenceAnswer': item['referenceAnswer'],
        'referenceSources': item['referenceSources'],
        'quality': score.toJson(),
      });
      await save();
      _log('QUALITY_TURN', {
        'id': item['id'],
        'seconds': clock.elapsedMilliseconds / 1000,
        'sources': sources.length,
        'quality': score.toJson(),
      });
      if (!accepted || state.error != null || text.isEmpty) {
        throw StateError(
          'Research pipeline failed for ${item['id']}: ${state.error}',
        );
      }
    }
    _log('QUALITY_OK', {
      'questions': rows.length,
      'factualRulesPassed': rows
          .where((r) => (r['quality'] as Map)['factualRulesPassed'] == true)
          .length,
      'appropriateAbstention': rows
          .where((r) => (r['quality'] as Map)['appropriateAbstention'] == true)
          .length,
      'output': output.path,
      'semanticSupportRequiresReview': true,
    });
  } finally {
    container.dispose();
    engine.dispose();
    await db.close();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Research recipe evaluation'))),
    ),
  );
  unawaited(
    _run().catchError((Object error, StackTrace stack) {
      _log('QUALITY_FAILED', {'error': '$error', 'stack': '$stack'});
    }),
  );
}
