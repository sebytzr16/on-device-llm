import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:ondevice_llm/features/chat/domain/entities/turn_run.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/reasoning_accordion.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/run_details_sheet.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

double _sizeFactor(WidgetTester t) =>
    t.widget<SizeTransition>(find.byType(SizeTransition)).sizeFactor.value;

void main() {
  testWidgets('run details sheet reports paused speculation', (tester) async {
    final run = TurnRun(
      settings: const {},
      engine: const {},
      metrics: const {
        'draftModel': 'tiny',
        'draftProposed': 48,
        'draftAccepted': 12,
        'draftAcceptRate': 0.25,
        'draftRounds': 8,
        'draftDisabled': true,
      },
      modelId: 'm',
      modelName: 'Model',
      presetId: 'p',
      presetName: 'Preset',
      sources: 0,
      at: DateTime.utc(2026, 9, 19),
    );
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      ),
    );
    unawaited(showRunDetailsSheet(ctx, run));
    await tester.pumpAndSettle();
    expect(find.text('12 / 48 (25%)'), findsOneWidget);
    expect(
      find.text('paused after 8 rounds (acceptance below 35%)'),
      findsOneWidget,
    );
    // Good acceptance but no speed win: the other reason.
    final slow = TurnRun(
      settings: const {},
      engine: const {},
      metrics: const {
        'draftModel': 'tiny',
        'draftProposed': 30,
        'draftAccepted': 21,
        'draftAcceptRate': 0.7,
        'draftRounds': 8,
        'draftDisabled': true,
        'draftSpeedup': 0.41,
      },
      modelId: 'm',
      modelName: 'Model',
      presetId: 'p',
      presetName: 'Preset',
      sources: 0,
      at: DateTime.utc(2026, 9, 19),
    );
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    unawaited(showRunDetailsSheet(ctx, slow));
    await tester.pumpAndSettle();
    expect(find.text('0.41x plain'), findsOneWidget);
    expect(
      find.text('paused after 8 rounds (slower than plain decoding)'),
      findsOneWidget,
    );
  });

  testWidgets(
    'ReasoningAccordion is open while streaming and folds on completion',
    (tester) async {
      await tester.pumpWidget(
        _host(const ReasoningAccordion(content: 'step one', isComplete: false)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Thinking…'), findsOneWidget);
      expect(_sizeFactor(tester), 1);

      await tester.pumpWidget(
        _host(const ReasoningAccordion(content: 'step one', isComplete: true)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Reasoning ·'), findsOneWidget);
      expect(find.text('Thinking…'), findsNothing);
      expect(_sizeFactor(tester), 0);

      // Still reachable: a tap reopens the folded block.
      await tester.tap(find.textContaining('Reasoning ·'));
      await tester.pumpAndSettle();
      expect(_sizeFactor(tester), 1);
    },
  );

  testWidgets('ReasoningAccordion starts folded when already complete', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ReasoningAccordion(
          content: 'done',
          isComplete: true,
          duration: Duration(seconds: 4),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reasoning · 4.0 s'), findsOneWidget);
    expect(_sizeFactor(tester), 0);
  });

  testWidgets('a warning shows a triangle that opens all of it', (
    tester,
  ) async {
    const warning =
        'Not backed by the sources: "This can also be paid as \$144/month '
        'with a 24-month contract." Check these statements before relying '
        'on them.';
    ChatMessage answer(Map<String, dynamic> metrics) => ChatMessage(
      id: metrics.isEmpty ? 'plain' : 'warned',
      role: ChatRole.assistant,
      content: 'The Fold8 Ultra costs \$3,265.',
      timestamp: DateTime(2026),
      runJson: TurnRun(
        settings: const {},
        engine: const {},
        metrics: metrics,
        modelId: 'remote:gemma',
        modelName: 'gemma',
        presetId: 'general',
        presetName: 'General',
        sources: 5,
        at: DateTime(2026),
      ).encode(),
    );
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            ChatBubble(message: answer(const {})),
            ChatBubble(message: answer(const {'warning': warning})),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('warning-plain')), findsNothing);
    expect(find.byKey(const Key('warning-warned')), findsOneWidget);
    await tester.tap(find.byKey(const Key('warning-warned')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('turn-notice-full')))
          .data,
      warning,
    );
  });

  testWidgets('superseded turns collapse; last turns expose their actions', (
    tester,
  ) async {
    final old = ChatMessage(
      id: 'a1',
      role: ChatRole.assistant,
      content: 'first draft of a long answer that was replaced later on',
      timestamp: DateTime(2026),
      status: 'superseded:b1:complete',
    );
    final stopped = ChatMessage(
      id: 'a2',
      role: ChatRole.assistant,
      content: 'partial',
      timestamp: DateTime(2026),
      status: 'stopped',
    );
    var continued = false, regenerated = false;
    String? edited;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            ChatBubble(message: old),
            ChatBubble(
              message: ChatMessage(
                id: 'u1',
                role: ChatRole.user,
                content: 'question',
                timestamp: DateTime(2026),
              ),
              onEdit: (t) => edited = t,
            ),
            ChatBubble(
              message: stopped,
              onContinue: () => continued = true,
              onRegenerate: () => regenerated = true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Earlier answer ·'), findsOneWidget);
    expect(find.text(old.content), findsNothing);
    await tester.tap(find.byKey(const Key('superseded-a1')));
    await tester.pumpAndSettle();
    expect(find.text(old.content), findsOneWidget);
    await tester.tap(find.byKey(const Key('continue-answer')));
    await tester.tap(find.byKey(const Key('regenerate-answer')));
    expect(continued && regenerated, true);
    await tester.tap(find.byKey(const Key('edit-question')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'better question');
    await tester.tap(find.text('Ask again'));
    await tester.pumpAndSettle();
    expect(edited, 'better question');
  });

  testWidgets('answer actions sit under the answer and delete is labelled', (
    tester,
  ) async {
    bool? deleted;
    await tester.pumpWidget(
      _host(
        ChatBubble(
          message: ChatMessage(
            id: 'a9',
            role: ChatRole.assistant,
            content: 'An answer.',
            timestamp: DateTime(2026),
          ),
          onSpeak: () {},
          onDelete: (pair) => deleted = pair,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-a9')), findsOneWidget);
    expect(find.byKey(const Key('speak-a9')), findsOneWidget);
    await tester.tap(find.byKey(const Key('answer-more-a9')));
    await tester.pumpAndSettle();
    expect(find.text('Delete answer'), findsOneWidget);
    expect(find.text('Delete question and answer'), findsOneWidget);
    await tester.tap(find.byKey(const Key('message-action-delete-answer')));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);
  });

  testWidgets('tapping a source opens the inspector with its passages', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'a1',
      role: ChatRole.assistant,
      content: 'Answer [1].',
      timestamp: DateTime(2026),
      sourcesJson:
          r'[{"number":1,"title":"Docs","url":"https://docs.flutter.dev/x","retrievalStatus":"page_read","excerpt":"first passage\n[…]\nsecond passage","fetchedAt":"2026-09-15T10:00:00.000Z","publishedAt":"2026-09-01T00:00:00.000Z"}]',
    );
    await tester.pumpWidget(_host(ChatBubble(message: message)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sources-bubble')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sources-bubble')));
    await tester.pumpAndSettle();
    expect(find.textContaining('published 2026-09-01'), findsOneWidget);
    await tester.tap(find.byKey(const Key('source-1')));
    await tester.pumpAndSettle();
    expect(find.text('first passage'), findsOneWidget);
    expect(find.textContaining('Page read'), findsOneWidget);
    expect(find.text('What the model was given'), findsOneWidget);
    expect(find.text('2 passages'), findsOneWidget);
    // The shared header and pinned actions leave a smaller scrolling body.
    await tester.scrollUntilVisible(
      find.text('second passage'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('second passage'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Full address'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Open in browser'), findsOneWidget);
    expect(find.text('Full address'), findsOneWidget);
  });

  testWidgets('sponsored results are disclosed separately from evidence', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'a-sponsored',
      role: ChatRole.assistant,
      content: 'Answer [1].',
      timestamp: DateTime(2026),
      sourcesJson:
          r'[{"number":1,"title":"Docs","url":"https://docs.example/x","retrievalStatus":"page_read","excerpt":"evidence"},{"title":"Buy now","url":"https://shop.example/offer","retrievalStatus":"sponsored_not_used","sponsored":true}]',
    );
    await tester.pumpWidget(_host(ChatBubble(message: message)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources-bubble')));
    await tester.pumpAndSettle();
    expect(find.text('1 reference · 1 sponsored'), findsOneWidget);
    expect(find.text('Sponsored (not used)'), findsOneWidget);
    expect(find.text('Buy now'), findsOneWidget);
    expect(find.textContaining('[null]'), findsNothing);
  });

  testWidgets('question version picker restores an earlier branch', (
    tester,
  ) async {
    final old = ChatMessage(
      id: 'old',
      role: ChatRole.user,
      content: 'Earlier question',
      timestamp: DateTime.utc(2026),
      status: 'superseded:branch-a:complete',
    );
    final current = ChatMessage(
      id: 'current',
      role: ChatRole.user,
      content: 'Current question',
      timestamp: DateTime.utc(2026),
    );
    String? restored;
    await tester.pumpWidget(
      _host(
        ChatBubble(
          message: current,
          versions: [old, current],
          onRestoreVersion: (branch) => restored = branch,
        ),
      ),
    );
    expect(find.text('2/2'), findsOneWidget);
    await tester.tap(find.text('2/2'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Earlier question'));
    await tester.pumpAndSettle();
    expect(restored, 'branch-a');
    // The arrows: back to version 1; there is no version 3.
    restored = null;
    await tester.tap(find.byTooltip('Previous version'));
    expect(restored, 'branch-a');
    final next = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    expect(next.onPressed, isNull);
  });
}
