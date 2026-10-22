import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';

GoalSpec _spec(double target) => GoalSpec(
  objective: 'Compare cameras',
  successCriteria: [for (var i = 1; i <= 7; i++) 'Requirement $i'].join('\n'),
  completionTarget: target,
);

List<GoalCriterion> _assessments({bool invalid = false}) => [
  for (var i = 1; i <= 7; i++)
    GoalCriterion(
      text: 'Requirement $i',
      satisfied: i <= 6,
      validationError: invalid && i == 1 ? 'Invalid evidence' : '',
    ),
];

void main() {
  test(
    'report describes a met coverage target while retaining limitations',
    () {
      final spec = _spec(0.85);
      String prompt(bool met) => GoalNotifier.reportPrompt(
        spec,
        GoalProgress(
          spec: spec,
          status: GoalStatus.running,
          steps: 1,
          startedAt: DateTime(2026),
          criteria: _assessments(),
          criteriaSatisfied: met,
          missing: const ['Requirement 7'],
        ),
        findings: 'Saved findings',
        sourceList: '',
        open: const [],
        today: '2026-09-28',
      );
      expect(prompt(true), contains('Configured completion target: 85%'));
      expect(prompt(true), contains('Evidence-assessed coverage: 86%'));
      expect(prompt(true), contains('The selected target is met'));
      expect(prompt(true), contains('Requirement 7'));
      expect(prompt(false), contains('Do not claim that it is met'));
    },
  );
  test(
    '85% completes at six of seven, retains gaps and skips extra research',
    () async {
      var researched = 0;
      final runner = GoalRunner(
        plan: (_) async =>
            const GoalPlan(['What camera specifications exist?']),
        research: (_, _, _) async {
          researched++;
          return const GoalStepResult(answer: 'Supported camera facts [1].');
        },
        evaluate: (_, _) async => GoalDecision(
          satisfied: false,
          criteria: _assessments(),
          missing: const ['Requirement 7'],
          nextSteps: const ['What additional camera measurements exist?'],
        ),
        write: (_, p) async {
          expect(p.missing, ['Requirement 7']);
          return 'Report, with Requirement 7 unknown.';
        },
        verify: (_, _, report) async => (report, const <GoalCheck>[]),
        checkpoint: (_) async {},
      );
      final result = await runner.run(_spec(0.85));
      expect(result.status, GoalStatus.completed);
      expect(researched, 1);
      expect(result.missing, ['Requirement 7']);
      expect(result.spec.coverage(result.criteria), closeTo(6 / 7, 1e-9));
    },
  );

  test('coverage cannot pass a stricter target or malformed assessment', () {
    expect(_spec(0.9).meetsTarget(_assessments()), isFalse);
    expect(_spec(0.85).meetsTarget(_assessments(invalid: true)), isFalse);
    expect(_spec(0.85).meetsTarget(_assessments().take(6).toList()), isFalse);
    expect(
      _spec(0.85).meetsTarget([
        ..._assessments().take(6),
        const GoalCriterion(text: 'Invented requirement', satisfied: true),
      ]),
      isFalse,
    );
  });

  test(
    'factual report problems still prevent completion above target',
    () async {
      final runner = GoalRunner(
        plan: (_) async =>
            const GoalPlan(['What camera specifications exist?']),
        research: (_, _, _) async =>
            const GoalStepResult(answer: 'Supported camera facts.'),
        evaluate: (_, _) async => GoalDecision(
          satisfied: false,
          criteria: _assessments(),
          missing: const ['Requirement 7'],
        ),
        write: (_, _) async => 'An unsupported price.',
        verify: (_, _, report) async => (
          report,
          const [GoalCheck(GoalCheckKind.figures, 'invented price')],
        ),
        checkpoint: (_) async {},
      );
      expect((await runner.run(_spec(0.85))).status, GoalStatus.partial);
    },
  );

  test(
    'refinement preserves evidence and report, clears old judgments, and persists guidance',
    () {
      final original = GoalProgress(
        spec: _spec(0.85),
        status: GoalStatus.completed,
        startedAt: DateTime(2026),
        steps: 2,
        usedTokens: 500,
        usedToolCalls: 2,
        report: 'Previous report',
        criteria: _assessments(),
        criteriaSatisfied: true,
        reviews: 2,
        tasks: const [
          GoalTask(
            'Camera resolution?',
            status: GoalTaskStatus.done,
            findings: '20 MP [1].',
          ),
          GoalTask('Unstarted follow-up?'),
        ],
        sources: const [
          GoalSource(
            title: 'Specs',
            url: 'https://example.com',
            evidence: '20 MP',
          ),
        ],
      );
      final spec = original.spec.copyWith(
        successCriteria: 'Video recording limits\nAudio inputs',
        rules: 'Prices in CAD',
        searchGuidance: 'Search recording time limits for long interviews.',
        completionTarget: 0.8,
      );
      final updated = GoalNotifier.refinedProgress(original, spec);
      expect(updated.report, original.report);
      expect(updated.sources, original.sources);
      expect(updated.tasks.single.findings, '20 MP [1].');
      expect(updated.criteria, isEmpty);
      expect(updated.criteriaSatisfied, isFalse);
      expect(updated.usedTokens, 500);
      final restored = GoalNotifier.decode(GoalNotifier.encode(updated));
      expect(restored.spec.completionTarget, 0.8);
      expect(
        restored.spec.effectiveRules,
        contains('Search recording time limits'),
      );
      expect(restored.spec.criteriaItems, [
        'Video recording limits',
        'Audio inputs',
      ]);
      expect(
        GoalNotifier.continuationSpec(restored, DateTime.now()).searchGuidance,
        spec.searchGuidance,
      );
    },
  );
}
