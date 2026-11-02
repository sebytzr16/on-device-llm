import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/app.dart';
import 'package:ondevice_llm/core/design/app_dialog.dart';
import 'package:ondevice_llm/core/motion/spring_routes.dart';

void main() {
  Future<FocusNode> pumpComposer(WidgetTester tester) async {
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [KeyboardGuard()],
        home: Scaffold(body: TextField(focusNode: focus)),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    return focus;
  }

  // The keyboard was down (no view insets) as each one opened, so closing it
  // must not hand focus back to the composer (owner's phone, 2026-11-01).
  testWidgets('closing a sheet does not refocus the composer', (tester) async {
    final focus = await pumpComposer(tester);
    final context = tester.element(find.byType(TextField));
    unawaited(
      showMorphSheet<void>(context: context, builder: (_) => const Text('s')),
    );
    await tester.pumpAndSettle();
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('closing a dialog does not refocus the composer', (tester) async {
    final focus = await pumpComposer(tester);
    final context = tester.element(find.byType(TextField));
    unawaited(
      showAppDialog<void>(context: context, builder: (_) => const Text('d')),
    );
    await tester.pumpAndSettle();
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('closing a menu does not refocus the composer', (tester) async {
    final focus = await pumpComposer(tester);
    final context = tester.element(find.byType(TextField));
    unawaited(
      showMenu<int>(
        context: context,
        position: const RelativeRect.fromLTRB(10, 10, 10, 10),
        items: const [PopupMenuItem(value: 1, child: Text('m'))],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 500));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
  });
}
