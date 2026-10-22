import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence_audit.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';
import 'package:ondevice_llm/inference/engine/turn_budget.dart';
import 'package:ondevice_llm/features/chat/domain/answer_shape.dart';

void main() {
  test('explicit sentence limits override default answer structure', () {
    for (final question in [
      'Summarize the article in three sentences.',
      'Résume en trois phrases.',
      'Resume en tres oraciones.',
    ]) {
      final instruction = AnswerShapes.instructions(
        AnswerShape.explanation,
        question: question,
        sources: 2,
      );
      expect(instruction, contains('single paragraph'));
      expect(instruction, isNot(contains('two-sentence summary first')));
      expect(instruction, contains('only the numbered sources'));
    }
  });

  test('repeated continuation preserves the original resource allowance', () {
    var p = GoalProgress(
      spec: const GoalSpec(
        objective: 'Camera',
        successCriteria: 'Price',
        maxSteps: 2,
        maxTokens: 500,
        maxToolCalls: 3,
        maxDuration: Duration(minutes: 5),
      ),
      status: GoalStatus.paused,
      steps: 2,
      usedTokens: 500,
      usedToolCalls: 3,
      startedAt: DateTime(2026),
    );
    final first = GoalNotifier.continuationSpec(p, DateTime(2026, 1, 1, 0, 6));
    p = GoalNotifier.decode(
      GoalNotifier.encode(
        p.copyWith(spec: first, steps: 4, usedTokens: 1000, usedToolCalls: 6),
      ),
    );
    final second = GoalNotifier.continuationSpec(
      p,
      DateTime(2026, 1, 1, 0, 15),
    );
    expect(second.maxSteps, 6);
    expect(second.maxTokens, 1500);
    expect(second.maxToolCalls, 9);
    expect(second.maxDuration, const Duration(minutes: 20));
  });

  test('the same page read again stays one source with both excerpts', () {
    const first = GoalSource(
      title: 'Price',
      url: 'https://example.com',
      evidence: 'Price is 710 USD.',
    );
    const second = GoalSource(
      title: 'Price',
      url: 'https://www.example.com/?utm_source=feed',
      evidence: 'Price is 999 USD.\nPrice is 710 USD.',
    );
    final merged = GoalRunner.renumber(
      'Updated price 999 USD [1].',
      [second],
      [first],
    );
    expect(merged.$1, 'Updated price 999 USD [1].');
    expect(merged.$2, hasLength(1));
    final evidence = GoalSource.fromJson(merged.$2.single.toJson()).evidence;
    expect(evidence, startsWith('Price is 710 USD.'));
    expect(evidence, contains('Price is 999 USD.'));
    expect(
      'Price is 710 USD.'.allMatches(evidence),
      hasLength(1),
      reason: 'a passage already kept is not added twice',
    );
    expect(
      GoalRunner.renumber('Other page [1].', [
        const GoalSource(
          title: 'Other',
          url: 'https://example.com/other',
          evidence: 'Other.',
        ),
      ], merged.$2).$1,
      'Other page [2].',
    );
  });
  test('a figure in a different source cannot validate the cited claim', () {
    final audit = EvidenceAudit.check('The Z30 costs 999 USD [1].', [
      'Z30 costs 710 USD',
      'ZV-E10 costs 999 USD',
    ]);
    expect(audit.unsupportedFigures, ['999']);
    expect(
      EvidenceAudit.check('The Z30 costs 710 USD [1].', [
        'Z30 costs 710 USD',
      ]).passes,
      isTrue,
    );
  });
  test('numeric substrings and different software patches do not pass', () {
    expect(
      EvidenceAudit.check('ISO 512000 [1].', ['ISO 51200']).passes,
      isFalse,
    );
    expect(
      EvidenceAudit.check('Version 3.47.9 [1].', ['Version 3.47.4']).passes,
      isFalse,
    );
  });
  test('invalid citations and grouped valid citations are distinguished', () {
    expect(EvidenceAudit.check('Claim [0, 4].', ['one']).invalidCitations, [
      0,
      4,
    ]);
    expect(
      EvidenceAudit.check('Costs 710 USD [1, 2].', [
        '710 USD',
        'Review',
      ]).passes,
      isTrue,
    );
  });
  test('resource allowance includes every prompt and tool call', () {
    final budget = TurnBudget(maxTokens: 100, maxToolCalls: 1);
    expect(budget.outputAllowance(60, 80), 40);
    budget.charge(60, 30);
    expect(
      () => budget.outputAllowance(11, 50),
      throwsA(isA<TurnLimitException>()),
    );
    budget.useTool();
    expect(budget.useTool, throwsA(isA<TurnLimitException>()));
  });
  test('criterion claims require a quote from an eligible step', () {
    final p = GoalProgress(
      spec: const GoalSpec(
        objective: 'Cameras',
        successCriteria: 'Price\nBattery life',
      ),
      status: GoalStatus.running,
      steps: 1,
      startedAt: DateTime(2026),
      tasks: const [
        GoalTask(
          'Price?',
          status: GoalTaskStatus.done,
          findings: 'The price is 710 USD [1].',
        ),
      ],
      sources: const [
        GoalSource(
          title: 'Camera price',
          url: 'https://example.com/price',
          evidence: 'The price is 710 USD.',
        ),
      ],
    );
    final criteria = GoalNotifier.validateCriteria({
      'criteria': [
        {
          'id': 'C1',
          'satisfied': true,
          'steps': [1],
          'quote': 'The price is 710 USD [1].',
          'evidence': [
            {'source': 1, 'quote': 'The price is 710 USD.'},
          ],
        },
        {
          'id': 'C2',
          'satisfied': true,
          'steps': [1],
          'quote': 'Battery lasts all day.',
        },
      ],
    }, p);
    expect(criteria.map((c) => c.satisfied), [true, false]);
    final single = p.copyWith(
      spec: const GoalSpec(objective: 'Cameras', successCriteria: 'Price'),
    );
    const base = {
      'id': 'C1',
      'satisfied': true,
      'steps': [1],
      'quote': 'The price is 710 USD [1].',
    };
    // Tolerated: stray step numbers and the reviewer's own evidence are
    // ignored; the passages come from the cited source.
    for (final extra in [
      {
        'steps': [1, 999],
      },
      {
        'steps': [1, '1'],
      },
      {
        'evidence': [
          {'source': 2, 'quote': 'The price is 999 USD.'},
        ],
      },
    ]) {
      final c = GoalNotifier.validateCriteria({
        'criteria': [
          {...base, ...extra},
        ],
      }, single).single;
      expect(c.satisfied, isTrue, reason: '$extra');
      expect(c.steps, [1]);
      expect(c.evidence.map((e) => (e.source, e.quote)), [
        (1, 'The price is 710 USD.'),
      ]);
    }
    // Refused: a figure the findings do not state, a claim the review calls
    // unmet, and a step that established nothing.
    for (final invalid in [
      {'quote': 'The price is 999 USD [1].'},
      {'quote': 'The price is 710 EUR and 1,299 USD [1].'},
      {'satisfied': false},
    ]) {
      expect(
        GoalNotifier.validateCriteria({
          'criteria': [
            {...base, ...invalid},
          ],
        }, single).single.satisfied,
        isFalse,
        reason: '$invalid',
      );
    }
    final failed = single.copyWith(
      tasks: const [
        GoalTask(
          'Price?',
          status: GoalTaskStatus.failed,
          error: 'timeout',
          findings: 'The price is 710 USD [1].',
        ),
      ],
    );
    expect(
      GoalNotifier.validateCriteria({
        'criteria': [base],
      }, failed).single.satisfied,
      isFalse,
    );
    expect(
      GoalNotifier.validateCriteria({
        'satisfied': true,
      }, p).every((c) => !c.satisfied),
      isTrue,
    );
  });
  test(
    'report check failures and unsatisfied reviews remain partial',
    () async {
      final runner = GoalRunner(
        plan: (_) async => const GoalPlan(['Research the camera price?']),
        research: (_, _, _) async =>
            const GoalStepResult(answer: '710 USD [1]'),
        evaluate: (_, _) async =>
            const GoalDecision(satisfied: false, missing: ['battery']),
        write: (_, _) async => 'A partial report.',
        checkpoint: (_) async {},
      );
      final result = await runner.run(
        const GoalSpec(
          objective: 'Camera',
          successCriteria: 'Price and battery',
        ),
      );
      expect(result.status, GoalStatus.partial);
      expect(result.missing, ['battery']);
    },
  );
  test('stop while writing wins over completion', () async {
    late GoalRunner runner;
    runner = GoalRunner(
      plan: (_) async => const GoalPlan(['Research the camera price?']),
      research: (_, _, _) async => const GoalStepResult(answer: '710 USD [1]'),
      evaluate: (_, _) async => const GoalDecision(satisfied: true),
      write: (_, _) async {
        runner.stop();
        return 'Interrupted report.';
      },
      checkpoint: (_) async {},
    );
    expect(
      (await runner.run(
        const GoalSpec(objective: 'Camera', successCriteria: 'Price'),
      )).status,
      GoalStatus.stopped,
    );
  });
  test('drafts survive reopening and remain isolated across chats', () async {
    final dir = await Directory.systemTemp.createTemp('odllm-drafts-');
    addTearDown(() => dir.delete(recursive: true));
    final store = ChatDraftStore(root: () async => dir);
    await store.save('one', const ChatDraft(text: 'First unsent question'));
    await store.save('two', const ChatDraft(text: 'Second unsent question'));
    final reopened = ChatDraftStore(root: () async => dir);
    expect((await reopened.read('one')).text, 'First unsent question');
    expect((await reopened.read('two')).text, 'Second unsent question');
    await store.save('one', const ChatDraft());
    expect((await reopened.read('one')).isEmpty, isTrue);
    expect((await reopened.read('two')).isEmpty, isFalse);
  });
}
