import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/adapters/adapter_store.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/presets/presentation/providers/presets_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/litert_engine.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'chat_test.dart' show testModel;

/// A second model the user loads while the first one is being stopped.
const otherModel = ModelInfo(
  id: 'other',
  displayName: 'Other',
  fileName: 'other.gguf',
  sizeBytes: 100,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: 'other.gguf',
);

/// Two LiteRT files: their load runs in the engine's own runtime, which a
/// Stop cannot abort (a phone MethodChannel call).
final liteRtA = liteRtCatalog[0].copyWith(
  isDownloaded: true,
  localPath: 'a.litertlm',
);
final liteRtB = liteRtCatalog[1].copyWith(
  isDownloaded: true,
  localPath: 'b.litertlm',
);

class _Adapters extends AdaptersNotifier {
  @override
  AdaptersState build() {
    ready = Future.value();
    return const AdaptersState();
  }
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(catalog: [testModel, otherModel]);
  }
}

/// The manager over the two LiteRT files of the file-engine test.
class _FileEngineModels extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [liteRtA, liteRtB]);
  }
}

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(
      backend: GpuBackend.cpu,
      speculationMode: 'off',
    );
  }
}

/// Settings still being read from storage: a load waits for them before it
/// can know the cascade (and before it may start the native load).
class _SlowSettings extends SettingsNotifier {
  _SlowSettings(this.gate);
  final Completer<void> gate;

  @override
  InferenceSettings build() {
    ready = gate.future;
    return const InferenceSettings(
      backend: GpuBackend.cpu,
      speculationMode: 'off',
    );
  }
}

class _Profiles extends ModelProfilesNotifier {
  @override
  Map<String, Map<String, dynamic>> build() {
    ready = Future.value();
    return const {};
  }
}

class _Presets extends PresetsNotifier {
  @override
  PresetsState build() {
    ready = Future.value();
    return const PresetsState();
  }
}

class _Chat extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}

class _Database extends AppDatabase {
  _Database() : super.forTesting(NativeDatabase.memory());
}

/// A load that only finishes when it is cancelled, like llama.cpp's progress
/// callback refusing to continue: the manager must not wait for it to return
/// to idle.
class _SlowEngine extends LlamaEngine {
  final List<String> loads = [];
  final Map<String, Completer<void>> gates = {};
  final started = Completer<void>();

  /// When set, the Stop only reaches the running load once this completes:
  /// the load keeps freeing its runtime while the next Load waits for it.
  Completer<void>? cancelGate;

  /// When set, the Stop ends the load with a plain load error instead of a
  /// Stop, like a worker that keeps the runtime mapped (E3).
  bool refuseStop = false;
  String? loading;
  bool loaded = false;

  @override
  bool get isLoaded => loaded;

  @override
  Future<Map<String, dynamic>> probe() async => {'devices': const []};

  @override
  Future<void> loadModel({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    String engineId = 'llama.cpp',
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
    bool memoryGuard = true,
  }) async {
    loads.add(modelPath);
    loading = modelPath;
    if (!started.isCompleted) started.complete();
    try {
      await gate(modelPath).future;
    } finally {
      if (loading == modelPath) loading = null;
    }
    loaded = true;
  }

  Completer<void> gate(String path) =>
      gates.putIfAbsent(path, Completer<void>.new);

  @override
  void cancel() {
    final path = loading;
    if (path == null) return;
    final held = cancelGate;
    if (held == null) {
      _end(path);
    } else {
      unawaited(held.future.then((_) => _end(path)));
    }
  }

  void _end(String path) {
    final pending = gate(path);
    if (pending.isCompleted) return;
    pending.completeError(
      refuseStop
          ? const ModelLoadException(
              'The stopped load could not free the native engine.',
            )
          : const ModelLoadStopped(),
    );
  }

  @override
  Future<void> unload() async {
    loaded = false;
  }

  @override
  Future<void> stopAndWait() async {}
}

/// A llama load its `cancel()` cannot abort, like a worker stuck in the native
/// bridge: the manager's stop signal is only read once the call returns.
class _DeafEngine extends _SlowEngine {
  @override
  void cancel() {}

  @override
  Future<void> loadModel({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    String engineId = 'llama.cpp',
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
    bool memoryGuard = true,
  }) async {
    loads.add(modelPath);
    loading = modelPath;
    if (!started.isCompleted) started.complete();
    try {
      await gate(modelPath).future;
      // As the real engine: a Stop seen after the native call gives way.
      if (loadStop?.call() ?? false) throw const ModelLoadStopped();
      loaded = true;
    } finally {
      if (loading == modelPath) loading = null;
    }
  }
}

/// A LiteRT load that only finishes when the native host answers, like the
/// phone's MethodChannel call: a Stop cannot abort it.
class _SlowLiteRt extends LiteRtEngine {
  final List<String> loads = [];
  final List<String> unloads = [];
  final Map<String, Completer<void>> gates = {};
  final started = Completer<void>();
  String? _held;

  @override
  bool get isLoaded => _held != null;

  @override
  bool holdsLoad(String path, LiteRtBackend backend, {required bool vision}) =>
      _held == path;

  @override
  Future<void> loadModel(
    String path, {
    required LiteRtBackend backend,
    required bool vision,
  }) async {
    loads.add(path);
    if (!started.isCompleted) started.complete();
    await gate(path).future;
    _held = path;
  }

  Completer<void> gate(String path) =>
      gates.putIfAbsent(path, Completer<void>.new);

  @override
  Future<void> unload() async {
    final held = _held;
    if (held != null) unloads.add(held);
    _held = null;
  }

  @override
  void cancel() {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer c;
  late _SlowEngine engine;
  late _Database db;
  late ModelManagerNotifier manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = _Database();
    engine = _SlowEngine();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        adaptersProvider.overrideWith(_Adapters.new),
        modelManagerProvider.overrideWith(_Models.new),
        settingsProvider.overrideWith(_Settings.new),
        modelProfilesProvider.overrideWith(_Profiles.new),
        presetsProvider.overrideWith(_Presets.new),
        chatProvider.overrideWith(_Chat.new),
      ],
    );
    manager = c.read(modelManagerProvider.notifier);
  });
  tearDown(() async {
    engine.dispose();
    c.dispose();
    await db.close();
  });

  test('Stop during a slow load leaves the user idle at once', () async {
    final loading = manager.loadModel(testModel, forChat: true);
    expect(c.read(modelManagerProvider).isLoadingModel, isTrue);
    await engine.started.future;
    expect(engine.loads, [testModel.localPath]);

    manager.stopLoad();
    final failed = expectLater(loading, throwsA(isA<ModelLoadStopped>()));
    // Back to idle before the native teardown has run: the state is cleared
    // synchronously, and the cancelled load frees its runtime behind it.
    final state = c.read(modelManagerProvider);
    expect(state.isLoadingModel, isFalse);
    expect(state.loadingModelId, isNull);
    expect(state.loadProgress, isNull);
    expect(state.loadedModelId, isNull);

    await pumpEventQueue();
    expect(c.read(modelManagerProvider).isLoadingModel, isFalse);
    await failed;
    expect(c.read(modelManagerProvider).error, isNull);
    expect(engine.loaded, isFalse);
  });

  test('Stop while the settings are still loading never starts a native '
      'load', () async {
    final gate = Completer<void>();
    final slowEngine = _SlowEngine();
    final slowDb = _Database();
    final slow = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(slowDb),
        llamaEngineProvider.overrideWithValue(slowEngine),
        adaptersProvider.overrideWith(_Adapters.new),
        modelManagerProvider.overrideWith(_Models.new),
        settingsProvider.overrideWith(() => _SlowSettings(gate)),
        modelProfilesProvider.overrideWith(_Profiles.new),
        presetsProvider.overrideWith(_Presets.new),
        chatProvider.overrideWith(_Chat.new),
      ],
    );
    addTearDown(() async {
      slowEngine.dispose();
      slow.dispose();
      await slowDb.close();
    });
    final slowManager = slow.read(modelManagerProvider.notifier);
    final loading = slowManager.loadModel(testModel, forChat: true);
    // The load shows at once, before its settings have been read (OR-02).
    expect(slow.read(modelManagerProvider).isLoadingModel, isTrue);
    expect(slow.read(modelManagerProvider).loadingModelId, testModel.id);
    final failed = expectLater(loading, throwsA(isA<ModelLoadStopped>()));

    slowManager.stopLoad();
    // Idle at once, and the native load is never reached.
    expect(slow.read(modelManagerProvider).isLoadingModel, isFalse);
    gate.complete();
    await failed;
    await pumpEventQueue();
    expect(slowEngine.loads, isEmpty);
    expect(slow.read(modelManagerProvider).isLoadingModel, isFalse);
    expect(slow.read(modelManagerProvider).error, isNull);
  });

  test(
    'Load B right after Stop A waits for the teardown and succeeds',
    () async {
      // A chat turn started the load: the session is busy while it runs.
      c.read(sessionBusyProvider.notifier).state = true;
      final first = manager.loadModel(testModel, forChat: true);
      await engine.started.future;
      expect(engine.loads, [testModel.localPath]);

      manager.stopLoad();
      final failed = expectLater(first, throwsA(isA<ModelLoadStopped>()));
      // No raw StateError and no "stop the current response" here: the stop
      // frees the session and the new load waits for the cancelled load to let
      // go of the engine.
      expect(c.read(sessionBusyProvider), isFalse);
      final second = manager.loadModel(otherModel);
      expect(c.read(modelManagerProvider).isLoadingModel, isTrue);
      expect(c.read(modelManagerProvider).loadingModelId, otherModel.id);
      await failed;

      engine.gate(otherModel.localPath!).complete();
      await second;
      final state = c.read(modelManagerProvider);
      expect(state.loadedModelId, otherModel.id);
      expect(state.isLoadingModel, isFalse);
      expect(state.error, isNull);
      expect(engine.loads, [testModel.localPath, otherModel.localPath]);
      expect(engine.loaded, isTrue);
    },
  );

  test('a superseded file engine load never marks itself loaded or clears '
      'the next load spinner', () async {
    final liteRt = _SlowLiteRt();
    final llama = _SlowEngine();
    final fileDb = _Database();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(fileDb),
        llamaEngineProvider.overrideWithValue(llama),
        liteRtAvailableProvider.overrideWithValue(true),
        liteRtEngineProvider.overrideWithValue(liteRt),
        adaptersProvider.overrideWith(_Adapters.new),
        modelManagerProvider.overrideWith(_FileEngineModels.new),
        settingsProvider.overrideWith(_Settings.new),
        modelProfilesProvider.overrideWith(_Profiles.new),
        presetsProvider.overrideWith(_Presets.new),
        chatProvider.overrideWith(_Chat.new),
      ],
    );
    addTearDown(() async {
      llama.dispose();
      container.dispose();
      await fileDb.close();
    });
    final fileManager = container.read(modelManagerProvider.notifier);
    const settings = InferenceSettings(
      backend: GpuBackend.cpu,
      speculationMode: 'off',
    );
    final first = fileManager.loadModel(liteRtA, settings: settings);
    await liteRt.started.future;
    expect(liteRt.loads, [liteRtA.localPath]);

    fileManager.stopLoad();
    final failed = expectLater(first, throwsA(isA<ModelLoadStopped>()));
    // The next Load owns the spinner while it waits for the stopped load's
    // teardown.
    final second = fileManager.loadModel(liteRtB, settings: settings);
    expect(container.read(modelManagerProvider).loadingModelId, liteRtB.id);
    expect(container.read(modelManagerProvider).isLoadingModel, isTrue);

    // The stopped load finishes only now, as the phone's MethodChannel call
    // would: it may not mark itself loaded nor end the next load's spinner.
    liteRt.gate(liteRtA.localPath!).complete();
    await failed;
    await pumpEventQueue();
    expect(liteRt.unloads, [liteRtA.localPath]);
    var state = container.read(modelManagerProvider);
    expect(state.loadedModelId, isNull);
    expect(state.isLoadingModel, isTrue);
    expect(state.loadingModelId, liteRtB.id);

    liteRt.gate(liteRtB.localPath!).complete();
    await second;
    state = container.read(modelManagerProvider);
    expect(state.loadedModelId, liteRtB.id);
    expect(state.isLoadingModel, isFalse);
    expect(liteRt.loads, [liteRtA.localPath, liteRtB.localPath]);
  });

  test('a second Stop still frees the file engine model the first Stop left '
      'loading', () async {
    final liteRt = _SlowLiteRt();
    final llama = _SlowEngine();
    final fileDb = _Database();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(fileDb),
        llamaEngineProvider.overrideWithValue(llama),
        liteRtAvailableProvider.overrideWithValue(true),
        liteRtEngineProvider.overrideWithValue(liteRt),
        adaptersProvider.overrideWith(_Adapters.new),
        modelManagerProvider.overrideWith(_FileEngineModels.new),
        settingsProvider.overrideWith(_Settings.new),
        modelProfilesProvider.overrideWith(_Profiles.new),
        presetsProvider.overrideWith(_Presets.new),
        chatProvider.overrideWith(_Chat.new),
      ],
    );
    addTearDown(() async {
      llama.dispose();
      container.dispose();
      await fileDb.close();
    });
    final fileManager = container.read(modelManagerProvider.notifier);
    const settings = InferenceSettings(
      backend: GpuBackend.cpu,
      speculationMode: 'off',
    );
    final first = fileManager.loadModel(liteRtA, settings: settings);
    await liteRt.started.future;
    expect(liteRt.loads, [liteRtA.localPath]);

    fileManager.stopLoad();
    final failed = expectLater(first, throwsA(isA<ModelLoadStopped>()));
    final second = fileManager.loadModel(liteRtB, settings: settings);
    expect(container.read(modelManagerProvider).loadingModelId, liteRtB.id);
    // A second Stop before A's MethodChannel call answers: the stopped epoch
    // is B's now, so A's own branch no longer matches it (finding #1).
    fileManager.stopLoad();
    final secondFailed = expectLater(second, throwsA(isA<ModelLoadStopped>()));

    liteRt.gate(liteRtA.localPath!).complete();
    await failed;
    await secondFailed;
    await pumpEventQueue();
    // The runtime A mapped is freed even though the second Stop took the
    // stopped epoch: the phone must not keep the model resident.
    expect(liteRt.unloads, [liteRtA.localPath]);
    final state = container.read(modelManagerProvider);
    expect(state.loadedModelId, isNull);
    expect(state.isLoadingModel, isFalse);
    expect(liteRt.loads, [liteRtA.localPath]);
  });

  test('a Stop reaches a load whose cancel() cannot abort it', () async {
    // The engine only reads the manager's stop signal when its native call
    // returns: the Stop alone ends nothing.
    final deaf = _DeafEngine();
    final deafDb = _Database();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(deafDb),
        llamaEngineProvider.overrideWithValue(deaf),
        adaptersProvider.overrideWith(_Adapters.new),
        modelManagerProvider.overrideWith(_Models.new),
        settingsProvider.overrideWith(_Settings.new),
        modelProfilesProvider.overrideWith(_Profiles.new),
        presetsProvider.overrideWith(_Presets.new),
        chatProvider.overrideWith(_Chat.new),
      ],
    );
    addTearDown(() async {
      deaf.dispose();
      container.dispose();
      await deafDb.close();
    });
    final deafManager = container.read(modelManagerProvider.notifier);
    final first = deafManager.loadModel(testModel, forChat: true);
    await deaf.started.future;
    expect(deaf.loads, [testModel.localPath]);

    deafManager.stopLoad();
    final failed = expectLater(first, throwsA(isA<ModelLoadStopped>()));
    final second = deafManager.loadModel(otherModel);
    await pumpEventQueue();
    // The stopped load still holds the engine: the next one does not start on
    // top of it.
    expect(deaf.loads, [testModel.localPath]);

    // The native call returns and asks the per-load stop signal: the load the
    // user stopped ends as a Stop instead of loading the model.
    deaf.gate(testModel.localPath!).complete();
    await failed;
    await pumpEventQueue();
    expect(deaf.loads, [testModel.localPath, otherModel.localPath]);

    deaf.gate(otherModel.localPath!).complete();
    await second;
    final state = container.read(modelManagerProvider);
    expect(state.loadedModelId, otherModel.id);
    expect(state.isLoadingModel, isFalse);
    expect(deaf.loaded, isTrue);
  });

  test('a second Load while one is really running says so, cleanly', () async {
    final loading = manager.loadModel(testModel, forChat: true);
    await engine.started.future;
    // Not a Stop: the running load does not accept a replacement silently,
    // and the message is the localized one, not "Bad state: ...".
    await expectLater(
      manager.loadModel(otherModel, forChat: true),
      throwsA(
        isA<ModelLoadException>().having(
          (e) => e.toString(),
          'message',
          isNot(contains('Bad state')),
        ),
      ),
    );
    // The rejected duplicate must not replace the running load's future: the
    // Stop below still tears that load down (M1).
    engine.cancelGate = Completer<void>();
    manager.stopLoad();
    final failed = expectLater(loading, throwsA(isA<ModelLoadStopped>()));
    final second = manager.loadModel(otherModel);
    expect(c.read(modelManagerProvider).loadingModelId, otherModel.id);
    await pumpEventQueue();
    // The load after the Stop waits for the stopped load's teardown instead
    // of starting on top of it.
    expect(engine.loads, [testModel.localPath]);
    engine.cancelGate!.complete();
    await failed;
    // The teardown is over: the queued load runs and ends up loaded.
    engine.gate(otherModel.localPath!).complete();
    await second;
    expect(engine.loads, [testModel.localPath, otherModel.localPath]);
    expect(c.read(modelManagerProvider).loadedModelId, otherModel.id);
    expect(c.read(modelManagerProvider).error, isNull);
    expect(engine.loaded, isTrue);
  });

  test('a Stop whose runtime stays mapped reports the load error', () async {
    // The engine answers the Stop with a load failure, not a Stop: the model
    // is still mapped, and the caller must be told instead of a silent Stop
    // (E3).
    engine.refuseStop = true;
    final loading = manager.loadModel(testModel, forChat: true);
    await engine.started.future;
    manager.stopLoad();
    await expectLater(
      loading,
      throwsA(
        isA<ModelLoadException>()
            .having((e) => e is ModelLoadStopped, 'not a Stop', isFalse)
            .having(
              (e) => e.message,
              'message',
              contains('could not free the native engine'),
            ),
      ),
    );
    // The Stop itself still returned the user to idle at once.
    expect(c.read(modelManagerProvider).isLoadingModel, isFalse);
    expect(c.read(modelManagerProvider).loadedModelId, isNull);
  });
}
