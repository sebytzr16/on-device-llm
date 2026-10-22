// A whole Goal on a real model with the live web: plan, research steps,
// review, report. Prints GOAL_STEP lines while it runs and one GOAL: JSON
// line at the end. Run through scripts/test-android.ps1 -Model <gguf>
// -Test integration_test/goal_probe_test.dart.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _family = String.fromEnvironment('MODEL_FAMILY', defaultValue: 'qwen');

/// The goal to run: the tester's Nikon Z30 vs Sony ZV-E10 comparison by
/// default (the runs that drifted to the ZV-E10 II on 2026-09-24).
const _objective = String.fromEnvironment(
  'GOAL_OBJECTIVE',
  defaultValue: 'Compare the nikon z30 to the sony zv-e10.',
);
const _kind = String.fromEnvironment('GOAL_KIND', defaultValue: 'product');

final _model = ModelInfo(
  id: 'goal',
  displayName: 'Goal model',
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
      webMode: WebMode.auto,
      contextSize: 8192,
      maxTokens: 700,
      temperature: 0.2,
      thinkingModeEnabled: false,
      searchRegion: 'ca-en',
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
    if (state.loadedModelId == info.id) return;
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
  testWidgets('live goal probe', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Goal probe'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    await (await SharedPreferences.getInstance()).remove('active_goal_v2');
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
    final clock = Stopwatch()..start();
    var lastPhase = '';
    final sub = container.listen(goalProvider, (_, next) {
      if (next == null) return;
      final line =
          '${next.status.name}/${next.phase.name} steps=${next.steps} '
          'tasks=${next.tasks.length} done=${next.done} sources=${next.sources.length}';
      if (line != lastPhase) {
        lastPhase = line;
        // ignore: avoid_print
        print('GOAL_STEP: ${clock.elapsed.inSeconds}s $line');
      }
    }, fireImmediately: true);
    await container
        .read(goalProvider.notifier)
        .start(
          GoalSpec(
            objective: _objective,
            successCriteria: '',
            maxSteps: 5,
            maxDuration: const Duration(minutes: 35),
            maxTokens: 200000,
            maxToolCalls: 20,
            specialization: GoalSpecialization.byName(_kind),
          ),
        );
    sub.close();
    final g = container.read(goalProvider)!;
    // ignore: avoid_print
    print(
      'GOAL: ${jsonEncode({
        'seconds': clock.elapsed.inSeconds,
        'status': g.status.name,
        'phase': g.phase.name,
        'error': g.error,
        'steps': g.steps,
        'reviews': g.reviews,
        'usedTokens': g.usedTokens,
        'terms': g.spec.terms,
        'plan': g.planNotes.length > 600 ? '${g.planNotes.substring(0, 600)}…' : g.planNotes,
        'tasks': [
          for (final t in g.tasks) {
              'q': t.question,
              'status': t.status.name,
              'checks': [for (final c in t.checks) c.toJson()],
              'queries': t.trace?.queries,
              'tools': t.trace?.tools.length,
              'sources': t.trace?.sources,
              'ms': t.trace?.ms,
              'attempts': t.trace?.attempts,
              'thinkChars': t.trace?.reasoning.length,
              'findingsChars': t.findings.length,
              'findings': t.findings.length > 700 ? '${t.findings.substring(0, 700)}…' : t.findings,
              'error': t.error,
            },
        ],
        'reportChecks': [for (final c in g.reportChecks) c.toJson()],
        'sources': [for (final s in g.sources) s.url],
        'missing': g.missing,
        'report': g.report,
      })}',
    );
    expect(g.status, isNot(GoalStatus.failed), reason: g.error);
  }, timeout: const Timeout(Duration(minutes: 40)));
}
