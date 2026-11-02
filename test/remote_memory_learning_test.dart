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

/// Runs [during] while the answer streams, as a user flipping a switch.
class _RevokingEngine extends _PrivateRemoteEngine {
  void Function()? during;
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    during?.call();
    await Future<void>.delayed(Duration.zero);
    yield* super.generate(
      messages: messages,
      fallbackTemplate: fallbackTemplate,
      settings: settings,
      assistantPrefix: assistantPrefix,
      tools: tools,
      toolChoice: toolChoice,
    );
  }
}

/// Asks for one calculator round, flipping a switch while it does.
class _ToolRoundEngine extends RemoteEngine {
  final prompts = <List<Map<String, Object>>>[];
  void Function()? during;

  /// Runs while the second round's prompt is measured, after the tool ran
  /// and before that round is sent.
  void Function()? whileFitting;
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    if (prompts.length == 1) whileFitting?.call();
    await Future<void>.delayed(Duration.zero);
    return super.previewPrompt(
      messages: messages,
      fallbackTemplate: fallbackTemplate,
      settings: settings,
      assistantPrefix: assistantPrefix,
      tools: tools,
    );
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
    prompts.add(messages);
    final first = prompts.length == 1;
    if (first) during?.call();
    metrics = {
      'promptTokens': 40,
      'tokens': 4,
      'finishReason': first ? 'tool_calls' : 'eog',
      if (first)
        'toolCalls': [
          {
            'id': 'c1',
            'name': 'calculator',
            'arguments': {'expression': '12 * 3'},
          },
        ],
    };
    yield first ? '' : 'It is 36.';
  }
}

/// Runs [onRead] each time the notes are listed, as a user flipping a
/// switch while the app reads them.
class _WatchedStore extends MemoryStore {
  void Function()? onRead;
  _WatchedStore(super.db);
  @override
  Future<List<Memory>> all() async {
    final rows = await super.all();
    onRead?.call();
    return rows;
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
  for (final whileFitting in [false, true]) {
    test(
      'turning memory sharing off between tool rounds sends no second request '
      '(P2-15, ${whileFitting ? 'while the next prompt is fitted' : 'during the first round'})',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final engine = _ToolRoundEngine();
        const profile = RemoteProfile(
          id: 'test',
          name: 'Remote',
          baseUrl: 'https://example.com',
          providerId: 'lmstudio',
          model: 'fixture',
          shareMemory: true,
        );
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            remoteEngineProvider.overrideWithValue(engine),
            settingsProvider.overrideWith(
              () => RemoteMemoryTestSettings(profile),
            ),
            modelManagerProvider.overrideWith(TestModels.new),
          ],
        );
        addTearDown(() async {
          container.dispose();
          engine.dispose();
          await db.close();
        });
        // Pinned, so the note is in the first request's system prompt.
        final store = container.read(memoryStoreProvider);
        await store.pin(
          await store.add('The user buys 12 eggs every week'),
          true,
        );
        // The shared fixture asks for JSON, which offers no tools.
        await container
            .read(settingsProvider.notifier)
            .update(
              container
                  .read(settingsProvider)
                  .copyWith(responseFormat: ResponseFormat.text),
            );
        void revoke() {
          final settings = container.read(settingsProvider);
          container
              .read(settingsProvider.notifier)
              .update(
                settings.copyWith(
                  remoteProfiles: [profile.copyWith(shareMemory: false)],
                ),
              );
        }

        if (whileFitting) {
          engine.whileFitting = revoke;
        } else {
          engine.during = revoke;
        }
        await container
            .read(chatProvider.notifier)
            .send('How many eggs do I buy in 3 weeks? Use the calculator.');
        final first = jsonEncode(engine.prompts.first);
        expect(first, contains('12 eggs'), reason: 'the note was shared once');
        expect(engine.prompts, hasLength(1));
      },
    );
  }
  test(
    'turning sharing off while a batched title reads the notes sends none (P2-15)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final mainEngine = _PrivateRemoteEngine();
      final adapter = _MemoryAdapter('custom');
      final store = _WatchedStore(db);
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
          memoryStoreProvider.overrideWithValue(store),
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
          .read(settingsProvider.notifier)
          .update(container.read(settingsProvider).copyWith(autoTitles: true));
      await store.add('The user owns a red bicycle');
      // The answer is in; the batched title + memory request reads the
      // notes, and the user turns sharing off during that read.
      store.onRead = () {
        if (mainEngine.prompts.isEmpty) return;
        store.onRead = null;
        final settings = container.read(settingsProvider);
        container
            .read(settingsProvider.notifier)
            .update(
              settings.copyWith(
                remoteProfiles: [profile.copyWith(shareMemory: false)],
              ),
            );
      };
      await container
          .read(chatProvider.notifier)
          .send('I am a chef. My hobby is restoring motorcycles.');
      await _eventually(() => adapter.requests.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(jsonEncode(adapter.requests), isNot(contains('red bicycle')));
    },
  );
  test(
    'turning remote learning off while the answer streams sends no notes (P2-15)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final mainEngine = _RevokingEngine();
      final adapter = _MemoryAdapter('custom');
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
        container.dispose();
        mainEngine.dispose();
        await db.close();
      });
      mainEngine.during = () {
        final settings = container.read(settingsProvider);
        container
            .read(settingsProvider.notifier)
            .update(
              settings.copyWith(
                remoteProfiles: [profile.copyWith(learnMemory: false)],
              ),
            );
      };
      await container
          .read(chatProvider.notifier)
          .send('I am a chef. My hobby is restoring motorcycles.');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(adapter.requests, isEmpty);
      expect(await container.read(memoryStoreProvider).facts(), [
        'The user is a chef',
      ]);
    },
  );
}
