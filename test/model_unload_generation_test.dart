import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/helper/helper_runner.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(loadedModelId: 'model');
  }
}

class _Chat extends ChatNotifier {
  final List<String> events;
  _Chat(this.events);
  @override
  ChatState build() => const ChatState(isGenerating: true);
  @override
  void cancel() => events.add('chat cancel');
}

class _Engine extends LlamaEngine {
  final List<String> events;
  final stop = Completer<void>();
  bool fail = false;
  _Engine(this.events);
  @override
  bool get isLoaded => true;
  @override
  Future<void> stopAndWait() async {
    events.add('engine cancel');
    await stop.future;
    events.add('engine stopped');
  }

  @override
  Future<void> unload() async {
    events.add('unload');
    if (fail) throw StateError('native unload failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Eject during generation cancels and waits before unloading', () async {
    final events = <String>[];
    final engine = _Engine(events);
    final helper = HelperRunner(
      engine: LlamaEngine(),
      chatEngine: engine,
      catalog: () => [],
      loadedModelId: () => null,
      settingsFor: (_) => const InferenceSettings(),
    );
    final container = ProviderContainer(
      overrides: [
        modelManagerProvider.overrideWith(_Models.new),
        chatProvider.overrideWith(() => _Chat(events)),
        llamaEngineProvider.overrideWithValue(engine),
        helperRunnerProvider.overrideWithValue(helper),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionBusyProvider.notifier).state = true;
    final eject = container.read(modelManagerProvider.notifier).unloadModel();
    expect(
      identical(
        eject,
        container.read(modelManagerProvider.notifier).unloadModel(),
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, ['chat cancel', 'engine cancel']);
    engine.stop.complete();
    await eject;
    expect(events, [
      'chat cancel',
      'engine cancel',
      'engine stopped',
      'unload',
    ]);
    expect(container.read(modelManagerProvider).loadedModelId, isNull);
    expect(container.read(modelManagerProvider).error, isNull);
  });

  test('Eject catches native errors for UI handlers', () async {
    final engine = _Engine([])..fail = true;
    engine.stop.complete();
    final helper = HelperRunner(
      engine: LlamaEngine(),
      chatEngine: engine,
      catalog: () => [],
      loadedModelId: () => null,
      settingsFor: (_) => const InferenceSettings(),
    );
    final container = ProviderContainer(
      overrides: [
        modelManagerProvider.overrideWith(_Models.new),
        llamaEngineProvider.overrideWithValue(engine),
        helperRunnerProvider.overrideWithValue(helper),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(modelManagerProvider.notifier).unloadModel(),
      completes,
    );
    expect(
      container.read(modelManagerProvider).error,
      contains('native unload failed'),
    );
    expect(container.read(modelManagerProvider).loadedModelId, 'model');
  });
}
