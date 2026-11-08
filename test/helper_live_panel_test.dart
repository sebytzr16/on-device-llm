import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/core/design/app_design.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:ondevice_llm/features/helper/helper_jobs.dart';
import 'package:ondevice_llm/features/helper/helper_live_panel.dart';

HelperJob _job(
  String id, {
  HelperPhase phase = HelperPhase.generating,
  String? reason,
  String output = 'A useful result',
}) => HelperJob(
  id: id,
  task: 'Summarise the notes',
  inputPreview: 'Some notes',
  modelName: 'Small model',
  messageId: 'answer',
  phase: phase,
  reason: reason,
  output: output,
  thinking: 'Working through the notes',
  elapsed: const Duration(seconds: 2),
  firstToken: const Duration(milliseconds: 500),
  metrics: const {
    'tokens': 31,
    'promptTokens': 40,
    'tokensPerSecond': 20.0,
    'peakRssMb': 700,
  },
);

void main() {
  test(
    'tok/s uses inter-token time, handles zero duration and missing counters',
    () {
      expect(HelperJob.rate(31, const Duration(milliseconds: 1500)), 20);
      expect(HelperJob.rate(1, const Duration(seconds: 1)), 0);
      expect(HelperJob.rate(0, Duration.zero), 0);
      expect(HelperJob.rate(10, const Duration(microseconds: -1)), 0);
      expect(_job('one').tokensPerSecond, 20);
      const fallback = HelperJob(
        id: 'a',
        task: '',
        inputPreview: '',
        modelName: '',
        elapsed: Duration(seconds: 2),
        firstToken: Duration(milliseconds: 500),
        metrics: {'tokens': 31},
      );
      expect(fallback.tokensPerSecond, 20);
      const unknown = HelperJob(
        id: 'a',
        task: '',
        inputPreview: '',
        modelName: '',
      );
      expect(unknown.tokens, isNull);
      expect(unknown.tokensPerSecond, isNull);
    },
  );

  testWidgets(
    'unmeasured row stats use dashes and phase chips include timeouts',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final jobs = container.read(helperJobsProvider.notifier);
      jobs.publish(_job('one', phase: HelperPhase.done));
      jobs.publish(_job('two', phase: HelperPhase.timedOut));
      jobs.publish(
        const HelperJob(
          id: 'three',
          task: '',
          inputPreview: '',
          modelName: '',
          phase: HelperPhase.timedOut,
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: HelperLivePanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 agents'), findsOneWidget);
      expect(find.byTooltip('Agent 2 · Timed out'), findsOneWidget);
      await tester.tap(find.byKey(const Key('helper-live-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('— tok · — tok/s'), findsOneWidget);
      expect(find.textContaining('Unavailable'), findsNothing);
    },
  );

  testWidgets('shared jobs omit process RAM and load measurements', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: HelperJobCard(
              job: HelperJob(
                id: 'shared',
                task: 'Draft',
                inputPreview: '',
                modelName: 'Chat (shared GPU)',
                metrics: {
                  'sharedGpu': true,
                  'backend': 'CUDA (shared)',
                  'gpuLayers': 43,
                  'loadMs': 0,
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Backend: CUDA (shared)'), findsOneWidget);
    expect(find.textContaining('GPU layers: 43'), findsOneWidget);
    expect(find.textContaining('Peak RAM'), findsNothing);
    expect(find.textContaining('Load time'), findsNothing);
  });

  test('only the transition to all terminal collapses visible jobs', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final jobs = container.read(helperJobsProvider.notifier);
    jobs.publish(_job('one'));
    jobs.publish(_job('two'));
    jobs.publish(_job('one', phase: HelperPhase.failed));
    expect(container.read(helperJobsProvider).expanded, isTrue);
    jobs.publish(_job('two', phase: HelperPhase.cancelled));
    expect(container.read(helperJobsProvider).expanded, isFalse);
    jobs.toggle();
    jobs.publish(_job('two', phase: HelperPhase.cancelled));
    expect(container.read(helperJobsProvider).expanded, isTrue);
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets(
      'live panel appears, expands, collapses and dismisses at width $width',
      (tester) async {
        tester.view.reset();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: HelperLivePanel(),
                ),
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('helper-live-toggle')), findsNothing);
        final notifier = container.read(helperJobsProvider.notifier);
        notifier.publish(_job('one'));
        notifier.publish(_job('two', phase: HelperPhase.queued));
        await tester.pumpAndSettle();
        expect(find.text('2 agents'), findsOneWidget);
        expect(find.text('40.0 tok/s'), findsOneWidget);
        expect(find.text('A useful result'), findsNWidgets(2));
        // New work opens automatically; the user can still fold it.
        await tester.tap(find.byKey(const Key('helper-live-toggle')));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('helper-live-strip'))).height,
          lessThanOrEqualTo(56),
        );
        expect(find.text('Summarise the notes'), findsNothing);
        expect(find.byType(HelperJobCard), findsNothing);
        await tester.tap(find.byKey(const Key('helper-live-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('Summarise the notes'), findsNWidgets(2));
        expect(find.textContaining('31 tok'), findsNWidgets(2));
        expect(find.byType(HelperJobCard), findsNothing);
        await tester.tap(find.byKey(const Key('agent-details-one')));
        await tester.pumpAndSettle();
        expect(find.byType(HelperJobCard), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('A useful result'),
          ),
          findsOneWidget,
        );
        notifier.publish(_job('one', output: 'A streamed update'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('A streamed update'),
          ),
          findsOneWidget,
        );
        Navigator.of(tester.element(find.byType(HelperJobCard))).pop();
        await tester.pumpAndSettle();
        notifier.publish(_job('one', phase: HelperPhase.done));
        notifier.report('answer', 'Summarise the notes', 'Main model');
        await tester.pumpAndSettle();
        expect(find.text('20.0 tok/s'), findsOneWidget);
        expect(find.text('Summarise the notes'), findsNWidgets(2));
        notifier.publish(_job('two', phase: HelperPhase.done));
        await tester.pumpAndSettle();
        expect(find.text('Summarise the notes'), findsNothing);
        await tester.tap(find.byKey(const Key('helper-live-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('Summarise the notes'), findsNWidgets(2));
        await tester.tap(find.byKey(const Key('helper-live-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('Summarise the notes'), findsNothing);
        await tester.tap(find.byKey(const Key('helper-live-dismiss')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('helper-live-strip')), findsNothing);
        expect(container.read(helperJobsProvider).jobs.length, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'phone expansion is capped, scrolls and shows the failure reason',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(helperJobsProvider.notifier);
      notifier.publish(
        _job(
          'failed',
          phase: HelperPhase.failed,
          reason: 'Not enough memory for this agent',
        ),
      );
      for (var i = 0; i < 12; i++) {
        notifier.publish(_job('job-$i'));
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(12),
                child: HelperLivePanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('helper-live-strip'));
      expect(find.text('Not enough memory for this agent'), findsOneWidget);
      await tester.tap(find.byKey(const Key('helper-live-toggle')));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, lessThanOrEqualTo(56));
      expect(find.text('Not enough memory for this agent'), findsNothing);
      await tester.tap(find.byKey(const Key('helper-live-toggle')));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, lessThanOrEqualTo(844 * .4));
      final reason = tester.widget<Text>(
        find.text('Not enough memory for this agent'),
      );
      expect(reason.maxLines, 1);
      expect(reason.overflow, TextOverflow.ellipsis);
      expect(reason.style?.color, AppTheme.dark.extension<AppColors>()!.danger);
      await tester.scrollUntilVisible(
        find.byKey(const Key('helper-phone-row-job-11')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('helper-live-agents')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.byKey(const Key('helper-phone-row-job-11')))
            .overlaps(tester.getRect(panel)),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('helper-live-toggle')));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, lessThanOrEqualTo(56));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('four phone agents keep their live previews visible together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (var i = 0; i < 4; i++) {
      container
          .read(helperJobsProvider.notifier)
          .publish(
            _job('four-$i', output: 'Agent $i is writing a separate answer'),
          );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: HelperLivePanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byKey(const Key('helper-live-strip')));
    for (var i = 0; i < 4; i++) {
      final preview = tester.getRect(
        find.byKey(Key('helper-phone-output-four-$i')),
      );
      expect(preview.top, greaterThanOrEqualTo(panel.top));
      expect(preview.bottom, lessThanOrEqualTo(panel.bottom));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone previews stream, respect manual folding and reopen a fresh batch',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final jobs = container.read(helperJobsProvider.notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: HelperLivePanel()),
          ),
        ),
      );
      jobs.publish(_job('live', output: 'First words'));
      await tester.pumpAndSettle();
      expect(find.text('First words'), findsOneWidget);
      jobs.publish(_job('live', output: 'First words and more'));
      await tester.pumpAndSettle();
      expect(find.text('First words and more'), findsOneWidget);
      await tester.tap(find.byKey(const Key('helper-live-toggle')));
      await tester.pumpAndSettle();
      jobs.publish(_job('live', output: 'Still writing'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helper-live-agents')), findsNothing);
      jobs.publish(_job('live', phase: HelperPhase.done));
      jobs.publish(_job('next', output: 'Next task'));
      await tester.pumpAndSettle();
      expect(find.text('Next task'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'answer chip reopens retained details after dismissal with reduced motion',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(helperJobsProvider.notifier);
      notifier.publish(_job('one', phase: HelperPhase.done));
      notifier.dismiss();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChatBubble(
                  message: ChatMessage(
                    id: 'answer',
                    role: ChatRole.assistant,
                    content: 'Main answer',
                    timestamp: DateTime(2026),
                  ),
                  helperChip: const HelperUsedChip(messageId: 'answer'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Helper used'), findsOneWidget);
      await tester.tap(find.byKey(const Key('helper-used-answer')));
      await tester.pumpAndSettle();
      expect(find.byType(HelperJobCard), findsOneWidget);
      expect(find.text('Summarise the notes'), findsOneWidget);
      expect(find.text('A useful result'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
