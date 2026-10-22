import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

import 'chat_test.dart' show TestModels, TestSettings;
import 'package:ondevice_llm/features/chat/domain/turn_prompts.dart';

/// Decision 2026-10-18: with a remote connection, the remote model
/// decides whether to search and what to read; the app's keyword rules,
/// follow-up recall and yes/no judge stay out of its way.
class _Remote extends TestSettings {
  final bool serverSettings;
  final WebMode web;
  _Remote({this.serverSettings = true, this.web = WebMode.auto});
  @override
  InferenceSettings build() => super.build().copyWith(
    webMode: web,
    remoteEnabled: true,
    remoteProfiles: [
      RemoteProfile(
        id: 'laptop',
        name: 'Laptop',
        providerId: 'lmstudio',
        baseUrl: 'http://10.0.0.9:1234/v1',
        model: 'qwen3-32b',
        serverSettings: serverSettings,
      ),
    ],
    remoteProfileId: 'laptop',
    autoTitles: false,
  );
}

class _Call {
  final List<Map<String, Object>> messages;
  final InferenceSettings settings;
  final List<ToolSpec> tools;
  final String toolChoice;
  _Call(this.messages, this.settings, this.tools, this.toolChoice);
}

class _Engine extends RemoteEngine {
  final calls = <_Call>[];

  /// Scripted rounds, in order: each one's text and tool calls.
  final replies = <(String, List<Map<String, Object>>)>[];

  /// The server's speed, when a test sets one.
  double? rate;
  @override
  Future<void> learnWindow(InferenceSettings s) async {}
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    calls.add(_Call(messages, settings, tools, toolChoice));
    final (text, toolCalls) = replies.isEmpty
        ? ('It is cloudy in Toronto.', const <Map<String, Object>>[])
        : replies.removeAt(0);
    metrics = {
      'promptTokens': 40,
      'tokens': rate == null ? 4 : 80,
      'tokensPerSecond': ?rate,
      'finishReason': toolCalls.isEmpty ? 'eog' : 'tool_calls',
      if (toolCalls.isNotEmpty) 'toolCalls': toolCalls,
    };
    yield text;
  }
}

Future<(ProviderContainer, _Engine)> _start(_Remote settings) async {
  SharedPreferences.setMockInitialValues({});
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final engine = _Engine();
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      remoteEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(() => settings),
      modelManagerProvider.overrideWith(TestModels.new),
    ],
  );
  addTearDown(() async {
    container.dispose();
    engine.dispose();
    await db.close();
  });
  return (container, engine);
}

void main() {
  test(
    'a timely question goes to the remote model with the web tools',
    () async {
      final (container, engine) = await _start(_Remote());
      await container
          .read(chatProvider.notifier)
          .send("What's the weather in Toronto today?");
      expect(container.read(chatProvider).error, isNull);
      // No yes/no judge and no app search: one request, the answer's.
      expect(engine.calls, hasLength(1));
      final call = engine.calls.single;
      final names = call.tools.map((t) => t.name).toSet();
      expect(names, containsAll(['search_web', 'read_url']));
      expect(call.toolChoice, 'auto', reason: 'the model decides');
      final system = call.messages.first['content'] as String;
      expect(system, contains(TurnPrompts.remoteBrainText));
      expect(system, contains('Today is'));
      expect(system, isNot(contains('Live information is unavailable')));
      expect(call.settings.serverSampling, isTrue);
      expect(
        call.settings.toolMaxRounds,
        greaterThanOrEqualTo(TurnPrompts.remoteBrainRounds),
      );
      expect(
        container.read(chatProvider).messages.last.content,
        'It is cloudy in Toronto.',
      );
    },
  );

  test('Web always makes the first round call a tool', () async {
    final (container, engine) = await _start(_Remote(web: WebMode.always));
    await container
        .read(chatProvider.notifier)
        .send('Who won the last Formula 1 race?');
    expect(engine.calls.first.toolChoice, 'required');
  });

  test('a profile can keep the phone settings', () async {
    final (container, engine) = await _start(_Remote(serverSettings: false));
    await container
        .read(chatProvider.notifier)
        .send('Explain how a heat pump works.');
    expect(engine.calls.last.settings.serverSampling, isFalse);
  });

  test(
    'a spoken Conversation turn keeps the conversation and the brain',
    () async {
      // Phone test, 2026-10-18: Conversation uses the remote model, which must
      // remember what was said earlier (it forgot on the phone).
      final (container, engine) = await _start(_Remote());
      final chat = container.read(chatProvider.notifier);
      await chat.send('My name is Ana and I live in Lyon.', spoken: true);
      await chat.send(
        "What's the weather where I live today?",
        spoken: true,
        extraSystem: 'Answer in one to three short spoken sentences.',
        turnOverrides: const {'thinkingModeEnabled': false, 'maxTokens': 300},
      );
      final call = engine.calls.last;
      final said = call.messages.map((m) => '${m['content']}').join(' ');
      expect(said, contains('I live in Lyon'));
      expect(call.tools.map((t) => t.name), contains('search_web'));
      expect(
        call.messages.first['content'] as String,
        contains(TurnPrompts.remoteBrainText),
      );
      // The connection's own sampling and length, thinking still off.
      expect(call.settings.serverSampling, isTrue);
      expect(call.settings.thinkingModeEnabled, isFalse);
    },
  );

  test('"double that" gets the result the app worked out', () async {
    final (container, engine) = await _start(_Remote());
    final chat = container.read(chatProvider.notifier);
    await chat.send('What is fifteen plus twenty-seven?', spoken: true);
    String asked() => '${engine.calls.last.messages.last['content']}';
    expect(asked(), contains('= 42'));
    await chat.send('Now double that.', spoken: true);
    expect(asked(), contains('= 84'));
    // Spoken, the answer is the app's (round 5: "eighty-four doubled
    // again is one hundred sixty-eight").
    expect(
      container.read(chatProvider).messages.last.content,
      '42 times 2 is 84.',
    );
  });

  test('a remote model offering to read on is told to', () async {
    final (container, engine) = await _start(_Remote());
    engine.replies.addAll([
      (
        '',
        [
          {
            'id': 'c1',
            'name': 'calculator',
            'arguments': {'expression': '1 + 1'},
          },
        ],
      ),
      (
        'Several sites report the weather in Toronto today. Would you like '
            'the specific details from Environment Canada?',
        const [],
      ),
      ('It is 18 °C and sunny in Toronto.', const []),
    ]);
    await container
        .read(chatProvider.notifier)
        .send("What's the weather in Toronto today?", spoken: true);
    expect(engine.calls, hasLength(3));
    expect(
      '${engine.calls.last.messages.last['content']}',
      startsWith('Yes. Read the best source'),
    );
    final answer = container.read(chatProvider).messages.last.content;
    expect(answer, 'It is 18 °C and sunny in Toronto.');
  });

  test('a remote answer pointing at sources is told to read one', () async {
    final (container, engine) = await _start(_Remote());
    engine.replies.addAll([
      (
        '',
        [
          {
            'id': 'c1',
            'name': 'calculator',
            'arguments': {'expression': '1 + 1'},
          },
        ],
      ),
      (
        'You can check Environment Canada for detailed hourly forecasts '
            '[1]. Temperatures and conditions are all available right now.',
        const [],
      ),
      ('It is eighteen degrees and sunny in Toronto.', const []),
    ]);
    await container
        .read(chatProvider.notifier)
        .send("What's the weather in Toronto today?", spoken: true);
    expect(engine.calls, hasLength(3));
    expect(
      '${engine.calls.last.messages.last['content']}',
      startsWith('Read the best page now'),
    );
    expect(
      container.read(chatProvider).messages.last.content,
      'It is eighteen degrees and sunny in Toronto.',
    );
  });

  test('a changing figure given from nothing is looked up first', () async {
    final (container, engine) = await _start(_Remote());
    engine.replies.addAll([
      ('Tomorrow in Rome it will be sunny and twenty-eight degrees.', const []),
      (
        '',
        [
          {
            'id': 'c1',
            'name': 'calculator',
            'arguments': {'expression': '1 + 1'},
          },
        ],
      ),
      ('It will be twenty-four degrees and cloudy.', const []),
    ]);
    await container
        .read(chatProvider.notifier)
        .send('And what about tomorrow in Rome?', spoken: true);
    expect(engine.calls, hasLength(3));
    expect(
      '${engine.calls[1].messages.last['content']}',
      startsWith('Search first'),
    );
    expect(
      container.read(chatProvider).messages.last.content,
      'It will be twenty-four degrees and cloudy.',
    );
  });

  test('a slower server is not called a hot phone', () async {
    // Remote probe, 2026-10-18: "Speed dropped 48% (117.3 → 60.6 tok/s).
    // The phone may be throttling" on LM Studio's turns.
    final (container, engine) = await _start(_Remote());
    final chat = container.read(chatProvider.notifier);
    engine.rate = 117;
    await chat.send('Tell me a short joke.');
    engine.rate = 60;
    await chat.send('Another one, please.');
    expect(container.read(chatProvider).notice ?? '', isNot(contains('%')));
  });

  test('a phone-only turn never reaches the remote model', () async {
    final (container, engine) = await _start(_Remote());
    await container
        .read(chatProvider.notifier)
        .send('Hello there', localOnly: true, spoken: true);
    expect(engine.calls, isEmpty);
  });
}
