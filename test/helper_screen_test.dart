import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/composer.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/helper/helper_web_approval.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/desktop/chat_pane.dart';
import 'package:ondevice_llm/features/chat/presentation/screens/chat_screen.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/helper/helper_jobs.dart';
import 'package:ondevice_llm/features/helper/helper_live_panel.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/domain/model_recommendations.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_recommendations_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

import 'chat_test.dart' as fixtures;

class _Settings extends fixtures.TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(
    toolsEnabled: true,
    toolHelper: true,
    helperModelId: 'helper',
    toolWeb: false,
    wikipediaLookup: false,
  );
}

class _Models extends fixtures.TestModels {
  final String path;
  _Models(this.path);
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(
      catalog: [
        fixtures.testModel,
        ModelInfo(
          id: 'helper',
          displayName: 'Helper',
          fileName: 'helper.gguf',
          sizeBytes: 1,
          family: ModelFamily.qwen,
          quantization: ModelQuantization.q4_k_m,
          isDownloaded: true,
          localPath: path,
        ),
      ],
      loadedModelId: 'test',
    );
  }
}

class _Recommendations extends ModelRecommendationsNotifier {
  @override
  Map<String, ModelRecommendation> build() => {};
}

class _HelperEngine extends fixtures.TestEngine {
  final gate = Completer<void>();
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    await gate.future;
    yield 'A useful helper reply';
  }
}

class _PhoneChat extends ChatNotifier {
  void showChat(String? id) => state = ChatState(chatId: id);

  @override
  ChatState build() => ChatState(
    chatId: 'phone-chat',
    messages: [
      ChatMessage(
        id: 'answer',
        role: ChatRole.assistant,
        content: 'The last message stays above the agents',
        timestamp: DateTime(2026),
      ),
    ],
  );
}

void main() {
  for (final nextChat in <String?>[null, 'other-chat']) {
    testWidgets('desktop clears helpers on navigation to $nextChat', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          chatProvider.overrideWith(_PhoneChat.new),
          settingsProvider.overrideWith(_Settings.new),
          modelManagerProvider.overrideWith(() => _Models('unused')),
          modelRecommendationsProvider.overrideWith(_Recommendations.new),
        ],
      );
      addTearDown(container.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final jobs = container.read(helperJobsProvider.notifier);
      jobs.publish(
        const HelperJob(
          id: 'background',
          task: 'Old chat work',
          inputPreview: '',
          modelName: 'Helper',
          messageId: 'answer',
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(body: DesktopChatPane(composerFocus: focus)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helper-side-column')), findsOneWidget);
      (container.read(chatProvider.notifier) as _PhoneChat).showChat(nextChat);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helper-side-column')), findsNothing);
      expect(container.read(helperJobsProvider).jobs.single.terminal, isFalse);
      jobs.publish(container.read(helperJobsProvider).jobs.single);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helper-side-column')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final allow in [true, false]) {
    testWidgets(
      'phone strip reserves chat space and approval can ${allow ? 'allow' : 'deny'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final previousDesktop = DesktopHost.active;
        DesktopHost.active = false;
        addTearDown(() => DesktopHost.active = previousDesktop);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            llamaEngineProvider.overrideWithValue(fixtures.TestEngine()),
            settingsProvider.overrideWith(_Settings.new),
            modelManagerProvider.overrideWith(() => _Models('unused')),
            modelRecommendationsProvider.overrideWith(_Recommendations.new),
            chatProvider.overrideWith(_PhoneChat.new),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await db.close();
        });
        final jobs = container.read(helperJobsProvider.notifier);
        jobs.publish(
          const HelperJob(
            id: 'one',
            task: 'A long task that should truncate on the phone',
            inputPreview: '',
            modelName: 'Helper',
            phase: HelperPhase.generating,
          ),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ChatScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final strip = find.byKey(const Key('helper-live-strip'));
        final composer = find.byType(ChatComposer);
        final lastMessage = find.text(
          'The last message stays above the agents',
        );
        final composerRect = tester.getRect(composer);
        // A running agent auto-opens the strip (f5ae144e,
        // docs/phone-agent-display-2026-11-03.md), capped at 40% of the screen.
        final opened = tester.getRect(strip);
        expect(opened.height, greaterThan(56));
        expect(opened.height, lessThanOrEqualTo(844 * .4));
        expect(opened.left, 12);
        expect(opened.right, 390 - 12);
        expect(opened.bottom, composerRect.top);
        expect(tester.getRect(composer), composerRect);
        expect(
          tester.getRect(lastMessage).bottom,
          lessThanOrEqualTo(opened.top),
        );
        // Folded, the strip is one low row pinned above the composer.
        await tester.tap(find.byKey(const Key('helper-live-toggle')));
        await tester.pumpAndSettle();
        final collapsed = tester.getRect(strip);
        expect(collapsed.height, lessThanOrEqualTo(56));
        expect(collapsed.left, 12);
        expect(collapsed.right, 390 - 12);
        expect(collapsed.bottom, composerRect.top);
        expect(tester.getRect(composer), composerRect);
        expect(
          tester.getRect(lastMessage).bottom,
          lessThanOrEqualTo(collapsed.top),
        );
        // Unfold again: the same geometry, and the composer never moves.
        await tester.tap(find.byKey(const Key('helper-live-toggle')));
        await tester.pumpAndSettle();
        expect(tester.getRect(strip), opened);
        final gate = container.read(agentWebApprovalProvider);
        final answer = gate.request(
          chatId: 'phone-chat',
          mode: AgentWebAccess.askOnce,
          read: () async => null,
          save: (_) async {},
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('agent-web-approval')), findsOneWidget);
        await tester.tap(
          find.byKey(Key(allow ? 'agent-web-allow' : 'agent-web-deny')),
        );
        await tester.pumpAndSettle();
        expect(await answer, allow);
        expect(find.byKey(const Key('agent-web-approval')), findsNothing);
        // Fold the auto-opened strip back to one row before tearing down.
        await tester.tap(find.byKey(const Key('helper-live-toggle')));
        await tester.pumpAndSettle();
        expect(tester.getSize(strip).height, lessThanOrEqualTo(56));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('real helper runner reaches ChatScreen and Windows chat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final previousDesktop = DesktopHost.active;
    DesktopHost.active = true;
    addTearDown(() => DesktopHost.active = previousDesktop);
    final directory = Directory.systemTemp.createTempSync('helper-screen');
    final file = File('${directory.path}/helper.gguf')
      ..writeAsStringSync('test');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final helper = _HelperEngine();
    final engine = fixtures.TestEngine()
      ..toolBlock =
          '<tool_call>{"name":"ask_helper","arguments":{"task":"Draft the design"}}</tool_call>';
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        helperEngineProvider.overrideWithValue(helper),
        settingsProvider.overrideWith(_Settings.new),
        modelManagerProvider.overrideWith(() => _Models(file.path)),
        modelRecommendationsProvider.overrideWith(_Recommendations.new),
      ],
    );
    final focus = FocusNode();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ChatScreen()),
        ),
      ),
    );
    late Future<bool> sent;
    await tester.runAsync(() async {
      sent = container
          .read(chatProvider.notifier)
          .send('Use a helper to draft a design');
    });
    for (
      var i = 0;
      i < 100 && container.read(helperJobsProvider).jobs.isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      container.read(helperJobsProvider).jobs,
      hasLength(1),
      reason:
          '${container.read(chatProvider).error} / ${container.read(chatProvider).notice}',
    );
    expect(find.byType(HelperJobCard), findsNothing);
    // The strip auto-opens when the agent starts; only tap if it is folded.
    if (find.text('Draft the design').evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('helper-live-toggle')));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Draft the design'), findsOneWidget);
    // The separate Windows pane used to omit both widgets.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DesktopChatPane(composerFocus: focus)),
        ),
      ),
    );
    // The column folds itself once the agent finishes, which on a slow
    // machine can happen before this point.
    if (!container.read(helperJobsProvider).expanded) {
      await tester.tap(find.byKey(const Key('helper-live-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    // Windows shows one small card per agent.
    expect(
      find.byKey(
        Key('agent-card-${container.read(helperJobsProvider).jobs.single.id}'),
      ),
      findsOneWidget,
    );
    // A thin column left of the conversation: it never covers the messages
    // or the composer, and folds to one row per helper.
    final column = tester.getRect(find.byKey(const Key('helper-side-column')));
    expect(
      column.right,
      lessThanOrEqualTo(tester.getRect(find.byType(TextField).last).left),
    );
    expect(column.width, lessThanOrEqualTo(HelperSideColumn.openWidth));
    await tester.tap(find.byKey(const Key('helper-live-toggle')));
    // One frame starts the width animation, the next one ends it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(
        Key('agent-card-${container.read(helperJobsProvider).jobs.single.id}'),
      ),
      findsNothing,
    );
    expect(find.textContaining('Agent 1 · '), findsOneWidget);
    expect(find.text('Draft the design'), findsOneWidget);
    await tester.tap(find.byKey(const Key('helper-live-toggle')));
    // One frame starts the width animation, the next one ends it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(
        Key('agent-card-${container.read(helperJobsProvider).jobs.single.id}'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        Key(
          'agent-details-${container.read(helperJobsProvider).jobs.single.id}',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HelperJobCard), findsOneWidget);
    Navigator.of(tester.element(find.byType(HelperJobCard))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    helper.gate.complete();
    var finished = false;
    unawaited(sent.then((_) => finished = true));
    for (var i = 0; i < 100 && !finished; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(finished, isTrue);
    await tester.pumpAndSettle();
    final answer = container.read(chatProvider).messages.last;
    expect(find.byKey(Key('helper-used-${answer.id}')), findsOneWidget);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ChatScreen()),
        ),
      ),
    );
    expect(find.byKey(Key('helper-used-${answer.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    focus.dispose();
    await tester.runAsync(db.close);
    directory.deleteSync(recursive: true);
  });
}
