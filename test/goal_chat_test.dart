import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/goals/presentation/goals_page.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart'
    show TestEngine, TestModels, TestReader, TestSearch, TestSettings;

class _WebOn extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(webMode: WebMode.auto);
}

void main() {
  late AppDatabase db;
  late TestEngine engine;
  late TestSearch search;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = TestEngine();
    search = TestSearch();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(_WebOn.new),
        modelManagerProvider.overrideWith(TestModels.new),
        duckDuckGoScraperProvider.overrideWithValue(search),
        webPageReaderProvider.overrideWithValue(TestReader()),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'a goal step: its own question, researched, alone in the prompt',
    () async {
      final n = container.read(chatProvider.notifier);
      await n.send('An earlier unrelated question');
      // A plain question with no timely wording: Auto alone would not search.
      await n.send(
        'Which electric cars sell most in Canada',
        forceResearch: true,
        isolated: true,
        extraSystem: 'You are working step by step on this goal: EV report',
      );
      expect(search.queries.last, 'Which electric cars sell most in Canada');
      final sent = engine.receivedMessages!;
      expect(sent.map((m) => m['role']), ['system', 'user']);
      expect(
        sent.first['content'],
        contains('working step by step on this goal'),
      );
      expect(sent.last['content'], contains('Question: Which electric cars'));
    },
  );

  test('the report: the prompt is replaced, the sources are stored', () async {
    final n = container.read(chatProvider.notifier);
    await n.send(
      'Write the final report',
      isolated: true,
      promptOverride: 'Findings: Tesla leads [1]. Write the report.',
      answerSources: const [
        SearchResult(
          title: 'EV sales 2026',
          url: 'https://cbc.ca/ev',
          snippet: '',
          rank: 1,
        ),
      ],
    );
    expect(search.calls, 0, reason: 'a report does no retrieval');
    expect(
      engine.receivedMessages!.last['content'],
      'Findings: Tesla leads [1]. Write the report.',
    );
    final state = container.read(chatProvider);
    expect(state.messages.first.content, 'Write the final report');
    final sources = jsonDecode(state.messages.last.sourcesJson) as List;
    expect(sources.single['url'], 'https://cbc.ca/ev');
  });

  test('goal progress round-trips through its saved form', () {
    final progress = GoalProgress(
      spec: const GoalSpec(objective: 'EV report', successCriteria: 'Prices'),
      status: GoalStatus.running,
      phase: GoalPhase.researching,
      steps: 1,
      startedAt: DateTime.utc(2026, 9, 23, 10),
      tasks: const [
        GoalTask('Q1?', status: GoalTaskStatus.done, findings: 'A [1].'),
        GoalTask('Q2?'),
      ],
      sources: const [GoalSource(title: 'T', url: 'https://t.example')],
      reviews: 1,
    );
    final back = GoalNotifier.decode(
      jsonDecode(jsonEncode(GoalNotifier.encode(progress, chatId: 'c1')))
          as Map<String, dynamic>,
    );
    expect(
      back.status,
      GoalStatus.paused,
      reason: 'a running goal resumes paused',
    );
    expect(back.tasks.map((t) => t.status), [
      GoalTaskStatus.done,
      GoalTaskStatus.pending,
    ]);
    expect(back.tasks.first.findings, 'A [1].');
    expect(back.sources.single.url, 'https://t.example');
    expect(back.reviews, 1);
    expect(back.nextTask!.question, 'Q2?');
    expect(back.spec.specialization, GoalSpecialization.general);
    final coded = GoalNotifier.decode(
      GoalNotifier.encode(
        progress.copyWith(
          spec: const GoalSpec(
            objective: 'Fix a Flutter build error',
            successCriteria: '',
            specialization: GoalSpecialization.code,
          ),
        ),
      ),
    );
    expect(coded.spec.specialization, GoalSpecialization.code);
  });

  test('the kind of research is guessed from the wording', () {
    GoalSpecialization g(String t) => GoalSpecialization.guess(t);
    expect(
      g('Why does my Flutter build throw this exception?'),
      GoalSpecialization.code,
    );
    expect(
      g('Prove that the square root of 2 is irrational'),
      GoalSpecialization.math,
    );
    expect(
      g('What do clinical studies say about intermittent fasting?'),
      GoalSpecialization.science,
    );
    expect(
      g('Compare the Pixel 10 and the Galaxy S26'),
      GoalSpecialization.product,
    );
    expect(
      g('What happened in the Canadian election?'),
      GoalSpecialization.news,
    );
    expect(g('Plan a three-day trip to Lisbon'), GoalSpecialization.general);
    // A long research request earns the "research as a goal" offer; a
    // question for one answer does not.
    expect(
      GoalSpecialization.looksLikeGoal(
        'Compare the three most popular electric cars in Canada for a family of four, with prices and range',
      ),
      true,
    );
    expect(GoalSpecialization.looksLikeGoal('Compare Rome and Paris'), false);
    expect(
      GoalSpecialization.looksLikeGoal(
        'What is the capital of Australia and why was it chosen over Sydney or Melbourne back then?',
      ),
      false,
    );
    // Every kind but General shapes the plan, the steps and the report.
    for (final k in GoalSpecialization.values.skip(1)) {
      expect(k.planHint, isNotEmpty, reason: k.name);
      expect(k.stepInstruction, isNotEmpty, reason: k.name);
      expect(k.reportFormat, isNot(GoalSpecialization.general.reportFormat));
    }
  });

  testWidgets('a finished goal shows its guardrails, checks and step details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final done = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        goalProvider.overrideWith(_FinishedGoal.new),
      ],
    );
    addTearDown(done.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: done,
        child: const MaterialApp(home: GoalsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('nikon z30'), findsOneWidget);
    expect(find.text('Prices in CAD'), findsOneWidget);
    expect(find.textContaining('Rewritten once'), findsOneWidget);
    final step = find.byKey(const Key('goal-task-1'));
    await tester.scrollUntilVisible(
      step,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(step);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Mentions ZV-E10 II'), findsOneWidget);
    expect(
      find.textContaining('nikon z30 vs sony zv-e10 video modes'),
      findsOneWidget,
    );
    expect(find.textContaining('calculator'), findsOneWidget);
    expect(find.textContaining('Researched again'), findsOneWidget);
    // The off-target step says it was left out of the report.
    await tester.scrollUntilVisible(
      find.byKey(const Key('goal-task-2')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-task-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('left out of the report'), findsOneWidget);
  });

  testWidgets('the goals page offers budgets and warns when web is off', (
    tester,
  ) async {
    final offline = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(offline.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: offline,
        child: const MaterialApp(home: GoalsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Web research is off'), findsOneWidget);
    expect(find.byKey(const Key('goal-kind-science')), findsOneWidget);
    // The budgets sit below the kinds of research now.
    await tester.scrollUntilVisible(
      find.byKey(const Key('goal-budget-quick')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('goal-budget-quick')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('goal-start')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('goal-budget-unlimited')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('goal-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-start')));
    await tester.pump();
    expect(find.text('Describe the goal first.'), findsOneWidget);
  });

  testWidgets('a goal opened from the chat arrives with its kind picked', (
    tester,
  ) async {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: GoalsPage(
            initialObjective: 'Fix a Kotlin build error',
            initialSpecialization: GoalSpecialization.code,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fix a Kotlin build error'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('goal-kind-code')),
    );
    expect(chip.selected, true);
    expect(find.text(GoalSpecialization.code.description), findsOneWidget);
    await tester.tap(find.byKey(const Key('goal-kind-math')));
    await tester.pump();
    expect(find.text(GoalSpecialization.math.description), findsOneWidget);
  });
}

class _FinishedGoal extends GoalNotifier {
  @override
  GoalProgress? build() => GoalProgress(
    spec: const GoalSpec(
      objective: 'Compare the nikon z30 to the sony zv-e10.',
      successCriteria: '',
      specialization: GoalSpecialization.product,
      terms: ['nikon z30', 'sony zv-e10'],
      rules: 'Prices in CAD\nOnly 2026 sources',
    ),
    status: GoalStatus.completed,
    phase: GoalPhase.done,
    steps: 2,
    startedAt: DateTime(2026, 9, 24),
    planNotes: 'Two named cameras: ask per criterion, naming both.',
    report: 'The **nikon z30** records 4K30 [1]; the **sony zv-e10** 4K30 [2].',
    reportChecks: const [GoalCheck(GoalCheckKind.revised)],
    sources: const [
      GoalSource(title: 'Nikon Z30 vs Sony ZV-E10', url: 'https://a.example/1'),
      GoalSource(title: 'Sony ZV-E10 review', url: 'https://b.example/2'),
    ],
    tasks: [
      GoalTask(
        'What video modes does the Nikon Z30 have compared to the Sony ZV-E10?',
        status: GoalTaskStatus.done,
        findings: 'The Z30 records 4K30 [1]. The ZV-E10 records 4K30 [2].',
        checks: const [
          GoalCheck(GoalCheckKind.drift, 'ZV-E10 II'),
          GoalCheck(GoalCheckKind.retried),
        ],
        trace: GoalTrace(
          queries: const ['nikon z30 vs sony zv-e10 video modes'],
          tools: const [
            {
              'name': 'calculator',
              'args': '{"expression":"3840/2160"}',
              'ok': true,
              'output': '1.7777',
            },
          ],
          sources: const [1, 2],
          reasoning: 'Both record 4K30; compare frame rates. ' * 20,
          promptTokens: 3200,
          tokens: 640,
          ms: 152000,
          attempts: 2,
          tokensPerSecond: 14.2,
        ),
      ),
      const GoalTask(
        'What is the price of the Sony ZV-E10 in Canada?',
        status: GoalTaskStatus.done,
        findings: 'The ZV-E10 II costs 1,099 CAD [3].',
        checks: [GoalCheck(GoalCheckKind.offTarget, 'ZV-E10 II')],
      ),
    ],
  );
}
