import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/app_dialog.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';

Widget _app(Widget child, MotionChoice choice, {bool reduce = false}) =>
    MaterialApp(
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: SpringPageTransitionsBuilder(),
            TargetPlatform.windows: SpringPageTransitionsBuilder(),
          },
        ),
      ),
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: MotionScope(choice: choice, child: page!),
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  for (final choice in MotionChoice.values) {
    testWidgets('$choice size motion has distinct timing and overshoot', (
      tester,
    ) async {
      Widget box(double width) => _app(
        SpringSize(
          key: const Key('box'),
          child: SizedBox(width: width, height: 40),
        ),
        choice,
      );
      await tester.pumpWidget(box(100));
      await tester.pumpWidget(box(300));
      await tester.pump();
      double width() => tester.getSize(find.byKey(const Key('box'))).width;
      if (choice == MotionChoice.off) {
        expect(width(), 300);
        expect(tester.binding.transientCallbackCount, 0);
      } else {
        expect(width(), lessThan(300));
        var peak = width();
        for (var i = 0; i < 24; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (width() > peak) peak = width();
          if (i == 9 && choice == MotionChoice.subtle) {
            expect(width(), 300);
            expect(tester.binding.transientCallbackCount, 0);
          }
        }
        expect(peak, choice == MotionChoice.full ? greaterThan(303) : 300);
      }
      await tester.pumpAndSettle();
    });

    testWidgets('$choice dialogs use spring, plain fade, or no transition', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('Dialog body')),
              ),
              child: const Text('Open'),
            ),
          ),
          choice,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final scales = find.ancestor(
        of: find.text('Dialog body'),
        matching: find.byType(ScaleTransition),
      );
      if (choice == MotionChoice.full) {
        expect(scales, findsOneWidget);
      } else {
        expect(scales, findsNothing);
        expect(
          ModalRoute.of(
            tester.element(find.text('Dialog body')),
          )!.animation!.isCompleted,
          isTrue,
        );
      }
      await tester.pumpAndSettle();
    });

    testWidgets('$choice pages use depth morph only at Full', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Next page')),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
          choice,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final text = find.text('Next page');
      if (choice == MotionChoice.full) {
        expect(tester.getTopLeft(text).dx, greaterThan(20));
      } else {
        expect(tester.getTopLeft(text).dx, closeTo(0, 0.01));
      }
      await tester.pumpAndSettle();
    });

    testWidgets('$choice sheets morph only at Full', (tester) async {
      final previous = DesktopHost.active;
      DesktopHost.active = false;
      addTearDown(() => DesktopHost.active = previous);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              key: const Key('source'),
              onPressed: () => showMorphSheet<void>(
                context: context,
                from: context,
                builder: (_) => const SizedBox(
                  width: 400,
                  height: 300,
                  child: Text('Sheet body'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
          choice,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final route = ModalRoute.of(tester.element(find.text('Sheet body')))!;
      expect(route.animation!.isCompleted, choice != MotionChoice.full);
      final slides = find.ancestor(
        of: find.text('Sheet body'),
        matching: find.byType(SlideTransition),
      );
      expect(
        slides,
        choice == MotionChoice.subtle ? findsOneWidget : findsNothing,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'OS reduce motion overrides Full and Subtle and stops size motion',
    (tester) async {
      for (final choice in [MotionChoice.full, MotionChoice.subtle]) {
        late Motion motion;
        Widget box(double width, bool reduce) => _app(
          Builder(
            builder: (context) {
              motion = context.motion;
              return SpringSize(
                key: const Key('size'),
                child: SizedBox(width: width, height: 40),
              );
            },
          ),
          choice,
          reduce: reduce,
        );
        await tester.pumpWidget(box(100, false));
        await tester.pumpWidget(box(300, false));
        await tester.pump(const Duration(milliseconds: 30));
        await tester.pumpWidget(box(300, true));
        expect(motion.choice, MotionChoice.off);
        expect(motion.fade(AppMotion.glide), Duration.zero);
        expect(tester.getSize(find.byKey(const Key('size'))).width, 300);
        expect(tester.binding.transientCallbackCount, 0);
      }
    },
  );
}
