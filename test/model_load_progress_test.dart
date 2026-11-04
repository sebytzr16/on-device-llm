import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/adapters/adapter_store.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

import 'local_backup_service_test.dart' show BackupPaths;

class _Engine extends LlamaEngine {
  final progress = StreamController<double?>.broadcast(sync: true);
  final started = Completer<void>();
  final finish = Completer<void>();
  int loads = 0;
  String? held;
  String? projector;

  @override
  Stream<double?> get loadProgressChanges => progress.stream;

  @override
  bool holdsLoad(String modelPath, String config) =>
      held == '$modelPath|$config';

  @override
  Future<void> loadModel({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    loads++;
    projector = mmprojPath;
    if (!started.isCompleted) started.complete();
    await finish.future;
    // As the real engine: a Stop seen after the native load gives way.
    if (loadStop?.call() ?? false) throw const ModelLoadStopped();
    held =
        '$modelPath|${LlamaEngine.loadConfig(settings: settings, mmprojPath: mmprojPath, adapters: adapters, draftModelPath: draftModelPath)}';
  }
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState();
}

class _SeeingModels extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState(vision: {'loading'});
}

class _Adapters extends AdaptersNotifier {
  @override
  AdaptersState build() {
    ready = Future.value();
    return const AdaptersState();
  }
}

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() => const InferenceSettings();
}

const _model = ModelInfo(
  id: 'loading',
  displayName: 'Loading',
  fileName: 'loading.gguf',
  sizeBytes: 16,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: 'loading.gguf',
);

ProviderContainer _container(_Engine engine, {bool seeing = false}) {
  final container = ProviderContainer(
    overrides: [
      llamaEngineProvider.overrideWithValue(engine),
      seeing
          ? modelManagerProvider.overrideWith(_SeeingModels.new)
          : modelManagerProvider.overrideWith(_Models.new),
      adaptersProvider.overrideWith(_Adapters.new),
      settingsProvider.overrideWith(_Settings.new),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(engine.progress.close);
  return container;
}

void main() {
  test('Stop ends a load at any moment, with no error shown (OR-02)', () async {
    final engine = _Engine();
    final container = _container(engine);
    final manager = container.read(modelManagerProvider.notifier);
    final load = manager.loadModel(_model, settings: const InferenceSettings());
    await engine.started.future;
    expect(container.read(modelManagerProvider).isLoadingModel, isTrue);
    manager.stopLoad();
    engine.finish.complete();
    await expectLater(load, throwsA(isA<ModelLoadStopped>()));
    final state = container.read(modelManagerProvider);
    expect(state.isLoadingModel, isFalse);
    expect(state.loadedModelId, isNull);
    expect(state.error, isNull);
    // The next load runs normally.
    await manager.loadModel(_model, settings: const InferenceSettings());
    expect(container.read(modelManagerProvider).loadedModelId, _model.id);
  });

  test('Stop before the engine is reached never starts the native load '
      '(P1-19)', () async {
    final engine = _Engine()..finish.complete();
    final container = _container(engine);
    final manager = container.read(modelManagerProvider.notifier);
    container.read(engineHandoffProvider.notifier).state = (_) async =>
        manager.stopLoad();
    await expectLater(
      manager.loadModel(_model, settings: const InferenceSettings()),
      throwsA(isA<ModelLoadStopped>()),
    );
    expect(engine.loads, 0);
    expect(container.read(modelManagerProvider).error, isNull);
  });

  test('an unchanged model is not loaded again and never shows loading '
      '(P1-18)', () async {
    final engine = _Engine()..finish.complete();
    final container = _container(engine);
    final manager = container.read(modelManagerProvider.notifier);
    await manager.loadModel(_model, settings: const InferenceSettings());
    expect(engine.loads, 1);
    var started = false;
    final states = <bool>[];
    container.listen(
      modelManagerProvider.select((s) => s.isLoadingModel),
      (_, next) => states.add(next),
    );
    await manager.loadModel(
      _model,
      settings: const InferenceSettings(),
      onLoadStart: () => started = true,
    );
    expect(engine.loads, 1);
    expect(started, isFalse);
    expect(states, isEmpty);
    // A changed setting does load again.
    await manager.loadModel(
      _model,
      settings: const InferenceSettings(contextSize: 8192),
      onLoadStart: () => started = true,
    );
    expect(engine.loads, 2);
    expect(started, isTrue);
  });

  test(
    'unchanged chat load waits for a pooled server handoff (P2-05)',
    () async {
      final engine = _Engine()..finish.complete();
      final container = _container(engine);
      final manager = container.read(modelManagerProvider.notifier);
      await manager.loadModel(_model, settings: const InferenceSettings());
      final entered = Completer<void>();
      final settled = Completer<void>();
      container.read(engineHandoffProvider.notifier).state = (id) async {
        expect(id, _model.id);
        entered.complete();
        await settled.future;
      };
      var returned = false;
      final reuse = manager
          .loadModel(_model, forChat: true, settings: const InferenceSettings())
          .then((_) => returned = true);
      await entered.future;
      expect(returned, isFalse);
      expect(engine.loads, 1);
      expect(container.read(modelManagerProvider).isLoadingModel, isFalse);
      settled.complete();
      await reuse;
      expect(returned, isTrue);
      expect(engine.loads, 1);
    },
  );

  test('the projector loads with the first photo and then stays; a model '
      'with vision off never loads it (owner 2026-11-01)', () async {
    final dir = await Directory.systemTemp.createTemp('lazy-vision-');
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = BackupPaths(dir.path, dir.path);
    addTearDown(() async {
      PathProviderPlatform.instance = original;
      await dir.delete(recursive: true);
    });
    final seeing = _model.copyWith(
      projector: const VisionProjector(
        fileName: 'mmproj-loading.gguf',
        downloadUrl: '',
        sha256: '',
        sizeBytes: 1,
      ),
    );
    final engine = _Engine()..finish.complete();
    final container = _container(engine, seeing: true);
    final manager = container.read(modelManagerProvider.notifier);
    const settings = InferenceSettings();
    await manager.loadModel(seeing, settings: settings);
    expect(engine.projector, isNull);
    await manager.loadModel(seeing, settings: settings, vision: true);
    expect(engine.loads, 2);
    expect(engine.projector, endsWith('mmproj-loading.gguf'));
    // A later turn without a photo keeps it: no reload.
    await manager.loadModel(seeing, settings: settings);
    expect(engine.loads, 2);
    await manager.loadModel(
      seeing,
      settings: settings.copyWith(visionEnabled: false),
      vision: true,
    );
    expect(engine.loads, 3);
    expect(engine.projector, isNull);
  });

  test(
    'server text loads leave vision out until a photo requests it',
    () async {
      final dir = await Directory.systemTemp.createTemp('server-lazy-vision-');
      final original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = BackupPaths(dir.path, dir.path);
      addTearDown(() async {
        PathProviderPlatform.instance = original;
        await dir.delete(recursive: true);
      });
      final seeing = _model.copyWith(
        projector: const VisionProjector(
          fileName: 'mmproj-loading.gguf',
          downloadUrl: '',
          sha256: '',
          sizeBytes: 1,
        ),
      );
      final engine = _Engine()..finish.complete();
      final container = _container(engine, seeing: true);
      final manager = container.read(modelManagerProvider.notifier);
      await manager.loadServed(seeing, engine);
      expect(engine.projector, isNull);
      await manager.loadServed(seeing, engine, vision: true);
      expect(engine.projector, endsWith('mmproj-loading.gguf'));
    },
  );

  test('load fields survive copyWith and can be cleared', () {
    const state = ModelManagerState(
      loadingModelId: 'loading',
      loadProgress: 0.4,
      isLoadingModel: true,
    );
    expect(state.copyWith(error: 'error').loadProgress, 0.4);
    expect(state.copyWith().loadingModelId, 'loading');
    final cleared = state.copyWith(
      clearLoadProgress: true,
      clearLoadingModel: true,
    );
    expect(cleared.loadProgress, isNull);
    expect(cleared.loadingModelId, isNull);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'load progress is throttled and cleared on ${fails ? 'error' : 'success'}',
      (tester) async {
        final engine = _Engine();
        final container = ProviderContainer(
          overrides: [
            llamaEngineProvider.overrideWithValue(engine),
            modelManagerProvider.overrideWith(_Models.new),
            adaptersProvider.overrideWith(_Adapters.new),
            settingsProvider.overrideWith(_Settings.new),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(engine.progress.close);
        final manager = container.read(modelManagerProvider.notifier);
        final load = manager.loadModel(
          _model,
          settings: const InferenceSettings(),
        );
        final result = expectLater(load, fails ? throwsStateError : completes);
        await tester.pump();
        expect(engine.started.isCompleted, isTrue);
        expect(container.read(modelManagerProvider).loadingModelId, _model.id);
        expect(container.read(modelManagerProvider).isLoadingModel, isTrue);
        expect(container.read(modelManagerProvider).loadProgress, isNull);

        engine.progress.add(0.1);
        engine.progress.add(0.3);
        await tester.pump(const Duration(milliseconds: 99));
        expect(container.read(modelManagerProvider).loadProgress, isNull);
        await tester.pump(const Duration(milliseconds: 1));
        expect(container.read(modelManagerProvider).loadProgress, 0.3);
        engine.progress.add(null);
        await tester.pump(const Duration(milliseconds: 100));
        expect(container.read(modelManagerProvider).loadProgress, isNull);
        engine.progress.add(0.9);
        await tester.pump(const Duration(milliseconds: 100));
        expect(container.read(modelManagerProvider).loadProgress, 0.9);
        engine.progress.add(0.97);
        if (fails) {
          engine.finish.completeError(StateError('load failed'));
        } else {
          engine.finish.complete();
        }
        await tester.pump();
        await result;
        final state = container.read(modelManagerProvider);
        expect(state.isLoadingModel, isFalse);
        expect(state.loadingModelId, isNull);
        expect(state.loadProgress, isNull);
        expect(state.loadedModelId, fails ? isNull : _model.id);
        expect(engine.progress.hasListener, isFalse);
        engine.progress.add(1);
        await tester.pump(const Duration(milliseconds: 200));
        expect(container.read(modelManagerProvider).loadProgress, isNull);
      },
    );
  }
}
