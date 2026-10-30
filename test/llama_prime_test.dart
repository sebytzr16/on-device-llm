import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

class _Engine extends LlamaEngine {
  final started = Completer<void>();
  final finish = Completer<void>();
  bool busy = false, cancelled = false;
  final events = <String>[];
  @override
  bool get isLoaded => true;
  @override
  bool get isBusy => busy && !isPriming;

  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => {
    'formattedPrompt':
        '<system>${messages.first['content']}</system><user>${messages.last['content']}</user>',
  };

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    if (settings.maxTokens == 1) {
      busy = true;
      started.complete();
      await finish.future;
      busy = false;
      events.add('prime finished');
    } else {
      expect(busy, isFalse);
      events.add('foreground');
      yield 'answer';
    }
  }

  // Enters the production foreground handoff; no native generation is needed.
  Stream<String> foreground() => super.generate(
    messages: const [
      {'role': 'user', 'content': 'question'},
    ],
    fallbackTemplate: 'chatml',
    settings: const InferenceSettings(maxTokens: 32),
  );

  @override
  void cancel() {
    super.cancel();
    cancelled = true;
    events.add('cancel');
    if (!finish.isCompleted) finish.complete();
  }
}

class _PreviewEngine extends _Engine {
  final previewStarted = Completer<void>();
  final previewFinish = Completer<void>();
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    previewStarted.complete();
    await previewFinish.future;
    return super.previewPrompt(
      messages: messages,
      fallbackTemplate: fallbackTemplate,
      settings: settings,
      assistantPrefix: assistantPrefix,
      tools: tools,
    );
  }
}

void main() {
  test(
    'foreground engine generation cancels priming before taking ownership',
    () async {
      final engine = _Engine();
      final prime = engine.primePrompt(
        system: 'system',
        fallbackTemplate: 'chatml',
        settings: const InferenceSettings(),
      );
      await engine.started.future;
      expect(engine.isBusy, isFalse);
      expect(engine.isPriming, isTrue);
      final foreground = engine.foreground();
      expect(engine.cancelled, isTrue);
      expect(await foreground.toList(), ['answer']);
      await prime;
      expect(engine.events, ['cancel', 'prime finished', 'foreground']);
    },
  );

  test('engine unload cancels priming before proceeding', () async {
    final engine = _Engine();
    final prime = engine.primePrompt(
      system: 'system',
      fallbackTemplate: 'chatml',
      settings: const InferenceSettings(),
    );
    await engine.started.future;
    await engine.unload();
    await prime;
    expect(engine.cancelled, isTrue);
    expect(engine.busy, isFalse);
  });

  test('another engine operation preempts priming', () async {
    final engine = _Engine();
    final prime = engine.primePrompt(
      system: 'system',
      fallbackTemplate: 'chatml',
      settings: const InferenceSettings(),
    );
    await engine.started.future;
    expect(await engine.embed(const []), isEmpty);
    await prime;
    expect(engine.events, ['cancel', 'prime finished']);
  });

  test(
    'cancellation during template preview prevents a late generation',
    () async {
      final engine = _PreviewEngine();
      final prime = engine.primePrompt(
        system: 'system',
        fallbackTemplate: 'chatml',
        settings: const InferenceSettings(),
      );
      await engine.previewStarted.future;
      engine.cancel();
      engine.previewFinish.complete();
      await prime;
      expect(engine.started.isCompleted, isFalse);
      expect(engine.isPriming, isFalse);
    },
  );
}
