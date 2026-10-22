// The 2026-10-20 tidy rounds: behaviour kept while the code got cheaper.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/domain/answer_cleanup.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/memory/domain/user_memory.dart';
import 'package:ondevice_llm/features/memory/presentation/providers/memory_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

import 'chat_test.dart' show TestModels, TestSettings;
import 'package:ondevice_llm/features/chat/domain/chat_titles.dart';

class _TitledRemoteSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(
    autoTitles: true,
    memoryEnabled: true,
    remoteEnabled: true,
    remoteProfiles: const [
      RemoteProfile(
        id: 'test',
        name: 'Remote',
        baseUrl: 'https://example.com',
        model: 'fixture',
        shareMemory: true,
        learnMemory: true,
      ),
    ],
    remoteProfileId: 'test',
    remoteApiKeys: const {'test': 'fixture-key'},
  );
}

class _AnswerEngine extends RemoteEngine {
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    metrics = {'promptTokens': 40, 'tokens': 4};
    yield 'Nice hobby.';
  }
}

class _TitleAndNotesAdapter implements HttpClientAdapter {
  final requests = <Map<String, dynamic>>[];
  bool closed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(options.data as Map),
    );
    const reply =
        "TITLE: Restoring motorcycles\nNOTES:\n- The user's hobby is restoring motorcycles";
    final event = {
      'choices': [
        {
          'delta': {'content': reply},
          'finish_reason': 'stop',
        },
      ],
    };
    return ResponseBody.fromString(
      'data: ${jsonEncode(event)}\n\n',
      200,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  test('the streamed tail flags narration exactly like the whole answer', () {
    const answers = [
      'He is 32.\nThe user asked for his age, so I should answer briefly.',
      'Sunny, 20 °C [1].\nI should keep it short',
      'We need to keep it under 5 V.\nWe need to keep it cool too.',
      '\nThe user is asking',
      'It is 11 °C [1].\nTomorrow is clear',
      '   \n\nOkay, the user wants to know the time.',
      'Line one\n\nOkay, the user wants to know the time.',
      'No newline here, the user asked',
    ];
    final random = Random(7);
    for (final a in answers) {
      for (var run = 0; run < 20; run++) {
        final tail = AnswerTail();
        var at = 0;
        while (at < a.length) {
          final end = min(a.length, at + 1 + random.nextInt(6));
          tail.add(a.substring(at, end));
          at = end;
          expect(
            tail.narrating,
            AnswerCleanup.isNarrating(a.substring(0, at)),
            reason: '"${a.substring(0, at)}"',
          );
        }
      }
    }
  });

  test('a cleared tail starts again', () {
    final tail = AnswerTail()..add('Text.\nThe user asked for the time');
    expect(tail.narrating, isTrue);
    tail.clear();
    tail.add('The user asked for the time');
    expect(tail.narrating, isFalse);
  });

  group('one remote request for the title and the notes', () {
    test('the prompt carries the question, the notes and the rules', () {
      final prompt =
          ChatTitles.titleAndNotesMessages(
                'I restore motorcycles.',
                'Nice hobby.',
                notes: ['The user is a chef'],
              )[1]['content']
              as String;
      expect(prompt, contains('User: I restore motorcycles.'));
      expect(prompt, contains('Assistant: Nice hobby.'));
      expect(prompt, contains('- The user is a chef'));
      expect(prompt, contains('"""I restore motorcycles."""'));
      expect(prompt, contains(UserMemory.extractionRules));
      expect(prompt, contains('TITLE: <the title>\nNOTES:'));
    });

    test('the reply splits into a title and the note lines', () {
      var r = ChatTitles.splitTitleAndNotes(
        "TITLE: Restoring motorcycles\nNOTES:\n- The user's hobby is restoring motorcycles",
      );
      expect(r.title, 'Restoring motorcycles');
      expect(r.notes.trim(), "- The user's hobby is restoring motorcycles");

      r = ChatTitles.splitTitleAndNotes(
        '<think>hm</think>**TITLE:** Weekend plans\n\n**Notes:**\nNONE',
      );
      expect(r.title, 'Weekend plans');
      expect(r.notes.trim(), 'NONE');

      // No notes header: the notes are none, never the title line.
      r = ChatTitles.splitTitleAndNotes('Paris weather');
      expect(r.title, 'Paris weather');
      expect(r.notes, 'NONE');
    });

    test(
      'a first remote turn names the chat and learns in one request',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final main = _AnswerEngine();
        final adapter = _TitleAndNotesAdapter();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            remoteEngineProvider.overrideWithValue(main),
            remoteMemoryEngineFactoryProvider.overrideWithValue(
              () => RemoteEngine(
                dio: Dio()..httpClientAdapter = adapter,
                usage: main.usage,
              ),
            ),
            settingsProvider.overrideWith(_TitledRemoteSettings.new),
            modelManagerProvider.overrideWith(TestModels.new),
          ],
        );
        addTearDown(() async {
          container.dispose();
          main.dispose();
          await db.close();
        });
        await container
            .read(chatProvider.notifier)
            .send('My hobby is restoring motorcycles.');
        for (var i = 0; i < 150 && !adapter.closed; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(adapter.closed, isTrue);
        expect(container.read(chatProvider).error, isNull);
        expect(adapter.requests, hasLength(1));
        final chatId = container.read(chatProvider).chatId!;
        expect((await db.getChat(chatId))?.title, 'Restoring motorcycles');
        final notes = await container.read(memoryStoreProvider).all();
        expect(
          notes.map((n) => n.content),
          contains("The user's hobby is restoring motorcycles"),
        );
      },
    );
  });
}
