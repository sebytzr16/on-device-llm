import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_deliverables.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_markup.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';

// Audit 2026-10-08 G1, G3, G4, G5.
const _nikon =
    'Find the official weight of the Nikon Z30, and prepare a text file '
    'with the answer.';

void main() {
  group('what a goal asks to have made', () {
    test('a text file', () {
      expect(GoalDeliverables.of(_nikon), [
        const GoalDeliverable(GoalDeliverableKind.file, format: 'txt'),
      ]);
    });

    test('formats and languages', () {
      GoalDeliverable? file(String o) => GoalDeliverables.of(
        o,
      ).where((d) => d.kind == GoalDeliverableKind.file).firstOrNull;
      expect(
        file('Compare three laptops and export it as a CSV')?.format,
        'csv',
      );
      expect(
        file('Compare three laptops and make a spreadsheet of them')?.format,
        'csv',
      );
      expect(file('Résume la loi et crée un fichier avec')?.format, 'md');
      expect(file('Busca el precio y guarda un archivo JSON')?.format, 'json');
    });

    test('a goal about files or calendars asks for none', () {
      expect(GoalDeliverables.of('What is the best calendar app?'), isEmpty);
      expect(
        GoalDeliverables.of('Why is the PDF file format so popular?'),
        isEmpty,
      );
    });

    test('a calendar event next to a file', () {
      final d = GoalDeliverables.of(
        'Find the next Lyon concert, add it to my calendar and save a file '
        'with the details',
      );
      expect(d.map((x) => x.kind), [
        GoalDeliverableKind.file,
        GoalDeliverableKind.event,
      ]);
    });

    test('the research part leaves the file request out', () {
      expect(
        GoalDeliverables.researchPart(_nikon),
        'Find the official weight of the Nikon Z30.',
      );
      expect(
        GoalDeliverables.isDeliverableQuestion(
          'Prepare a text file with the Nikon Z30 weight',
        ),
        isTrue,
      );
      expect(
        GoalDeliverables.isDeliverableQuestion(
          'What does the Nikon Z30 weigh?',
        ),
        isFalse,
      );
    });
  });

  group('the file is the whole report', () {
    final sources = [
      GoalSource(
        title: 'Nikon Z30 specifications',
        url: 'https://www.nikon.com/z30',
        retrievedAt: DateTime(2026, 10, 8),
      ),
    ];

    test('nothing at its end is lost, sources and read dates kept', () {
      final report =
          '# Nikon Z30\n\nThe Z30 weighs **405 g** with *battery* [1].\n\n'
          '${'More detail. ' * 400}\n\nLast line kept.';
      final a = GoalDeliverables.reportFile(
        _nikon,
        report,
        sources,
        format: 'txt',
      )!;
      expect(a.kind, 'save_file');
      final content = a.args['content'] as String;
      expect(content, contains('Last line kept.'));
      // Seen on the phone: emphasis became "$1".
      expect(content, contains('The Z30 weighs 405 g with battery [1].'));
      expect(content, isNot(contains(r'$1')));
      expect(content, isNot(contains('# ')));
      expect(
        content,
        contains(
          '[1] Nikon Z30 specifications — https://www.nikon.com/z30 '
          '(read 2026-10-08)',
        ),
      );
      expect(a.args['format'], 'txt');
      expect(a.args['name'], 'official weight of the Nikon Z30');
    });

    test('the file name is the subject, not the request', () {
      expect(
        GoalDeliverables.fileName(
          'Find the official Nikon Z30 body weight including battery and '
          'memory card. Cite Nikon as the source. Save it as a text file.',
        ),
        'official Nikon Z30 body weight',
      );
      expect(
        GoalDeliverables.fileName('Busca el precio de la Switch 2 en Espana'),
        'precio de la Switch 2',
      );
      expect(
        GoalDeliverables.fileName('Save it as a file'),
        'Save it as a file',
      );
    });

    test('a CSV is the report table', () {
      const report =
          'Intro.\n\n| Car | Range |\n|---|---|\n| **Model 3** | 500 km |\n'
          '| Ioniq 6, LR | 580 km |\n\nAfter.';
      final a = GoalDeliverables.reportFile(
        'Compare cars and export as CSV',
        report,
        const [],
        format: 'csv',
      )!;
      expect(
        a.args['content'],
        'Car,Range\nModel 3,500 km\n"Ioniq 6, LR",580 km',
      );
    });

    test('a report without a table is saved as Markdown', () {
      final a = GoalDeliverables.reportFile(
        'Export as CSV',
        'No table here.',
        const [],
        format: 'csv',
      )!;
      expect(a.args['format'], 'md');
    });
  });

  test('missing deliverables round-trip with their reason', () {
    const wanted = [
      GoalDeliverable(GoalDeliverableKind.file, format: 'txt'),
      GoalDeliverable(GoalDeliverableKind.event),
    ];
    final lines = GoalDeliverables.missing(
      wanted,
      const [
        PhoneAction('save_file', {'name': 'x', 'content': 'y'}),
      ],
      reasons: {'create_event': 'invalid: no start'},
    );
    expect(lines, hasLength(1));
    final (d, reason) = GoalDeliverables.parseMissing(lines.single)!;
    expect(d.kind, GoalDeliverableKind.event);
    expect(reason, 'invalid: no start');
    expect(GoalDeliverables.parseMissing('Price for C2'), isNull);
  });

  group('the quick path', () {
    test('a one-fact goal is quick; a comparison is not', () {
      expect(
        const GoalSpec(objective: _nikon, successCriteria: '').quick,
        isTrue,
      );
      expect(
        const GoalSpec(
          objective: 'Compare the Nikon Z30 and the Sony ZV-E10',
          successCriteria: '',
        ).quick,
        isFalse,
      );
      expect(
        const GoalSpec(
          objective: 'Find the Nikon Z30 weight',
          successCriteria: 'Weight\nPrice\nBattery life',
        ).quick,
        isFalse,
      );
    });

    test('it runs one step without the planner, then delivers', () async {
      var planned = 0;
      final asked = <String>[];
      final runner = GoalRunner(
        plan: (_) async {
          planned++;
          return const GoalPlan(['unused']);
        },
        research: (_, task, _) async {
          asked.add(task.question);
          return const GoalStepResult(
            answer: 'The Z30 weighs 405 g [1].',
            sources: [GoalSource(title: 'Nikon', url: 'https://nikon.com')],
            tokens: 100,
          );
        },
        evaluate: (_, _) async => const GoalDecision(satisfied: true),
        write: (_, _) async => 'The Nikon Z30 weighs 405 g [1].',
        deliver: (spec, p) async {
          final file = GoalDeliverables.reportFile(
            spec.objective,
            p.report,
            p.sources,
            format: 'txt',
          )!;
          return GoalDelivery(actions: [file]);
        },
        checkpoint: (_) async {},
        overheadUsage: () => const GoalUsage(tokens: 50),
      );
      final result = await runner.run(
        const GoalSpec(objective: _nikon, successCriteria: ''),
      );
      expect(planned, 0);
      expect(asked, ['Find the official weight of the Nikon Z30.']);
      expect(result.status, GoalStatus.completed);
      expect(result.actions.single.kind, 'save_file');
      expect(result.actions.single.args['content'], contains('405 g'));
      // The delivery's tokens are the goal's.
      expect(result.usedTokens, greaterThanOrEqualTo(150));
    });

    test('a deliverable left out makes the goal partial', () async {
      final runner = GoalRunner(
        plan: (_) async => const GoalPlan(['unused']),
        research: (_, _, _) async => const GoalStepResult(
          answer: 'Found [1].',
          sources: [GoalSource(title: 'A', url: 'https://a.example')],
          tokens: 10,
        ),
        evaluate: (_, _) async => const GoalDecision(satisfied: true),
        write: (_, _) async => 'Report [1].',
        deliver: (spec, _) async => GoalDelivery(
          missing: GoalDeliverables.missing(spec.deliverables, const []),
        ),
        checkpoint: (_) async {},
      );
      final result = await runner.run(
        const GoalSpec(objective: _nikon, successCriteria: ''),
      );
      expect(result.status, GoalStatus.partial);
      expect(result.missing.single, startsWith('deliverable:file:txt:'));
    });
  });

  test('the review is told which source each citation is', () {
    final p = GoalProgress(
      spec: const GoalSpec(objective: 'Nikon Z30 weight', successCriteria: ''),
      status: GoalStatus.running,
      steps: 1,
      startedAt: DateTime(2026, 10, 9),
      tasks: const [
        GoalTask(
          'Nikon Z30 weight',
          status: GoalTaskStatus.done,
          findings: 'Approx. 405 g with battery and card [3].',
        ),
      ],
      sources: const [
        GoalSource(title: 'A', url: 'https://cameradecision.com/a'),
        GoalSource(title: 'B', url: 'https://cameradecision.com/b'),
        GoalSource(
          title: 'Z 30 | Nikon',
          url: 'https://www.imaging.nikon.com/z_30/',
        ),
      ],
    );
    expect(GoalNotifier.cited(p), '[3] Z 30 | Nikon — imaging.nikon.com');
  });

  test('stray closing tags are not an answer', () {
    expect(ToolMarkup.stripOrphans('</think>\n\n</tool_call>'), '');
    expect(ToolMarkup.strip('Timer set.</tool_call>'), 'Timer set.');
  });
}
