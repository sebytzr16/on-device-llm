// Release-mode phone acceptance probe. Run scripts/test-release-quality.ps1.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/domain/search_steps.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _path = String.fromEnvironment('BENCH_MODEL');
final _model = ModelInfo(
  id: 'quality-smoke',
  displayName: _path.split('/').last.replaceAll('.gguf', ''),
  fileName: _path.split('/').last,
  sizeBytes: 0,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: _path,
);

class QualitySettings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(
      backend: GpuBackend.cpu,
      webMode: WebMode.always,
      contextSize: 8192,
      maxTokens: 512,
      temperature: 0,
      thinkingModeEnabled: false,
      thinkingBudgetTokens: 256,
      searchQueryPlanning: false,
      maxPagesRead: 3,
      memoryEnabled: false,
    );
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

class QualityModels extends ModelManagerNotifier {
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
          modelPath: _path,
          settings: settings ?? ref.read(settingsProvider),
        );
    state = state.copyWith(loadedModelId: info.id);
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _log(String marker, Object value) {
  // ignore: avoid_print
  print('$marker ${jsonEncode(value)}');
}

Future<void> _run() async {
  _log('QUALITY_PROGRESS', {'model': _path});
  _log('QUALITY_PROGRESS', {
    'exists': await File(_path).exists(),
    'support': (await getApplicationSupportDirectory()).path,
    'external': (await getExternalStorageDirectory())?.path,
  });
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
    await (await SharedPreferences.getInstance()).remove('active_goal_v2');
    final chat = container.read(chatProvider.notifier);
    chat.newChat();
    for (final question in [
      'What is the latest stable Flutter SDK version and its release date?',
      'Summarize https://en.wikipedia.org/wiki/Adreno in three sentences.',
      'What does that article say about the Adreno name?',
    ]) {
      _require(await chat.send(question), 'Turn was rejected.');
      final state = container.read(chatProvider);
      _require(state.error == null, state.error ?? 'Chat failed.');
      final answer = state.messages.last;
      final sources = SearchSteps.sourcesFromJson(answer.sourcesJson);
      _require(
        answer.content.trim().isNotEmpty && sources.isNotEmpty,
        'Research lost its answer or sources.',
      );
      _log('QUALITY_TURN', {
        'question': question,
        'answer': answer.content,
        'notice': state.notice,
        'sources': sources.length,
        'metrics': state.metrics,
      });
    }
    var last = '';
    final listener = container.listen(goalProvider, (_, next) {
      if (next == null) return;
      final phase = '${next.status.name}/${next.phase.name}/${next.steps}';
      if (phase != last) {
        last = phase;
        _log('QUALITY_PROGRESS', {
          'phase': phase,
          'sources': next.sources.length,
        });
      }
    });
    try {
      await container
          .read(goalProvider.notifier)
          .start(
            const GoalSpec(
              objective:
                  'Compare the Nikon Z30 and Sony ZV-E10 sensor resolution.',
              successCriteria:
                  'State the sensor resolution of each exact camera model, with cited sources.',
              specialization: GoalSpecialization.product,
              maxSteps: 3,
              maxDuration: Duration(minutes: 12),
              maxTokens: 60000,
              maxToolCalls: 30,
            ),
          );
    } finally {
      listener.close();
    }
    final goal = container.read(goalProvider)!;
    _log('QUALITY_GOAL', GoalNotifier.encode(goal));
    _require(goal.status != GoalStatus.failed, goal.error ?? 'Goal failed.');
    _require(
      goal.steps > 0 && goal.sources.isNotEmpty,
      'Goal made no research progress.',
    );
    _require(
      goal.usedTokens <= 60000 && goal.usedToolCalls <= 30,
      'Goal exceeded its allowance.',
    );
    _require(
      goal.status != GoalStatus.completed ||
          (goal.criteriaSatisfied && goal.spec.meetsTarget(goal.criteria)),
      'Goal completed without criterion evidence.',
    );
    _log('QUALITY_OK', {'goalStatus': goal.status.name, 'steps': goal.steps});
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
      home: Scaffold(
        body: Center(child: Text('Research and Goal release probe')),
      ),
    ),
  );
  unawaited(
    _run().catchError((Object error, StackTrace stack) {
      _log('QUALITY_FAILED', {'error': '$error', 'stack': '$stack'});
    }),
  );
}
