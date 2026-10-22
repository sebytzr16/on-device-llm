import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_markup.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

import 'chat_test.dart' show TestEngine, TestModels, TestSettings;
import 'package:ondevice_llm/features/chat/domain/answer_checks.dart';

class _Tools extends TestSettings {
  final int rounds;
  _Tools([this.rounds = 4]);
  @override
  InferenceSettings build() =>
      super.build().copyWith(toolsEnabled: true, toolMaxRounds: rounds);
}

/// A model with a native tool template: it writes Qwen-style call markup,
/// and the "bridge" reports the parsed calls and the text around them.
class _NativeEngine extends TestEngine {
  /// Calls the calculator whenever tools are offered.
  final bool alwaysCall;
  final requests =
      <
        ({
          List<Map<String, Object>> messages,
          List<ToolSpec> tools,
          String choice,
        })
      >[];
  _NativeEngine({this.alwaysCall = false}) {
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
    requests.add((
      messages: List.of(messages),
      tools: tools,
      choice: toolChoice,
    ));
    receivedMessages = messages;
    final hasResult = messages.any((m) => m['role'] == 'tool');
    if (toolChoice != 'none' &&
        tools.isNotEmpty &&
        (alwaysCall || !hasResult)) {
      yield 'Let me work that out. ';
      yield '<tool_call>\n{"name": "calculator", "arguments": {"expression": "6*7"}}\n</tool_call>';
      metrics = {
        'supportsTools': true,
        'toolContent': 'Let me work that out.',
        'toolCalls': [
          {
            'id': 'call_${requests.length}',
            'name': 'calculator',
            'arguments': '{"expression": "6*7"}',
          },
        ],
      };
      return;
    }
    metrics = {'supportsTools': true, 'toolCalls': const []};
    yield 'Six times seven is 42.';
  }
}

/// Writes chat where a call was required, then answers the result.
class _ChattyEngine extends _NativeEngine {
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    requests.add((
      messages: List.of(messages),
      tools: tools,
      choice: toolChoice,
    ));
    metrics = {'supportsTools': true, 'toolCalls': const []};
    yield messages.any((m) => m['role'] == 'tool')
        ? 'Your five-minute timer is ready.'
        : 'I can set a timer! 😊 </parameter></function></tool_call>';
  }
}

Future<(ProviderContainer, AppDatabase)> _container(
  TestEngine engine, {
  int rounds = 4,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      llamaEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(() => _Tools(rounds)),
      modelManagerProvider.overrideWith(TestModels.new),
      // "What is six times seven?" reads as encyclopedic; no archive here.
      zimWikipediaProvider.overrideWith((ref) async => null),
    ],
  );
  return (container, db);
}

class _PhoneEngine extends TestEngine {
  final requests = <({String system, List<ToolSpec> tools, String choice})>[];
  _PhoneEngine() {
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
    requests.add((
      system: '${messages.first['content']}',
      tools: tools,
      choice: toolChoice,
    ));
    if (toolChoice == 'required' && !messages.any((m) => m['role'] == 'tool')) {
      metrics = {
        'supportsTools': true,
        'toolContent': '',
        'toolCalls': [
          {'id': 'timer', 'name': 'set_timer', 'arguments': '{"minutes":5}'},
        ],
      };
      yield '<tool_call>{"name":"set_timer","arguments":{"minutes":5}}</tool_call>';
    } else {
      metrics = {'supportsTools': true, 'toolCalls': const []};
      yield toolChoice == 'none'
          ? 'Hello! How can I help?'
          : 'Your timer card is ready.';
    }
  }
}

void main() {
  test(
    'small talk after an action keeps the cached system schema without calling tools',
    () async {
      final engine = _PhoneEngine();
      final (container, db) = await _container(engine);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final chat = container.read(chatProvider.notifier);
      await chat.send('Set a timer for five minutes');
      final previous = engine.requests.last;
      await chat.send('Hello');
      final next = engine.requests.last;
      expect(next.system, previous.system);
      expect(next.tools.map((t) => t.name), previous.tools.map((t) => t.name));
      expect(next.choice, 'none');
      expect(
        container.read(chatProvider).messages.last.content,
        'Hello! How can I help?',
      );
    },
  );
  test('a native call is sent back once: structured, not as markup', () async {
    final engine = _NativeEngine();
    final (container, db) = await _container(engine);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container
        .read(chatProvider.notifier)
        .send('What is six times seven?');
    final second = engine.requests.last.messages;
    final call = second.lastWhere((m) => m['tool_calls'] != null);
    expect(call['content'], 'Let me work that out.');
    expect('${call['content']}', isNot(contains('<tool_call>')));
    expect(second.last['role'], 'tool');
    expect(second.last['content'], contains('42'));
    final answer = container.read(chatProvider).messages.last;
    expect(answer.content, 'Six times seven is 42.');
    expect(answer.reasoning, contains('▸ calculator'));
  });

  test('a spoken sum on the phone is said as the app worked it out', () async {
    // Phone probe round 3, 2026-10-18: given the result, the 0.8B still
    // added "You are from the UK… Your name is James".
    final engine = _NativeEngine();
    final (container, db) = await _container(engine);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final chat = container.read(chatProvider.notifier);
    await chat.send('What is fifteen plus twenty-seven?', spoken: true);
    expect(
      container.read(chatProvider).messages.last.content,
      '15 plus 27 is 42.',
    );
    await chat.send('Now double that.', spoken: true);
    expect(
      container.read(chatProvider).messages.last.content,
      '42 times 2 is 84.',
    );
    // A question that is not plain arithmetic keeps the model's answer.
    await chat.send('Why is the sky blue?', spoken: true);
    expect(
      container.read(chatProvider).messages.last.content,
      'Six times seven is 42.',
    );
  });

  test(
    'a spoken "what\'s my name?" on the phone is answered by the app',
    () async {
      final engine = _NativeEngine();
      final (container, db) = await _container(engine);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final chat = container.read(chatProvider.notifier);
      await chat.send('Hi, my name is Robin.', spoken: true);
      await chat.send("What's my name?", spoken: true);
      expect(
        container.read(chatProvider).messages.last.content,
        'Your name is Robin.',
      );
    },
  );

  test('a timer the model only talked about is prepared by the app', () async {
    // Phone probe round 4, 2026-10-18: Qwen3.5 0.8B wrote emoji and a
    // closing </tool_call> with no call, and no timer was set.
    final engine = _ChattyEngine();
    final (container, db) = await _container(engine);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container
        .read(chatProvider.notifier)
        .send('Set a timer for five minutes.', spoken: true);
    final results = engine.requests.last.messages.where(
      (m) => m['role'] == 'tool',
    );
    expect(results.map((m) => m['name']), ['set_timer']);
    final call = engine.requests.last.messages.lastWhere(
      (m) => m['tool_calls'] != null,
    );
    expect(call['content'], '', reason: 'the chat is not kept');
    expect('${call['tool_calls']}', contains('minutes'));
    expect(
      container.read(chatProvider).messages.last.content,
      'Your five-minute timer is ready.',
    );
  });

  test('a spoken answer that narrates the card is said by the app', () {
    expect(
      AnswerChecks.actionTalk(
        "The timer has been set for five minutes, and you've tapped 'Yes' "
        'to confirm.',
      ),
      isTrue,
    );
    expect(
      AnswerChecks.actionTalk('One. Two. Three. Four.'),
      isTrue,
      reason: 'a long reply to a timer is the model rambling',
    );
    expect(
      AnswerChecks.actionTalk(
        'Okay, I have set a timer for five minutes labeled "Boiling Eggs."',
      ),
      isTrue,
      reason: 'nothing is set until the card is tapped',
    );
    expect(
      AnswerChecks.actionTalk('Your five-minute timer is ready.'),
      isFalse,
    );
  });

  test('out of tool rounds, the model answers without tools', () async {
    final engine = _NativeEngine(alwaysCall: true);
    final (container, db) = await _container(engine, rounds: 1);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container
        .read(chatProvider.notifier)
        .send('What is six times seven?');
    final last = engine.requests.last;
    expect(last.tools, isNotEmpty, reason: 'the schema remains stable');
    expect(last.choice, 'none', reason: 'the final round disables tool use');
    expect(
      last.messages.last['content'],
      contains('No more tool calls are available'),
    );
    final answer = container.read(chatProvider).messages.last.content;
    expect(answer, 'Six times seven is 42.');
    expect(answer, isNot(contains('tool_call')));
  });

  group('ToolMarkup', () {
    test('strips every family of call markup', () {
      expect(
        ToolMarkup.strip(
          'Checking. <tool_call>{"name":"x","arguments":{}}</tool_call>',
        ),
        'Checking.',
      );
      expect(
        ToolMarkup.strip('<|tool_call>call:search{q:"a"}<tool_call|> done'),
        'done',
      );
      expect(ToolMarkup.strip('Sure [TOOL_CALLS][{"name":"x"}]'), 'Sure');
      expect(
        ToolMarkup.strip('A <function=search>{"q":"b"}</function> B'),
        'A  B',
      );
      expect(ToolMarkup.strip('No markup at all.'), 'No markup at all.');
    });

    test('a streaming answer hides a call, even one still arriving', () {
      expect(
        ToolMarkup.visible('Let me check. <tool_call>{"na'),
        'Let me check. ',
      );
      expect(ToolMarkup.visible('Let me check. <tool_c'), 'Let me check. ');
      expect(ToolMarkup.visible('Plain answer.'), 'Plain answer.');
    });
  });

  group('text protocol', () {
    test('parses fenced and tagged calls, several at once', () {
      final calls = TextToolProtocol.parse(
        'First\n```tool\n{"name": "search_web", "arguments": {"query": "a"}}\n```\n'
        '<tool_call>{"name": "calculator", "arguments": {"expression": "1+1"}}</tool_call>',
        counter: 3,
      );
      expect(calls.map((c) => c.name), ['search_web', 'calculator']);
      expect(calls.first.id, 'call_3');
      expect(calls.last.args['expression'], '1+1');
    });

    test('a JSON example in an answer is neither a call nor stripped', () {
      const answer =
          'Here is the config:\n```json\n{"port": 8080, "name": "demo"}\n```';
      expect(TextToolProtocol.parse(answer, counter: 1), isEmpty);
      expect(TextToolProtocol.strip(answer), answer);
    });
  });
}
