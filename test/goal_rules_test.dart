import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/retrieval/domain/subject_terms.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';
import 'package:ondevice_llm/features/tools/domain/tool_markup.dart';

void main() {
  const cams = SubjectTerms(['nikon z30', 'sony zv-e10']);
  const allowed = 'Compare the nikon z30 to the sony zv-e10.';

  group('rules block', () {
    test('names the subject, the user rules and the date', () {
      final block = GoalRules.block(
        terms: cams.terms,
        userRules: '- Prices in CAD\n2. Only 2026 sources',
        today: '2026-09-24',
        kind: GoalSpecialization.product,
      );
      expect(block, contains('"nikon z30", "sony zv-e10"'));
      expect(block, contains('- Prices in CAD'));
      expect(block, contains('- Only 2026 sources'));
      expect(block, contains('Never ask the user'));
      expect(block, contains('Today is 2026-09-24.'));
      final plan = GoalRules.block(
        terms: cams.terms,
        userRules: '',
        today: '2026-09-24',
        phase: GoalRulePhase.plan,
      );
      expect(plan, contains('do not ask which options exist'));
    });
  });

  group('step checks (phone runs, 2026-09-24)', () {
    test('a step about the ZV-E10 II is off target', () {
      final checks = GoalChecker.step(
        'The Sony ZV-E10 II has a 26 MP sensor and 4K60 [1].',
        subject: cams,
        allowed: allowed,
        evidence: ['Sony ZV-E10 II review: 26 MP, 4K60'],
        sources: 1,
      );
      expect(checks.map((c) => c.kind), [GoalCheckKind.offTarget]);
      expect(checks.first.detail, 'ZV-E10 II');
      expect(checks.first.excludes, isTrue);
    });

    test('a step that also mentions the II is drift and excluded', () {
      final checks = GoalChecker.step(
        'The Sony ZV-E10 shoots 4K30 [1]; the ZV-E10 II adds 4K60 [1].',
        subject: cams,
        allowed: allowed,
        evidence: ['ZV-E10 4K30, ZV-E10 II 4K60'],
        sources: 1,
      );
      expect(checks.map((c) => c.kind), [GoalCheckKind.drift]);
      expect(checks.first.excludes, isTrue);
    });

    test('no citations, figures in no source, asking the user', () {
      final checks = GoalChecker.step(
        'The Nikon Z30 has an ISO up to 512000. Please provide additional sources.',
        subject: cams,
        allowed: allowed,
        evidence: ['Nikon Z30: ISO 100-51200'],
        sources: 1,
      );
      expect(checks.map((c) => c.kind).toSet(), {
        GoalCheckKind.noCitations,
        GoalCheckKind.figures,
        GoalCheckKind.askedUser,
      });
    });

    test('clean drops meta talk, requests and leftover tool calls', () {
      final text = GoalChecker.clean(
        'The Z30 records 4K30 [1].\n'
        'Note on sources: The sources are untrusted text. They were retrieved on 2026-09-24.\n'
        'If you have specific questions, please provide additional sources.\n'
        '<function name="search_web"><param name="query">z30</param></function>',
      );
      expect(text, 'The Z30 records 4K30 [1].');
    });
  });

  group('reasoning leaks (Qwen3.5 0.8B on the phone)', () {
    test('thinking aloud and prompt echoes are removed, the answer kept', () {
      const raw =
          '*Wait, I need to check if the sources actually contain the comparison data.*\n'
          'Source [7] title: "The 6 Best Cameras". It does not list scores.\n'
          '\n'
          '**Question:** Which specs distinguish the Nikon Z30 from the Sony ZV-E10?\n'
          '**Answer:** The Nikon Z30 has 209 AF points [1].\n'
          '[2] Nikon Z30 vs Sony ZV-E10 | Camera Fight — https://camerafight.com/x (read 2026-09-25T01:32:54Z; published 2025-11-22)\n'
          'The Sony ZV-E10 has 425 AF points [2].';
      expect(GoalChecker.leaked(raw), isTrue);
      expect(
        GoalChecker.clean(raw),
        'The Nikon Z30 has 209 AF points [1].\nThe Sony ZV-E10 has 425 AF points [2].',
      );
    });

    test('a report that is only a checklist cleans to almost nothing', () {
      const raw =
          'I need to extract specific information from the provided research findings.\n'
          '\n'
          '**Constraint Checklist & Confidence Score:**\n'
          '1. Match length? Yes.\n'
          '2. No filler.';
      expect(GoalChecker.leaked(raw), isTrue);
      expect(GoalChecker.clean(raw).length, lessThan(40));
    });

    test('a normal answer is not touched', () {
      const answer =
          '## Video\n\nThe Nikon Z30 records 4K30 [1]. The ZV-E10 does too [2].';
      expect(GoalChecker.leaked(answer), isFalse);
      expect(GoalChecker.clean(answer), answer);
    });
  });

  group('report checks', () {
    test('bogus citations and a report with none', () {
      expect(
        GoalChecker.report(
          'The Nikon Z30 costs 710 USD [9].',
          subject: cams,
          allowed: allowed,
          findings: 'Nikon Z30 price 710 USD [1]',
          sources: 3,
        ).map((c) => c.kind),
        [GoalCheckKind.badCitations],
      );
      expect(
        GoalChecker.report(
          'Both cameras are great.',
          subject: cams,
          allowed: allowed,
          findings: 'x',
          sources: 3,
        ).map((c) => c.kind),
        [GoalCheckKind.noCitations],
      );
    });

    test('what to fix is written for the model', () {
      final fixes = GoalChecker.fixes([
        const GoalCheck(GoalCheckKind.drift, 'ZV-E10 II'),
        const GoalCheck(GoalCheckKind.figures, '512000'),
      ], cams);
      expect(fixes, contains('ZV-E10 II'));
      expect(fixes, contains('512000'));
    });
  });

  group('goal pieces', () {
    test('a step researched about another model is NOT ESTABLISHED', () {
      final p = GoalProgress(
        spec: const GoalSpec(objective: allowed, successCriteria: ''),
        status: GoalStatus.running,
        steps: 1,
        startedAt: DateTime(2026, 9, 24),
        tasks: const [
          GoalTask(
            'Battery life of the Sony ZV-E10?',
            status: GoalTaskStatus.done,
            findings: 'The ZV-E10 II lasts 610 shots [1].',
            checks: [GoalCheck(GoalCheckKind.offTarget, 'ZV-E10 II')],
          ),
        ],
      );
      final ledger = GoalNotifier.ledger(p, perStep: 900);
      expect(ledger, contains('NOT ESTABLISHED'));
      expect(ledger, isNot(contains('610 shots')));
    });

    test('a thinking reply: reasoning and JSON are split', () {
      final (notes, reply) = GoalNotifier.splitThinking(
        '<think>Two cameras, ask per criterion.</think>\n```json\n{"steps": ["a"]}\n```',
      );
      expect(notes, 'Two cameras, ask per criterion.');
      expect(GoalNotifier.parseJsonObject(reply), {
        'steps': ['a'],
      });
      expect(GoalNotifier.splitThinking('<think>cut off').$2, isEmpty);
    });

    test('the subject lock and rules survive the saved form', () {
      final p = GoalProgress(
        spec: const GoalSpec(
          objective: allowed,
          successCriteria: '',
          terms: ['nikon z30', 'sony zv-e10'],
          rules: 'Prices in CAD',
        ),
        status: GoalStatus.completed,
        steps: 1,
        startedAt: DateTime(2026, 9, 24),
        reportChecks: const [GoalCheck(GoalCheckKind.revised)],
        planNotes: 'plan',
        tasks: const [
          GoalTask(
            'q',
            status: GoalTaskStatus.done,
            trace: GoalTrace(queries: ['nikon z30 battery'], sources: [1]),
            checks: [GoalCheck(GoalCheckKind.retried)],
          ),
        ],
      );
      final back = GoalNotifier.decode(GoalNotifier.encode(p));
      expect(back.spec.terms, ['nikon z30', 'sony zv-e10']);
      expect(back.spec.rules, 'Prices in CAD');
      expect(back.reportChecks.single.kind, GoalCheckKind.revised);
      expect(back.planNotes, 'plan');
      expect(back.tasks.single.trace!.queries, ['nikon z30 battery']);
      expect(back.tasks.single.checks.single.kind, GoalCheckKind.retried);
    });
  });

  group('XML-style tool calls', () {
    test('function/param tags parse and are stripped', () {
      const text =
          '<function name="search_news"><param name="query">independent reviews nikon Z30</param></function> '
          '<function name="search_web"><param name="query">Sony ZV-E10 review</param></function>';
      final calls = TextToolProtocol.parse(text, counter: 1);
      expect(calls.map((c) => c.name), ['search_news', 'search_web']);
      expect(calls.first.arguments, contains('independent reviews nikon Z30'));
      expect(ToolMarkup.strip(text), isEmpty);
      expect(TextToolProtocol.strip(text), isEmpty);
    });

    test('Qwen3-Coder parameter tags parse', () {
      final calls = TextToolProtocol.parse(
        '<function=search_web>\n<parameter=query>\nqwen3.5 speed\n</parameter>\n</function>',
        counter: 1,
      );
      expect(calls.single.name, 'search_web');
      expect(calls.single.arguments, contains('qwen3.5 speed'));
    });
  });
}
