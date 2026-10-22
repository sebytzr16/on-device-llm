import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/life_dates.dart';

void main() {
  final today = DateTime(2026, 9, 24);

  test('birth dates in the ways pages write them', () {
    expect(
      LifeDates.birthDates('Justin Drew Bieber (born March 1, 1994) is a'),
      [DateTime(1994, 3, 1)],
    );
    expect(LifeDates.birthDates('Born 1 March 1994 in London, Ontario'), [
      DateTime(1994, 3, 1),
    ]);
    expect(LifeDates.birthDates('Date of birth: 1994-03-01'), [
      DateTime(1994, 3, 1),
    ]);
    expect(LifeDates.birthDates('Céline Dion, née le 30 mars 1968 à'), [
      DateTime(1968, 3, 30),
    ]);
    expect(LifeDates.birthDates('Shakira nació el 2 de febrero de 1977'), [
      DateTime(1977, 2, 2),
    ]);
    expect(
      LifeDates.birthDates('The album was released March 1, 2026'),
      isEmpty,
    );
  });

  test('the age line: majority date, age today, next birthday', () {
    final note = LifeDates.note(
      [
        'Justin Bieber (born March 1, 1994) is a Canadian singer.',
        'Chart history for Justin Bieber',
        'Justin Bieber, born 1 March 1994, turned 32 in 2026.',
      ],
      'Can you please tell me how old is Justin Bieber',
      today,
    )!;
    expect(note, contains('sources [1][3]'));
    expect(note, contains('born 1994-03-01'));
    expect(note, contains('32 years old on 2026-09-24'));
    expect(note, contains('turned 32 on 2026-03-01, not today'));
    expect(note, contains('next birthday 2027-03-01'));
    expect(
      LifeDates.note(['born September 24, 1994'], 'how old is Sam', today),
      contains('turns 32 today (2026-09-24)'),
    );
  });

  test('only for age questions, and only with a date in the sources', () {
    expect(
      LifeDates.note(['born March 1, 1994'], 'What songs did he write?', today),
      isNull,
    );
    expect(
      LifeDates.note(['no dates here'], 'how old is Drake', today),
      isNull,
    );
    expect(LifeDates.ageOn(DateTime(1994, 9, 25), today), 31);
    expect(LifeDates.ageOn(DateTime(1994, 9, 24), today), 32);
  });
}
