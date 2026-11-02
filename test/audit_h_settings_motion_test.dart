import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';

Widget _app(Widget home, {MotionChoice motion = MotionChoice.full}) =>
    MaterialApp(
      theme: AppTheme.dark,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, page) => MotionScope(choice: motion, child: page!),
      home: home,
    );

void main() {
  testWidgets('marquee text stays still with Motion set to Off (P2-54)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SizedBox(
            width: 60,
            child: MarqueeText('A title far too long to fit in the row'),
          ),
        ),
        motion: MotionChoice.off,
      ),
    );
    await tester.pump();
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 3);
    expect(
      find.descendant(
        of: find.byType(MarqueeText),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });
}
