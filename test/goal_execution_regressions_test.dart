import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/goal_watch.dart';
import 'package:ondevice_llm/features/goals/goal_watch_check.dart';
import 'package:ondevice_llm/features/goals/goal_watch_store.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:ondevice_llm/features/tools/presentation/phone_action_cards.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';

void main() {
  final at = DateTime(2026, 10, 11, 9);
  GoalWatch watch() => GoalWatch(
    id: 7,
    objective: 'Watch the price',
    query: 'price',
    hour: 9,
    minute: 0,
    createdAt: at.subtract(const Duration(days: 1)),
  );
  SearchResult result(String price) => SearchResult(
    title: 'Price',
    url: 'https://maker.example/product',
    snippet: price,
    rank: 1,
  );

  test(
    'a watch baseline and unchanged results stay quiet; changed figures alert',
    () async {
      var calls = 0;
      Future<List<SearchResult>> search(String _) async {
        calls++;
        return [result('\$449')];
      }

      final baseline = await GoalWatchCheck.run(
        watch(),
        webEnabled: true,
        search: search,
        now: () => at,
      );
      expect(GoalWatchCheck.shouldNotify(baseline), isFalse);
      final unchanged = await GoalWatchCheck.run(
        baseline,
        webEnabled: true,
        search: search,
        now: () => at.add(const Duration(days: 1)),
      );
      expect(GoalWatchCheck.shouldNotify(unchanged), isFalse);
      final changed = await GoalWatchCheck.run(
        unchanged,
        webEnabled: true,
        search: (_) async => [result('\$499')],
      );
      expect(GoalWatchCheck.shouldNotify(changed), isTrue);
      expect(changed.lastChange!.figures.single.after, ['\$499']);
      expect(calls, 2);
    },
  );
  test(
    'web-off and failed checks preserve the baseline without an alert',
    () async {
      final baseline = watch().checked(
        GoalWatches.snapshot([result('\$449')], at),
      );
      var requests = 0;
      Future<List<SearchResult>> search(String _) async {
        requests++;
        throw StateError('offline');
      }

      final off = await GoalWatchCheck.run(
        baseline,
        webEnabled: false,
        search: search,
      );
      expect(requests, 0);
      expect(off.lastError, 'webOff');
      final failed = await GoalWatchCheck.run(
        baseline,
        webEnabled: true,
        search: search,
      );
      expect(failed.last!.items.single.figures, ['\$449']);
      expect(GoalWatchCheck.shouldNotify(failed), isFalse);
    },
  );
  test(
    'a stale check cannot restore a removed watch or replace a newer edit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final w = watch();
      await GoalWatchStore.put(w);
      final next = w.checked(GoalWatches.snapshot([result('\$449')], at));
      await GoalWatchStore.remove(w.id);
      expect(await GoalWatchStore.put(next, expected: w), isFalse);
      expect(await GoalWatchStore.list(), isEmpty);
      await GoalWatchStore.put(w);
      await GoalWatchStore.put(w.at(10, 30));
      expect(await GoalWatchStore.put(next, expected: w), isFalse);
      expect((await GoalWatchStore.list()).single.hour, 10);
    },
  );

  const action = PhoneAction('set_timer', {'minutes': 5});
  GoalProgress progress({required bool confirmed}) => GoalProgress(
    spec: const GoalSpec(objective: 'Prepare a timer', successCriteria: ''),
    status: GoalStatus.partial,
    phase: GoalPhase.confirming,
    steps: 1,
    reviewedSteps: 1,
    startedAt: at,
    tasks: const [
      GoalTask('Prepare it', status: GoalTaskStatus.done, findings: 'Ready'),
    ],
    actions: const [action],
    actionOutcomes: {
      0: GoalActionOutcome(opened: true, confirmed: confirmed, at: at),
    },
  );
  test('opening an action is insufficient; confirmation is resumable once', () {
    expect(GoalNotifier.canContinue(progress(confirmed: false)), isFalse);
    final confirmed = progress(confirmed: true);
    expect(GoalNotifier.canContinue(confirmed), isTrue);
    final next = GoalNotifier.continuedProgress(confirmed, confirmed.spec);
    expect(next.tasks.last.kind, GoalTaskKind.recordOutcome);
    expect(
      next.tasks.last.findings,
      contains('Do not create this action again'),
    );
    expect(next.actionOutcomes[0]!.included, isTrue);
    final saved = GoalNotifier.decode(
      jsonDecode(jsonEncode(GoalNotifier.encode(next))) as Map<String, dynamic>,
    );
    expect(saved.tasks.last.kind, GoalTaskKind.recordOutcome);
    expect(saved.actionOutcomes[0]!.confirmed, isTrue);
    expect(
      GoalNotifier.continuedProgress(saved, saved.spec).tasks,
      hasLength(2),
    );
  });
  test(
    'the runner waits for an external confirmation, then continues without repeating research',
    () async {
      var researchCalls = 0;
      final runner = GoalRunner(
        plan: (_) async => const GoalPlan(['Prepare the requested timer']),
        research: (_, _, _) async {
          researchCalls++;
          return const GoalStepResult(answer: 'Timer: five minutes');
        },
        evaluate: (_, _) async => const GoalDecision(satisfied: true),
        write: (_, _) async => 'A five minute timer is ready.',
        deliver: (_, p) async =>
            GoalDelivery(actions: const [action], outcomes: p.actionOutcomes),
        checkpoint: (_) async {},
      );
      const spec = GoalSpec(
        objective: 'Set a timer for five minutes',
        successCriteria: 'Prepare the timer',
      );
      final first = await runner.run(spec);
      expect(first.status, GoalStatus.partial);
      expect(first.phase, GoalPhase.confirming);
      expect(GoalNotifier.canContinue(first), isFalse);
      final confirmed = first.copyWith(
        actionOutcomes: {
          0: GoalActionOutcome(opened: true, confirmed: true, at: at),
        },
      );
      final resumed = GoalNotifier.continuedProgress(confirmed, spec);
      final finalResult = await runner.run(spec, resume: resumed);
      expect(finalResult.status, GoalStatus.completed);
      expect(finalResult.actionOutcomes[0]!.confirmed, isTrue);
      expect(researchCalls, 1);
    },
  );
  testWidgets(
    'the confirmation control appears only after opening the action',
    (tester) async {
      var confirmations = 0;
      Future<void> show({
        Map<int, DateTime> opened = const {},
        Map<int, DateTime> confirmed = const {},
      }) => tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PhoneActionCards(
              actions: const [action],
              opened: opened,
              confirmed: confirmed,
              onConfirmed: (_) => confirmations++,
            ),
          ),
        ),
      );
      await show();
      expect(find.byKey(const Key('phone-action-confirm-0')), findsNothing);
      await show(opened: {0: at});
      await tester.tap(find.byKey(const Key('phone-action-confirm-0')));
      expect(confirmations, 1);
      await show(opened: {0: at}, confirmed: {0: at});
      expect(find.byKey(const Key('phone-action-confirm-0')), findsNothing);
      expect(find.textContaining('Confirmed at'), findsOneWidget);
    },
  );
}
