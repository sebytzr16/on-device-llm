import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/schedule/schedule_page.dart';
import 'package:ondevice_llm/features/schedule/scheduled_prompt.dart';
import 'package:ondevice_llm/features/share/share_inbox.dart';

void main() {
  test('a scheduled prompt survives the platform store, junk does not', () {
    const p = ScheduledPrompt(
      id: 3,
      prompt: 'Top news in Canada today?',
      hour: 7,
      minute: 5,
      kind: 'goal',
      enabled: false,
    );
    final back = ScheduledPrompt.decodeList('[${_json(p)}]').single;
    expect(back.toJson(), p.toJson());
    expect(back.time, '07:05');
    expect(
      () => ScheduledPrompt.decodeList(
        '[{"id":1,"prompt":"","hour":7,"minute":0},'
        '{"id":2,"prompt":"x","hour":25,"minute":0},'
        '{"id":"3","prompt":"x","hour":1,"minute":0}, 7]',
      ),
      throwsFormatException,
    );
    expect(() => ScheduledPrompt.decodeList('not json'), throwsFormatException);
  });

  test('next time, and fresh ids', () {
    const p = ScheduledPrompt(id: 1, prompt: 'x', hour: 8, minute: 30);
    expect(p.nextAfter(DateTime(2026, 9, 23, 7)), DateTime(2026, 9, 23, 8, 30));
    expect(p.nextAfter(DateTime(2026, 9, 23, 9)), DateTime(2026, 9, 24, 8, 30));
    expect(ScheduledPrompt.freshId(const [p]), 2);
    expect(ScheduledPrompt.freshId(const []), 1);
  });

  test('a tapped notification arrives as a scheduled payload', () {
    final s = SharedPayload.fromMap({'text': 'Ask me', 'scheduled': 'chat'});
    expect(s.scheduled, 'chat');
    expect(s.text, 'Ask me');
    expect(SharedPayload.fromMap(const {'text': 'x'}).scheduled, isNull);
  });

  testWidgets('denied permission keeps a prompt disabled', (tester) async {
    var stored = <ScheduledPrompt>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SchedulePage(
          load: () async => stored,
          save: (items) async => stored = items,
          requestPermission: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('schedule-prompt')),
      'Daily question',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('schedule-save')));
    await tester.pumpAndSettle();
    expect(stored.single.enabled, false);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(stored.single.enabled, false);
  });

  testWidgets('a failed save restores the prior list', (tester) async {
    const original = ScheduledPrompt(
      id: 1,
      prompt: 'Keep me',
      hour: 8,
      minute: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SchedulePage(
          load: () async => [original],
          save: (_) async => throw StateError('disk failed'),
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    expect(find.textContaining('disk failed'), findsOneWidget);
  });

  testWidgets('a failed schedule load offers a retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SchedulePage(
          load: () async {
            if (attempts++ == 0) throw StateError('storage unavailable');
            return const [];
          },
          save: (_) async {},
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('storage unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('None yet'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('add, switch off and delete a scheduled prompt', (tester) async {
    var stored = <ScheduledPrompt>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SchedulePage(
          load: () async => stored,
          save: (items) async => stored = items,
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('None yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('schedule-add')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('schedule-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('schedule-prompt')),
      'What are the top news stories in Canada today?',
    );
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(stored.single.hour, 8);
    expect(stored.single.kind, 'chat');
    expect(find.text('08:00'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(stored.single.enabled, false);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(stored, isEmpty);
  });
}

String _json(ScheduledPrompt p) =>
    '{"id":${p.id},"title":"","prompt":"${p.prompt}","kind":"${p.kind}",'
    '"hour":${p.hour},"minute":${p.minute},"enabled":${p.enabled}}';
