import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/helper/helper_tool_loop.dart';
import 'package:ondevice_llm/features/helper/helper_web_approval.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/effective_settings_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

class FakeAgentTools extends ToolRunner {
  final calls = <ToolCall>[];
  FakeAgentTools({bool enabled = true})
    : super(
        scraper: DuckDuckGoScraper(),
        reader: WebPageReader(),
        settings: InferenceSettings(
          webMode: enabled ? WebMode.auto : WebMode.off,
        ),
        webOnly: true,
      );

  @override
  Future<ToolResult> run(ToolCall call) async {
    calls.add(call);
    return ToolResult(
      call: call,
      output: 'Evidence ${'x' * 20000}',
      ok: true,
      elapsedMs: 7,
    );
  }
}

class _Chat extends ChatNotifier {
  @override
  ChatState build() => const ChatState(chatId: 'chat');
}

void main() {
  for (final fenced in [true, false]) {
    test(
      'helper executes JSON calls and receives the current date: $fenced',
      () async {
        final tools = FakeAgentTools();
        final loop = HelperToolLoop(tools: tools);
        var rounds = 0;
        final answer = await loop.run(
          task: 'Latest news',
          input: 'Provided task context',
          settings: const InferenceSettings(
            agentWebAccess: AgentWebAccess.alwaysAllow,
          ).forAgent(),
          generate: (messages) async {
            final today = DateTime.now().toIso8601String().substring(0, 10);
            expect(messages.first['content'], contains('Today is $today'));
            if (rounds++ > 0) return 'The result from the evidence.';
            const call =
                '{"name":"web_search","arguments":{"q":"latest news"}}';
            return fenced ? '```json\n$call\n```' : call;
          },
        );
        expect(tools.calls.single.name, 'search_web');
        expect(tools.calls.single.args['query'], 'latest news');
        expect(answer, 'The result from the evidence.');
      },
    );
  }
  test(
    'unanswered approval expires without persisting denial or leaking a call',
    () async {
      Map<String, AgentWebQuestion> pending = {};
      var saved = false;
      final gate = AgentWebApproval(
        timeout: const Duration(milliseconds: 10),
        changed: (value) => pending = value,
      );
      final tools = FakeAgentTools();
      final loop = HelperToolLoop(
        tools: tools,
        approve: () => gate.request(
          chatId: 'chat',
          mode: AgentWebAccess.askOnce,
          read: () async => null,
          save: (_) async {
            saved = true;
          },
        ),
      );
      var rounds = 0;
      final answer = await loop.run(
        task: 'Summarise',
        input: 'The supplied report says revenue rose.',
        settings: const InferenceSettings().forAgent(),
        generate: (_) async {
          rounds++;
          return '```json\n{"name":"search_web","arguments":{"query":"news"}}\n```';
        },
      );
      expect(rounds, 3);
      expect(answer, contains('revenue rose'));
      expect(answer, isNot(contains('search_web')));
      expect(tools.calls, isEmpty);
      expect(saved, isFalse);
      expect(pending, isEmpty);
      gate.dispose();
    },
  );

  test('chat settings edits preserve the host-owned web decision', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.upsertChat(
      ChatsCompanion.insert(
        id: 'chat',
        title: 'Chat',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final decisions = AgentWebDecisions(db);
    await decisions.write('chat', true);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chatProvider.overrideWith(_Chat.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatProvider.notifier).setChatOverrides({
      'temperature': .4,
      agentWebDecisionKey: false,
    });
    expect(await decisions.read('chat'), true);
    expect(container.read(chatOverridesProvider), {'temperature': .4});
    await container.read(chatProvider.notifier).setChatOverrides({});
    expect(await decisions.read('chat'), true);
  });

  test('parallel helper rounds obey the configured concurrency cap', () async {
    final release = Completer<void>();
    var active = 0, peak = 0, started = 0;
    final runner = ToolRunner(
      scraper: DuckDuckGoScraper(),
      reader: WebPageReader(),
      settings: const InferenceSettings(),
      helperMaxConcurrent: 2,
      helperOwnsDeadline: true,
      helper: (task, input) async {
        started++;
        active++;
        if (active > peak) peak = active;
        await release.future;
        active--;
        return 'Done';
      },
    );
    final calls = [
      for (var i = 0; i < 5; i++)
        runner.run(
          ToolCall(id: '$i', name: 'ask_helper', arguments: '{"task":"Check"}'),
        ),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(started, 2);
    release.complete();
    await Future.wait(calls);
    expect(peak, 2);
    expect(started, 5);
  });

  test(
    'agent parses aliases, runs web tools, trims context and records calls',
    () async {
      final tools = FakeAgentTools();
      final activity = <String?>[];
      final loop = HelperToolLoop(
        tools: tools,
        approve: () async => true,
        activity: activity.add,
      );
      var round = 0;
      final answer = await loop.run(
        task: 'Check the release',
        input: 'input ' * 5000,
        settings: const InferenceSettings().forAgent(),
        generate: (messages) async {
          final bytes = messages.fold<int>(
            0,
            (n, m) => n + utf8.encode(m['content'] as String).length,
          );
          expect(bytes, lessThanOrEqualTo(4096 - 512 - 256));
          if (round == 1) {
            expect(messages.last['content'], contains('Evidence'));
          }
          return switch (round++) {
            0 =>
              '<tool_call>{"name":"web_search","arguments":{"q":"release"}}</tool_call>',
            1 =>
              '```tool\n{"name":"open_url","arguments":{"link":"https://example.org/release"}}\n```',
            _ => 'The checked answer.',
          };
        },
      );
      expect(answer, 'The checked answer.');
      expect(tools.calls.map((c) => c.name), ['search_web', 'read_url']);
      expect(loop.trace.length, 2);
      expect(loop.trace.first.output.length, lessThan(6000));
      expect(
        activity,
        containsAll(['approval', 'search:release', 'read:example.org']),
      );
    },
  );

  test('denial continues without a network call or another approval', () async {
    final tools = FakeAgentTools();
    var asks = 0, rounds = 0;
    final loop = HelperToolLoop(
      tools: tools,
      approve: () async {
        asks++;
        return false;
      },
    );
    final answer = await loop.run(
      task: 'Check',
      input: '',
      settings: const InferenceSettings().forAgent(),
      generate: (messages) async {
        if (rounds++ == 0) {
          return '```tool\n{"name":"search_web","arguments":{"query":"x"}}\n```';
        }
        expect(messages.first['content'], contains('unavailable'));
        expect(messages.last['content'], contains('unavailable'));
        return 'I can continue offline.';
      },
    );
    expect(answer, 'I can continue offline.');
    expect(asks, 1);
    expect(tools.calls, isEmpty);
    expect(loop.trace.single.ok, false);
  });

  for (final enabled in [false, true]) {
    test('agent web gate enabled=$enabled and the round cap hold', () async {
      final tools = FakeAgentTools(enabled: enabled);
      final loop = HelperToolLoop(tools: tools);
      var rounds = 0;
      await loop.run(
        task: 'Check',
        input: '',
        settings: const InferenceSettings(
          agentWebAccess: AgentWebAccess.alwaysAllow,
          agentToolRounds: 2,
        ).forAgent(),
        generate: (messages) async {
          rounds++;
          return '```tool\n{"name":"search_web","arguments":{"query":"x"}}\n```';
        },
      );
      expect(tools.calls.length, enabled ? 2 : 0);
      expect(rounds, enabled ? 4 : 2);
    });
  }

  test('unknown tools and calls inside thinking never execute', () async {
    final tools = FakeAgentTools();
    final loop = HelperToolLoop(tools: tools);
    final answer = await loop.run(
      task: 'Check',
      input: '',
      settings: const InferenceSettings().forAgent(),
      generate: (_) async =>
          '<think><tool_call>{"name":"search_web","arguments":{"query":"x"}}</tool_call></think>Done',
    );
    expect(answer, 'Done');
    expect(tools.calls, isEmpty);
  });

  for (final allow in [true, false]) {
    test(
      'approval once per chat, persistence and concurrent waiters: $allow',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.upsertChat(
          ChatsCompanion.insert(
            id: 'chat',
            title: 'Chat',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        final decisions = AgentWebDecisions(db);
        Map<String, AgentWebQuestion> pending = {};
        final gate = AgentWebApproval(changed: (value) => pending = value);
        Future<bool> ask(AgentWebApproval gate) => gate.request(
          chatId: 'chat',
          mode: AgentWebAccess.askOnce,
          read: () => decisions.read('chat'),
          save: (allow) => decisions.write('chat', allow),
        );
        final first = ask(gate), second = ask(gate);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(pending.length, 1);
        expect(pending['chat']!.waiters, 2);
        gate.answer('chat', allow);
        expect(await Future.wait([first, second]), [allow, allow]);
        expect(pending, isEmpty);
        gate.dispose();
        final reopened = AgentWebApproval(changed: (value) => pending = value);
        expect(await ask(reopened), allow);
        expect(pending, isEmpty);
        expect(await decisions.read('chat'), allow);
        reopened.dispose();
      },
    );
  }

  test(
    'cancelled waiter leaves another waiting; cancelling all removes the card',
    () async {
      Map<String, AgentWebQuestion> pending = {};
      final gate = AgentWebApproval(changed: (value) => pending = value);
      final first = CancelToken(), second = CancelToken();
      var saved = 0;
      Future<bool> ask(CancelToken token) => gate.request(
        chatId: 'chat',
        mode: AgentWebAccess.askOnce,
        read: () async => null,
        save: (_) async {
          saved++;
        },
        cancel: token,
      );
      final a = expectLater(ask(first), throwsA(isA<DioException>()));
      final b = expectLater(ask(second), throwsA(isA<DioException>()));
      await Future<void>.delayed(Duration.zero);
      first.cancel();
      await a;
      expect(pending['chat']!.waiters, 1);
      second.cancel();
      await b;
      expect(pending, isEmpty);
      expect(saved, 0);
      gate.dispose();
    },
  );

  test('always and never bypass the per-chat question', () async {
    final gate = AgentWebApproval(changed: (_) => fail('No question expected'));
    for (final mode in [AgentWebAccess.alwaysAllow, AgentWebAccess.never]) {
      final result = await gate.request(
        chatId: 'chat',
        mode: mode,
        read: () async => throw StateError('No read'),
        save: (_) async => fail('No save'),
      );
      expect(result, mode == AgentWebAccess.alwaysAllow);
    }
    gate.dispose();
  });
}
