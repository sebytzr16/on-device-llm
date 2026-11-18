import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:drift/native.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/desktop_app.dart';
import 'package:ondevice_llm/desktop/keyboard_shortcuts.dart';
import 'package:ondevice_llm/desktop/launch_arguments.dart';
import 'package:ondevice_llm/desktop/title_bar.dart';
import 'package:ondevice_llm/desktop/sidebar.dart';

import 'support/desktop_chat_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(DesktopLaunchArguments.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  });

  test(
    'cold and forwarded args share a serialized GGUF import queue',
    () async {
      final paths = <String>[];
      final gate = Completer<void>();
      messenger.setMockMethodCallHandler(DesktopLaunchArguments.channel, (
        call,
      ) async {
        expect(call.method, 'getInitialArgs');
        return ['--flag', r'C:\Models\first file.GGUF', 'ignore.txt'];
      });
      final handler = DesktopLaunchArguments((path) async {
        paths.add(path);
        if (paths.length == 1) await gate.future;
      });
      final started = handler.start();
      await Future<void>.delayed(Duration.zero);
      expect(paths, [r'C:\Models\first file.GGUF']);
      final forwarded = messenger.handlePlatformMessage(
        DesktopLaunchArguments.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('launchArgs', [
            r'D:\Other\second.gguf',
            '--ignored',
          ]),
        ),
        (_) {},
      );
      expect(paths.length, 1);
      gate.complete();
      await started;
      await forwarded;
      expect(paths, [r'C:\Models\first file.GGUF', r'D:\Other\second.gguf']);
      handler.dispose();
      await handler.accept(['after-dispose.gguf']);
      expect(paths.length, 2);
    },
  );

  test(
    'an import failure does not discard the following launch argument',
    () async {
      final paths = <String>[];
      final handler = DesktopLaunchArguments((path) async {
        paths.add(path);
        if (paths.length == 1) throw StateError('invalid fixture');
      });
      await handler.accept(['broken.gguf', 'next.gguf', 42]);
      expect(paths, ['broken.gguf', 'next.gguf']);
      await handler.accept(null);
      handler.dispose();
    },
  );

  testWidgets('Ctrl+K focuses search after sidebar rename', (tester) async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    messenger.setMockMethodCallHandler(
      DesktopLaunchArguments.channel,
      (_) async => <String>[],
    );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final date = DateTime.utc(2026);
    await db.upsertChat(
      ChatsCompanion.insert(
        id: 'rename',
        title: 'Original',
        createdAt: date,
        updatedAt: date,
      ),
    );
    await db.upsertChat(
      ChatsCompanion.insert(
        id: 'newer',
        title: 'Newer',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await mountDesktopChat(
      tester,
      const DesktopShell(),
      shell: true,
      database: db,
    );
    await tester.tap(
      find.text('Original').last,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final menuFocus = Focus.of(tester.element(find.text('Rename')));
    menuFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(menuFocus.hasFocus, isTrue);
    final shortcutScope = tester.widget<DesktopShortcutScope>(
      find.byType(DesktopShortcutScope),
    );
    shortcutScope.restoreFocus!();
    await tester.pumpAndSettle();
    expect(menuFocus.hasFocus, isTrue);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final dialogField = tester.widget<TextField>(
      find.descendant(of: dialog, matching: find.byType(TextField)),
    );
    expect(dialogField.focusNode!.hasFocus, isTrue);
    shortcutScope.restoreFocus!();
    await tester.pumpAndSettle();
    expect(dialogField.focusNode!.hasFocus, isTrue);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'Renamed',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(() async {
      await db.watchAllChats().firstWhere(
        (rows) => rows.any((row) => row.title == 'Renamed'),
      );
    });
    await tester.pumpAndSettle();
    expect((await db.getChat('rename'))!.title, 'Renamed');
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final sidebar = tester.widget<DesktopSidebar>(find.byType(DesktopSidebar));
    expect(sidebar.searchFocus.hasFocus, isTrue);
    shortcutScope.restoreFocus!();
    await tester.pumpAndSettle();
    expect(sidebar.searchFocus.hasFocus, isTrue);

    final rowFocus = Focus.of(tester.element(find.text('Renamed')));
    rowFocus.requestFocus();
    await tester.pumpAndSettle();
    shortcutScope.restoreFocus!();
    await tester.pumpAndSettle();
    expect(rowFocus.hasPrimaryFocus, isTrue);

    // Cancellation uses the same shell recovery, without a transient row focus.
    await tester.tap(find.text('Renamed'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await db.getChat('rename'))!.title, 'Renamed');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(sidebar.searchFocus.hasFocus, isTrue);
  });

  testWidgets('Ctrl+/ dialog lists every actual shell binding', (tester) async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    messenger.setMockMethodCallHandler(
      DesktopLaunchArguments.channel,
      (_) async => <String>[],
    );
    await mountDesktopChat(tester, const DesktopShell(), shell: true);
    final scope = tester.widget<DesktopShortcutScope>(
      find.byType(DesktopShortcutScope),
    );
    final bindings = scope.shortcuts;
    expect(bindings.length, 13);
    expect(
      bindings.map((binding) => binding.keys).toSet().length,
      bindings.length,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopShortcutsDialog), findsOneWidget);
    for (final binding in bindings) {
      final dialog = find.byType(DesktopShortcutsDialog);
      expect(
        find.descendant(of: dialog, matching: find.text(binding.name)),
        findsWidgets,
      );
      expect(binding.name, isNot(contains('Ctrl+')));
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining(binding.keys),
        ),
        findsWidgets,
      );
    }
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    // Shortcuts keep working after the focused widget leaves the screen.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopShortcutsDialog), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    // Both traversal directions reach the model picker, sidebar and composer.
    for (final reverse in [false, true]) {
      final reached = <String>{};
      if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (var step = 0; step < 45; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        if (focusedContext == null) continue;
        focusedContext.visitAncestorElements((element) {
          if (element.widget is ModelPickerChip) reached.add('picker');
          if (element.widget is DesktopSidebar) reached.add('sidebar');
          if (element.widget is TextField &&
              (element.widget as TextField).maxLines != 1) {
            reached.add('composer');
          }
          return true;
        });
      }
      if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(reached, containsAll(['picker', 'sidebar', 'composer']));
    }
  });
}
