import 'dart:async';

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
