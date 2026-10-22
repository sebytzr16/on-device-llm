import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/date_check.dart';

void main() {
  final now = DateTime(2026, 10, 11, 21, 30);

  group('a question about a future date', () {
    test('a full date in EN, FR and ES', () {
      for (final q in [
        'What was the closing price of Apple stock on 3 March 2043?',
        "What was Apple's closing stock price on March 3rd, 2043?",
        'Quel temps fera-t-il à Toronto le 1er janvier 2031 ?',
        '¿Qué tiempo hará en Toronto el 1 de enero de 2031?',
        'Weather in Toronto on 2031-01-01',
      ]) {
        final note = DateCheck.note(const [], q, now);
        expect(note, isNotNull, reason: q);
        expect(note, contains('today is 2026-10-11'));
        expect(note, contains('cannot be known yet'));
      }
    });

    test('says how far ahead it is', () {
      expect(
        DateCheck.note(const [], 'Weather in Toronto on 1 January 2031?', now),
        contains('"1 January 2031" is in the future, 4 years after today'),
      );
      expect(
        DateCheck.note(const [], 'Forecast for 20 October 2026?', now),
        contains('9 days after today'),
      );
      expect(
        DateCheck.note(const [], 'Who wins the final in March 2027?', now),
        contains('"March 2027" is in the future, 5 months after today'),
      );
    });

    test('a year alone counts only for an outcome', () {
      expect(
        DateCheck.note(const [], 'Who will win the 2034 FIFA World Cup?', now),
        contains('"2034" is in the future, 7 years after today'),
      );
      expect(
        DateCheck.note(const [], 'Qui gagnera la Coupe du monde 2030 ?', now),
        isNotNull,
      );
      expect(
        DateCheck.note(const [], 'Predict the bitcoin price in 2030.', now),
        contains('"2030" is in the future'),
      );
      expect(DateCheck.note(const [], 'What is Agenda 2030?', now), isNull);
      expect(
        DateCheck.note(const [], 'When is the 2034 FIFA World Cup?', now),
        isNull,
      );
    });

    test('past dates, the current month and plain numbers are not', () {
      for (final q in [
        'Who won the 2022 FIFA World Cup?',
        'What happened on 9 October 2026?',
        'What is on in October 2026?',
        'Is the RTX 5090 worth 2000 dollars?',
        'Price of 3000 shares of Apple',
        'What will 2500 shares of Apple cost?',
        'How tall is LeBron James?',
      ]) {
        expect(DateCheck.note(const [], q, now), isNull, reason: q);
      }
    });

    test('month names inside other words are not dates', () {
      // "mar" in "Omar", "mai" in "Maine", "dec" in "decade".
      expect(
        DateCheck.note(const [], 'Will Omar 2040 win the decade award?', now),
        contains('"2040"'),
      );
      expect(DateCheck.fullDates('Omar 12 2040, Maine 3 2041'), isEmpty);
    });
  });

  group('a question about the next occurrence', () {
    const eclipse = [
      'Solar eclipse of August 12, 2026\nA total solar eclipse occurred on '
          '12 August 2026, visible from Spain. The next total eclipse visible '
          'from Spain is on 2 August 2027. An annular eclipse on 26 January '
          '2028 follows.',
      'Eclipses in Spain\nThe last one before 2026 was on 30 August 1905.',
    ];

    test('sorts the dates in the sources into passed and still ahead', () {
      final note = DateCheck.note(
        eclipse,
        'When is the next total solar eclipse visible from Spain?',
        now,
      )!;
      expect(
        note,
        contains(
          'none of them is the next one: 2026-08-12 [1], 1905-08-30 [2].',
        ),
      );
      expect(
        note,
        contains('still ahead: 2027-08-02 [1], 2028-01-26 [1]. Answer with'),
      );
    });

    test('says when no date in the sources is ahead', () {
      expect(
        DateCheck.note(
          const ['The last eclipse was on 12 August 2026.'],
          'When is the next eclipse?',
          now,
        ),
        contains('say the sources do not give the next date'),
      );
    });

    test('in French and Spanish', () {
      expect(
        DateCheck.note(eclipse, 'Quand a lieu la prochaine éclipse ?', now),
        contains('2026-08-12 [1]'),
      );
      expect(
        DateCheck.note(eclipse, '¿Cuándo es el próximo eclipse?', now),
        contains('2026-08-12 [1]'),
      );
    });

    test('keeps the three most recent and merges sources', () {
      final note = DateCheck.note(
        [
          'On 1 May 2026, 2 June 2026, 3 July 2026 and 4 August 2026.',
          'Also 4 August 2026.',
        ],
        'When is the next launch?',
        now,
      )!;
      expect(
        note,
        contains('2026-08-04 [1][2], 2026-07-03 [1], 2026-06-02 [1].'),
      );
      expect(note, isNot(contains('2026-05-01')));
    });

    test('says nothing without a when-question or a past date', () {
      expect(
        DateCheck.note(eclipse, 'What is the next step after login?', now),
        isNull,
      );
      expect(
        DateCheck.note(
          const ['The next eclipse is on 2 August 2027.'],
          'When is the next eclipse?',
          now,
        ),
        isNull,
      );
    });
  });

  test('fullDates reads every format once, in order', () {
    expect(
      DateCheck.fullDates(
        'Born March 1, 1994; died 2 avril 2030; fecha 3 de mayo de 2031; '
        'ISO 2032-02-29 and 2033-02-29 (not a date); 31 June 2026 neither.',
      ),
      [
        DateTime(1994, 3, 1),
        DateTime(2030, 4, 2),
        DateTime(2031, 5, 3),
        DateTime(2032, 2, 29),
      ],
    );
  });
}
