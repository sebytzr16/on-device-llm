import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/domain/conversation_workspace.dart';
import 'package:ondevice_llm/features/memory/presentation/providers/memory_provider.dart';
import 'package:ondevice_llm/features/presets/domain/preset.dart';
import 'package:ondevice_llm/features/presets/presentation/providers/presets_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

import 'chat_test.dart' show TestEngine, TestSettings, testModel;

class _Settings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(
    toolsEnabled: true,
    toolChoice: ToolChoice.required,
    thinkingModeEnabled: true,
    promptCache: true,
  );
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(catalog: [testModel]);
  }
}

typedef _Request = ({
  List<Map<String, Object>> messages,
  List<ToolSpec> tools,
  InferenceSettings settings,
  String choice,
});

class _Engine extends TestEngine {
  int loads = 0;
  bool busy = false, loaded = false, omitEmpty = false, broken = false;
  bool fail = false;
  Completer<void>? primeGate;
  final primeStarted = Completer<void>();
  final requests = <_Request>[];
  final previewsOf = <String>[];
  @override
  bool get isLoaded => loaded;
  @override
  bool get isBusy => busy && !isPriming;
  @override
  int get loadCount => loads;

  @override
  Future<void> loadModel({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    if (loaded &&
        loadedWith != null &&
        LlamaEngine.loadConfig(settings: loadedWith!) ==
            LlamaEngine.loadConfig(settings: settings)) {
      return;
    }
    loadedWith = settings;
    loaded = true;
    loads++;
    metrics = {'supportsTools': true, 'supportsThinking': true};
  }

  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    final user = messages.last['content'] as String;
    previewsOf.add(user);
    final system = messages.first['content'];
    return {
      'fits': true,
      'formattedPrompt': broken
          ? 'no user content'
          : omitEmpty && user.isEmpty
          ? '<system>$system</system><assistant>'
          : '<system>$system</system><user>$user</user><assistant>',
    };
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
      messages: messages,
      tools: tools,
      settings: settings,
      choice: toolChoice,
    ));
    busy = true;
    try {
      if (settings.maxTokens == 1) {
        if (!primeStarted.isCompleted) primeStarted.complete();
        if (primeGate != null) await primeGate!.future;
        if (fail) throw StateError('prime failure');
        metrics = {'promptTokens': 700};
      }
      yield 'Rainbows form when light refracts through water droplets.';
    } finally {
      busy = false;
    }
  }

  @override
  void cancel() {
    stopped = true;
    if (primeGate != null && !primeGate!.isCompleted) primeGate!.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ProviderContainer container;
  late _Engine engine;

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> load() async {
    await container.read(modelManagerProvider.notifier).loadModel(testModel);
    await settle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DesktopHost.active = true;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = _Engine();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(_Settings.new),
        modelManagerProvider.overrideWith(_Models.new),
      ],
    );
    container.read(chatProvider);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    DesktopHost.active = false;
  });

  test(
    'load primes once with the first ordinary turn system and tools',
    () async {
      final before = container.read(chatProvider);
      await load();
      expect(engine.requests, hasLength(1));
      final prime = engine.requests.single;
      expect(prime.messages.map((m) => m['role']), ['system', 'user']);
      expect(prime.messages.last['content'], '');
      expect(prime.settings.maxTokens, 1);
      expect(prime.settings.thinkingModeEnabled, isTrue);
      expect(prime.tools, isNotEmpty);
      expect(prime.choice, 'required');
      expect(identical(container.read(chatProvider), before), isTrue);
      expect(await db.select(db.messages).get(), isEmpty);
      expect(engine.metrics, {'supportsTools': true, 'supportsThinking': true});
      await container.read(chatProvider.notifier).primeLoadedModel(testModel);
      expect(engine.requests, hasLength(1));

      expect(
        await container
            .read(chatProvider.notifier)
            .send('Explain how a rainbow forms.'),
        isTrue,
      );
      final real = engine.requests.firstWhere((r) => r.settings.maxTokens != 1);
      expect(prime.messages.first, real.messages.first);
      expect(
        prime.tools.map((t) => t.toJson()).toList(),
        real.tools.map((t) => t.toJson()).toList(),
      );
      expect(
        prime.settings.thinkingModeEnabled,
        real.settings.thinkingModeEnabled,
      );
      expect(prime.choice, real.choice);
    },
  );

  test('a real turn cancels priming and proceeds', () async {
    engine.primeGate = Completer<void>();
    await load();
    await engine.primeStarted.future.timeout(const Duration(seconds: 5));
    expect(engine.busy, isTrue);
    expect(
      await container
          .read(chatProvider.notifier)
          .send('Explain how a rainbow forms.'),
      isTrue,
    );
    expect(engine.stopped, isTrue);
    expect(engine.requests.any((r) => r.settings.maxTokens != 1), isTrue);
    expect(container.read(chatProvider).error, isNull);
  });

  test('preset, project and memory notes match the first real turn', () async {
    final presets = container.read(presetsProvider.notifier);
    await presets.ready;
    final preset = await presets.create(
      const Preset(
        id: '',
        name: 'Science',
        emoji: '',
        systemPrompt: 'Use concrete scientific examples.',
      ),
    );
    await presets.activate(preset.id);
    await container
        .read(conversationWorkspaceProvider.notifier)
        .saveProject(
          id: 'science',
          name: 'Science',
          instructions: 'Keep explanations brief.',
        );
    container.read(chatProvider.notifier).newChat(projectId: 'science');
    await container
        .read(settingsProvider.notifier)
        .update(container.read(settingsProvider).copyWith(memoryEnabled: true));
    final memory = container.read(memoryStoreProvider);
    final note = await memory.add('I prefer metric units.');
    await memory.pin(note, true);
    await load();
    final prime = engine.requests.single;
    expect(
      prime.messages.first['content'],
      contains('Use concrete scientific examples.'),
    );
    expect(
      prime.messages.first['content'],
      contains('Keep explanations brief.'),
    );
    expect(prime.messages.first['content'], contains('I prefer metric units.'));
    await container
        .read(chatProvider.notifier)
        .send('Explain why the sky is blue.', learn: false);
    final real = engine.requests.firstWhere((r) => r.settings.maxTokens != 1);
    expect(prime.messages.first, real.messages.first);
    expect(
      prime.tools.map((t) => t.toJson()).toList(),
      real.tools.map((t) => t.toJson()).toList(),
    );
  });

  test('a reload primes again', () async {
    await load();
    engine.loaded = false;
    await load();
    expect(engine.requests, hasLength(2));
  });

  test('changing load settings primes the reloaded model', () async {
    await load();
    final context = container.read(settingsProvider).contextSize * 2;
    await container
        .read(settingsProvider.notifier)
        .update(
          container.read(settingsProvider).copyWith(contextSize: context),
        );
    await load();
    expect(engine.loads, 2);
    expect(engine.requests, hasLength(2));
    expect(engine.requests.last.settings.contextSize, context);
  });

  test('phone loads do not prime', () async {
    DesktopHost.active = false;
    await load();
    expect(engine.requests, isEmpty);
  });

  test('remote settings do not prime the local engine', () async {
    await container
        .read(settingsProvider.notifier)
        .update(
          container
              .read(settingsProvider)
              .copyWith(
                remoteEnabled: true,
                remoteProfiles: const [
                  RemoteProfile(
                    id: 'test',
                    name: 'Test',
                    baseUrl: 'http://localhost:1234/v1',
                  ),
                ],
              ),
        );
    await load();
    expect(engine.requests, isEmpty);
  });

  test('disabled prompt cache does not prime', () async {
    await container
        .read(settingsProvider.notifier)
        .update(container.read(settingsProvider).copyWith(promptCache: false));
    await load();
    expect(engine.requests, isEmpty);
  });

  test('busy engine is left alone', () async {
    engine.busy = true;
    await load();
    expect(engine.requests, isEmpty);
    expect(engine.stopped, isFalse);
  });

  test('template omitting an empty turn uses a verified space', () async {
    engine.omitEmpty = true;
    await load();
    expect(engine.requests.single.messages.last['content'], ' ');
    expect(engine.previewsOf, containsAllInOrder(['', ' ']));
  });

  test('unverifiable template is skipped', () async {
    engine.broken = true;
    await load();
    expect(engine.requests, isEmpty);
  });

  test('priming failures never reach chat state', () async {
    engine.fail = true;
    await load();
    expect(engine.requests, hasLength(1));
    expect(container.read(chatProvider).error, isNull);
    expect(container.read(modelManagerProvider).error, isNull);
  });
}
