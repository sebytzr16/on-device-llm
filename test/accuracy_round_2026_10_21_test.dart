import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/answer_cleanup.dart';
import 'package:ondevice_llm/features/chat/domain/answer_shape.dart';
import 'package:ondevice_llm/features/retrieval/domain/claim_check.dart';
import 'package:ondevice_llm/features/retrieval/domain/date_check.dart';
import 'package:ondevice_llm/features/retrieval/domain/research_evaluation.dart';

/// The accuracy misses of the October 20 sweep and the October 21 media
/// probe.
void main() {
  final today = DateTime(2026, 10, 21);

  group('a follow-up whose recalled pages lack the answer', () {
    test('an answer saying the sources lack it is recognised', () {
      for (final answer in [
        'The provided source does not contain information about how many '
            'shots the battery lasts [1].',
        "The sources don't mention the battery life.",
        "I couldn't find the number of shots in the pages.",
        'Les sources ne mentionnent pas l’autonomie.',
      ]) {
        expect(ClaimCheck.saysSourcesLack(answer), isTrue, reason: answer);
      }
    });

    test('an answer that gives the fact is not', () {
      for (final answer in [
        'The battery lasts about 330 shots per charge [2].',
        'The Z30 does not have a viewfinder [1].',
        'Battery life is rated at 330 shots (CIPA) [3].',
      ]) {
        expect(ClaimCheck.saysSourcesLack(answer), isFalse, reason: answer);
      }
    });
  });

  group('a "next" date that has already passed', () {
    const question = 'When is the next total solar eclipse visible from Spain?';

    test('is caught', () {
      expect(
        DateCheck.passedNext(
          'The next total solar eclipse visible from Spain is scheduled for '
          '**August 12, 2026**, which occurs on Tuesday, October 20, 2026 [3].',
          question,
          today,
        ),
        isTrue,
      );
    });

    test('a future date, a question not about "next", or no date is not', () {
      expect(
        DateCheck.passedNext(
          'The next one is on 2 August 2027 [2].',
          question,
          today,
        ),
        isFalse,
      );
      expect(
        DateCheck.passedNext(
          'It was on August 12, 2026 [1].',
          'When was the last total solar eclipse in Spain?',
          today,
        ),
        isFalse,
      );
      expect(
        DateCheck.passedNext(
          'The sources do not give the next date.',
          question,
          today,
        ),
        isFalse,
      );
      // "Next" without asking when: the date is context, not the answer.
      expect(
        DateCheck.passedNext(
          'Since August 12, 2026, the path has been mapped [1].',
          'Where does the next eclipse path cross Spain?',
          today,
        ),
        isFalse,
      );
    });
  });

  test('the grounded prompt asks for dates with their year', () {
    final rules = AnswerShapes.instructions(
      AnswerShape.figure,
      question: 'When did the WHO declare COVID-19 a pandemic?',
      local: true,
    );
    expect(rules, contains('with its year'));
  });

  group('a note that live data is unavailable', () {
    test('is dropped from an answer about an attached file', () {
      const answer =
          'Based on the data provided in the Excel file, coffee beans '
          'currently cost **12.9** per unit.\n\n'
          '*Note: While I have extracted this specific value from your source '
          'material, live information is unavailable for verification.*';
      expect(
        AnswerCleanup.dropLiveNote(answer),
        'Based on the data provided in the Excel file, coffee beans '
        'currently cost **12.9** per unit.',
      );
      expect(
        AnswerCleanup.dropLiveNote(
          'The total is CHF 54.50.\n\n(Please note: I do not have real-time '
          'exchange rates.)',
        ),
        'The total is CHF 54.50.',
      );
    });

    test('other notes and single paragraphs stay', () {
      for (final answer in [
        'The rent is \$1,450.\n\n*Note: the rent is due on the fifth.*',
        'Live information is unavailable for verification.',
        'Prices:\n\n- Apples 3.2\n- Bread 4.75',
        'The rent is \$1,450.\n\nNote: this lease is current until March '
            '2028 and cannot be extended.',
      ]) {
        expect(AnswerCleanup.dropLiveNote(answer), answer, reason: answer);
      }
    });
  });

  group('the research grader', () {
    test('counts "impossible to provide a forecast" as abstaining', () {
      const gold = {'unanswerable': true};
      for (final answer in [
        'The source [4] states that "1 January 2031" is in the future, '
            'meaning no weather data exists yet for that date. Therefore, it '
            'is impossible to provide a forecast or prediction for January 1, '
            '2031, based on the provided sources.',
        'No forecast exists yet for that date.',
      ]) {
        expect(
          ResearchEvaluation.score(
            answer: answer,
            evidence: const [],
            gold: gold,
            today: today,
          ).appropriateAbstention,
          isTrue,
          reason: answer,
        );
      }
    });

    test('a confident forecast is still not an abstention', () {
      expect(
        ResearchEvaluation.score(
          answer: 'It will be sunny and 25 °C in Toronto on 1 January 2031.',
          evidence: const [],
          gold: const {'unanswerable': true},
          today: today,
        ).appropriateAbstention,
        isFalse,
      );
    });
  });
}
