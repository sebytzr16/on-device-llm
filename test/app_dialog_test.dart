import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/app_dialog.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';

/// Opens [ask] from a button and keeps what it returned in [result].
Future<void> _open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext context) ask,
  void Function(Object? value) result,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, page) =>
          MotionScope(choice: MotionChoice.off, child: page!),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result(await ask(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<String?> _name(BuildContext context, {String initial = ''}) =>
    promptText(
      context,
      title: 'Rename',
      initial: initial,
      confirmLabel: 'Save',
      confirmKey: const Key('ok'),
    );

void main() {
  testWidgets('validation keeps the prompt open and clears when edited', (
    tester,
  ) async {
    Object? value = 'unset';
    await _open(
      tester,
      (c) => promptText(
        c,
        title: 'Limit',
        initial: '8',
        confirmLabel: 'Save',
        allowEmpty: true,
        validate: (text) => text.isEmpty || int.tryParse(text) != null
            ? null
            : 'Invalid number',
      ),
      (v) => value = v,
    );
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(value, 'unset');
    expect(find.text('Invalid number'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' 12 ');
    await tester.pump();
    expect(find.text('Invalid number'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, '12');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(value, '');
  });

  testWidgets(
    'a prompt returns null on barrier dismissal and selects initial text',
    (tester) async {
      Object? value = 'unset';
      await _open(tester, (c) => _name(c, initial: 'Old'), (v) => value = v);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(value, isNull);
    },
  );

  testWidgets('a prompt returns the trimmed text and starts filled in', (
    tester,
  ) async {
    Object? value = 'unset';
    await _open(tester, (c) => _name(c, initial: 'Old'), (v) => value = v);
    expect(find.widgetWithText(TextField, 'Old'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  New name  ');
    await tester.tap(find.byKey(const Key('ok')));
    await tester.pumpAndSettle();
    expect(value, 'New name');
  });

  testWidgets('a prompt waits for text, submits on Enter, null on Cancel', (
    tester,
  ) async {
    Object? value = 'unset';
    await _open(tester, _name, (v) => value = v);
    final ok = tester.widget<FilledButton>(find.byKey(const Key('ok')));
    expect(ok.onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Typed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, 'Typed');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(value, isNull);
  });

  testWidgets('confirmAction is true only when confirmed', (tester) async {
    Object? value;
    await _open(
      tester,
      (c) => confirmAction(
        c,
        title: 'Delete?',
        message: 'Gone for good.',
        confirmLabel: 'Delete',
        destructive: true,
      ),
      (v) => value = v,
    );
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(value, isFalse);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
  });
}
