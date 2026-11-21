import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';

// Audit 05a-4: a saved goal a newer build wrote differently must still open,
// instead of throwing and taking the goal, report and sources with it.
void main() {
  test('a status and phase this build does not know still decode', () {
    final goal = GoalNotifier.decode({
      'objective': 'Compare the two prices',
      'status': 'archived',
      'startedAt': '2026-11-20T10:00:00Z',
      'phase': 'researching',
      'report': 'The cheaper one is [1].',
      'sources': [
        {'title': 'Price list', 'url': 'https://shop.example/prices'},
      ],
    });
    expect(goal.spec.objective, 'Compare the two prices');
    expect(goal.status, GoalStatus.paused);
    expect(goal.report, 'The cheaper one is [1].');
    expect(goal.sources.single.url, 'https://shop.example/prices');
    expect(goal.startedAt, DateTime.utc(2026, 11, 20, 10));
  });

  test('a document missing its objective still decodes', () {
    final goal = GoalNotifier.decode({
      'status': 'completed',
      'startedAt': '2026-10-08T20:00:00.000',
    });
    expect(goal.spec.objective, isEmpty);
    expect(goal.status, GoalStatus.completed);
  });

  test('a running goal comes back paused, as before', () {
    final goal = GoalNotifier.decode({
      'objective': 'Find the weight',
      'status': 'running',
      'startedAt': '2026-10-08T20:00:00.000',
    });
    expect(goal.status, GoalStatus.paused);
  });

  test('a field of another type falls back instead of throwing', () {
    final goal = GoalNotifier.decode({
      'objective': 'Compare the two prices',
      'startedAt': '2026-11-20T10:00:00Z',
      'criteria': 5,
      'rules': 7,
      'maxSteps': '60',
      // A corrupt cap is not "no cap": it falls back to the goal's default.
      'maxTokens': {'a': 1},
      'maxToolCalls': true,
      'maxDurationMs': 'soon',
      'maxMinutes': '15',
      'completionTarget': 5,
      'terms': {'a': 1},
      'steps': '3',
      'usedTokens': 2.5,
      'models': 'qwen',
      'missing': [1, 'no price'],
      'nextStep': 9,
      'actionOutcomes': {
        'x': {'at': '2026-11-20T10:00:00Z'},
        '1': 5,
      },
    });
    expect(goal.spec.maxSteps, 60);
    expect(goal.spec.maxTokens, 64000);
    expect(goal.spec.maxToolCalls, 20);
    expect(goal.spec.maxDuration, const Duration(minutes: 15));
    expect(goal.spec.successCriteria, isEmpty);
    expect(goal.spec.rules, isEmpty);
    expect(goal.spec.completionTarget, 0.85);
    expect(goal.spec.terms, isEmpty);
    expect(goal.steps, 3);
    expect(goal.usedTokens, 2);
    expect(goal.models, isEmpty);
    expect(goal.missing, ['no price']);
    expect(goal.nextStep, 'Compare the two prices');
    expect(goal.actionOutcomes, isEmpty);
  });

  test('an unreadable item is dropped, not the goal', () {
    final goal = GoalNotifier.decode({
      'objective': 'Compare the two prices',
      'startedAt': '2026-11-20T10:00:00Z',
      'tasks': [
        {'question': 5, 'status': 'weird'},
        {'question': 'What costs less?', 'status': 'done'},
      ],
      'sources': ['not a source'],
      'reportChecks': [
        {'kind': 'nope', 'detail': 3},
      ],
    });
    expect(goal.spec.objective, 'Compare the two prices');
    expect(goal.tasks.single.question, 'What costs less?');
    expect(goal.sources, isEmpty);
    expect(goal.reportChecks, isEmpty);
  });

  test('a goal without a readable start time is dropped, not re-stamped', () {
    // startedAt is the goal's id (GoalHistoryNotifier.idOf): restoring it
    // with the current time would list it as a different goal.
    expect(
      () => GoalNotifier.decode({
        'objective': 'Compare the two prices',
        'startedAt': 'yesterday',
      }),
      throwsFormatException,
    );
    expect(
      () => GoalNotifier.decode({'objective': 'Compare the two prices'}),
      throwsFormatException,
    );
  });
}
