import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/design/app_design.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/goals/presentation/goals_page.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_evidence_page.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/features/chat/domain/entities/turn_run.dart';
import 'package:ondevice_llm/features/chat/presentation/screens/context_inspector_page.dart';
import 'chat_test.dart' as harness;

class _NoGoal extends GoalNotifier {
  @override
  GoalProgress? build() => null;
}

class _EvidenceGoal extends GoalNotifier {
  @override
  GoalProgress? build() => GoalProgress(
    spec: const GoalSpec(
      objective: 'Compare cameras',
      successCriteria: 'Sensor resolution',
    ),
    status: GoalStatus.paused,
    steps: 2,
    startedAt: DateTime(2026),
    sources: [
      GoalSource(
        title: 'Manufacturer A',
        url: 'https://example.com/specs',
        evidence: 'Camera A: 20.9 MP',
        retrievedAt: DateTime(2026, 9, 27),
      ),
      GoalSource(
        title: 'Manufacturer B',
        url: 'https://example.com/specs',
        evidence: 'Camera B: 24.2 MP',
        retrievedAt: DateTime(2026, 9, 28),
      ),
    ],
    tasks: const [
      GoalTask(
        'Camera A resolution',
        status: GoalTaskStatus.done,
        findings: 'Camera A is 20.9 MP [1].',
        trace: GoalTrace(sources: [1]),
      ),
      GoalTask(
        'Camera B resolution',
        status: GoalTaskStatus.done,
        findings: 'Camera B is 24.2 MP [2].',
        trace: GoalTrace(sources: [2]),
      ),
    ],
    criteria: const [
      GoalCriterion(
        text: 'Sensor resolution',
        satisfied: true,
        steps: [1, 2],
        evidence: [
          GoalCriterionEvidence(1, '20.9 MP'),
          GoalCriterionEvidence(2, '24.2 MP'),
        ],
      ),
    ],
  );
}

class _ChangeModels extends harness.TwoModels {
  void useSecond() =>
      state = state.copyWith(loadedModelId: harness.pinnable.id);
}

class _RunningGoal extends _EvidenceGoal {
  @override
  GoalProgress? build() => super.build()!.copyWith(status: GoalStatus.running);
}

class _ChangeSettings extends harness.TestSettings {
  void remote() => state = state.copyWith(
    remoteEnabled: true,
    remoteProfiles: const [
      RemoteProfile(
        id: 'remote',
        name: 'Remote',
        baseUrl: 'https://example.com/v1',
        model: 'remote-test-model',
      ),
    ],
  );
}

Widget _host(ProviderContainer container, Widget page) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: page),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('four running Goal controls occupy two equal phone rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        goalProvider.overrideWith(_RunningGoal.new),
        settingsProvider.overrideWith(harness.TestSettings.new),
        modelManagerProvider.overrideWith(harness.TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const GoalsPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byKey(const Key('goal-evidence')));
    final a = tester.getRect(find.byKey(const Key('goal-evidence')));
    final b = tester.getRect(find.byKey(const Key('goal-pause')));
    final c = tester.getRect(find.byKey(const Key('goal-stop')));
    final d = tester.getRect(find.byKey(const Key('goal-open-chat')));
    expect(a.width, b.width);
    expect(a.width, c.width);
    expect(a.width, d.width);
    expect(a.top, b.top);
    expect(c.top, d.top);
    expect(c.top, greaterThan(a.bottom));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('goal-active-model')))
          .style!
          .fontSize,
      AppText.small.fontSize,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('context inspector explains saved omissions and older answers', (
    tester,
  ) async {
    TurnRun run(Map<String, dynamic> metrics) => TurnRun(
      settings: const {'contextSize': 4096},
      engine: const {},
      metrics: metrics,
      modelId: 'test',
      modelName: 'Test model',
      presetId: '',
      presetName: '',
      sources: 0,
      at: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ContextInspectorPage(
          run: run({
            'contextAudit': {
              'includedMessages': 2,
              'omittedMessages': 103,
              'earlierEntriesHidden': 5,
              'instructionChars': 21,
              'instructions': 'Use saved sources only',
              'turns': [
                {
                  'id': 'old',
                  'role': 'user',
                  'excerpt': 'Older question',
                  'chars': 14,
                  'included': false,
                  'reason': 'context_limit',
                },
              ],
            },
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Included: 2 · Omitted: 103'), findsOneWidget);
    expect(find.text('Earlier message previews not shown: 5'), findsOneWidget);
    expect(find.textContaining('kept in history'), findsOneWidget);
    await tester.tap(find.byKey(const Key('context-instructions')));
    await tester.pumpAndSettle();
    expect(find.text('Use saved sources only'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ContextInspectorPage(run: run(const {})),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This older answer has no saved context snapshot.'),
      findsOneWidget,
    );
  });
  testWidgets('Goal shows the active local and remote model without a menu', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        goalProvider.overrideWith(_EvidenceGoal.new),
        settingsProvider.overrideWith(_ChangeSettings.new),
        modelManagerProvider.overrideWith(_ChangeModels.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container, const GoalsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Model: Test'), findsOneWidget);
    (container.read(modelManagerProvider.notifier) as _ChangeModels)
        .useSecond();
    await tester.pump();
    expect(find.text('Model: ${harness.pinnable.displayName}'), findsOneWidget);
    (container.read(settingsProvider.notifier) as _ChangeSettings).remote();
    await tester.pump();
    expect(find.text('Model: remote-test-model'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone evidence workspace keeps separate snapshots at the same URL',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [goalProvider.overrideWith(_EvidenceGoal.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _host(
          container,
          const GoalEvidencePage(initialCriterion: 'Sensor resolution'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('evidence-panel-left')), findsOneWidget);
      await tester.ensureVisible(find.text('Camera A: 20.9 MP'));
      expect(find.text('Camera A: 20.9 MP'), findsOneWidget);
      await tester.ensureVisible(find.text('Camera B: 24.2 MP'));
      expect(find.text('Camera B: 24.2 MP'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('evidence-search')));
      await tester.enterText(find.byKey(const Key('evidence-search')), '24.2');
      await tester.pumpAndSettle();
      expect(find.text('No match in this saved excerpt.'), findsOneWidget);
      expect(find.text('Camera B: 24.2 MP'), findsOneWidget);
    },
  );

  testWidgets(
    'Goal draft restores custom budgets and flushes the last edit when closed',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'goal_draft_v1': jsonEncode({
          'objective': 'Compare cameras',
          'criteria': 'Sensor resolution',
          'rules': 'Exact models',
          'searchGuidance': 'Use manufacturer specifications',
          'budget': 'custom',
          'completionTarget': 0.9,
          'steps': '9',
          'minutes': '37',
          'tokens': '73000',
          'toolCalls': '29',
        }),
      });
      final container = ProviderContainer(
        overrides: [
          goalProvider.overrideWith(_NoGoal.new),
          settingsProvider.overrideWith(harness.TestSettings.new),
          modelManagerProvider.overrideWith(harness.TestModels.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container, const GoalsPage()));
      await tester.pumpAndSettle();
      // Lazy fields are inspected after scrolling to the custom limits.
      await tester.scrollUntilVisible(
        find.byKey(const Key('goal-budget-custom')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      for (final value in ['9', '37', '73000', '29']) {
        expect(find.text(value), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('goal-setup-guidance')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('goal-setup-guidance')),
        'Check the exact generation',
      );
      await tester.pumpWidget(
        const SizedBox(),
      ); // leave before the debounce fires
      await tester.pumpAndSettle();
      final saved =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'goal_draft_v1',
                )!,
              )
              as Map;
      expect(saved['searchGuidance'], 'Check the exact generation');
      expect(saved['completionTarget'], 0.9);
      expect(saved['steps'], '9');
      expect(saved['minutes'], '37');
      expect(saved['tokens'], '73000');
      expect(saved['toolCalls'], '29');
      expect(tester.takeException(), isNull);
    },
  );
}
