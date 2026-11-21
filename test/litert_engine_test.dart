import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/litert_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('ondevice_llm/litert');
  const tokens = MethodChannel('ondevice_llm/litert/tokens');
  const codec = StandardMethodCodec();
  const messages = [
    {'role': 'system', 'content': 'Be concise.'},
    {'role': 'user', 'content': 'First question'},
    {'role': 'assistant', 'content': 'First answer'},
    {'role': 'user', 'content': 'Second question'},
  ];
  const settings = InferenceSettings(
    temperature: 0.4,
    topK: 24,
    topP: 0.8,
    maxTokens: 128,
  );
  late LiteRtEngine engine;
  late StreamController<Map<Object?, Object?>> started;
  late List<int> cancelled;

  /// Every `listen`/`cancel` the engine sent to the token EventChannel, so a
  /// turn cannot silently reuse the subscription of the one before it.
  late List<String> tokenCalls;

  /// Holds the host's 'cancel' reply, so a test can look at the engine while
  /// the native generation is still settling.
  late Completer<void>? cancelGate;

  Stream<String> generate() => engine.generate(
    messages: messages,
    fallbackTemplate: '',
    settings: settings,
  );

  Future<void> emit(Map<String, Object> event) =>
      messenger.handlePlatformMessage(
        tokens.name,
        codec.encodeSuccessEnvelope(event),
        (_) {},
      );

  setUp(() async {
    engine = LiteRtEngine();
    started = StreamController<Map<Object?, Object?>>.broadcast();
    cancelled = [];
    tokenCalls = [];
    cancelGate = null;
    messenger.setMockMethodCallHandler(tokens, (call) async {
      tokenCalls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(methods, (call) async {
      switch (call.method) {
        case 'load':
          return {'backend': 'cpu', 'contextSize': 4096};
        case 'generate':
          started.add(call.arguments as Map<Object?, Object?>);
        case 'cancel':
          cancelled.add((call.arguments as Map)['id'] as int);
          final gate = cancelGate;
          if (gate != null) await gate.future;
      }
      return null;
    });
    await engine.loadModel(
      'test.litertlm',
      backend: LiteRtBackend.auto,
      vision: false,
    );
  });

  tearDown(() async {
    cancelGate = null;
    await engine.unload();
    await started.close();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(tokens, null);
  });

  test(
    'streams text and thought for the matching request, with metrics',
    () async {
      final next = started.stream.first;
      final result = generate().join();
      final request = await next;
      expect(request['messages'], messages);
      expect(request['temperature'], 0.4);
      expect(request['topK'], 24);
      expect(request['topP'], 0.8);
      expect(request['maxTokens'], settings.maxTokens);
      expect(request['responseFormat'], 'text');
      final id = request['id'] as int;
      await emit({'id': id - 1, 'type': 'text', 'text': 'old'});
      await emit({'id': id, 'type': 'thought', 'text': 'reason'});
      await emit({'id': id, 'type': 'thought', 'text': 'ing'});
      await emit({'id': id, 'type': 'text', 'text': 'Hello'});
      await emit({'id': id, 'type': 'text', 'text': ' world'});
      await emit({
        'id': id,
        'type': 'done',
        'finishReason': 'eog',
        'metrics': {
          'tokensPerSecond': 12.5,
          'firstTokenMs': 100,
          'contextSize': 4096,
        },
      });
      expect(await result, '<think>reasoning</think>Hello world');
      expect(engine.metrics, containsPair('backend', 'cpu'));
      expect(engine.metrics, containsPair('tokensPerSecond', 12.5));
      expect(engine.metrics, containsPair('firstTokenMs', 100));
      expect(engine.metrics, containsPair('contextSize', 4096));
      expect(engine.metrics, containsPair('finishReason', 'eog'));
      expect(engine.metrics['toolCalls'], isEmpty);
      expect(cancelled, isEmpty);
    },
  );

  test(
    'asks the host for JSON, and for its schema, when the turn does',
    () async {
      final first = started.stream.first;
      final json = engine
          .generate(
            messages: messages,
            fallbackTemplate: '',
            settings: settings.copyWith(responseFormat: ResponseFormat.json),
          )
          .join();
      final request = await first;
      expect(request['responseFormat'], 'json');
      expect(request['jsonSchema'], '');
      await emit({
        'id': request['id'] as int,
        'type': 'done',
        'finishReason': 'eog',
      });
      await json;

      final schema = started.stream.first;
      final constrained = engine
          .generate(
            messages: messages,
            fallbackTemplate: '',
            settings: settings.copyWith(
              responseFormat: ResponseFormat.jsonSchema,
              jsonSchema: '{"type":"object"}',
            ),
          )
          .join();
      final second = await schema;
      expect(second['responseFormat'], 'json');
      expect(second['jsonSchema'], '{"type":"object"}');
      await emit({
        'id': second['id'] as int,
        'type': 'done',
        'finishReason': 'eog',
      });
      await constrained;
    },
  );

  test('a Stop during the prefill reaches the host without a token', () async {
    final next = started.stream.first;
    final chunks = <String>[];
    final stream = generate().listen(chunks.add);
    final id = (await next)['id'] as int;
    // Nothing has streamed yet: detaching must not wait for a first token
    // to reach native cleanup.
    await stream.cancel().timeout(const Duration(seconds: 2));
    expect(chunks, isEmpty);
    expect(cancelled, [id]);
    expect(engine.metrics['finishReason'], 'cancelled');
  });

  test('a prefill Stop frees the engine for the next turn', () async {
    final next = started.stream.first;
    final stream = generate().listen(null);
    final id = (await next)['id'] as int;
    await stream.cancel().timeout(const Duration(seconds: 2));
    expect(cancelled, [id]);

    // The stopped request settled on its own, so the engine takes a new one
    // without waiting for a token the stopped turn never sends.
    final second = started.stream.first;
    final text = generate().join();
    final request = await second;
    expect(request['id'], isNot(id));
    await emit({'id': request['id'] as int, 'type': 'text', 'text': 'fresh'});
    await emit({
      'id': request['id'] as int,
      'type': 'done',
      'finishReason': 'eog',
    });
    expect(await text, 'fresh');
  });

  test(
    'a stopped request settles, then the next one streams on a fresh listen',
    () async {
      final gate = cancelGate = Completer<void>();
      final next = started.stream.first;
      final chunks = <String>[];
      final stream = generate().listen(chunks.add);
      final id = (await next)['id'] as int;
      await emit({'id': id, 'type': 'text', 'text': 'partial'});
      await pumpEventQueue();
      expect(chunks, ['partial']);

      // The host has not answered the cancel yet: the stopped request still
      // owns the engine, so no second one may start.
      engine.cancel();
      await expectLater(generate(), emitsError(isA<StateError>()));
      await emit({'id': id, 'type': 'text', 'text': 'late'});

      gate.complete();
      await pumpEventQueue();
      await stream.cancel();
      await pumpEventQueue();
      expect(chunks, ['partial']);
      expect(cancelled, [id]);
      expect(engine.metrics['finishReason'], 'cancelled');
      // The stopped turn closed its own token subscription.
      expect(tokenCalls, ['listen', 'cancel']);

      // The next turn listens on its own subscription and ignores the stale
      // events of the one before it.
      final second = started.stream.first;
      final text = generate().join();
      final request = await second;
      await pumpEventQueue();
      expect(request['id'], isNot(id));
      expect(tokenCalls, ['listen', 'cancel', 'listen']);
      await emit({'id': id, 'type': 'text', 'text': 'stale'});
      await emit({'id': request['id'] as int, 'type': 'text', 'text': 'fresh'});
      await emit({
        'id': request['id'] as int,
        'type': 'done',
        'finishReason': 'eog',
      });
      expect(await text, 'fresh');
    },
  );

  test('native error events surface on the stream', () async {
    final next = started.stream.first;
    final error = expectLater(
      generate(),
      emitsError(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'litert_generate')
            .having((e) => e.message, 'message', 'context full'),
      ),
    );
    final id = (await next)['id'] as int;
    await emit({'id': id, 'type': 'error', 'message': 'context full'});
    await error;
    expect(engine.metrics['finishReason'], 'error');
  });

  test('prompt preview renders roles and whole history', () async {
    final preview = await engine.previewPrompt(
      messages: messages,
      fallbackTemplate: '',
      settings: settings,
    );
    expect(
      preview['prompt'],
      'system: Be concise.\n\nuser: First question\n\n'
      'assistant: First answer\n\nuser: Second question',
    );
  });

  test(
    'prompt preview judges the fit from the context the load reported',
    () async {
      final preview = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: '',
        settings: settings,
      );
      expect(preview['contextSize'], 4096);
      expect(preview['reservedTokens'], settings.maxTokens);
      expect(preview['availableTokens'], 4096 - settings.maxTokens);
      expect(preview['fits'], isTrue);

      final tooLong = await engine.previewPrompt(
        messages: [
          {'role': 'user', 'content': 'x' * 16384},
        ],
        fallbackTemplate: '',
        settings: settings,
      );
      expect(tooLong['fits'], isFalse);
    },
  );

  test(
    'prompt preview holds back the reasoning the host also reserves',
    () async {
      final thinking = settings.copyWith(
        thinkingModeEnabled: true,
        thinkingBudgetTokens: 512,
      );
      final budget = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: '',
        settings: thinking,
      );
      expect(budget['reservedTokens'], settings.maxTokens + 512);
      expect(budget['availableTokens'], 4096 - settings.maxTokens - 512);

      // Unlimited (zero) resolves against the window the host knows, the way
      // generation caps it: the answer keeps its allowance, reasoning gets
      // half of what the window leaves.
      final unlimited = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: '',
        settings: thinking.copyWith(thinkingBudgetTokens: 0),
      );
      final thinkingRoom = (4096 - settings.maxTokens) ~/ 2;
      expect(unlimited['reservedTokens'], settings.maxTokens + thinkingRoom);
      expect(
        unlimited['availableTokens'],
        4096 - settings.maxTokens - thinkingRoom,
      );
    },
  );

  test(
    'a prompt whose fit cannot be known is not reported as fitting',
    () async {
      messenger.setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'load') return {'backend': 'cpu'};
        return null;
      });
      final unknown = LiteRtEngine();
      addTearDown(unknown.dispose);
      await unknown.loadModel(
        'test.litertlm',
        backend: LiteRtBackend.auto,
        vision: false,
      );
      final preview = await unknown.previewPrompt(
        messages: messages,
        fallbackTemplate: '',
        settings: settings,
      );
      expect(preview['contextSize'], isNull);
      expect(preview['availableTokens'], isNull);
      expect(preview['fits'], isNull);
    },
  );
}
