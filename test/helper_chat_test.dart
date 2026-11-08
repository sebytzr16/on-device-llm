import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/chat/domain/entities/turn_run.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/helper/helper_runner.dart';
import 'package:ondevice_llm/features/helper/helper_jobs.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

import 'chat_test.dart' as fixtures;

class _Settings extends fixtures.TestSettings {
  final bool enabled;
  final String model;
  _Settings(this.enabled, [this.model = 'helper']);
  @override
  InferenceSettings build() => super.build().copyWith(
    toolsEnabled: enabled,
    toolHelper: true,
    helperModelId: model,
    toolWeb: false,
    wikipediaLookup: false,
  );
}

class _Helper extends HelperRunner {
  int calls = 0, cancellations = 0;
  final gates = <Completer<void>>[];
  final started = <String>[];
  String? message;
  _Helper()
    : super(
        engine: fixtures.TestEngine(),
        chatEngine: fixtures.TestEngine(),
        catalog: () => [],
        loadedModelId: () => null,
        settingsFor: (_) => const InferenceSettings(),
      );
  @override
  Future<HelperReply> run({
    required String modelId,
    required String task,
    String input = '',
    String? messageId,
    int? maxTokens,
    ToolRunner? webTools,
    InferenceSettings? agentSettings,
    Future<bool> Function(CancelToken)? approveWeb,
    CancelToken? cancel,
  }) async {
    calls++;
    started.add(task);
    if (gates.isNotEmpty) {
      final gate = gates[calls - 1];
      unawaited(
        cancel?.whenCancel.then((_) {
          cancellations++;
          if (!gate.isCompleted) gate.complete();
        }),
      );
      await gate.future;
      if (cancel?.isCancelled == true) {
        throw const HelperUnavailable('cancelled');
      }
    }
    message = messageId;
    return HelperReply(
      text: gates.isEmpty ? 'A helper result' : 'Result for $task',
      took: const Duration(seconds: 1),
      modelName: 'Helper',
    );
  }
}

class _NativeEngine extends fixtures.TestEngine {
  final choices = <String>[];
  _NativeEngine() {
    metrics = {'supportsTools': true};
  }
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    receivedTools = tools;
    receivedMessages = messages;
    choices.add(toolChoice);
    yield 'I will use the helper.';
  }
}

class _BackgroundEngine extends fixtures.TestEngine {
  int rounds = 0;
  final prompts = <List<Map<String, Object>>>[];
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    prompts.add(messages);
    rounds++;
    yield switch (rounds) {
      1 =>
        '<tool_call>{"name":"ask_helper","arguments":{"task":"first"}}</tool_call>'
            '<tool_call>{"name":"ask_helper","arguments":{"task":"second"}}</tool_call>',
      _ => 'The final answer',
    };
  }
}

class _EmptySynthesisEngine extends fixtures.TestEngine {
  final bool recover;
  int rounds = 0;
  final choices = <String>[];
  _EmptySynthesisEngine(this.recover) {
    metrics = {'supportsTools': true};
  }
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    rounds++;
    choices.add(toolChoice);
    if (rounds == 1) {
      yield "I've launched the helpers. Please share their replies.";
    } else {
      // The schema stays (prompt cache); the final round only forbids calls.
      expect(toolChoice, 'none');
      yield recover && rounds == 3
          ? 'Recovered final answer from the helper findings.'
          : rounds == 2
          ? '```json\n{"name":"search_web","arguments":{"query":"news"}}\n```'
          : '<think>Only thinking</think>';
    }
  }
}

class _SourceEmptyEngine extends fixtures.TestEngine {
  int calls = 0;
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    calls++;
    if (calls > 1) {
      expect(tools, isEmpty);
      expect(toolChoice, 'none');
    }
    yield '<think>Only thinking, no answer.</think>';
  }
}

class _SharedBackgroundEngine extends _BackgroundEngine {
  final sideGate = Completer<void>();
  int sideCalls = 0;
  _SharedBackgroundEngine() {
    metrics = {'backend': 'CUDA', 'gpuLayers': 43};
  }
  @override
  bool get isLoaded => true;
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    await for (final part in super.generate(
      messages: messages,
      fallbackTemplate: fallbackTemplate,
      settings: settings,
      assistantPrefix: assistantPrefix,
      tools: tools,
      toolChoice: toolChoice,
    )) {
      yield rounds == 1
          ? '$part<tool_call>{"name":"ask_helper","arguments":{"task":"third"}}</tool_call>'
          : part;
    }
  }

  @override
  Stream<String> generateSide({
    required String jobId,
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    void Function()? onStarted,
  }) async* {
    sideCalls++;
    onStarted?.call();
    await sideGate.future;
    sideMetrics[jobId] = {'tokens': 3, 'tokensPerSecond': 50};
    yield 'Shared result for ${messages.last['content']}';
  }
}

void main() {
  test(
    'empty source-based answer retries once and retains cited findings',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = _SourceEmptyEngine();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          settingsProvider.overrideWith(() => _Settings(false)),
          modelManagerProvider.overrideWith(fixtures.TestModels.new),
        ],
      );
      try {
        await container
            .read(chatProvider.notifier)
            .send(
              'Explain tides',
              promptOverride: 'Explain tides from the supplied report',
              answerSources: [
                const SearchResult(
                  title: 'Tides report',
                  url: 'https://example.org/tides',
                  snippet: 'Tides follow the gravitational pull of the Moon.',
                  rank: 1,
                ),
              ],
            );
        expect(engine.calls, 2);
        final answer = container.read(chatProvider).messages.last.content;
        expect(answer, contains('Tides report'));
        expect(answer, contains('gravitational pull'));
        expect(answer, contains('[1]'));
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );

  for (final recover in [true, false]) {
    test(
      'empty synthesis retries without tools then preserves evidence: $recover',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final helper = _Helper()..gates.add(Completer<void>());
        final engine = _EmptySynthesisEngine(recover);
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            llamaEngineProvider.overrideWithValue(engine),
            settingsProvider.overrideWith(() => _Settings(true)),
            modelManagerProvider.overrideWith(fixtures.TestModels.new),
            helperRunnerProvider.overrideWithValue(helper),
          ],
        );
        final partials = <String>[];
        final sub = container.listen(
          chatProvider,
          (_, next) => partials.add(next.partialAnswer),
        );
        try {
          final sent = container
              .read(chatProvider.notifier)
              .send('Use one helper to explain tides');
          for (var i = 0; i < 200 && helper.calls == 0; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(helper.calls, 1);
          expect(engine.rounds, 1);
          expect(partials.every((p) => p.isEmpty), isTrue);
          helper.gates.single.complete();
          await sent;
          expect(engine.rounds, 3);
          final answer = container.read(chatProvider).messages.last.content;
          expect(
            answer,
            contains(recover ? 'Recovered final answer' : 'Result for'),
          );
          expect(answer, isNot(contains('search_web')));
          expect(partials.join(), isNot(contains('Please share')));
        } finally {
          if (!helper.gates.single.isCompleted) helper.gates.single.complete();
          sub.close();
          container.dispose();
          helper.dispose();
          await db.close();
        }
      },
    );
  }

  test(
    'three shared GPU replies all reach the main final prompt and report to its answer',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'shared-helper-chat',
      );
      final file = await File(
        '${directory.path}/helper.gguf',
      ).writeAsString('test');
      final helperModel = ModelInfo(
        id: 'helper',
        displayName: 'Helper',
        fileName: 'helper.gguf',
        sizeBytes: 1,
        family: ModelFamily.qwen,
        quantization: ModelQuantization.q8_0,
        isDownloaded: true,
        localPath: file.path,
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = _SharedBackgroundEngine();
      late ProviderContainer container;
      final helper = HelperRunner(
        engine: fixtures.TestEngine(),
        chatEngine: engine,
        catalog: () => [fixtures.testModel, helperModel],
        loadedModelId: () => 'test',
        settingsFor: (_) => const InferenceSettings(),
        desktop: () => true,
        shareChat: false,
        publish: (job) =>
            container.read(helperJobsProvider.notifier).publish(job),
      );
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          settingsProvider.overrideWith(
            () => _Settings(true, HelperRunner.sameAsChat),
          ),
          modelManagerProvider.overrideWith(fixtures.TestModels.new),
          helperRunnerProvider.overrideWithValue(helper),
        ],
      );
      try {
        final sent = container
            .read(chatProvider.notifier)
            .send('Use three helpers for independent parts');
        for (var i = 0; i < 200 && engine.sideCalls < 3; ++i) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(engine.sideCalls, 3);
        expect(engine.rounds, 1);
        expect(container.read(helperStreamsProvider('test')), 3);
        final modelName = '${fixtures.testModel.displayName} (shared GPU)';
        expect(container.read(chatProvider).partialAnswer, isEmpty);
        engine.sideGate.complete();
        await sent;
        final answer = container.read(chatProvider).messages.last;
        final trace = TurnRun.decode(answer.runJson)!.toolTrace;
        expect(
          trace
              .where((r) => (r['call'] as Map)['name'] == 'ask_helper')
              .every(
                (r) => '${r['output']}'.contains('Helper model: $modelName'),
              ),
          isTrue,
        );

        final results = engine.prompts.last
            .where((m) => m['name'] == 'ask_helper')
            .toList();
        expect(results.length, 3);
        for (final task in ['first', 'second', 'third']) {
          expect(
            results.any(
              (m) => '${m['content']}'.contains('Shared result for $task'),
            ),
            isTrue,
          );
        }
        expect(
          container
              .read(helperJobsProvider)
              .jobs
              .every(
                (j) => j.phase == HelperPhase.done && j.reportedTo != null,
              ),
          isTrue,
        );
      } finally {
        if (!engine.sideGate.isCompleted) engine.sideGate.complete();
        helper.dispose();
        container.dispose();
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  for (final native in [false, true]) {
    test(
      'explicit helper request fires despite a model promising instead of calling (native=$native)',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final helper = _Helper();
        final engine = native ? _NativeEngine() : fixtures.TestEngine();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            llamaEngineProvider.overrideWithValue(engine),
            settingsProvider.overrideWith(() => _Settings(true)),
            modelManagerProvider.overrideWith(fixtures.TestModels.new),
            helperRunnerProvider.overrideWithValue(helper),
          ],
        );
        try {
          expect(
            await container
                .read(chatProvider.notifier)
                .send('Hi, use the sub-agent to write a title for these notes'),
            isTrue,
          );
          expect(helper.calls, 1);
          final answer = container.read(chatProvider).messages.last;
          expect(helper.message, answer.id);
          final trace = TurnRun.decode(answer.runJson)!.toolTrace;
          expect((trace.single['call'] as Map)['name'], 'ask_helper');
          expect(trace.single['ok'], isTrue);
          // Collaboration: the helper's reply is in the main model's next
          // prompt, so the main model writes the answer from it.
          expect(
            engine.receivedMessages!.map((m) => '${m['content']}').join(' '),
            contains('A helper result'),
          );
          if (engine is _NativeEngine) {
            expect(engine.choices.first, 'required');
            expect(
              engine.receivedTools.any((t) => t.name == 'ask_helper'),
              isTrue,
            );
          }
        } finally {
          container.dispose();
          helper.dispose();
          await db.close();
        }
      },
    );
  }

  test('other tool calls retain all four fallback helpers', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final helper = _Helper();
    final engine = fixtures.TestEngine()
      ..toolBlock =
          '<tool_call>{"name":"calculator","arguments":{"expression":"1+1"}}</tool_call>';
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(() => _Settings(true)),
        modelManagerProvider.overrideWith(fixtures.TestModels.new),
        helperRunnerProvider.overrideWithValue(helper),
      ],
    );
    try {
      await container
          .read(chatProvider.notifier)
          .send('Explain tides and use four agents to do that');
      expect(helper.calls, 4);
      final trace = TurnRun.decode(
        container.read(chatProvider).messages.last.runJson,
      )!.toolTrace;
      expect(
        trace.where((r) => (r['call'] as Map)['name'] == 'ask_helper'),
        hasLength(4),
      );
      expect(
        trace.where((r) => (r['call'] as Map)['name'] == 'calculator'),
        hasLength(1),
      );
    } finally {
      container.dispose();
      helper.dispose();
      await db.close();
    }
  });

  test('parallel helpers start together and report in call order', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final helper = _Helper()
      ..gates.addAll([Completer<void>(), Completer<void>()]);
    final engine = fixtures.TestEngine()
      ..toolBlock =
          '<tool_call>{"name":"ask_helper","arguments":{"task":"first"}}</tool_call>'
          '<tool_call>{"name":"ask_helper","arguments":{"task":"second"}}</tool_call>';
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(() => _Settings(true)),
        modelManagerProvider.overrideWith(fixtures.TestModels.new),
        helperRunnerProvider.overrideWithValue(helper),
      ],
    );
    try {
      final sent = container
          .read(chatProvider.notifier)
          .send('Use two helpers to draft independent titles');
      for (var i = 0; i < 100 && helper.calls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(helper.started, ['first', 'second']);
      helper.gates[1].complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(chatProvider).partialAnswer, isEmpty);
      helper.gates[0].complete();
      expect(await sent, isTrue);
      final replies = engine.receivedMessages!
          .where((m) => m['role'] == 'tool')
          .toList();
      expect(replies.length, 2);
      expect(replies[0]['content'], contains('Result for first'));
      expect(replies[1]['content'], contains('Result for second'));
      final trace = TurnRun.decode(
        container.read(chatProvider).messages.last.runJson,
      )!.toolTrace;
      expect(trace.map((r) => ((r['call'] as Map)['arguments'])), [
        '{"task":"first"}',
        '{"task":"second"}',
      ]);
      expect(
        engine.receivedMessages!.map((m) => m['content']).join(' '),
        contains('make N calls'),
      );
    } finally {
      for (final gate in helper.gates) {
        if (!gate.isCompleted) gate.complete();
      }
      container.dispose();
      helper.dispose();
      await db.close();
    }
  });

  for (final cancel in [false, true]) {
    test(
      'helpers block further generation until all settle (cancel=$cancel)',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final helper = _Helper()
          ..gates.addAll([Completer<void>(), Completer<void>()]);
        final engine = _BackgroundEngine();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            llamaEngineProvider.overrideWithValue(engine),
            settingsProvider.overrideWith(() => _Settings(true)),
            modelManagerProvider.overrideWith(fixtures.TestModels.new),
            helperRunnerProvider.overrideWithValue(helper),
          ],
        );
        try {
          final chat = container.read(chatProvider.notifier);
          final sent = chat.send('Use two helpers for independent parts');
          for (var i = 0; i < 200 && helper.calls < 2; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(helper.calls, 2);
          expect(helper.gates.every((g) => !g.isCompleted), isTrue);
          expect(engine.rounds, 1);
          expect(container.read(chatProvider).partialAnswer, isEmpty);
          if (cancel) {
            chat.cancel();
          } else {
            helper.gates[1].complete();
            helper.gates[0].complete();
          }
          await sent;
          if (cancel) {
            expect(helper.cancellations, 2);
            expect(engine.rounds, 1);
          } else {
            expect(engine.rounds, 2);
            final results = engine.prompts.last
                .where((m) => m['name'] == 'ask_helper')
                .toList();
            expect(
              results[0]['content'],
              contains(
                'Helper result (check it before you use it):\nHelper model: Helper\nResult for first',
              ),
            );
            expect(results[1]['content'], contains('Result for second'));
            final trace = TurnRun.decode(
              container.read(chatProvider).messages.last.runJson,
            )!.toolTrace;
            expect(trace, hasLength(2));
            expect(
              trace.take(2).every((r) => (r['elapsedMs'] as int) > 0),
              isTrue,
            );
          }
        } finally {
          container.dispose();
          helper.dispose();
          await db.close();
        }
      },
    );
  }

  test('explicit delegation respects the Tools off switch', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final helper = _Helper();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(fixtures.TestEngine()),
        settingsProvider.overrideWith(() => _Settings(false)),
        modelManagerProvider.overrideWith(fixtures.TestModels.new),
        helperRunnerProvider.overrideWithValue(helper),
      ],
    );
    try {
      await container
          .read(chatProvider.notifier)
          .send('Use the helper to write a title');
      expect(helper.calls, 0);
    } finally {
      container.dispose();
      helper.dispose();
      await db.close();
    }
  });
}
