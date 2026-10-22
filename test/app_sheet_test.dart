import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/app_sheet.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';

Future<void> _open(
  WidgetTester tester, {
  bool actions = false,
  int rows = 1,
  MotionChoice motion = MotionChoice.off,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (_, child) => MotionScope(choice: motion, child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMorphSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AppSheet(
                title: 'A long sheet title that wraps onto more than one line',
                meta: 'Details',
                primary: actions
                    ? FilledButton(
                        key: const Key('primary'),
                        onPressed: () {},
                        child: const Text('Apply'),
                      )
                    : null,
                secondary: actions
                    ? TextButton(onPressed: () {}, child: const Text('Cancel'))
                    : null,
                children: [
                  for (var i = 0; i < rows; i++)
                    ListTile(title: Text('Row $i')),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sheet actions keep the app button theme, only taller pills', (
    tester,
  ) async {
    await _open(tester, actions: true);
    final button = find.byKey(const Key('primary'));
    final context = tester.element(button);
    final style = FilledButtonTheme.of(context).style!;
    final app = AppTheme.dark.filledButtonTheme.style!;
    expect(
      style.backgroundColor?.resolve({}),
      app.backgroundColor?.resolve({}),
    );
    expect(style.textStyle?.resolve({}), app.textStyle?.resolve({}));
    expect(style.shape?.resolve({}), isA<StadiumBorder>());
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
  });

  testWidgets('header renders, no action bar without actions, close pops', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Details'), findsOneWidget);
    expect(
      find.text('A long sheet title that wraps onto more than one line'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('app-sheet-actions')), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final motion in MotionChoice.values) {
    testWidgets('long body keeps actions above keyboard at ${motion.name}', (
      tester,
    ) async {
      await _open(tester, actions: true, rows: 40, motion: motion);
      final primary = find.byKey(const Key('primary'));
      final before = tester.getRect(primary);
      expect(before.bottom, lessThanOrEqualTo(915));
      expect(before.height, greaterThanOrEqualTo(48));
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      final after = tester.getRect(primary);
      expect(after.bottom, lessThanOrEqualTo(915 - 260));
      expect(before.bottom - after.bottom, closeTo(260, 1));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2400),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(primary), after);
      expect(tester.takeException(), isNull);
    });
  }
}
