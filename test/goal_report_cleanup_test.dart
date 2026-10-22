import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence.dart';
import 'package:ondevice_llm/inference/engine/turn_budget.dart';

// Review round 4 (2026-09-28): a figure no source states is left out
// with its sentence or table cell instead of sinking the step or the
// report; the report says what it does not cover; Continue does not review
// the same findings again; page reads have their own allowance.

const _objective = 'Compare the Nikon Z30 to the Sony ZV-E10';

GoalSpec _spec({
  String criteria = 'Price',
  GoalSpecialization kind = GoalSpecialization.general,
}) => GoalSpec(
  objective: _objective,
  successCriteria: criteria,
  specialization: kind,
);

void main() {
  group('figures no source states are left out', () {
    test('a sentence holding one goes, the others stay', () {
      final (text, removed) = GoalChecker.withoutUnsupported(
        'The Z30 has a 20.9 MP sensor [1]. It costs \$699 [1]. '
        'It weighs 405 g [1].',
        ['The Z30 has a 20.9 MP sensor and weighs 405 g.'],
      );
      expect(text, 'The Z30 has a 20.9 MP sensor [1]. It weighs 405 g [1].');
      expect(removed, ['699']);
    });

    test('a table cell holding one is emptied, checked against its row', () {
      final (table, removed) = GoalChecker.withoutUnsupported(
        '| Model | Price |\n|---|---|\n| Z30 | \$699 [1] |\n'
        '| ZV-E10 | \$799 [2] |',
        ['The Z30 costs \$699.', 'The ZV-E10 costs \$749.'],
      );
      expect(
        table,
        '| Model | Price |\n|---|---|\n| Z30 | \$699 [1] |\n| ZV-E10 | — |',
      );
      expect(removed, ['799']);
    });

    test('a report\'s uncited figure must be in its findings', () {
      final (text, removed) = GoalChecker.withoutUnsupported(
        'The Z30 costs 699 USD [1]. The ZV-E10 costs 749 USD.',
        ['Z30: 699 USD', 'ZV-E10: 749 USD'],
        findings: 'The Z30 costs 699 USD [1].',
      );
      expect(text, 'The Z30 costs 699 USD [1].');
      expect(removed, ['749']);
    });

    test('a full stop after a figure ends the sentence', () {
      expect(
        EvidenceRanker.unsupportedFigures('It costs 699.', [
          'The price is \$699.',
        ]),
        isEmpty,
      );
      expect(
        EvidenceRanker.unsupportedFigures('It costs 699.', [
          'The price is 699.5 USD',
        ]),
        ['699'],
        reason: 'a decimal part makes it another number',
      );
    });

    test('steps saved with the old figures check are cleaned on resume', () {
      final legacy = GoalProgress(
        spec: _spec(),
        status: GoalStatus.partial,
        steps: 2,
        startedAt: DateTime(2026),
        tasks: const [
          GoalTask(
            'Prices?',
            status: GoalTaskStatus.done,
            findings:
                'The Z30 costs 699 USD [1]. The ZV-E10 costs 799 USD [2].',
            checks: [GoalCheck(GoalCheckKind.figures, '799')],
          ),
          GoalTask(
            'Sensor?',
            status: GoalTaskStatus.done,
            findings: 'A 20.9 MP sensor [1].',
          ),
        ],
        sources: const [
          GoalSource(
            title: 'Nikon',
            url: 'https://example.com/nikon',
            evidence: 'The Z30 costs 699 USD. It has a 20.9 MP sensor.',
          ),
          GoalSource(
            title: 'Sony',
            url: 'https://example.com/sony',
            evidence: 'The ZV-E10 costs 749 USD.',
          ),
        ],
      );
      final cleaned = GoalRunner.withoutLegacyFigures(legacy);
      final first = cleaned.tasks.first;
      expect(first.findings, 'The Z30 costs 699 USD [1].');
      expect(first.checks.map((c) => (c.kind, c.detail)), [
        (GoalCheckKind.droppedFigures, '799'),
      ]);
      expect(first.excluded, isFalse);
      expect(identical(cleaned.tasks.last, legacy.tasks.last), isTrue);
      expect(
        identical(GoalRunner.withoutLegacyFigures(cleaned), cleaned),
        isTrue,
        reason: 'nothing is left to clean',
      );
      final math = legacy.copyWith(spec: _spec(kind: GoalSpecialization.math));
      expect(identical(GoalRunner.withoutLegacyFigures(math), math), isTrue);
    });
  });

  group('the report loses unsupported figures, not its place', () {
    GoalProgress progress({
      GoalSpecialization kind = GoalSpecialization.general,
    }) => GoalProgress(
      spec: _spec(kind: kind),
      status: GoalStatus.running,
      steps: 1,
      startedAt: DateTime(2026),
      sources: const [
        GoalSource(
          title: 'Prices',
          url: 'https://example.com/prices',
          evidence: 'The Z30 costs 699 USD. The ZV-E10 costs 749 USD.',
        ),
      ],
    );
    const findings = 'The Z30 costs 699 USD [1]. The ZV-E10 costs 749 USD [1].';
    const report =
        'Both cameras are made for vlogging with an APS-C sensor [1]. '
        'The Z30 costs 699 USD [1]. The ZV-E10 costs 799 USD [1].\n\n'
        '## Not covered\n- Nothing requested is missing.';
    const checks = [
      GoalCheck(GoalCheckKind.figures, '799'),
      GoalCheck(GoalCheckKind.revised),
    ];

    test('the sentence goes and the note says what was left out', () {
      var checked = '';
      final (text, after) = GoalNotifier.withoutReportFigures(
        report,
        checks,
        progress: progress(),
        findings: findings,
        check: (t) {
          checked = t;
          return const [];
        },
      );
      expect(
        text,
        'Both cameras are made for vlogging with an APS-C sensor [1]. '
        'The Z30 costs 699 USD [1].\n\n'
        '## Not covered\n- Nothing requested is missing.',
      );
      expect(checked, text, reason: 'the cleaned report is checked again');
      expect(after.map((c) => c.kind), [
        GoalCheckKind.revised,
        GoalCheckKind.droppedFigures,
      ]);
      expect(after.last.detail, '799');
      expect(after.every((c) => !c.fixable), isTrue);
    });

    test('left alone: a math goal, no figures check, or half the report', () {
      List<GoalCheck> never(String _) => fail('not checked again');
      for (final (p, c) in [
        (progress(kind: GoalSpecialization.math), checks),
        (progress(), const [GoalCheck(GoalCheckKind.revised)]),
      ]) {
        final (text, after) = GoalNotifier.withoutReportFigures(
          report,
          c,
          progress: p,
          findings: findings,
          check: never,
        );
        expect(text, report);
        expect(after, c);
      }
      const mostly =
          'The ZV-E10 costs 799 USD and weighs 343 g with battery and card '
          '[1]. Short [1].';
      final (text, after) = GoalNotifier.withoutReportFigures(
        mostly,
        checks,
        progress: progress(),
        findings: findings,
        check: never,
      );
      expect(text, mostly);
      expect(after, checks);
    });
  });

  group('the report says what it does not cover', () {
    final spec = _spec(criteria: 'Price\nWeight');
    final base = GoalProgress(
      spec: spec,
      status: GoalStatus.running,
      steps: 2,
      startedAt: DateTime(2026),
    );
    String prompt(GoalProgress p, {List<String> open = const []}) =>
        GoalNotifier.reportPrompt(
          spec,
          p,
          findings: 'Saved findings',
          sourceList: '',
          open: open,
          today: '2026-09-28',
        );

    test('unmet criteria, empty steps and open questions are listed', () {
      final text = prompt(
        base.copyWith(
          missing: const ['Weight'],
          tasks: const [
            GoalTask(
              'Price?',
              status: GoalTaskStatus.done,
              findings: 'The Z30 costs 699 USD [1].',
            ),
            GoalTask(
              'Weight?',
              status: GoalTaskStatus.failed,
              error: 'timeout',
            ),
          ],
        ),
        open: const ['What does the ZV-E10 weigh?'],
      );
      expect(text, contains('Write the interim report'));
      expect(text, contains('section headed "Not covered"'));
      expect(text, contains('- Criterion not met: Weight'));
      expect(text, contains('- Step that established nothing: Weight?'));
      expect(text, isNot(contains('established nothing: Price?')));
      expect(
        text,
        contains('- Not researched yet: What does the ZV-E10 weigh?'),
      );
      expect(text, contains('do not calculate new ones'));
    });

    test('nothing missing is said in one line', () {
      final text = prompt(base);
      expect(text, contains('Write the final report'));
      expect(text, contains('- Nothing requested is missing'));
    });

    test('an unchecked review asks for the unaddressed criteria', () {
      final text = prompt(
        base.copyWith(missing: const [GoalDecision.uncheckedNote]),
      );
      expect(text, contains('the automatic review could not check them'));
      expect(text, isNot(contains('Criterion not met')));
    });

    test('a math report derives its figures', () {
      final math = _spec(kind: GoalSpecialization.math);
      final text = GoalNotifier.reportPrompt(
        math,
        base.copyWith(spec: math),
        findings: 'Saved findings',
        sourceList: '',
        open: const [],
        today: '2026-09-28',
      );
      expect(text, isNot(contains('do not calculate new ones')));
      expect(text, contains('Not covered'));
    });
  });

  group('Continue', () {
    final ran = GoalProgress(
      spec: _spec(),
      status: GoalStatus.partial,
      steps: 3,
      startedAt: DateTime(2026),
      reviews: 2,
      reviewedSteps: 3,
      gapRounds: 1,
      error: 'timeout',
      missing: const ['Price'],
      criteria: const [GoalCriterion(text: 'Price')],
      tasks: const [
        GoalTask(
          'Price?',
          status: GoalTaskStatus.done,
          findings: 'The Z30 costs 699 USD [1].',
        ),
        GoalTask('Weight?', status: GoalTaskStatus.failed, error: 'timeout'),
      ],
    );

    test('keeps the reviews and asks failed steps again', () {
      final resumed = GoalNotifier.continuedProgress(ran, ran.spec);
      expect(resumed.reviews, 2);
      expect(resumed.reviewedSteps, 3);
      expect(resumed.gapRounds, 1);
      expect(resumed.missing, ['Price']);
      expect(resumed.criteria.single.text, 'Price');
      expect(resumed.status, GoalStatus.paused);
      expect(resumed.error, isNull);
      expect(resumed.tasks.first.findings, 'The Z30 costs 699 USD [1].');
      expect(resumed.tasks.last.question, 'Weight?');
      expect(resumed.tasks.last.status, GoalTaskStatus.pending);
      expect(resumed.tasks.last.error, isNull);
    });

    test('is offered only when there is something new to do', () {
      expect(GoalNotifier.canContinue(ran), isTrue, reason: 'a step failed');
      final reviewed = ran.copyWith(tasks: [ran.tasks.first]);
      expect(
        GoalNotifier.canContinue(reviewed),
        isFalse,
        reason: 'the same findings would be reviewed again',
      );
      expect(GoalNotifier.canContinue(reviewed.copyWith(steps: 4)), isTrue);
      for (final status in [
        GoalStatus.paused,
        GoalStatus.failed,
        GoalStatus.stopped,
      ]) {
        expect(
          GoalNotifier.canContinue(reviewed.copyWith(status: status)),
          isTrue,
          reason: '$status',
        );
      }
      for (final status in [
        GoalStatus.running,
        GoalStatus.completed,
        GoalStatus.ready,
      ]) {
        expect(
          GoalNotifier.canContinue(reviewed.copyWith(status: status)),
          isFalse,
          reason: '$status',
        );
      }
    });
  });

  test('page reads have their own allowance', () {
    final budget = TurnBudget(maxToolCalls: 1, maxReads: 2);
    expect(budget.useRead(), isTrue);
    expect(budget.useRead(), isTrue);
    expect(budget.useRead(), isFalse, reason: 'the page is skipped');
    expect(budget.usedReads, 2);
    expect(budget.remainingTools, 1, reason: 'reads spend no tool call');
    expect(TurnBudget().useRead(), isTrue);
    final overdue = TurnBudget(
      maxReads: 5,
      deadline: DateTime(2026),
      now: () => DateTime(2026, 1, 2),
    );
    expect(overdue.useRead, throwsA(isA<TurnLimitException>()));
  });

  test('the same page under another address is one source', () {
    expect(
      GoalRunner.pageKey(
        'https://www.Example.com/a/?utm_source=x&b=2&a=1#part',
      ),
      'example.com/a?a=1&b=2',
    );
    expect(
      GoalRunner.pageKey('http://example.com'),
      GoalRunner.pageKey('https://example.com/'),
    );
    expect(
      GoalRunner.pageKey('https://example.com/a?id=1'),
      isNot(GoalRunner.pageKey('https://example.com/a?id=2')),
    );
  });

  test('a single comma-separated criteria line becomes its items', () {
    expect(
      GoalRules.criteriaLines(
        'Specifications, in what one is better, best use cases',
      ),
      ['Specifications', 'In what one is better', 'Best use cases'],
    );
    expect(GoalRules.criteriaLines('Price, including tax, and weight'), [
      'Price, including tax, and weight',
    ]);
    expect(GoalRules.criteriaLines('Price under 1,299 USD, weight, size'), [
      'Price under 1,299 USD, weight, size',
    ]);
    expect(GoalRules.criteriaLines('Price\nWeight'), ['Price', 'Weight']);
  });

  test('an all-reasoning report reply falls back to the findings', () async {
    final runner = GoalRunner(
      plan: (_) async => const GoalPlan(['What is the camera resolution?']),
      research: (_, _, _) async => const GoalStepResult(
        answer: 'A 20.9 MP sensor [1].',
        sources: [
          GoalSource(
            title: 'Nikon',
            url: 'https://example.com/nikon',
            evidence: 'A 20.9 MP sensor.',
          ),
        ],
      ),
      evaluate: (_, _) async =>
          const GoalDecision(satisfied: false, missing: ['Price']),
      write: (_, _) async => '  ',
      checkpoint: (_) async {},
    );
    final result = await runner.run(
      const GoalSpec(
        objective: 'Nikon Z30 resolution',
        successCriteria: 'Resolution',
      ),
    );
    expect(
      result.report,
      '### ${result.tasks.single.question}\n\nA 20.9 MP sensor [1].',
    );
    expect(result.status, GoalStatus.partial);
  });
}
