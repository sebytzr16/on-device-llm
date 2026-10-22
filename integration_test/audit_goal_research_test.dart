// Audit-only bounded end-to-end probe: live sources, a real local model,
// Goal accounting and prepared file actions. Uses the isolated smoke app.
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
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _path = String.fromEnvironment('BENCH_MODEL');
final _model = ModelInfo(
  id: 'audit-goal',
  displayName: 'Audit Gemma',
  fileName: _path.split('/').last,
  sizeBytes: 0,
  family: ModelFamily.gemma,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: _path,
);

void _report(Map<String, Object?> data) =>
    debugPrint('AUDIT_GOAL: ${jsonEncode(data)}');

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(
      backend: GpuBackend.cpu,
      cpuThreads: 4,
      webMode: WebMode.auto,
      contextSize: 8192,
      maxTokens: 700,
      temperature: 0.2,
      thinkingModeEnabled: false,
      searchRegion: 'ca-en',
      memoryEnabled: false,
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
          settings: settings ?? ref.read(settingsProvider),
        );
    state = state.copyWith(loadedModelId: info.id);
  }
}

class _Engine extends LlamaEngine {
  final Stopwatch clock;
  final rounds = <Map<String, Object?>>[];
  String phase = '';
  _Engine(this.clock)
    : super(
        cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
      );

  @override
  Future<void> loadModel({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    final before = loadCount;
    final load = Stopwatch()..start();
    await super.loadModel(
      modelPath: modelPath,
      settings: settings,
      mmprojPath: mmprojPath,
      adapters: adapters,
      draftModelPath: draftModelPath,
    );
    _report({
      'kind': 'load',
      'ms': load.elapsedMilliseconds,
      'newLoads': loadCount - before,
      'requestedContext': settings.contextSize,
      'loadedContext': metrics['contextSize'],
    });
  }

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    final started = clock.elapsedMilliseconds;
    final startedPhase = phase;
    int? firstText;
    try {
      await for (final text in super.generate(
        messages: messages,
        fallbackTemplate: fallbackTemplate,
        settings: settings,
        assistantPrefix: assistantPrefix,
        tools: tools,
        toolChoice: toolChoice,
      )) {
        firstText ??= clock.elapsedMilliseconds - started;
        yield text;
      }
    } finally {
      final round = <String, Object?>{
        'kind': 'round',
        'phase': startedPhase,
        'startMs': started,
        'ms': clock.elapsedMilliseconds - started,
        'firstTextMs': firstText,
        'requestedContext': settings.contextSize,
        'loadedContext': metrics['contextSize'],
        'promptTokens': metrics['promptTokens'],
        'tokens': metrics['tokens'],
        'thinkingTokens': metrics['thinkingTokens'],
        'tokensPerSecond': metrics['tokensPerSecond'],
        'cachedPromptTokens': metrics['cachedPromptTokens'],
        'finishReason': metrics['finishReason'],
      };
      rounds.add(round);
      _report(round);
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bounded live Goal research and action accounting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Audit: bounded Goal research')),
      ),
    );
    expect(_path, isNotEmpty);
    await (await SharedPreferences.getInstance()).remove('active_goal_v2');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final clock = Stopwatch()..start();
    final engine = _Engine(clock);
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
    String last = '';
    final sub = container.listen(goalProvider, (_, next) {
      if (next == null) return;
      engine.phase = next.preparingActions
          ? 'preparingActions'
          : next.phase.name;
      final line =
          '${next.status.name}/${engine.phase}/${next.steps}/${next.usedTokens}';
      if (line == last) return;
      last = line;
      _report({
        'kind': 'phase',
        'ms': clock.elapsedMilliseconds,
        'status': next.status.name,
        'phase': engine.phase,
        'steps': next.steps,
        'usedTokens': next.usedTokens,
        'sources': next.sources.length,
      });
    }, fireImmediately: true);
    await container
        .read(goalProvider.notifier)
        .start(
          const GoalSpec(
            objective:
                'Find the official Nikon Z30 body weight including battery and memory card. Cite Nikon as the source, and prepare a text file with the answer.',
            successCriteria:
                'State the official Nikon Z30 weight including battery and memory card, with a Nikon source citation.',
            maxSteps: 2,
            maxDuration: Duration(minutes: 4),
            maxTokens: 20000,
            maxToolCalls: 10,
            specialization: GoalSpecialization.product,
          ),
        );
    sub.close();
    final goal = container.read(goalProvider)!;
    _report({
      'kind': 'result',
      'ms': clock.elapsedMilliseconds,
      'status': goal.status.name,
      'error': goal.error,
      'usedTokens': goal.usedTokens,
      'usedToolCalls': goal.usedToolCalls,
      'coverage': goal.spec.coverage(goal.criteria),
      'tasks': [
        for (final task in goal.tasks)
          {
            'question': task.question,
            'status': task.status.name,
            'findings': task.findings,
            'trace': task.trace?.toJson(),
            'checks': [for (final check in task.checks) check.toJson()],
          },
      ],
      'sources': [for (final source in goal.sources) source.toJson()],
      'report': goal.report,
      'checks': [for (final check in goal.reportChecks) check.toJson()],
      'actions': [for (final action in goal.actions) action.toJson()],
      'missing': goal.missing,
      'quick': goal.spec.quick,
      'rounds': engine.rounds,
    });
    expect(engine.rounds, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
