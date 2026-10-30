import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/desktop/desktop_app.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/projects_page.dart';
import 'package:ondevice_llm/features/chat/domain/conversation_workspace.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

class _Chat extends ChatNotifier {
  final opened = <String>[];
  final deleted = <String>[];
  @override
  ChatState build() => const ChatState();
  @override
  Future<void> openChat(String id) async {
    opened.add(id);
  }

  @override
  Future<void> deleteChat(String id) async {
    deleted.add(id);
  }
}

void main() {
  final date = DateTime(2026, 1, 1);
  Chat chat(String id, String title) => Chat(
    id: id,
    title: title,
    createdAt: date,
    updatedAt: date,
    pinned: false,
    tags: '[]',
    overridesJson: '{}',
  );

  Future<ProviderContainer> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      ConversationWorkspaceNotifier.key: jsonEncode({
        'projects': [
          {'id': 'research', 'name': 'Research'},
          {'id': 'notes', 'name': 'Notes'},
        ],
        'memberships': {'one': 'research', 'two': 'research'},
        'states': {'old': 'archived', 'gone': 'trash'},
      }),
    });
    final container = ProviderContainer(
      overrides: [
        chatProvider.overrideWith(_Chat.new),
        chatsProvider.overrideWith(
          (ref) => Stream.value([
            chat('one', 'First conversation'),
            chat('two', 'Second conversation'),
            chat('old', 'Archived conversation'),
            chat('gone', 'Trashed conversation'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(conversationWorkspaceProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DesktopProjectsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder row(String id) => find.byKey(ValueKey('project-chat-$id'));
  Future<void> select(WidgetTester tester, String id) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(row(id));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'projects list active counts and Archived filters conversations',
    (tester) async {
      await mount(tester);
      final research = find.byKey(const ValueKey('project-place-research'));
      expect(
        find.descendant(of: research, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('project-place-notes')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(row('one'), findsOneWidget);
      expect(row('old'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('project-place-archived')));
      await tester.pumpAndSettle();
      expect(row('old'), findsOneWidget);
      expect(row('one'), findsNothing);
      expect(row('gone'), findsNothing);
    },
  );

  testWidgets('Ctrl click selects many, Escape clears, normal click opens', (
    tester,
  ) async {
    final container = await mount(tester);
    expect(find.byType(Checkbox), findsNothing);
    await select(tester, 'one');
    await select(tester, 'two');
    expect(find.byKey(const Key('projects-bulk-bar')), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
    expect((container.read(chatProvider.notifier) as _Chat).opened, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects-bulk-bar')), findsNothing);
    await tester.tap(row('one'));
    await tester.pumpAndSettle();
    expect((container.read(chatProvider.notifier) as _Chat).opened, ['one']);
    expect(container.read(desktopSectionProvider), DesktopSection.chat);
  });

  testWidgets('bulk move uses the existing workspace membership', (
    tester,
  ) async {
    final container = await mount(tester);
    await select(tester, 'one');
    await tester.tap(find.text('Move to project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Notes'));
    await tester.pumpAndSettle();
    expect(
      container.read(conversationWorkspaceProvider).memberships['one'],
      'notes',
    );
    expect(
      container.read(conversationWorkspaceProvider).memberships['two'],
      'research',
    );
  });

  testWidgets(
    'Delete confirms and moves selection to Trash without permanent deletion',
    (tester) async {
      final container = await mount(tester);
      await select(tester, 'one');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        container.read(conversationWorkspaceProvider).stateOf('one'),
        'active',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Move to trash'));
      await tester.pumpAndSettle();
      expect(
        container.read(conversationWorkspaceProvider).stateOf('one'),
        'trash',
      );
      expect((container.read(chatProvider.notifier) as _Chat).deleted, isEmpty);
      expect(row('one'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('project-place-trash')));
      await tester.pumpAndSettle();
      expect(row('one'), findsOneWidget);
    },
  );

  testWidgets('Shift selects a range, Ctrl+A selects the filtered pane', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 'one');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(row('two'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('projects-search')), 'First');
    await tester.pumpAndSettle();
    expect(row('one'), findsOneWidget);
    expect(row('two'), findsNothing);
    expect(find.byKey(const Key('projects-bulk-bar')), findsNothing);
  });

  testWidgets('dragging selection onto a project moves every selected chat', (
    tester,
  ) async {
    final container = await mount(tester);
    await select(tester, 'one');
    await select(tester, 'two');
    await tester.dragFrom(
      tester.getCenter(row('one')),
      tester.getCenter(find.byKey(const ValueKey('project-place-notes'))) -
          tester.getCenter(row('one')),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(conversationWorkspaceProvider).memberships['one'],
      'notes',
    );
    expect(
      container.read(conversationWorkspaceProvider).memberships['two'],
      'notes',
    );
  });
  testWidgets('archived and trashed conversations can be restored', (
    tester,
  ) async {
    final container = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('project-place-archived')));
    await tester.pumpAndSettle();
    await select(tester, 'old');
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(
      container.read(conversationWorkspaceProvider).stateOf('old'),
      'active',
    );
    await tester.tap(find.byKey(const ValueKey('project-place-trash')));
    await tester.pumpAndSettle();
    await select(tester, 'gone');
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(
      container.read(conversationWorkspaceProvider).stateOf('gone'),
      'active',
    );
    await tester.tap(find.byKey(const ValueKey('project-place-active')));
    await tester.pumpAndSettle();
    await select(tester, 'one');
    await tester.tap(find.widgetWithText(TextButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(
      container.read(conversationWorkspaceProvider).stateOf('one'),
      'archived',
    );
  });
  testWidgets('Trash permanently deletes only after confirmation', (
    tester,
  ) async {
    final container = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('project-place-trash')));
    await tester.pumpAndSettle();
    await select(tester, 'gone');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect((container.read(chatProvider.notifier) as _Chat).deleted, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((container.read(chatProvider.notifier) as _Chat).deleted, ['gone']);
  });

  testWidgets('mouse hover and right click expose the same row actions', (
    tester,
  ) async {
    final container = await mount(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(row('one')));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open'), findsOneWidget);
    expect(find.byTooltip('Move to project'), findsOneWidget);
    expect(find.byTooltip('Archive'), findsOneWidget);
    await tester.tap(row('one'), kind: PointerDeviceKind.mouse, buttons: 2);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, 'Open'), findsOneWidget);
    await tester.tap(find.widgetWithText(MenuItemButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(
      container.read(conversationWorkspaceProvider).stateOf('one'),
      'archived',
    );
  });

  testWidgets(
    'project editor creates, renames and removes projects with metadata',
    (tester) async {
      final container = await mount(tester);
      final t = AppLocalizationsEn();
      await tester.tap(find.text('New project'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, t.projectName),
        'Planning',
      );
      await tester.enterText(
        find.widgetWithText(TextField, t.projectInstructions),
        'Use concise answers.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, t.knowledgeCollectionName),
        'Reference',
      );
      await tester.tap(find.widgetWithText(FilledButton, t.save));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      final project = container
          .read(conversationWorkspaceProvider)
          .projects
          .last;
      expect(project.name, 'Planning');
      expect(project.instructions, 'Use concise answers.');
      expect(project.collection, 'Reference');
      await tester.tap(find.byKey(ValueKey('project-place-${project.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t.rename));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, t.projectName),
        'Plan',
      );
      await tester.tap(find.widgetWithText(FilledButton, t.save));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      final renamed = container
          .read(conversationWorkspaceProvider)
          .projects
          .last;
      expect(renamed.id, project.id);
      expect(renamed.name, 'Plan');
      expect(renamed.instructions, project.instructions);
      expect(renamed.collection, project.collection);
      await tester.tap(find.byTooltip(t.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, t.delete));
      await tester.pumpAndSettle();
      expect(
        container
            .read(conversationWorkspaceProvider)
            .projects
            .any((p) => p.id == project.id),
        isFalse,
      );
    },
  );
}
