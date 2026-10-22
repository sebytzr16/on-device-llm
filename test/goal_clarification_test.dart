import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_clarification_dialog.dart';

const _question = GoalClarification(
  id: 'Q1',
  question: 'What will you use the camera for?',
  options: ['Cooking videos', 'Travel photos', 'Both'],
);

void main() {
  test('specific factual research skips unrelated preference questions', () {
    expect(
      GoalClarification.preferencesMayMatter(
        'Compare Nikon Z30 and original Sony ZV-E10 effective sensor resolution',
        'State each effective megapixel count with a manufacturer citation',
      ),
      isFalse,
    );
    expect(
      GoalClarification.preferencesMayMatter(
        'Recommend a camera',
        'Choose one',
      ),
      isTrue,
    );
    expect(
      GoalClarification.preferencesMayMatter(
        'Plan a trip',
        'Give an itinerary',
      ),
      isTrue,
    );
    expect(
      GoalClarification.preferencesMayMatter(
        'Choisir un appareil photo',
        'Recommander un modèle',
      ),
      isTrue,
    );
    expect(
      GoalClarification.preferencesMayMatter(
        'Elegir una cámara',
        'Recomendar un modelo',
      ),
      isTrue,
    );
    expect(
      GoalClarification.preferencesMayMatter('Compare cameras', ''),
      isTrue,
    );
  });
  test(
    'questions pause before research, persist, and resume using answers once',
    () async {
      var time = DateTime(2026, 9, 27, 10);
      var asked = 0, planned = 0, researched = 0;
      final runner = GoalRunner(
        clarify: (_) async {
          asked++;
          return [_question];
        },
        plan: (spec) async {
          planned++;
          expect(spec.effectiveRules, contains('Cooking videos'));
          return const GoalPlan(['What features help with cooking videos?']);
        },
        research: (spec, _, _) async {
          researched++;
          expect(spec.effectiveRules, contains('Cooking videos'));
          return const GoalStepResult(
            answer: 'The cameras have articulated screens [1].',
          );
        },
        evaluate: (_, _) async => const GoalDecision(satisfied: true),
        write: (spec, _) async => spec.clarificationContext,
        checkpoint: (_) async {},
        now: () => time,
      );
      const spec = GoalSpec(
        objective: 'Compare cameras',
        successCriteria: 'Recommend one',
        maxDuration: Duration(minutes: 10),
      );
      final waiting = await runner.run(spec);
      expect(waiting.status, GoalStatus.paused);
      expect(waiting.phase, GoalPhase.clarifying);
      expect(waiting.awaitingInputSince, time);
      expect(planned, 0);
      expect(researched, 0);
      final saved = GoalNotifier.decode(GoalNotifier.encode(waiting));
      expect(saved.spec.clarifications.single.options, _question.options);
      expect(saved.clarificationChecked, isTrue);
      time = time.add(const Duration(hours: 2));
      final answered = GoalNotifier.withClarificationAnswers(saved, {
        'Q1': 'Cooking videos',
      }, time);
      expect(time.difference(answered.startedAt), Duration.zero);
      expect(answered.spec.maxTokens, waiting.spec.maxTokens);
      expect(answered.spec.maxDuration, waiting.spec.maxDuration);
      final result = await runner.run(answered.spec, resume: answered);
      expect(result.status, GoalStatus.completed);
      expect(result.report, contains('Cooking videos'));
      expect(asked, 1);
      expect(planned, 1);
      expect(researched, 1);
      final back = GoalNotifier.decode(GoalNotifier.encode(result));
      expect(back.spec.clarifications.single.answer, 'Cooking videos');
      expect(back.awaitingInputSince, isNull);
    },
  );

  test('skip records assumptions and keeps spent planning time', () {
    final start = DateTime(2026);
    final waiting = GoalProgress(
      spec: const GoalSpec(
        objective: 'Camera recommendation',
        successCriteria: '',
        clarifications: [_question],
      ),
      status: GoalStatus.paused,
      steps: 0,
      usedTokens: 100,
      startedAt: start,
      awaitingInputSince: start.add(const Duration(minutes: 1)),
    );
    final answered = GoalNotifier.withClarificationAnswers(
      waiting,
      {},
      start.add(const Duration(hours: 2)),
    );
    expect(
      start.add(const Duration(hours: 2)).difference(answered.startedAt),
      const Duration(minutes: 1),
    );
    expect(answered.usedTokens, 100);
    expect(
      answered.spec.clarificationContext,
      contains('state them in the report'),
    );
    expect(answered.spec.clarifications.single.answer, isEmpty);
  });

  test('questions are bounded and malformed proposals are ignored', () {
    final questions = GoalClarification.parse([
      {'question': ''},
      {
        'question': 'Use?',
        'options': ['Video', 'Video', 'Photo', 'Both', 3],
      },
      {'question': 'use?'},
      {'question': 'Budget?'},
      {'question': 'Priority?'},
      {'question': 'Unnecessary fourth question?'},
    ]);
    expect(questions.map((q) => q.id), ['Q1', 'Q2', 'Q3']);
    expect(questions.first.options, ['Video', 'Photo', 'Both']);
  });

  testWidgets('popup choices remain editable and submit custom answers', (
    tester,
  ) async {
    Map<String, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<Map<String, String>>(
                  context: context,
                  builder: (_) =>
                      const GoalClarificationDialog(questions: [_question]),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cooking videos'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('goal-answer-Q1')))
          .controller!
          .text,
      'Cooking videos',
    );
    await tester.enterText(
      find.byKey(const Key('goal-answer-Q1')),
      'Restaurant tutorials, mostly indoors',
    );
    await tester.tap(find.byKey(const Key('goal-questions-submit')));
    await tester.pumpAndSettle();
    expect(result, {'Q1': 'Restaurant tutorials, mostly indoors'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('three questions fit a narrow screen and can be skipped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<Map<String, String>>(
                  context: context,
                  builder: (_) => const GoalClarificationDialog(
                    questions: [
                      _question,
                      GoalClarification(
                        id: 'Q2',
                        question: 'What is your total budget including a lens?',
                      ),
                      GoalClarification(
                        id: 'Q3',
                        question: 'Which features matter most to you?',
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('goal-questions-skip')));
    await tester.pumpAndSettle();
    expect(result, isEmpty);
  });
}
