import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/memory/presentation/providers/memory_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

import 'chat_test.dart' show TestModels, TestSettings;

class _PrivateRemoteSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(
    memoryEnabled: true,
    remoteEnabled: true,
    remoteProfiles: const [
      RemoteProfile(
        id: 'test',
        name: 'Test remote',
        baseUrl: 'https://example.com',
        model: 'test',
      ),
    ],
    remoteProfileId: 'test',
  );
}

class _PrivateRemoteEngine extends RemoteEngine {
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
    metrics = {'promptTokens': 40, 'tokens': 4};
    yield 'Understood.';
  }
}

class RemoteMemoryTestSettings extends TestSettings {
  final RemoteProfile profile;
  RemoteMemoryTestSettings(this.profile);
  @override
  InferenceSettings build() => super.build().copyWith(
    memoryEnabled: true,
    remoteEnabled: true,
    remoteProfiles: [profile],
    remoteProfileId: profile.id,
    remoteApiKeys: {profile.id: 'fixture-key'},
    // Extraction must override chat-specific formats and tool settings.
    responseFormat: ResponseFormat.json,
    thinkingModeEnabled: true,
    toolsEnabled: true,
  );
}

class _MemoryAdapter implements HttpClientAdapter {
  final String provider;
  final Completer<void>? gate;
  final requests = <Map<String, dynamic>>[];
  bool closed = false;
  _MemoryAdapter(this.provider, {this.gate});
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
    if (gate != null) await gate!.future;
    const facts =
        "- The user's hobby is restoring motorcycles\n- The user's second hobby is woodworking\n- The user owns a Nikon Z30";
    final event = switch (provider) {
      'gemini' => {
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': facts},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      },
      'anthropic' => {
        'type': 'content_block_delta',
        'delta': {'type': 'text_delta', 'text': facts},
      },
      _ => {
        'choices': [
          {
            'delta': {'content': facts},
            'finish_reason': 'stop',
          },
        ],
      },
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

Future<void> _eventually(bool Function() condition) async {
  for (var i = 0; i < 150 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  test(
    'remote occupation capture stays local when remote sharing and learning are off',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = _PrivateRemoteEngine();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          remoteEngineProvider.overrideWithValue(engine),
          settingsProvider.overrideWith(_PrivateRemoteSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        engine.dispose();
        await db.close();
      });
      await container
          .read(memoryStoreProvider)
          .add('The user lives in a private city');
      final profile = container.read(settingsProvider).activeRemoteProfile!;
      expect(profile.shareMemory, isFalse);
      expect(profile.learnMemory, isFalse);
      await container
          .read(chatProvider.notifier)
          .send('Hi, I am a chef. What are you?');
      expect(container.read(chatProvider).error, isNull);
      expect(
        container.read(chatProvider).learned.single.content,
        'The user is a chef',
      );
      expect(
        engine.prompts,
        hasLength(1),
        reason: 'No remote extraction request',
      );
      expect(engine.prompts.single.toString(), isNot(contains('private city')));
      await container.read(chatProvider.notifier).send('What does a chef do?');
      expect(
        engine.prompts.last.first['content'],
        isNot(contains('The user is a chef')),
      );
      expect(await container.read(memoryStoreProvider).facts(), hasLength(2));
      await container
          .read(chatProvider.notifier)
          .send(
            "I'm a self-taught IT technician, and I'm building two apps at the moment.",
          );
      expect(
        await container.read(memoryStoreProvider).facts(),
        containsAll([
          'The user is a chef',
          'The user is a self-taught IT technician',
          'The user is building two apps',
        ]),
      );
      expect(
        engine.prompts,
        hasLength(3),
        reason: 'Each chat message has only its answer request',
      );
    },
  );
  for (final provider in ['custom', 'gemini', 'anthropic']) {
    test(
      '$provider background extraction stores grounded facts with provenance',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final mainEngine = _PrivateRemoteEngine();
        final adapter = _MemoryAdapter(provider);
        final profile = RemoteProfile(
          id: 'test',
          name: 'Remote',
          providerId: provider,
          baseUrl: 'https://example.com',
          model: provider == 'gemini' ? 'gemini-3.5-flash' : 'fixture-model',
          shareMemory: true,
          learnMemory: true,
        );
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            remoteEngineProvider.overrideWithValue(mainEngine),
            remoteMemoryEngineFactoryProvider.overrideWithValue(
              () => RemoteEngine(
                dio: Dio()..httpClientAdapter = adapter,
                usage: mainEngine.usage,
              ),
            ),
            settingsProvider.overrideWith(
              () => RemoteMemoryTestSettings(profile),
            ),
            modelManagerProvider.overrideWith(TestModels.new),
          ],
        );
        addTearDown(() async {
          container.dispose();
          mainEngine.dispose();
          await db.close();
        });
        await container
            .read(chatProvider.notifier)
            .send(
              'Hi, I am a chef. My hobby is restoring motorcycles. My second hobby is woodworking.',
            );
        await _eventually(() => adapter.closed);
        expect(container.read(chatProvider).error, isNull);
        final notes = await container.read(memoryStoreProvider).all();
        expect(
          notes.map((n) => n.content),
          unorderedEquals([
            'The user is a chef',
            "The user's hobby is restoring motorcycles",
            "The user's second hobby is woodworking",
          ]),
        );
        expect(
          notes.every(
            (n) =>
                n.sourceChatId == container.read(chatProvider).chatId &&
                n.sourceMessageId != null,
          ),
          isTrue,
        );
        expect(adapter.requests, hasLength(1));
        final request = adapter.requests.single;
        expect(request.toString(), isNot(contains('Understood.')));
        expect(request.containsKey('tools'), isFalse);
        expect(request.containsKey('response_format'), isFalse);
        if (provider == 'gemini') {
          expect(
            (request['generationConfig'] as Map)['responseMimeType'],
            isNot('application/json'),
          );
          expect((request['generationConfig'] as Map)['thinkingConfig'], {
            'thinkingLevel': 'minimal',
          });
        }
      },
    );
  }
  for (final permissions in [(false, false), (true, false), (false, true)]) {
    test('remote model extraction respects opt-ins $permissions', () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final mainEngine = _PrivateRemoteEngine();
      var backgroundCalls = 0;
      final profile = const RemoteProfile(
        id: 'test',
        name: 'Remote',
        baseUrl: 'https://example.com',
        model: 'fixture',
      ).copyWith(shareMemory: permissions.$1, learnMemory: permissions.$2);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          remoteEngineProvider.overrideWithValue(mainEngine),
          remoteMemoryEngineFactoryProvider.overrideWithValue(() {
            backgroundCalls++;
            return _PrivateRemoteEngine();
          }),
          settingsProvider.overrideWith(
            () => RemoteMemoryTestSettings(profile),
          ),
          modelManagerProvider.overrideWith(TestModels.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        mainEngine.dispose();
        await db.close();
      });
      await container
          .read(chatProvider.notifier)
          .send('I am a chef. My hobby is restoring motorcycles.');
      expect(backgroundCalls, 0);
      expect(await container.read(memoryStoreProvider).facts(), [
        'The user is a chef',
      ]);
    });
  }
  test(
    'turning Memory off during remote extraction prevents a late save',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final mainEngine = _PrivateRemoteEngine();
      final gate = Completer<void>();
      final adapter = _MemoryAdapter('custom', gate: gate);
      const profile = RemoteProfile(
        id: 'test',
        name: 'Remote',
        baseUrl: 'https://example.com',
        model: 'fixture',
        shareMemory: true,
        learnMemory: true,
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          remoteEngineProvider.overrideWithValue(mainEngine),
          remoteMemoryEngineFactoryProvider.overrideWithValue(
            () => RemoteEngine(
              dio: Dio()..httpClientAdapter = adapter,
              usage: mainEngine.usage,
            ),
          ),
          settingsProvider.overrideWith(
            () => RemoteMemoryTestSettings(profile),
          ),
          modelManagerProvider.overrideWith(TestModels.new),
        ],
      );
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        container.dispose();
        mainEngine.dispose();
        await db.close();
      });
      await container
          .read(chatProvider.notifier)
          .send('My hobby is restoring motorcycles.');
      await _eventually(() => adapter.requests.isNotEmpty);
      final settings = container.read(settingsProvider);
      await container
          .read(settingsProvider.notifier)
          .update(settings.copyWith(memoryEnabled: false));
      gate.complete();
      await _eventually(() => adapter.closed);
      expect(await container.read(memoryStoreProvider).facts(), isEmpty);
    },
  );
}
