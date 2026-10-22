import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';

void main() {
  test('the actions prompt gives the local date, weekday and the kinds', () {
    final prompt = GoalNotifier.actionsPrompt(
      'Find the next Lyon concert and add it to my calendar',
      'The concert is on 12 October at 20:00 at the Halle.',
      DateTime(2026, 10, 7, 14, 30),
    );
    expect(prompt, contains('Wednesday 2026-10-07T14:30'));
    expect(prompt, contains('create_event: title, start'));
    expect(prompt, contains('12 October at 20:00'));
    expect(prompt, contains('{"actions": []}'));
    // Real line breaks, not escaped ones.
    expect(prompt, isNot(contains(r'\n')));
  });

  test('a long report is cut for the prompt', () {
    final prompt = GoalNotifier.actionsPrompt(
      'x',
      'a' * 20000,
      DateTime(2026, 10, 7),
    );
    expect(prompt.length, lessThan(11000));
  });

  test('the reply keeps valid actions only, at most six', () {
    final actions = GoalNotifier.actionsFrom({
      'actions': [
        {
          'kind': 'create_event',
          'args': {'title': 'Concert', 'start': '2026-10-12T20:00'},
        },
        // Fields beside the kind are accepted.
        {'kind': 'set_alarm', 'time': '07:15', 'label': 'Train'},
        // Invalid: no start.
        {
          'kind': 'create_event',
          'args': {'title': 'X'},
        },
        // Unknown kind.
        {
          'kind': 'delete_everything',
          'args': {'all': true},
        },
        'nonsense',
        for (var i = 0; i < 8; i++)
          {
            'kind': 'set_timer',
            'args': {'minutes': i + 1},
          },
      ],
    });
    expect(actions, hasLength(GoalNotifier.maxActions));
    expect(actions[0].kind, 'create_event');
    expect(actions[1].kind, 'set_alarm');
    expect(actions[1].args['label'], 'Train');
    expect(GoalNotifier.actionsFrom(null), isEmpty);
    expect(GoalNotifier.actionsFrom({'actions': 'none'}), isEmpty);
  });

  test('actions survive saving and loading a goal', () {
    final progress = GoalProgress(
      spec: const GoalSpec(
        objective: 'Plan my week and set reminders',
        successCriteria: '',
      ),
      status: GoalStatus.completed,
      steps: 2,
      startedAt: DateTime(2026, 10, 7, 9),
      report: 'Report',
      actions: const [
        PhoneAction('set_reminder', {
          'text': 'Gym',
          'when': '2026-10-08T18:00',
        }),
      ],
      preparingActions: true,
    );
    final back = GoalNotifier.decode(
      jsonDecode(jsonEncode(GoalNotifier.encode(progress)))
          as Map<String, dynamic>,
    );
    expect(back.actions.single.kind, 'set_reminder');
    expect(back.actions.single.args['text'], 'Gym');
    // The busy flag is not saved.
    expect(back.preparingActions, isFalse);
  });

  test('a goal that asks for an action is recognised', () {
    expect(
      PhoneActions.wanted(
        'Find the opening hours of the pool and remind me on Saturday',
      ),
      isTrue,
    );
    expect(
      PhoneActions.wanted('Compare the three best e-bikes under 2000 euros'),
      isFalse,
    );
  });
}
