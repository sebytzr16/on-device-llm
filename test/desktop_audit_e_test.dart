import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/desktop/chat_drafts.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/desktop/chat_pane.dart';
import 'package:ondevice_llm/desktop/sidebar.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/domain/conversation_workspace.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/remote_server_page.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/settings_screen.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/export/desktop_chat_export.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/streaming_markdown.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/reasoning_accordion.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/schedule/scheduled_prompt.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

import 'support/desktop_chat_harness.dart';

void main() {
  test(
    'P1-24 draft disposal deletes only files still owned by drafts',
    () async {
      final deleted = <String>[];
      final drafts = DesktopChatDrafts(
        persist: false,
        delete: (attachment) async {
          deleted.add(attachment.id);
        },
      );
      Attachment attachment(String id) => Attachment(
        id: id,
        kind: AttachmentKind.document,
        name: id,
        mime: 'text/plain',
        path: id,
        sizeBytes: 1,
      );
      drafts.save('a', DesktopChatDraft('pending', [attachment('pending')]));
      drafts.save('b', DesktopChatDraft('sent', [attachment('sent')]));
      drafts.save('b', const DesktopChatDraft('', []));
      drafts.save('temporary', DesktopChatDraft('', [attachment('temporary')]));
      drafts.discard('temporary');
      drafts.dispose();
      expect(deleted, ['temporary', 'pending']);
    },
  );

  testWidgets('P1-24 drafts follow chat and survive section disposal', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final container = await mountDesktopChat(
      tester,
      ValueListenableBuilder(
        valueListenable: visible,
        builder: (_, value, _) =>
            value ? DesktopChatPane(composerFocus: focus) : const SizedBox(),
      ),
    );
    final chat = container.read(chatProvider.notifier) as DesktopTestChat;
    final field = find.descendant(
      of: find.byType(DesktopChatPane),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'new draft');
    chat.show(const ChatState(chatId: 'other'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, 'other draft');
    visible.value = false;
    await tester.pumpAndSettle();
    visible.value = true;
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'other draft');
    chat.show(const ChatState());
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'new draft');
    expect(
      container.read(desktopChatDraftsProvider).read('other').text,
      'other draft',
    );
  });

  testWidgets(
    'P1-26 sidebar excludes Archive and Trash and follows workspace updates',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final date = DateTime.utc(2026);
      final container = await mountDesktopChat(
        tester,
        SizedBox(
          width: 250,
          child: DesktopSidebar(searchFocus: focus, onNewChat: () {}),
        ),
        chats: [
          for (final id in ['active', 'archive', 'trash'])
            Chat(
              id: id,
              title: 'Chat $id',
              createdAt: date,
              updatedAt: date,
              pinned: false,
              tags: '',
              overridesJson: '{}',
            ),
        ],
      );
      final workspace = container.read(conversationWorkspaceProvider.notifier);
      await workspace.setState(['archive'], 'archived');
      await workspace.setState(['trash'], 'trash');
      await tester.pumpAndSettle();
      expect(find.text('Chat active'), findsOneWidget);
      expect(find.text('Chat archive'), findsNothing);
      expect(find.text('Chat trash'), findsNothing);
      await workspace.setState(['archive'], 'active');
      await tester.pumpAndSettle();
      expect(find.text('Chat archive'), findsOneWidget);
    },
  );

  testWidgets('P1-23 desktop hides scheduling and camera QR controls', (
    tester,
  ) async {
    final container = await mountDesktopChat(tester, const RemoteServerPage());
    expect(find.byKey(const Key('remote-scan')), findsNothing);
    expect(find.byKey(const Key('remote-paste')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-row')), findsNothing);
  });

  testWidgets('P1-25 Remote-only button and Enter share readiness', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final container = await mountDesktopChat(
      tester,
      DesktopChatPane(composerFocus: focus),
    );
    (container.read(modelManagerProvider.notifier) as DesktopTestModels).show(
      const ModelManagerState(),
    );
    final settings = container.read(settingsProvider);
    await container
        .read(settingsProvider.notifier)
        .update(
          settings.copyWith(
            remoteEnabled: true,
            remoteProfileId: 'remote',
            remoteProfiles: const [
              RemoteProfile(
                id: 'remote',
                name: 'Server',
                providerId: 'custom',
                baseUrl: 'http://localhost:8787',
                model: 'model',
              ),
            ],
          ),
        );
    final field = find.descendant(
      of: find.byType(DesktopChatPane),
      matching: find.byType(TextField),
    );
    final send = find.byKey(const Key('send-stop'));
    await tester.enterText(field, 'button');
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'enter');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final chat = container.read(chatProvider.notifier) as DesktopTestChat;
    expect(chat.sent, ['button', 'enter']);
    await container
        .read(settingsProvider.notifier)
        .update(
          container
              .read(settingsProvider)
              .copyWith(
                remoteProfiles: const [
                  RemoteProfile(
                    id: 'remote',
                    name: 'Server',
                    providerId: 'custom',
                    baseUrl: 'http://localhost:8787',
                  ),
                ],
              ),
        );
    await tester.enterText(field, 'default model');
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    await container
        .read(settingsProvider.notifier)
        .update(settings.copyWith(remoteEnabled: false));
    await tester.enterText(field, 'blocked');
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(chat.sent, ['button', 'enter', 'default model']);
  });

  test('P1-27 both export formats use the live branch', () {
    final date = DateTime.utc(2026);
    final export = DesktopChatExport(
      title: 'Chat',
      model: null,
      date: date,
      messages: [
        for (final status in [
          'superseded:branch:complete',
          'alternative',
          'alternative:error',
          'complete',
        ])
          ChatMessage(
            id: status,
            role: ChatRole.assistant,
            content: status,
            timestamp: date,
            status: status,
          ),
      ],
    );
    expect(
      (jsonDecode(export.json)['messages'] as List).map((m) => m['content']),
      ['complete'],
    );
    expect(export.markdown, isNot(contains('superseded')));
    expect(export.markdown, isNot(contains('alternative')));
  });

  testWidgets(
    'CX-47 finished paragraphs are built once; complex tails stay intact',
    (tester) async {
      final calls = <String>[];
      Future<void> show(String data, {bool streaming = true}) =>
          tester.pumpWidget(
            MaterialApp(
              home: StreamingMarkdown(
                data: data,
                streaming: streaming,
                builder: (part) {
                  calls.add(part);
                  return Text(part);
                },
              ),
            ),
          );
      await show('First.\n\nTail');
      await show('First.\n\nTail grows');
      expect(calls.where((s) => s == 'First.\n\n'), hasLength(1));
      await show('```dart\n\narr[0]');
      expect(calls.last, '```dart\n\narr[0]');
      await show('```dart\n\narr[0]\n```\n\nTail');
      await show('```dart\n\narr[0]\n```\n\nTail grows');
      expect(
        calls.where((part) => part == '```dart\n\narr[0]\n```\n\n'),
        hasLength(1),
      );
      expect(calls.last, 'Tail grows');
      await show('Answer [1].\n\nTail');
      await show('Answer [1].\n\nTail grows');
      expect(calls.where((part) => part == 'Answer [1].\n\n'), hasLength(1));
      const references = 'Answer [1].\n\n[1]: https://example.test';
      await show(references);
      expect(calls.last, references);
      await show('First.\n\nTail grows', streaming: false);
      expect(calls.last, 'First.\n\nTail grows');
    },
  );

  testWidgets(
    'CX-47 streaming reasoning lays out only its last 2048 characters',
    (tester) async {
      final content = 'x' * 5000;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReasoningAccordion(content: content),
            ),
          ),
        ),
      );
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('x' * 2048), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byType(InkWell));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        content,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReasoningAccordion(content: content, isComplete: true),
            ),
          ),
        ),
      );
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        content,
      );
    },
  );

  test(
    'P1-23 desktop scheduling cannot claim notification permission',
    () async {
      final previous = DesktopHost.active;
      DesktopHost.active = true;
      try {
        expect(ScheduleStore.supported, isFalse);
        expect(await ScheduleStore.requestPermission(), isFalse);
      } finally {
        DesktopHost.active = previous;
      }
    },
  );
}
