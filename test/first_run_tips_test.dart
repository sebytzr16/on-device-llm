import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/tips/tip_anchor.dart';
import 'package:ondevice_llm/core/tips/tips_store.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _harness(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.dark,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: SafeArea(
        child: SizedBox(
          width: 400,
          height: 600,
          // Target at the top so a bubble below it stays on screen.
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TipsNotifier.showInTests = true;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'TipAnchor shows title after pumpAndSettle; Got it hides it and marks seen',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          const TipAnchor(
            id: 'a',
            title: 'Title A',
            body: 'Body A',
            child: TextButton(
              key: Key('target-a'),
              onPressed: null,
              child: Text('Target'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsOneWidget);
      expect(find.text('Body A'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tip-got-it')));
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TipAnchor)),
      );
      final tips = container.read(tipsProvider);
      expect(tips.seen, contains('a'));
    },
  );

  testWidgets(
    'Two TipAnchors in one Column: only one bubble at a time; second appears after first dismissed',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          const Column(
            children: [
              TipAnchor(
                id: 'a',
                title: 'Title A',
                body: 'Body A',
                child: TextButton(
                  key: Key('target-a'),
                  onPressed: null,
                  child: Text('Target A'),
                ),
              ),
              TipAnchor(
                id: 'b',
                title: 'Title B',
                body: 'Body B',
                child: TextButton(
                  key: Key('target-b'),
                  onPressed: null,
                  child: Text('Target B'),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsOneWidget);
      expect(find.text('Title B'), findsNothing);

      await tester.tap(find.byKey(const Key('tip-got-it')));
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsNothing);
      expect(find.text('Title B'), findsOneWidget);
    },
  );

  testWidgets(
    'active: false shows nothing; rebuilding with active: true shows it',
    (tester) async {
      bool active = false;
      await tester.pumpWidget(
        _harness(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(
                  key: const Key('toggle'),
                  onPressed: () => setState(() => active = !active),
                  child: const Text('Toggle'),
                ),
                TipAnchor(
                  id: 'a',
                  title: 'Title A',
                  body: 'Body A',
                  active: active,
                  child: const TextButton(
                    key: Key('target-a'),
                    onPressed: null,
                    child: Text('Target'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsNothing);

      await tester.tap(find.byKey(const Key('toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsNothing);
    },
  );

  testWidgets(
    'actionLabel "Do it" + onAction callback: tapping tip-action calls callback once and marks seen',
    (tester) async {
      int actionCalls = 0;
      await tester.pumpWidget(
        _harness(
          TipAnchor(
            id: 'a',
            title: 'Title A',
            body: 'Body A',
            actionLabel: 'Do it',
            onAction: () => actionCalls++,
            child: const TextButton(
              key: Key('target-a'),
              onPressed: null,
              child: Text('Target'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tip-action')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Do it'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tip-action')));
      await tester.pumpAndSettle();

      expect(actionCalls, 1);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TipAnchor)),
      );
      final tips = container.read(tipsProvider);
      expect(tips.seen, contains('a'));

      // The tip is gone, so its action cannot run again.
      expect(find.byKey(const Key('tip-action')), findsNothing);
      expect(actionCalls, 1);
    },
  );

  testWidgets(
    'step (2, 5) with onSkipAll: tapping tip-skip-all calls onSkipAll',
    (tester) async {
      int skipCalls = 0;
      await tester.pumpWidget(
        _harness(
          TipAnchor(
            id: 'a',
            title: 'Title A',
            body: 'Body A',
            step: (2, 5),
            onSkipAll: () => skipCalls++,
            child: const TextButton(
              key: Key('target-a'),
              onPressed: null,
              child: Text('Target'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 of 5'), findsOneWidget);
      expect(find.byKey(const Key('tip-skip-all')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tip-skip-all')));
      await tester.pumpAndSettle();

      expect(skipCalls, 1);
      expect(find.text('Title A'), findsNothing);
    },
  );

  testWidgets('dismissLabel "Later" replaces the Got it text', (tester) async {
    await tester.pumpWidget(
      _harness(
        const TipAnchor(
          id: 'a',
          title: 'Title A',
          body: 'Body A',
          dismissLabel: 'Later',
          child: TextButton(
            key: Key('target-a'),
            onPressed: null,
            child: Text('Target'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-got-it')), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Later'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Got it'), findsNothing);
  });

  testWidgets(
    'Tapping the target child itself dismisses (dismissOnTargetTap default true)',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          const TipAnchor(
            id: 'a',
            title: 'Title A',
            body: 'Body A',
            child: TextButton(
              key: Key('target-a'),
              onPressed: null,
              child: Text('Target'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsOneWidget);

      await tester.tap(find.byKey(const Key('target-a')));
      await tester.pumpAndSettle();

      expect(find.text('Title A'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TipAnchor)),
      );
      final tips = container.read(tipsProvider);
      expect(tips.seen, contains('a'));
    },
  );
}
