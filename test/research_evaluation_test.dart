import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/research_evaluation.dart';

void main() {
  final fixtures =
      jsonDecode(File('eval/research_adversarial.json').readAsStringSync())
          as Map;
  for (final row in fixtures['cases'] as List) {
    test('research quality: ${row['id']}', () {
      final scored = ResearchEvaluation.score(
        answer: row['answer'] as String,
        evidence: (row['evidence'] as List).cast<String>(),
        gold: Map<String, dynamic>.from(row['gold'] as Map),
      ).toJson();
      for (final item in (row['expected'] as Map).entries) {
        expect(
          scored[item.key],
          item.value,
          reason: '${row['id']}: ${item.key}',
        );
      }
    });
  }
  test(
    'numeric rules accept sentence punctuation and reject longer numbers',
    () {
      expect(ResearchEvaluation.matches('128.', '128'), isTrue);
      expect(ResearchEvaluation.matches('1280', '128'), isFalse);
      expect(ResearchEvaluation.matches('128.5', '128'), isFalse);
      expect(ResearchEvaluation.matches('Version 3.47.9', '3.47'), isFalse);
    },
  );
  test('emphasis does not hide a stated fact (device run 2026-10-01)', () {
    expect(
      ResearchEvaluation.matches('WHO recommends **two** doses.', 'two doses'),
      isTrue,
    );
    expect(ResearchEvaluation.matches('_20.9_ MP', '20.9 MP'), isTrue);
  });
  test('the device run\'s two correct declines count as abstentions', () {
    const gold = {'unanswerable': true};
    for (final answer in [
      'I cannot provide an exact temperature for that specific date because live meteorological data is unavailable.',
      'I do not have the specific closing stock price for Apple on March 3, 2043.',
      'No puedo predecir el precio de cierre de esa fecha.',
    ]) {
      expect(
        ResearchEvaluation.score(
          answer: answer,
          evidence: const [],
          gold: gold,
        ).appropriateAbstention,
        isTrue,
        reason: answer,
      );
    }
    expect(
      ResearchEvaluation.score(
        answer: 'Apple closed at 412.50 that day.',
        evidence: const [],
        gold: gold,
      ).appropriateAbstention,
      isFalse,
    );
  });
  test('a full-date gold needs the right date stated first (2026-10-11)', () {
    const gold = {
      'requiredFacts': [
        ['August 2, 2027', '2 August 2027', 'August 2nd, 2027'],
      ],
    };
    bool? passes(String answer) => ResearchEvaluation.score(
      answer: answer,
      evidence: const [],
      gold: gold,
      today: DateTime(2026, 10, 11),
    ).factualRulesPassed;
    // The IQ4_NL run: wrong date in the lead, right one in a cut-off table.
    expect(
      passes(
        'The next total solar eclipse visible from Spain is on **August 12, '
        '2026** [3].\n\n| Date | August 12, 2026 | August 2, 2027 |',
      ),
      isFalse,
    );
    expect(
      passes('It is on **August 2, 2027** [1], after August 12, 2026.'),
      isTrue,
    );
    // Today's date from the clock line is not a competing answer.
    expect(
      passes('Today is October 11, 2026; the next one is 2 August 2027 [1].'),
      isTrue,
    );
    expect(passes('No total eclipse is listed.'), isFalse);
    const born = {
      'requiredFacts': [
        ['10 de marzo de 1994', '10 de marzo', 'March 10, 1994'],
      ],
    };
    expect(
      ResearchEvaluation.score(
        answer: 'Bad Bunny nació el 10 de marzo de 1994 en Puerto Rico.',
        evidence: const [],
        gold: born,
      ).factualRulesPassed,
      isTrue,
    );
    expect(
      ResearchEvaluation.score(
        answer:
            'Nació el 3 de mayo de 1990; otras fuentes dicen 10 de marzo de 1994.',
        evidence: const [],
        gold: born,
      ).factualRulesPassed,
      isFalse,
    );
  });
}
