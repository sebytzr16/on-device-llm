import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';

void main() {
  test('invalid actions expose typed problems without throwing', () {
    const date = PhoneAction('create_event', {
      'title': 'Date',
      'start': '2027-02-31T10:00',
    });
    expect(date.validationProblem?.code, PhoneActionProblemCode.invalidDate);
    const timer = PhoneAction('set_timer', {'seconds': 'Infinity'});
    expect(timer.validationProblem?.code, PhoneActionProblemCode.invalidNumber);
  });
  test('an empty unit beside the meant one still sets the timer', () {
    for (final empty in [null, '', ' ']) {
      final timer = PhoneAction('set_timer', {'minutes': 5, 'seconds': empty});
      expect(timer.timerSeconds, 300);
      expect(timer.validationProblem, isNull);
    }
    const bad = PhoneAction('set_timer', {'minutes': 5, 'seconds': 'soon'});
    expect(bad.timerSeconds, isNull);
  });
  for (final start in [
    '2027-02-31T09:00',
    '2026-13-01T09:00',
    '2026-10-11T24:00',
    '2026-10-11T09:60',
    '2026-10-11T09:00+14:59',
    '2026-10-11',
  ]) {
    test(
      'rejects invalid event $start',
      () => expect(
        PhoneAction.fromJson({
          'kind': 'create_event',
          'args': {'title': 'Test', 'start': start},
        }),
        isNull,
      ),
    );
  }
  for (final seconds in ['Infinity', 'NaN', '-Infinity', 'abc', -1, 1e300]) {
    test(
      'rejects malformed timer $seconds without throwing',
      () => expect(
        PhoneAction.fromJson({
          'kind': 'set_timer',
          'args': {'seconds': seconds},
        }),
        isNull,
      ),
    );
  }
  test('invalid explicit end cannot silently become one hour', () {
    expect(
      PhoneAction.fromJson({
        'kind': 'create_event',
        'args': {'title': 'Test', 'start': '2026-10-11T09:00', 'end': 'bad'},
      }),
      isNull,
    );
  });
  test('all-day events use UTC date boundaries and exclusive end', () {
    final a = PhoneAction.fromJson({
      'kind': 'create_event',
      'args': {
        'title': 'Day',
        'start': '2026-10-11',
        'end': '2026-10-12',
        'all_day': true,
      },
    })!;
    expect(
      a.toPlatform()['begin'],
      DateTime.utc(2026, 10, 11).millisecondsSinceEpoch,
    );
    expect(
      a.toPlatform()['end'],
      DateTime.utc(2026, 10, 12).millisecondsSinceEpoch,
    );
  });
  test('offset time previews agree with the platform instant', () {
    const a = PhoneAction('create_event', {
      'title': 'Test',
      'start': '2026-10-11T14:30+02:00',
    });
    final d = DateTime.fromMillisecondsSinceEpoch(
      a.toPlatform()['begin'] as int,
    );
    expect(
      a.detail,
      contains(
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
      ),
    );
  });
}
