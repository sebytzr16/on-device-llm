import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:ondevice_llm/features/tools/presentation/phone_action_cards.dart';

ToolCall call(String name, Map<String, Object?> args) =>
    ToolCall(id: '1', name: name, arguments: jsonEncode(args));

void main() {
  group('PhoneActions.wanted', () {
    test('recognises requests to act on the phone in EN/FR/ES', () {
      for (final t in [
        'Remind me to call mum tomorrow at 6pm',
        'Set an alarm for 6:30',
        'wake me at 7',
        'Start a 10 minute timer for the pasta',
        'Add the dentist appointment on Friday at 3 to my calendar',
        'Draft an email to my landlord about the heating',
        'Text him that I will be late',
        'Save this as a CSV file',
        'Rappelle-moi de payer le loyer lundi',
        'Mets un minuteur de 5 minutes',
        'Écris un SMS à Paul pour lui dire que j\'arrive',
        'Recuérdame comprar pan mañana',
        'Pon una alarma a las 7',
        'Escribe un correo a mi jefe',
        'Remind me at 9 to take my pills',
        'Recuérdame que llame a Ana',
      ]) {
        expect(PhoneActions.wanted(t), isTrue, reason: t);
      }
    });

    test('leaves ordinary questions alone', () {
      for (final t in [
        'What is the capital of Australia?',
        'Explain how vaccines work',
        'Who won the match yesterday?',
        'Résume ce texte',
        'Hola, ¿qué tal?',
        'What is the best calendar app in 2026?',
        'Who invented the alarm clock?',
        'How does a kitchen timer work?',
        'Quel est le meilleur agenda papier ?',
        '¿Cuál es la mejor alarma para casa?',
        // Recall questions about the chat (phone probe 2026-10-07).
        'Remind me: what is my name and where am I going?',
        'Remind me what my budget was',
        'Rappelle-moi quel est mon budget',
        'Recuérdame cuál es mi presupuesto',
      ]) {
        expect(PhoneActions.wanted(t), isFalse, reason: t);
      }
    });

    test('an outright request is a command, a how-to question is not', () {
      for (final t in [
        'Set a timer for five minutes.',
        'Can you set an alarm for 7?',
        'Please remind me to call mum at 6',
        'Mets un minuteur de 5 minutes',
        'Pon una alarma a las 7',
      ]) {
        expect(PhoneActions.command(t), isTrue, reason: t);
      }
      for (final t in [
        'How do I set an alarm on my phone?',
        'Can I set a timer from the lock screen?',
        'Comment mettre un minuteur ?',
        '¿Cómo pongo una alarma?',
        'What is the capital of Australia?',
      ]) {
        expect(PhoneActions.command(t), isFalse, reason: t);
      }
    });

    test('a dated phone action is not sent to the web', () {
      expect(
        RetrievalPlan.of(
          'Remind me tomorrow at 9 to call the bank',
          webEnabled: true,
        ).wantsWeb,
        isFalse,
      );
      expect(
        RetrievalPlan.of(
          'Who won the match yesterday?',
          webEnabled: true,
        ).wantsWeb,
        isTrue,
      );
      // A question about such things still searches.
      expect(
        RetrievalPlan.of(
          'What is the best calendar app in 2026?',
          webEnabled: true,
        ).wantsWeb,
        isTrue,
      );
      // An explicit search still searches.
      expect(
        RetrievalPlan.of(
          'Search the web for the concert date and add it to my calendar',
          webEnabled: true,
        ).wantsWeb,
        isTrue,
      );
    });
  });

  group('prepare', () {
    test('a valid event is prepared, never claimed done', () {
      final out = PhoneActions.prepare(
        call('create_event', {
          'title': 'Dentist',
          'start': '2026-10-09T15:00',
          'location': 'Main St',
        }),
      );
      expect(out, contains('Prepared'));
      expect(out, contains('Dentist'));
      expect(out, contains('Do not say it is already done'));
    });

    test('bad arguments tell the model what to fix', () {
      expect(
        () => PhoneActions.prepare(
          call('create_event', {'title': 'X', 'start': 'tomorrow'}),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PhoneActions.prepare(call('set_alarm', {'time': '25:00'})),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PhoneActions.prepare(call('set_timer', {'minutes': 0})),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PhoneActions.prepare(call('draft_message', {'to': 'a@b.c'})),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PhoneActions.prepare(
          call('create_event', {
            'title': 'X',
            'start': '2026-10-09T15:00',
            'end': '2026-10-09T14:00',
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('platform mapping', () {
    test('event times are local and end defaults to one hour', () {
      const a = PhoneAction('create_event', {
        'title': 'Lunch',
        'start': '2026-10-09 12:30',
      });
      final m = a.toPlatform();
      expect(m['kind'], 'event');
      final begin = DateTime.fromMillisecondsSinceEpoch(m['begin']! as int);
      expect((begin.hour, begin.minute), (12, 30));
      expect((m['end']! as int) - (m['begin']! as int), 3600000);
    });

    test('alarm days map to Calendar weekday numbers', () {
      const a = PhoneAction('set_alarm', {
        'time': '6:45',
        'days': ['mon', 'Friday', 'sáb', 'xx'],
      });
      final m = a.toPlatform();
      expect((m['hour'], m['minute']), (6, 45));
      expect(m['days'], [2, 6, 7]);
    });

    test('timer adds minutes and seconds', () {
      const a = PhoneAction('set_timer', {'minutes': 2, 'seconds': 30});
      expect(a.toPlatform()['seconds'], 150);
      expect(a.detail, '2 min 30 s');
    });

    test('a reminder becomes a calendar entry with an alert', () {
      const a = PhoneAction('set_reminder', {
        'text': 'Pay rent',
        'when': '2026-11-01T09:00',
      });
      expect(a.toPlatform()['kind'], 'event');
      expect(a.toPlatform()['title'], 'Pay rent');
    });

    test('file names are made safe and get an allowed extension', () {
      expect(
        const PhoneAction('save_file', {
          'name': 'my/list:2026',
          'content': 'a',
        }).fileName,
        'my list 2026.md',
      );
      expect(
        const PhoneAction('save_file', {
          'name': 'budget',
          'format': 'csv',
          'content': 'a,b',
        }).fileName,
        'budget.csv',
      );
      expect(
        const PhoneAction('save_file', {
          'name': 'page.exe',
          'content': 'x',
        }).fileName,
        'page.exe.md',
      );
    });
  });

  test('actions are read back from a stored tool trace', () {
    final trace = [
      {
        'call': call('set_alarm', {'time': '07:00'}).toJson(),
        'output': 'Prepared.',
        'ok': true,
      },
      {
        'call': call('set_alarm', {'time': 'bad'}).toJson(),
        'output': 'Error',
        'ok': false,
      },
      {
        'call': call('search_web', {'query': 'x'}).toJson(),
        'output': '…',
        'ok': true,
      },
    ];
    final actions = PhoneActions.fromTrace(trace);
    expect(actions, hasLength(1));
    expect(actions.single.kind, 'set_alarm');
    expect(PhoneActions.mayHave(jsonEncode({'tools': trace})), isTrue);
    expect(PhoneActions.mayHave('{"tools":[]}'), isFalse);
  });

  test('the tools are only offered for action requests', () {
    final names = PhoneActions.specs().map((s) => s.name).toSet();
    expect(names, PhoneActions.kinds);
  });

  testWidgets('each prepared action gets a card with its button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PhoneActionCards(
              actions: [
                PhoneAction('create_event', {
                  'title': 'Dentist',
                  'start': '2026-10-09T15:00',
                }),
                PhoneAction('set_timer', {'minutes': 10, 'label': 'Pasta'}),
                PhoneAction('save_file', {'name': 'list', 'content': 'a'}),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Dentist'), findsOneWidget);
    expect(find.text('Pasta'), findsOneWidget);
    expect(find.text('list.md'), findsOneWidget);
    expect(find.text('Add to calendar'), findsOneWidget);
    expect(find.text('Start timer'), findsOneWidget);
    expect(find.text('Save or share'), findsOneWidget);
    expect(find.byKey(const Key('phone-action-go-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
