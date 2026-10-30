import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/adapters/adapter_store.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

class _Engine extends LlamaEngine {
  final progress = StreamController<double?>.broadcast(sync: true);
  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Stream<double?> get loadProgressChanges => progress.stream;

  @override
  Future<void> loadModel({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) {
    started.complete();
    return finish.future;
  }
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState();
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

void main() {
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
