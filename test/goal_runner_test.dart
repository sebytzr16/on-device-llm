import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';

const _spec = GoalSpec(
  objective: 'Compare the three most popular electric cars in Canada',
  successCriteria: 'Price, range and charging time for each car, with sources',
);

GoalStepResult _answer(String text, List<String> urls, {int tokens = 100}) =>
    GoalStepResult(
      answer: text,
      sources: [for (final u in urls) GoalSource(title: u, url: u)],
      tokens: tokens,
    );

GoalRunner _runner({
  List<String> plan = const [
    'Which EVs sell most in Canada?',
    'What do they cost?',
  ],
  Future<GoalStepResult> Function(GoalTask task)? research,
  GoalDecision decision = const GoalDecision(satisfied: true),
  List<GoalProgress>? checkpoints,
  GoalUsage overhead = const GoalUsage(),
}) {
  var reviews = 0;
  return GoalRunner(
    plan: (_) async => GoalPlan(plan),
    research: (_, task, _) async =>
        research?.call(task) ?? _answer('Found [1].', ['https://a.example']),
    evaluate: (_, _) async {
      reviews++;
      return reviews == 1 ? decision : const GoalDecision(satisfied: true);
    },
    write: (_, p) async => 'Report from ${p.done} steps.',
    checkpoint: (p) async => checkpoints?.add(p),
    overheadUsage: () => overhead,
  );
}

void main() {
  test(
    'plans, researches each step, reviews, then writes the report',
    () async {
      final checkpoints = <GoalProgress>[];
      final asked = <String>[];
      final runner = _runner(
        checkpoints: checkpoints,
        research: (task) async {
          asked.add(task.question);
          return asked.length == 1
              ? _answer('Tesla leads [1]; Hyundai second [2].', [
                  'https://a.example',
                  'https://b.example',
                ])
              : _answer('Prices vary [1] and [2].', [
                  'https://b.example',
                  'https://c.example',
                ]);
        },
      );
      final result = await runner.run(_spec);
      expect(result.status, GoalStatus.completed);
      expect(result.phase, GoalPhase.done);
      expect(asked, [
        'Which EVs sell most in Canada?',
        // "they" with nothing of the goal in it gets the goal as subject.
        'What do they cost? (${_spec.objective})',
      ]);
      expect(result.steps, 2);
      expect(result.report, 'Report from 2 steps.');
      // Citations move into one global list: b.example keeps number 2.
      expect(result.sources.map((s) => s.url), [
        'https://a.example',
        'https://b.example',
        'https://c.example',
      ]);
      expect(result.tasks[1].findings, 'Prices vary [2] and [3].');
      expect(checkpoints.any((p) => p.phase == GoalPhase.planning), isTrue);
      expect(checkpoints.any((p) => p.phase == GoalPhase.checking), isTrue);
      expect(checkpoints.any((p) => p.phase == GoalPhase.writing), isTrue);
      expect(result.usedTokens, 200);
    },
  );

  test('a review adds at most two new questions, once each', () async {
    final asked = <String>[];
    final runner = _runner(
      plan: const ['Which EVs sell most in Canada?'],
      research: (task) async {
        asked.add(task.question);
        return _answer('Answer [1].', ['https://${asked.length}.example']);
      },
      decision: const GoalDecision(
        satisfied: false,
        missing: ['charging times'],
        nextSteps: [
          'What is the charging time of the Tesla Model Y?',
          'Which EVs sell most in Canada?',
          'What is the range of the Hyundai Ioniq 5?',
          'What is the price of the Chevrolet Equinox EV?',
        ],
      ),
    );
    final result = await runner.run(_spec);
    expect(result.status, GoalStatus.completed);
    expect(asked, [
      'Which EVs sell most in Canada?',
      'What is the charging time of the Tesla Model Y?',
      'What is the range of the Hyundai Ioniq 5?',
    ]);
    expect(result.reviews, 2);
    expect(result.missing, isEmpty, reason: 'the second review was satisfied');
  });

  test('the step budget pauses; continuing resumes where it stopped', () async {
    final asked = <String>[];
    Future<GoalStepResult> research(GoalTask task) async {
      asked.add(task.question);
      return _answer('Answer [1].', ['https://x.example']);
    }

    final runner = _runner(
      plan: const [
        'Q one about cars?',
        'Q two about cars?',
        'Q three about cars?',
      ],
      research: research,
    );
    final paused = await runner.run(
      const GoalSpec(
        objective: 'Research',
        successCriteria: 'Done',
        maxSteps: 2,
      ),
    );
    expect(paused.status, GoalStatus.paused);
    expect(paused.steps, 2);
    expect(asked, hasLength(2));
    // Out of budget with a question left: an interim report, not nothing.
    expect(paused.report, 'Report from 2 steps.');
    final resumed = await runner.run(
      paused.spec,
      resume: paused.copyWith(status: GoalStatus.paused),
    );
    // The same limit is still reached: nothing more runs until extended.
    expect(resumed.status, GoalStatus.paused);
    expect(asked, hasLength(2));
    final extended = await runner.run(
      const GoalSpec(
        objective: 'Research',
        successCriteria: 'Done',
        maxSteps: 5,
      ),
      resume: paused,
    );
    expect(extended.status, GoalStatus.completed);
    expect(asked, [
      'Q one about cars?',
      'Q two about cars?',
      'Q three about cars?',
    ]);
  });

  test('unlimited mode runs until stopped', () async {
    late GoalRunner runner;
    runner = GoalRunner(
      plan: (_) async => const GoalPlan([
        'Endless question number one?',
        'Endless question two?',
      ]),
      research: (_, _, _) async {
        runner.stop();
        return _answer('partial', const []);
      },
      evaluate: (_, _) async => const GoalDecision(satisfied: false),
      write: (_, _) async => 'never',
      checkpoint: (_) async {},
    );
    final result = await runner.run(
      const GoalSpec(
        objective: 'Keep researching',
        successCriteria: 'Complete',
        maxSteps: null,
        maxDuration: null,
        maxTokens: null,
        maxToolCalls: null,
      ),
    );
    expect(result.status, GoalStatus.stopped);
    expect(result.steps, 1);
    expect(result.report, isEmpty);
  });

  test('token and tool budgets stop after a measured step', () async {
    var calls = 0;
    final runner = GoalRunner(
      plan: (_) async =>
          const GoalPlan(['First question here?', 'Second question here?']),
      research: (_, _, _) async {
        calls++;
        return const GoalStepResult(
          answer: 'still working',
          tokens: 120,
          toolCalls: 2,
        );
      },
      evaluate: (_, _) async => const GoalDecision(satisfied: false),
      write: (_, _) async => 'report',
      checkpoint: (_) async {},
    );
    final result = await runner.run(
      const GoalSpec(
        objective: 'Research',
        successCriteria: 'Complete',
        maxSteps: 10,
        maxTokens: 100,
        maxToolCalls: 2,
      ),
    );
    expect(result.status, GoalStatus.paused);
    expect(result.steps, 1);
    expect(result.usedTokens, 120);
    expect(result.usedToolCalls, 2);
    expect(calls, 1);
  });

  test('a failed step is recorded and the goal goes on', () async {
    var n = 0;
    final runner = _runner(
      research: (task) async {
        if (++n == 1) throw StateError('site down');
        return _answer('Fine [1].', ['https://ok.example']);
      },
    );
    final result = await runner.run(_spec);
    expect(result.status, GoalStatus.partial);
    expect(result.tasks.first.status, GoalTaskStatus.failed);
    expect(result.tasks.first.error, contains('site down'));
    expect(result.tasks.last.status, GoalTaskStatus.done);
  });

  test('stop requested during the review wins over completion', () async {
    late GoalRunner runner;
    runner = GoalRunner(
      plan: (_) async => const GoalPlan(['Only question here?']),
      research: (_, _, _) async => _answer('answer', const []),
      evaluate: (_, _) async {
        runner.stop();
        return const GoalDecision(satisfied: true);
      },
      write: (_, _) async => 'report',
      checkpoint: (_) async {},
    );
    final result = await runner.run(
      const GoalSpec(objective: 'A goal', successCriteria: 'B'),
    );
    expect(result.status, GoalStatus.stopped);
    expect(result.steps, 1);
  });

  test('an empty plan falls back to the objective itself', () async {
    final asked = <String>[];
    final runner = _runner(
      plan: const ['', '1.'],
      research: (task) async {
        asked.add(task.question);
        return _answer('ok', const []);
      },
    );
    await runner.run(_spec);
    expect(asked, [_spec.objective]);
  });

  test('questions about the research itself are not researched', () async {
    final asked = <String>[];
    final runner = _runner(
      plan: const ['What is the range of the Tesla Model Y?'],
      research: (task) async {
        asked.add(task.question);
        return _answer('ok [1]', ['https://a.example']);
      },
      decision: const GoalDecision(
        satisfied: false,
        nextSteps: [
          'Confirm that all claims regarding specifications have explicit citations.',
          'Identify the pricing details provided in Step 1 and verify they are backed by official sources.',
        ],
      ),
    );
    await runner.run(_spec);
    expect(asked, ['What is the range of the Tesla Model Y?']);
  });

  test('reworded repeats are dropped, different questions kept', () async {
    final asked = <String>[];
    final runner = _runner(
      plan: const [
        'What is the price of the Tesla Model Y in Canada?',
        'What are the prices of the Tesla Model Y in Canada?',
        'What is the range of the Tesla Model Y?',
        'Tesla Model Y range?',
      ],
      research: (task) async {
        asked.add(task.question);
        return _answer('ok [1]', ['https://a.example']);
      },
      decision: const GoalDecision(
        satisfied: false,
        nextSteps: [
          'Price of the Tesla Model Y in Canada',
          'How long does the Tesla Model Y take to charge?',
        ],
      ),
    );
    await runner.run(_spec);
    expect(asked, [
      'What is the price of the Tesla Model Y in Canada?',
      'What is the range of the Tesla Model Y?',
      'How long does the Tesla Model Y take to charge?',
    ]);
  });

  test('questions that name the subject are not anchored', () {
    expect(
      GoalRunner.anchored('Which electric cars sell most in Canada?', _spec),
      'Which electric cars sell most in Canada?',
    );
    expect(
      GoalRunner.anchored('How long does the Tesla Model Y charge?', _spec),
      'How long does the Tesla Model Y charge?',
    );
    expect(
      GoalRunner.anchored(
        'Which of these electric cars charges fastest?',
        _spec,
      ),
      'Which of these electric cars charges fastest?',
      reason: 'it repeats the goal\'s own words',
    );
    expect(
      GoalRunner.anchored('How much does it cost in Canada?', _spec),
      'How much does it cost in Canada? (${_spec.objective})',
      reason: 'one shared word does not name the subject when "it" leans',
    );
  });

  test(
    'an unreadable review is asked again, never taken as satisfied',
    () async {
      var reviews = 0;
      final unreadable = GoalRunner(
        plan: (_) async => const GoalPlan(['Which EVs sell most in Canada?']),
        research: (_, _, _) async => _answer('ok [1]', ['https://a.example']),
        evaluate: (_, _) async {
          reviews++;
          return const GoalDecision(satisfied: false, unchecked: true);
        },
        write: (_, p) async => 'Report.',
        checkpoint: (_) async {},
      );
      final result = await unreadable.run(_spec);
      expect(reviews, GoalRunner.maxReviewAttempts);
      expect(result.status, GoalStatus.partial);
      expect(result.missing, [GoalDecision.uncheckedNote]);
    },
  );

  test('citations are renumbered into the global list', () {
    final (text, all) = GoalRunner.renumber(
      'A [1]. B [2, 3]. C [9].',
      const [
        GoalSource(title: 'x', url: 'https://x'),
        GoalSource(title: 'y', url: 'https://y'),
        GoalSource(title: 'z', url: 'https://z'),
      ],
      const [GoalSource(title: 'y', url: 'https://y')],
    );
    expect(all.map((s) => s.url), ['https://y', 'https://x', 'https://z']);
    expect(text, 'A [2]. B [1, 3]. C .');
  });
}
