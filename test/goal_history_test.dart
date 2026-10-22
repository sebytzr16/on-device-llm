import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/goals/presentation/goals_page.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' show TestEngine, TestModels, TestSettings;

GoalProgress _finished(String objective, {DateTime? at}) => GoalProgress(
  spec: GoalSpec(objective: objective, successCriteria: ''),
  status: GoalStatus.completed,
  phase: GoalPhase.done,
  steps: 1,
  startedAt: at ?? DateTime(2026, 10, 8, 20),
  report: 'The Nikon Z30 weighs 405 g with battery and card [1].',
  sources: const [
    GoalSource(title: 'Nikon Z30 specifications', url: 'https://nikon.com/z30'),
  ],
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(TestEngine()),
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('finished goals are kept, newest first, and survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final a = container();
    final history = a.read(goalHistoryProvider.notifier);
    await history.ready;
    await history.put(_finished('first', at: DateTime(2026, 10, 1)));
    await history.put(_finished('second', at: DateTime(2026, 10, 2)));
    // Saving the same goal again updates it in place.
    await history.put(_finished('second', at: DateTime(2026, 10, 2)));
    expect(
      a.read(goalHistoryProvider).map((e) => e.goal.spec.objective),
      ['second', 'first'],
    );

    final b = container();
    await b.read(goalHistoryProvider.notifier).ready;
    expect(b.read(goalHistoryProvider), hasLength(2));
    final first = b.read(goalHistoryProvider).last;
    await b.read(goalHistoryProvider.notifier).remove(first.id);
    expect(
      b.read(goalHistoryProvider).map((e) => e.goal.spec.objective),
      ['second'],
    );
  });

  testWidgets(
    'a finished report comes first; leaving puts it in the past goals',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final goal = _finished('Nikon Z30 weight');
      SharedPreferences.setMockInitialValues({
        'active_goal_v2': jsonEncode(GoalNotifier.encode(goal)),
      });
      final c = container();
      await c.read(goalProvider.notifier).ready;
      await c.read(goalHistoryProvider.notifier).ready;
      expect(c.read(goalProvider)?.status, GoalStatus.completed);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const GoalsPage()),
                ),
                child: const Text('open goals'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open goals'));
      await tester.pumpAndSettle();

      // The report is above how it was made.
      final report = tester.getTopLeft(find.byKey(const Key('goal-report')));
      final howMade = tester.getTopLeft(find.text('How this report was made'));
      expect(report.dy, lessThan(howMade.dy));
      expect(report.dy, lessThan(400));

      // Leaving puts the goal away into the history.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(c.read(goalProvider), isNull);
      expect(c.read(goalHistoryProvider), hasLength(1));

      // Goals opens on a new goal, with the past one listed under it.
      await tester.tap(find.text('open goals'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('goal-objective')), findsOneWidget);
      await tester.tap(find.byKey(const Key('goal-past-jump')));
      await tester.pumpAndSettle();
      final past = find.byKey(Key('goal-past-${GoalHistoryNotifier.idOf(goal)}'));
      expect(past, findsOneWidget);
      await tester.tap(past);
      await tester.pumpAndSettle();
      expect(find.byType(GoalHistoryPage), findsOneWidget);
      expect(find.byKey(const Key('goal-report')), findsOneWidget);

      // Made current again from the history, to refine or continue.
      await tester.tap(find.byKey(const Key('goal-past-reopen')));
      await tester.pumpAndSettle();
      expect(c.read(goalProvider)?.spec.objective, 'Nikon Z30 weight');
      expect(find.byKey(const Key('goal-progress')), findsOneWidget);
    },
  );
}
