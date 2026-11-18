import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';

void main() {
  for (final reduce in [false, true]) {
    testWidgets(
      'iOS suppresses page motion and keeps swipe back (system reduce: $reduce)',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: MotionScope(
                choice: reduce ? MotionChoice.full : MotionChoice.off,
                child: child!,
              ),
            ),
            home: const Scaffold(body: Text('First page')),
          ),
        );
        await tester.pumpAndSettle();
        final route = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Second page', key: Key('second'))),
          ),
        );
        unawaited(navigator.currentState!.push(route));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        final resting = tester.getTopLeft(find.byKey(const Key('second')));
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.getTopLeft(find.byKey(const Key('second'))), resting);
        await tester.pumpAndSettle();
        expect(route.popGestureEnabled, isTrue);
        await tester.dragFrom(const Offset(1, 300), const Offset(700, 0));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('second')), findsNothing);
        expect(find.text('First page'), findsOneWidget);
      },
    );
  }
}
