import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';

const _unlimited = GoalSpec(
  objective: 'Compare camera specifications and recommend one',
  successCriteria: 'Compare the cameras and recommend one',
  maxSteps: null,
  maxDuration: null,
  maxTokens: null,
  maxToolCalls: null,
);

const _gaps = [
  'How does camera weight affect handheld filming?',
  'What audio inputs are available for recording?',
  'Which autofocus modes support moving subjects?',
  'How does low light noise affect footage?',
  'Which battery supports a full day of shooting?',
];

void main() {
  test(
    'manufacturer criteria reject third-party and wrong-brand citations',
    () {
      const criterion =
          'State Nikon Z30 effective megapixels with a manufacturer citation';
      const fact = 'The Nikon Z30 has 20.9 effective megapixels [1].';
      GoalCriterion review(String url, {String requirement = criterion}) =>
          GoalNotifier.validateCriteria(
            {
              'criteria': [
                {
                  'id': 'C1',
                  'satisfied': true,
                  'facts': [fact],
                  'steps': [1],
                },
              ],
            },
            GoalProgress(
              spec: GoalSpec(
                objective: 'Compare Nikon Z30',
                successCriteria: requirement,
              ),
              status: GoalStatus.running,
              steps: 1,
              startedAt: DateTime(2026),
              tasks: const [
                GoalTask(
                  'Resolution?',
                  status: GoalTaskStatus.done,
                  findings: fact,
                ),
              ],
              sources: [
                GoalSource(title: 'Specifications', url: url, evidence: fact),
              ],
            ),
          ).single;
      expect(review('https://reviews.example/nikon-z30').satisfied, isFalse);
      expect(review('https://sony.ca/nikon-z30').satisfied, isFalse);
      expect(
        review('https://nikonusa.com.evil.example/z30').satisfied,
        isFalse,
      );
      expect(review('https://imaging.nikon.com/z30').satisfied, isTrue);
      expect(
        review(
          'https://reviews.example/nikon-z30',
          requirement: 'State Nikon Z30 effective megapixels',
        ).satisfied,
        isTrue,
      );
      expect(
        review(
          'https://reviews.example/nikon-z30',
          requirement: 'State Nikon Z30 manufacturer and effective megapixels',
        ).satisfied,
        isTrue,
      );
    },
  );
  test(
    'a manufacturer comparison needs cited sources from both named makers',
    () {
      GoalCriterion review(
        String sonyUrl, {
        bool citeSony = true,
      }) => GoalNotifier.validateCriteria(
        {
          'criteria': [
            {
              'id': 'C1',
              'satisfied': true,
              'steps': [1],
              'facts': [
                'Nikon Z30 has 20.9 MP [1].',
                'Sony ZV-E10 has 24.2 MP ${citeSony ? '[2]' : '[1]'}.',
              ],
            },
          ],
        },
        GoalProgress(
          spec: const GoalSpec(
            objective: 'Compare Nikon Z30 and Sony ZV-E10',
            successCriteria: 'Compare resolution with manufacturer citations',
          ),
          status: GoalStatus.running,
          steps: 1,
          startedAt: DateTime(2026),
          tasks: [
            GoalTask(
              'Resolution?',
              status: GoalTaskStatus.done,
              findings:
                  'Nikon Z30 has 20.9 MP [1]. Sony ZV-E10 has 24.2 MP ${citeSony ? '[2]' : '[1]'}.',
            ),
          ],
          sources: [
            const GoalSource(
              title: 'Nikon',
              url: 'https://nikonusa.com/z30',
              evidence: 'Nikon Z30 has 20.9 MP.',
            ),
            GoalSource(
              title: 'Sony',
              url: sonyUrl,
              evidence: 'Sony ZV-E10 has 24.2 MP.',
            ),
          ],
        ),
      ).single;
      expect(review('https://reviews.example/sony').satisfied, isFalse);
      expect(review('https://sony.ca/zv-e10').satisfied, isTrue);
      expect(
        review('https://sony.ca/zv-e10', citeSony: false).satisfied,
        isFalse,
      );
    },
  );
  test(
    'comparison plans keep the same factual question for different cameras',
    () async {
      final asked = <String>[];
      final runner = GoalRunner(
        plan: (_) async => const GoalPlan([
          'What are the Nikon Z30 sensor specifications?',
          'What are the Sony ZV-E10 sensor specifications?',
          'Nikon Z30 sensor specifications?',
        ]),
        research: (_, task, _) async {
          asked.add(task.question);
          return const GoalStepResult(answer: 'Specifications.');
        },
        evaluate: (_, _) async => const GoalDecision(satisfied: true),
        write: (_, _) async => 'Report.',
        checkpoint: (_) async {},
      );
      await runner.run(
        const GoalSpec(
          objective: 'Compare Nikon Z30 to Sony ZV-E10',
          successCriteria: 'Compare sensors',
        ),
      );
      expect(asked, [
        'What are the Nikon Z30 sensor specifications?',
        'What are the Sony ZV-E10 sensor specifications?',
      ]);
    },
  );
  test(
    'one extra research round at most, then a report with the gaps',
    () async {
      var reviews = 0;
      final asked = <String>[];
      final runner = GoalRunner(
        plan: (_) async => const GoalPlan(['What is the camera resolution?']),
        research: (_, task, _) async {
          asked.add(task.question);
          return const GoalStepResult(answer: 'A supported finding [1].');
        },
        evaluate: (_, _) async {
          final checked = ++reviews;
          return GoalDecision(
            satisfied: false,
            criteria: [
              for (var i = 0; i < 4; i++)
                GoalCriterion(text: 'Criterion $i', satisfied: i < checked),
            ],
            missing: [for (var i = checked; i < 4; i++) 'Criterion $i'],
            nextSteps: [_gaps[checked - 1]],
          );
        },
        write: (_, _) async => 'The comparison, and what it does not cover.',
        checkpoint: (_) async {},
      );
      final result = await runner.run(_unlimited);
      expect(result.reviews, 2);
      expect(result.gapRounds, 1);
      expect(asked, ['What is the camera resolution?', _gaps[0]]);
      expect(result.status, GoalStatus.partial);
      expect(result.report, 'The comparison, and what it does not cover.');
      expect(result.missing, ['Criterion 2', 'Criterion 3']);
    },
  );

  test('a gap round that closes the criteria completes the goal', () async {
    var reviews = 0;
    final runner = GoalRunner(
      plan: (_) async => const GoalPlan(['What is the camera resolution?']),
      research: (_, _, _) async =>
          const GoalStepResult(answer: 'A supported finding [1].'),
      evaluate: (_, _) async {
        final checked = ++reviews;
        return GoalDecision(
          satisfied: checked == 2,
          criteria: [
            for (var i = 0; i < 2; i++)
              GoalCriterion(text: 'Criterion $i', satisfied: i < checked),
          ],
          nextSteps: checked == 2 ? const [] : [_gaps[0]],
        );
      },
      write: (_, _) async => 'The comparison and recommendation.',
      checkpoint: (_) async {},
    );
    final result = await runner.run(_unlimited);
    expect(result.status, GoalStatus.completed);
    expect(result.reviews, 2);
  });

  test(
    'a failed exploratory step does not veto proven replacement findings',
    () async {
      final runner = GoalRunner(
        plan: (_) async => const GoalPlan([
          'Which camera supports this feature?',
          'What do the camera specifications establish?',
        ]),
        research: (_, task, _) async {
          if (task.question.startsWith('Which')) {
            throw StateError('Source unavailable');
          }
          return const GoalStepResult(
            answer: 'The replacement establishes the feature [1].',
          );
        },
        evaluate: (_, _) async => const GoalDecision(
          satisfied: true,
          criteria: [
            GoalCriterion(
              text: 'Feature comparison',
              satisfied: true,
              steps: [2],
            ),
          ],
        ),
        write: (_, _) async => 'Supported report.',
        checkpoint: (_) async {},
      );
      final result = await runner.run(_unlimited);
      expect(result.status, GoalStatus.completed);
      expect(result.tasks.first.status, GoalTaskStatus.failed);
    },
  );

  test(
    'validated criteria outrank contradictory flags and invented extra gaps',
    () {
      final p = GoalProgress(
        spec: const GoalSpec(
          objective: 'Nikon Z30 resolution',
          successCriteria: 'State resolution',
        ),
        status: GoalStatus.running,
        steps: 1,
        startedAt: DateTime(2026),
        tasks: const [
          GoalTask(
            'Resolution?',
            status: GoalTaskStatus.done,
            findings: 'Nikon Z30 sensor resolution is 20.9 MP [1].',
          ),
        ],
        sources: const [
          GoalSource(
            title: 'Specification',
            url: 'https://example.com',
            evidence: 'Nikon Z30 sensor resolution is 20.9 MP.',
          ),
        ],
      );
      final reply = <String, dynamic>{
        'satisfied': false,
        'missing': ['Unrequested exhaustive laboratory tests'],
        'next_steps': ['Find exhaustive laboratory tests'],
        'criteria': [
          <String, dynamic>{
            'id': 'C1',
            'satisfied': true,
            'steps': [1],
            'quotes': [
              {
                'step': 1,
                'quote': 'Nikon Z30 sensor resolution is 20.9 MP [1].',
              },
            ],
            'evidence': [
              {'source': 1, 'quote': 'Nikon Z30 sensor resolution is 20.9 MP.'},
            ],
          },
        ],
      };
      final good = GoalNotifier.decisionFromReview(reply, p);
      expect(good.satisfied, isTrue);
      expect(good.missing, isEmpty);
      expect(good.nextSteps, isEmpty);
      final back = GoalCriterion.fromJson(good.criteria.single.toJson());
      expect(back.quotes.single.step, 1);
      expect(back.evidence.single.source, 1);
      final item = (reply['criteria'] as List).single as Map<String, dynamic>;
      item['quotes'] = [
        {'step': 1, 'quote': 'The Nikon has invented stabilization [1].'},
      ];
      final invented = GoalNotifier.decisionFromReview(reply, p);
      expect(invented.satisfied, isFalse);
      expect(
        invented.unchecked,
        isFalse,
        reason: 'an unsupported claim is an unmet criterion, not a bad reply',
      );
      expect(invented.criteria.single.validationError, isEmpty);
      expect(invented.criteria.single.explanation, contains('Not counted'));
      expect(invented.missing, ['State resolution']);
      expect(
        invented.nextSteps,
        ['Nikon Z30 resolution: State resolution'],
        reason:
            'the reviewer called everything met, so its extra gaps are not '
            'about this criterion',
      );
    },
  );

  group('the review check is tolerant', () {
    GoalProgress camera({String criteria = 'Sensor; Weight; Price'}) =>
        GoalProgress(
          spec: GoalSpec(
            objective: 'Compare the Nikon Z30 to the Sony ZV-E10',
            successCriteria: criteria,
          ),
          status: GoalStatus.running,
          steps: 3,
          startedAt: DateTime(2026),
          tasks: const [
            GoalTask(
              'Sensor?',
              status: GoalTaskStatus.done,
              findings:
                  'The Nikon Z30 has a 20.9 MP APS-C sensor [1]. The Sony '
                  'ZV-E10 has a 24.2 MP APS-C sensor [2].',
            ),
            GoalTask(
              'Weight?',
              status: GoalTaskStatus.done,
              findings: 'The Z30 weighs 405 g with battery and card [1].',
            ),
            GoalTask('Price?', status: GoalTaskStatus.failed, error: 'x'),
          ],
          sources: const [
            GoalSource(
              title: 'Nikon',
              url: 'https://example.com/nikon',
              evidence:
                  'Menu.\nThe Z30 has a 20.9 MP APS-C sensor. It weighs 405 g '
                  'with battery and card.',
            ),
            GoalSource(
              title: 'Sony',
              url: 'https://example.com/sony',
              evidence: 'The ZV-E10 has a 24.2 MP APS-C sensor.',
            ),
          ],
        );

    test('reworded facts count when every number matches', () {
      final criteria = GoalNotifier.validateCriteria({
        'criteria': [
          {
            'id': 'c1',
            'satisfied': 'yes',
            'steps': ['Step 1'],
            'facts': [
              'Step 1: Nikon Z30 sensor: 20.9 MP APS-C [1]',
              'Sony ZV-E10 sensor: 24.2 MP APS-C',
            ],
            'explanation': 'Both sensors are stated.',
          },
          {
            'id': 2,
            'satisfied': true,
            'steps': [2],
            'facts': ['The Z30 weighs 450 g [1]'],
          },
          {
            'id': 'C3',
            'satisfied': false,
            'steps': [3],
            'facts': [],
            'explanation': 'The price step failed.',
          },
        ],
      }, camera());
      expect(criteria.map((c) => c.satisfied), [true, false, false]);
      expect(criteria.map((c) => c.validationError), ['', '', '']);
      expect(criteria[0].quotes.map((q) => q.step), [1, 1]);
      expect(
        criteria[0].quotes.first.quote,
        'Nikon Z30 sensor: 20.9 MP APS-C [1]',
      );
      expect(
        criteria[0].evidence.map((e) => e.source),
        containsAll([1, 2]),
        reason: 'the passages come from the cited source, or the finding\'s',
      );
      expect(criteria[0].evidence.first.quote, contains('20.9 MP'));
      expect(criteria[1].explanation, contains('Not counted as met'));
      expect(criteria[2].explanation, 'The price step failed.');
    });

    test('a met criterion argued without facts is held to its explanation', () {
      final criteria = GoalNotifier.validateCriteria({
        'criteria': [
          {
            'id': 'C1',
            'satisfied': true,
            'explanation':
                'The Z30 has a 20.9 MP sensor and the ZV-E10 24.2 MP.',
          },
          {'id': 'C2', 'satisfied': true, 'explanation': 'Weight is known.'},
        ],
      }, camera(criteria: 'Sensor; Weight'));
      expect(criteria.first.satisfied, isTrue);
      expect(
        criteria.first.quotes.first.quote,
        'The Nikon Z30 has a 20.9 MP APS-C sensor [1].',
        reason: 'the finding it matches is quoted, not the explanation',
      );
      expect(criteria.last.satisfied, isFalse);
    });

    test('criteria are matched by id, then text, then position', () {
      final byText = GoalNotifier.validateCriteria({
        'criteria': [
          {'criterion': 'weight', 'satisfied': false},
          {
            'text': 'Sensor',
            'satisfied': true,
            'facts': ['24.2 MP APS-C sensor [2]'],
          },
        ],
      }, camera(criteria: 'Sensor; Weight'));
      expect(byText.map((c) => c.satisfied), [true, false]);
      final byPosition = GoalNotifier.validateCriteria({
        'criteria': [
          {
            'satisfied': true,
            'facts': ['24.2 MP APS-C sensor [2]'],
          },
          {'satisfied': false},
        ],
      }, camera(criteria: 'Sensor; Weight'));
      expect(byPosition.map((c) => c.satisfied), [true, false]);
      expect(byPosition.map((c) => c.validationError), ['', '']);
    });

    test('only unassessed criteria are errors; none assessed is unchecked', () {
      final partial = GoalNotifier.decisionFromReview({
        'criteria': [
          {
            'id': 'C1',
            'satisfied': true,
            'facts': ['24.2 MP APS-C sensor [2]'],
          },
        ],
      }, camera(criteria: 'Sensor; Weight'));
      expect(partial.unchecked, isFalse);
      expect(partial.criteria.last.validationError, contains('C2'));
      expect(partial.missing, ['Weight']);
      final none = GoalNotifier.decisionFromReview({
        'verdict': 'fine',
      }, camera(criteria: 'Sensor; Weight'));
      expect(none.unchecked, isTrue);
      expect(none.nextSteps, isEmpty);
      expect(none.missing, [GoalDecision.uncheckedNote]);
    });

    test('the reviewer\'s questions are used when it found the gap', () {
      final decision = GoalNotifier.decisionFromReview({
        'criteria': [
          {
            'id': 'C1',
            'satisfied': true,
            'facts': ['24.2 MP APS-C sensor [2]'],
          },
          {'id': 'C2', 'satisfied': false},
        ],
        'next_steps': ['What does the Sony ZV-E10 weigh?'],
      }, camera(criteria: 'Sensor; Weight'));
      expect(decision.nextSteps, ['What does the Sony ZV-E10 weigh?']);
    });
  });

  test(
    'Unlimited unreadable reviews stop retrying and deliver a report',
    () async {
      late GoalRunner runner;
      var written = 0;
      runner = GoalRunner(
        plan: (_) async => const GoalPlan(['What is the camera resolution?']),
        research: (_, _, _) async =>
            const GoalStepResult(answer: 'Resolution [1].'),
        evaluate: (_, _) async =>
            const GoalDecision(satisfied: false, unchecked: true),
        write: (_, _) async {
          written++;
          return 'Available findings, with limitations.';
        },
        checkpoint: (p) async {
          if (p.reviews > 6) runner.stop();
        },
      );
      final result = await runner.run(_unlimited);
      expect(result.status, GoalStatus.partial);
      expect(result.reviews, 2);
      expect(written, 1);
      expect(result.report, isNotEmpty);
    },
  );

  test(
    'Unlimited review stops when new questions do not close any criteria',
    () async {
      late GoalRunner runner;
      var reviews = 0;
      runner = GoalRunner(
        plan: (_) async => const GoalPlan(['What is the camera resolution?']),
        research: (_, _, _) async =>
            const GoalStepResult(answer: 'More findings [1].'),
        evaluate: (_, _) async => GoalDecision(
          satisfied: false,
          missing: const ['Compare the cameras and recommend one'],
          nextSteps: [_gaps[reviews++ % _gaps.length]],
        ),
        write: (_, _) async => 'Report from available findings.',
        checkpoint: (p) async {
          if (p.reviews > 6) runner.stop();
        },
      );
      final result = await runner.run(_unlimited);
      expect(result.status, GoalStatus.partial);
      expect(result.reviews, 2, reason: 'one gap round, then the report');
      expect(result.report, isNotEmpty);
    },
  );

  test(
    'a camera comparison can use separately verified findings from both steps',
    () {
      final p = GoalProgress(
        spec: const GoalSpec(
          objective: 'Nikon Z30 versus Sony ZV-E10',
          successCriteria: 'Compare sensor resolutions and recommend one',
        ),
        status: GoalStatus.running,
        steps: 2,
        startedAt: DateTime(2026),
        tasks: const [
          GoalTask(
            'Nikon resolution?',
            status: GoalTaskStatus.done,
            findings: 'The Nikon Z30 has 20.9 MP [1].',
          ),
          GoalTask(
            'Sony resolution?',
            status: GoalTaskStatus.done,
            findings: 'The Sony ZV-E10 has 24.2 MP [2].',
          ),
        ],
        sources: const [
          GoalSource(
            title: 'Nikon',
            url: 'https://example.com/nikon',
            evidence: 'The Nikon Z30 has 20.9 MP.',
          ),
          GoalSource(
            title: 'Sony',
            url: 'https://example.com/sony',
            evidence: 'The Sony ZV-E10 has 24.2 MP.',
          ),
        ],
      );
      final criterion = GoalNotifier.validateCriteria({
        'criteria': [
          {
            'id': 'C1',
            'satisfied': true,
            'steps': [1, 2],
            'quotes': [
              {'step': 1, 'quote': 'The Nikon Z30 has 20.9 MP [1].'},
              {'step': 2, 'quote': 'The Sony ZV-E10 has 24.2 MP [2].'},
            ],
            'evidence': [
              {'source': 1, 'quote': 'The Nikon Z30 has 20.9 MP.'},
              {'source': 2, 'quote': 'The Sony ZV-E10 has 24.2 MP.'},
            ],
            'explanation':
                'These verified resolutions support the comparison; the writer can explain the tradeoff.',
          },
        ],
      }, p).single;
      expect(criterion.satisfied, isTrue);
      expect(criterion.steps, [1, 2]);
    },
  );
}
