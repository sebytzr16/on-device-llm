import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/goals/presentation/goals_page.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'chat_test.dart' show TestModels, TestSettings;

class _FinishedGoal extends GoalNotifier {
  @override
  GoalProgress? build() => GoalProgress(
    spec: const GoalSpec(
      objective: 'Compare cameras',
      successCriteria: 'Compare video',
    ),
    status: GoalStatus.completed,
    steps: 0,
    startedAt: DateTime(2026),
    report: 'Existing report',
  );
}

void main() {
  testWidgets('edit goal saves requirements and steering at phone width', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        goalProvider.overrideWith(_FinishedGoal.new),
        modelManagerProvider.overrideWith(TestModels.new),
        settingsProvider.overrideWith(TestSettings.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.dark, home: const GoalsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('goal-refine')));
    await tester.tap(find.byKey(const Key('goal-refine')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('goal-refine-criteria')),
      'Recording limits\nAudio inputs',
    );
    await tester.enterText(
      find.byKey(const Key('goal-search-guidance')),
      'Prioritize long interview recording.',
    );
    await tester.ensureVisible(find.text('80%'));
    await tester.tap(find.text('80%'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final goal = container.read(goalProvider)!;
    expect(goal.spec.criteriaItems, ['Recording limits', 'Audio inputs']);
    expect(goal.spec.searchGuidance, 'Prioritize long interview recording.');
    expect(goal.spec.completionTarget, 0.8);
    expect(goal.report, 'Existing report');
    expect(goal.status, GoalStatus.paused);
  });
}
