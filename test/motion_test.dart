import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/island/status_island.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/turn_phase.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/send_button.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

Widget _app(Widget child, {MotionChoice motion = MotionChoice.full}) =>
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        builder: (context, page) => MotionScope(
          choice: motion,
          child: Stack(children: [page!, const StatusIsland()]),
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    );

/// A box whose size the test changes.
class _Sized extends StatelessWidget {
  final double width;
  const _Sized(this.width);
  @override
  Widget build(BuildContext context) => SpringSize(
    key: const Key('spring'),
    child: SizedBox(width: width, height: 40),
  );
}

double _width(WidgetTester tester) =>
    tester.getSize(find.byKey(const Key('spring'))).width;

/// Chat state the test sets directly.
class _Chat extends ChatNotifier {
  @override
  ChatState build() {
    super.build();
    return const ChatState();
  }

  void set(ChatState next) => state = next;
}

void main() {
  testWidgets('ambient loops start on the shared clock and rest when off', (
    tester,
  ) async {
    final a = AnimationController(vsync: tester, duration: AppMotion.ambient);
    addTearDown(a.dispose);
    a.loopAmbient(animate: true);
    // Every loop starts where the one shared breath is now.
    final gap = (a.value - AppMotion.ambientPhase()).abs();
    expect(math.min(gap, 1 - gap), lessThan(0.02));
    expect(a.isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    a.loopAmbient(animate: false);
    expect(a.isAnimating, isFalse);
    expect(a.value, 0);
  });

  testWidgets('a glide jumps when motion is off', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: scroll,
          children: [for (var i = 0; i < 60; i++) Text('$i')],
        ),
      ),
    );
    unawaited(scroll.glideTo(300, const Motion(MotionChoice.off)));
    expect(scroll.offset, 300);
    unawaited(scroll.glideTo(0, const Motion(MotionChoice.full)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, inExclusiveRange(0, 300));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
  });

  testWidgets('a spring-sized box swells past its new size, then lands on it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Sized(100)));
    expect(_width(tester), 100);
    await tester.pumpWidget(_app(const _Sized(300)));
    var peak = 0.0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final w = _width(tester);
      if (w > peak) peak = w;
    }
    await tester.pumpAndSettle();
    expect(peak, greaterThan(303), reason: 'the house spring overshoots');
    expect(peak, lessThan(330), reason: 'by a few percent, not a wobble');
    expect(_width(tester), 300);
  });

  testWidgets('with motion off the box jumps straight to its size', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Sized(100), motion: MotionChoice.off));
    await tester.pumpWidget(_app(const _Sized(300), motion: MotionChoice.off));
    await tester.pump();
    expect(_width(tester), 300);
    expect(
      tester
          .renderObject<RenderSpringSize>(find.byKey(const Key('spring')))
          .isAnimating,
      isFalse,
    );
  });

  testWidgets('the blur switcher crossfades and sizes to the new child', (
    tester,
  ) async {
    Widget switcher(String text) => _app(
      BlurSwitcher(
        key: const Key('switch'),
        child: Text(text, key: ValueKey(text)),
      ),
    );
    await tester.pumpWidget(switcher('Short'));
    await tester.pumpWidget(switcher('A much longer label'));
    await tester.pump(const Duration(milliseconds: 60));
    // Both are on screen mid-crossfade; the size is already the new one.
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('A much longer label'), findsOneWidget);
    final size = tester.getSize(find.byKey(const Key('switch')));
    expect(size, tester.getSize(find.text('A much longer label')));
    await tester.pumpAndSettle();
    expect(find.text('Short'), findsNothing);
  });

  testWidgets('rolling digits settle on the new value', (tester) async {
    await tester.pumpWidget(_app(const RollingText('19.5 tok/s')));
    await tester.pumpWidget(_app(const RollingText('31.2 tok/s')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('31.2 tok/s'), findsOneWidget);
    // At rest each digit shows only itself.
    for (final digit in ['3', '1', '2']) {
      expect(find.text(digit), findsWidgets);
    }
    expect(find.text('9'), findsNothing);
  });

  testWidgets('an entrance plays once and ends at rest', (tester) async {
    await tester.pumpWidget(
      _app(const SpringEntrance(child: Text('Hello', key: Key('hello')))),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Hello'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, lessThan(1));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.text('Hello'),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
    );
  });

  testWidgets('streaming text reveals behind a soft edge, then settles', (
    tester,
  ) async {
    Widget reveal(String text) => _app(
      SizedBox(
        width: 240,
        child: StreamingReveal(
          active: true,
          revision: text.length,
          background: Colors.black,
          child: Text(text),
        ),
      ),
    );
    await tester.pumpWidget(reveal('Hello'));
    await tester.pumpWidget(
      reveal('Hello there, this answer wraps onto a second line and a third'),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0, reason: 'edge settled');
  });

  testWidgets('a toast grows on the island and goes away by itself', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    showIslandToast(context, 'Copied', tone: IslandTone.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('a toast with Undo stays longer and runs it once tapped', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    var undone = 0;
    showIslandToast(
      context,
      'Message deleted',
      action: IslandAction('Undo', () => undone++),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Past the plain toast's time, the button is still there to reach.
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('island-action')));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Message deleted'), findsNothing);
  });

  testWidgets('a busy island is a small pill with a spinner', (tester) async {
    // Regression: an indeterminate spinner once fed a null tween end, and the
    // release error box made the island springs toward 100 000 px tall.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, page) =>
              Stack(children: [page!, const StatusIsland()]),
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    final island = container.read(islandProvider.notifier);
    island.activity(const IslandMessage('Searching…', tone: IslandTone.busy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(SpringSize)).height, lessThan(56));

    island.activity(
      const IslandMessage(
        'Reading your message',
        tone: IslandTone.busy,
        progress: 0.4,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.text('Reading your message'), findsOneWidget);
    expect(tester.widget<RollingText>(find.byType(RollingText)).text, '40%');
    island.activity(null);
    await tester.pumpAndSettle();
  });

  testWidgets('without an island a toast falls back to a snackbar', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showIslandToast(context, 'Saved');
    await tester.pump();
    expect(find.widgetWithText(SnackBar, 'Saved'), findsOneWidget);
  });

  testWidgets('the send button morphs: arrow, stop, check, arrow', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [chatProvider.overrideWith(_Chat.new)],
    );
    addTearDown(container.dispose);
    Widget button({required bool busy}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: SendButton(
              busy: busy,
              ready: true,
              onSend: () {},
              onStop: () {},
            ),
          ),
        ),
      ),
    );
    IconData? icon() => tester
        .widget<Icon>(
          find
              .descendant(
                of: find.byKey(const Key('send-stop')),
                matching: find.byType(Icon),
              )
              .last,
        )
        .icon;

    await tester.pumpWidget(button(busy: false));
    expect(icon(), Icons.arrow_upward_rounded);

    final chat = container.read(chatProvider.notifier) as _Chat;
    chat.set(const ChatState(isGenerating: true));
    await tester.pumpWidget(button(busy: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(icon(), Icons.stop_rounded);
    expect(
      container.read(turnPhaseProvider).phase,
      TurnPhase.preparing,
      reason: 'no text and no reading progress yet',
    );

    chat.set(
      ChatState(
        messages: [
          ChatMessage(
            id: 'a',
            role: ChatRole.assistant,
            content: 'Done.',
            timestamp: DateTime(2026, 9, 26),
          ),
        ],
      ),
    );
    await tester.pumpWidget(button(busy: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      icon(),
      Icons.check_rounded,
      reason: 'a complete answer pops a check',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(icon(), Icons.arrow_upward_rounded);
  });

  test('turn phase follows reading progress, then the first text', () {
    final container = ProviderContainer(
      overrides: [
        chatProvider.overrideWith(_Chat.new),
        prefillProgressProvider.overrideWith(_Reading.new),
      ],
    );
    addTearDown(container.dispose);
    final chat = container.read(chatProvider.notifier) as _Chat;
    expect(container.read(turnPhaseProvider).phase, TurnPhase.idle);
    chat.set(const ChatState(isGenerating: true));
    expect(container.read(turnPhaseProvider), (
      phase: TurnPhase.reading,
      progress: 0.4,
    ));
    chat.set(const ChatState(isGenerating: true, partialAnswer: 'Hi'));
    expect(container.read(turnPhaseProvider).phase, TurnPhase.writing);
  });

  test('the motion choice survives a settings round trip', () {
    const settings = InferenceSettings(motion: MotionChoice.subtle);
    final back = InferenceSettings.fromJson(settings.toJson());
    expect(back.motion, MotionChoice.subtle);
    expect(
      InferenceSettings.fromJson(const {}).motion,
      MotionChoice.full,
      reason: 'full motion is the default',
    );
  });
}

class _Reading extends PrefillProgress {
  @override
  double? build() => 0.4;
}
