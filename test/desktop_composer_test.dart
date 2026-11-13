import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/desktop/chat_pane.dart';
import 'package:ondevice_llm/desktop/title_bar.dart';
import 'package:ondevice_llm/features/attachments/presentation/attachment_chips.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/presets/presentation/providers/presets_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/effective_settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';

import 'support/desktop_chat_harness.dart';

void main() {
  final t = AppLocalizationsEn();
  final send = find.byKey(const Key('send-stop'));
  Finder getField() => find.descendant(
    of: find.byType(DesktopChatPane),
    matching: find.byType(TextField),
  );

  Future<DesktopTestChat> mount(WidgetTester tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final container = await mountDesktopChat(
      tester,
      DesktopChatPane(composerFocus: focus),
    );
    return container.read(chatProvider.notifier) as DesktopTestChat;
  }

  testWidgets(
    'Enter sends typed text and clears the field; empty text disables send',
    (tester) async {
      final chat = await mount(tester);
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      await tester.enterText(getField(), '   ');
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(chat.sent, isEmpty);
      await tester.enterText(getField(), 'Explain local inference');
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chat.sent, ['Explain local inference']);
      expect(tester.widget<TextField>(getField()).controller!.text, isEmpty);
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      await tester.enterText(getField(), 'Send with the button');
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(chat.sent.last, 'Send with the button');
    },
  );

  testWidgets('Shift+Enter inserts a newline without sending', (tester) async {
    final chat = await mount(tester);
    await tester.enterText(getField(), 'First line');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    // Raw key events do not synthesize platform text input in widget tests.
    // Deliver the multiline edit that the platform sends for Shift+Enter.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'First line\n',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(chat.sent, isEmpty);
    expect(
      tester.widget<TextField>(getField()).controller!.text,
      'First line\n',
    );
  });

  testWidgets('rejected send restores the draft', (tester) async {
    final chat = await mount(tester)
      ..accepts = false;
    await tester.enterText(getField(), 'Keep this draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();
    expect(chat.sent, ['Keep this draft']);
    expect(
      tester.widget<TextField>(getField()).controller!.text,
      'Keep this draft',
    );
  });

  testWidgets(
    'generating shows stop and prevents Enter and drops; stop cancels',
    (tester) async {
      final chat = await mount(tester);
      chat.show(const ChatState(isGenerating: true, partialAnswer: 'Working'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.byTooltip('${t.stop} (Esc)'), findsOneWidget);
      expect(
        tester.widget<DropTarget>(find.byType(DropTarget)).enable,
        isFalse,
      );
      await tester.enterText(getField(), 'Wait for this');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(chat.sent, isEmpty);
      expect(
        tester.widget<TextField>(getField()).controller!.text,
        'Wait for this',
      );
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(chat.cancellations, 1);
      expect(find.byTooltip('${t.send} (Enter)'), findsOneWidget);
    },
  );

  testWidgets('footer meters known context tokens and clamps overflow', (
    tester,
  ) async {
    final chat = await mount(tester);
    chat.show(
      const ChatState(
        metrics: {'promptTokens': 768, 'tokens': 256, 'tokensPerSecond': 12.5},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip(t.desktopContextUsed(1024, 4096)), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.25,
    );
    expect(find.text(t.desktopTokensPerSecond('12.5')), findsOneWidget);
    chat.show(const ChatState(metrics: {'promptTokens': 5000, 'tokens': 1000}));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    chat.show(const ChatState());
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('preset, thinking, web and tool pills update their settings', (
    tester,
  ) async {
    await mount(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopChatPane)),
    );
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Concise'));
    await tester.pumpAndSettle();
    expect(container.read(presetsProvider).activeId, 'concise');
    expect(
      container.read(effectiveSettingsProvider).effective.temperature,
      0.3,
    );
    // Return to the neutral preset before cycling chat thinking.
    await tester.tap(find.text('Concise'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'General'));
    await tester.pumpAndSettle();
    for (final expected in [
      ThinkingLevel.low,
      ThinkingLevel.medium,
      ThinkingLevel.high,
      ThinkingLevel.off,
    ]) {
      await tester.tap(find.byIcon(Icons.psychology_outlined));
      await tester.pumpAndSettle();
      expect(
        container.read(effectiveSettingsProvider).effective.thinkingLevel,
        expected,
      );
    }
    expect(
      container.read(chatOverridesProvider).containsKey('thinkingBudgetTokens'),
      isFalse,
    );
    await tester.tap(find.text(t.webLocal));
    await tester.pumpAndSettle();
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, t.turnOn));
      await tester.pumpAndSettle();
    }
    expect(container.read(settingsProvider).webMode, WebMode.auto);
    expect(find.text(t.webAuto), findsOneWidget);
    await tester.tap(find.text(t.webAuto));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).webMode, WebMode.always);
    await tester.tap(find.text(t.webAlways));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).webMode, WebMode.off);
    expect(find.text(t.webLocal), findsOneWidget);
    await tester.tap(find.byIcon(Icons.build_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-tools-enabled')));
    await tester.pumpAndSettle();
    expect(container.read(chatOverridesProvider)['toolsEnabled'], isTrue);
    await tester.tap(find.byKey(const Key('quick-tool-calculator')));
    await tester.pumpAndSettle();
    expect(container.read(chatOverridesProvider)['toolCalculator'], isFalse);
    await tester.tap(find.byKey(const Key('quick-tools-enabled')));
    await tester.pumpAndSettle();
    expect(container.read(chatOverridesProvider)['toolsEnabled'], isFalse);
  });

  testWidgets('model picker opens its model menu without loading a bridge', (
    tester,
  ) async {
    final container = await mountDesktopChat(
      tester,
      const Center(child: ModelPickerChip()),
    );
    await tester.tap(find.text('Test Model'));
    await tester.pumpAndSettle();
    // draft.gguf is a speculative-decoding drafter: it cannot chat.
    expect(find.widgetWithText(MenuItemButton, 'Draft Model'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, t.desktopEject), findsOneWidget);
    await tester.tap(find.text('Test Model').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, t.desktopEject), findsNothing);
    expect(container.read(modelManagerProvider).loadedModelId, 'test');
  });

  for (final image in [false, true]) {
    testWidgets(
      'dropped ${image ? 'image' : 'document'} adds a removable chip and attachment-only send becomes ready',
      (tester) async {
        // Real file I/O runs outside fake async; the import itself is reached
        // through DropTarget's public callback rather than private widget state.
        final directory = Directory.systemTemp.createTempSync(
          'desktop-attachment-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => directory.path,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final name = image ? 'image.png' : 'notes.txt';
        final file = File(p.join(directory.path, name));
        if (image) {
          await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
            final picture = recorder.endRecording();
            final bitmap = await picture.toImage(2, 2);
            final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
            file.writeAsBytesSync(png!.buffer.asUint8List());
            bitmap.dispose();
            picture.dispose();
          });
        } else {
          file.writeAsStringSync('Reference text');
        }
        final chat = await mount(tester);
        final target = tester.widget<DropTarget>(find.byType(DropTarget));
        await tester.runAsync(() async {
          await (Function.apply(target.onDragDone!, [
                DropDoneDetails(
                  files: [DropItemFile(file.path, name: name)],
                  localPosition: Offset.zero,
                  globalPosition: Offset.zero,
                ),
              ])
              as Future<void>);
          if (image) {
            final stored = await Directory(
              p.join(directory.path, 'attachments'),
            ).list().toList();
            // One import leaves exactly one stored file; the OCR copy is
            // temporary and removed before the import completes.
            expect(stored, hasLength(1));
            await precacheImage(
              MemoryImage(await File(stored.single.path).readAsBytes()),
              tester.element(find.byType(DesktopChatPane)),
            );
          }
        });
        await tester.pumpAndSettle();
        final chips = tester.widget<AttachmentChips>(
          find.byType(AttachmentChips),
        );
        final attachment = chips.attachments.single;
        expect(attachment.name, name);
        expect(attachment.isImage, image);
        if (!image) expect(attachment.text, 'Reference text');
        expect(File(attachment.path).existsSync(), isTrue);
        expect(tester.widget<IconButton>(send).onPressed, isNotNull);
        // Exercise the real composer's attachment-only send path, then reject
        // the handoff so the restored chip can also be removed below.
        chat.accepts = false;
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(chat.sent, ['']);
        expect(chat.sentAttachments.single.single.id, attachment.id);
        expect(chat.sentAttachments.single.single.path, attachment.path);
        expect(find.byType(AttachmentChips), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AttachmentChips),
            matching: find.byIcon(image ? Icons.close : Icons.clear),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentChips), findsNothing);
        expect(tester.widget<IconButton>(send).onPressed, isNull);
      },
    );
  }
}
