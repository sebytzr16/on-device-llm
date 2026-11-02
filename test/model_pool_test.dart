import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/model_pool.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';

import 'device_model_server_test.dart' show FakeEngine;

/// Answers with its own name so a test sees which runtime answered.
class _NamedEngine extends FakeEngine {
  final String name;
  _NamedEngine(this.name);
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    received.add(settings);
    yield name;
  }
}

class _Router implements ServedModelRouter {
  final engines = <String, TextEngine>{};
  final released = <String>[];
  RouteRefusal? refusal;
  @override
  List<String> get ids => engines.keys.toList();
  @override
  Future<TextEngine?> acquire(String id) async {
    if (refusal != null) throw refusal!;
    return engines[id];
  }

  @override
  void release(String id) => released.add(id);
  @override
  InferenceSettings settingsFor(String id) =>
      const InferenceSettings(temperature: 0.3);
  @override
  String templateFor(String id) => 'chatml';
  @override
  void cancelAll() {}
}

class _PoolEngine extends LlamaEngine {
  final String path;
  var unloads = 0;
  var disposed = false;
  bool busy = false;
  _PoolEngine(this.path);
  @override
  bool get isBusy => busy;
  @override
  bool get isLoaded => true;
  @override
  Future<void> unload() async => unloads++;
  @override
  void dispose() => disposed = true;
}

ModelInfo _model(String id) => ModelInfo(
  id: id,
  displayName: id,
  fileName: '$id.gguf',
  sizeBytes: 1,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q8_0,
  isDownloaded: true,
  localPath: '/models/$id.gguf',
);

void main() {
  const token = '0123456789abcdef0123456789abcdef';

  group('server routing', () {
    late DeviceModelServer server;
    late _Router router;
    late HttpClient client;
    late List<ServedRequest> served;

    setUp(() async {
      router = _Router()..engines['other'] = _NamedEngine('from-other');
      served = [];
      server = DeviceModelServer(
        engine: _NamedEngine('from-primary'),
        settings: () => const InferenceSettings(),
        modelId: 'primary',
        fallbackTemplate: '',
        accessToken: token,
        router: router,
        onServed: served.add,
      );
      await server.start();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<(int, Map<String, dynamic>)> send(
      String method,
      String path, [
      Object? body,
    ]) async {
      final request = await client.open(
        method,
        '127.0.0.1',
        server.port!,
        path,
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      return (
        response.statusCode,
        Map<String, dynamic>.from(jsonDecode(text) as Map),
      );
    }

    test('lists every model and answers each with its own runtime', () async {
      final (_, list) = await send('GET', DeviceModelServer.modelsPath);
      expect(
        [for (final m in list['data'] as List) m['id']],
        ['primary', 'other'],
      );
      final (code, answer) = await send(
        'POST',
        DeviceModelServer.completionsPath,
        {
          'model': 'other',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
      );
      expect(code, HttpStatus.ok);
      expect(answer['model'], 'other');
      expect(answer['choices'][0]['message']['content'], 'from-other');
      expect(router.released, ['other']);
      expect(
        (router.engines['other']! as FakeEngine).received.single.temperature,
        0.3,
      );
      final (_, primary) = await send(
        'POST',
        DeviceModelServer.completionsPath,
        {
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
      );
      expect(primary['model'], 'primary');
      expect(primary['choices'][0]['message']['content'], 'from-primary');
      // The log entry follows the response by a moment.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(served.where((r) => r.completion).map((r) => r.modelId), [
        'other',
        'primary',
      ]);
    });

    test('unknown models and refusals reach the client', () async {
      final (unknown, _) = await send(
        'POST',
        DeviceModelServer.completionsPath,
        {
          'model': 'missing',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
      );
      expect(unknown, HttpStatus.badRequest);
      router.refusal = const RouteRefusal(429, 'other is busy.');
      final (busy, body) = await send(
        'POST',
        DeviceModelServer.completionsPath,
        {
          'model': 'other',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
      );
      expect(busy, HttpStatus.tooManyRequests);
      expect(body['error']['message'], 'other is busy.');
      expect(router.released, isEmpty);
    });
  });

  group('model pool', () {
    late List<ModelInfo> installed;
    late List<String> loads;
    late Map<String, _PoolEngine> engines;
    late PoolOptions options;
    late DateTime clock;
    _PoolEngine? chat;
    String? chatModel;

    ModelPool pool({Future<void> Function(ModelInfo)? onLoad}) => ModelPool(
      primary: 'primary',
      installed: () => installed,
      load: (m, e) async {
        loads.add(m.id);
        engines[m.id] = e as _PoolEngine;
        await onLoad?.call(m);
      },
      settingsOf: (m) => InferenceSettings(maxTokens: m.id.length),
      newEngine: () => _PoolEngine('new'),
      options: () => options,
      chatEngineFor: (id) => id == chatModel ? chat : null,
      now: () => clock,
    );

    setUp(() {
      installed = [_model('primary'), _model('a'), _model('b'), _model('c')];
      loads = [];
      engines = {};
      options = const PoolOptions(jit: true, maxLoaded: 2);
      clock = DateTime(2026, 10, 22, 12);
      chat = null;
      chatModel = null;
    });

    test('loads on request only with JIT on, and lists installed', () async {
      options = const PoolOptions(jit: false);
      final p = pool();
      addTearDown(p.close);
      expect(await p.acquire('a'), isNull);
      expect(p.ids, isEmpty);
      options = const PoolOptions(jit: true);
      expect(p.ids, ['a', 'b', 'c']);
      expect(await p.acquire('a'), isNotNull);
      expect(loads, ['a']);
      expect(p.settingsFor('a').maxTokens, 1);
      expect(await p.acquire('primary'), isNull);
    });

    test('a busy model refuses; released it answers again', () async {
      final p = pool();
      addTearDown(p.close);
      await p.acquire('a');
      await expectLater(
        p.acquire('a'),
        throwsA(isA<RouteRefusal>().having((r) => r.status, 'status', 429)),
      );
      p.release('a');
      expect(await p.acquire('a'), same(engines['a']));
      expect(loads, ['a']);
    });

    test('the longest idle model makes room; all busy refuses', () async {
      final p = pool();
      addTearDown(p.close);
      await p.acquire('a');
      p.release('a');
      clock = clock.add(const Duration(minutes: 1));
      await p.acquire('b');
      p.release('b');
      clock = clock.add(const Duration(minutes: 1));
      await p.acquire('c');
      expect(p.holds('a'), false);
      expect(engines['a']!.unloads, 1);
      expect(engines['a']!.disposed, true);
      expect(p.holds('b'), true);
      await p.acquire('b');
      await expectLater(
        p.acquire('a'),
        throwsA(isA<RouteRefusal>().having((r) => r.status, 'status', 429)),
      );
    });

    test('eviction skips pinned LRU and refuses when pinned or busy', () async {
      options = options.copyWith(pinned: {'a'});
      final p = pool();
      addTearDown(p.close);
      await p.acquire('a');
      p.release('a');
      clock = clock.add(const Duration(minutes: 1));
      await p.acquire('b');
      p.release('b');
      await p.acquire('c');
      expect(p.holds('a'), isTrue);
      expect(p.holds('b'), isFalse);
      await expectLater(
        p.acquire('b'),
        throwsA(
          isA<RouteRefusal>()
              .having((r) => r.status, 'status', 429)
              .having((r) => r.message, 'message', contains('Pinned')),
        ),
      );
      p.release('c');
      options = options.copyWith(pinned: {'a', 'c'});
      await expectLater(p.acquire('b'), throwsA(isA<RouteRefusal>()));
      options = options.copyWith(pinned: {});
      expect(await p.acquire('b'), isNotNull);
    });

    test('sweep honours pins, overrides, and explicit keep loaded', () async {
      options = options.copyWith(
        maxLoaded: 3,
        pinned: {'a'},
        idleById: {
          'a': Duration.zero,
          'b': null,
          'c': const Duration(seconds: 5),
        },
      );
      final p = pool();
      addTearDown(p.close);
      for (final id in ['a', 'b', 'c']) {
        await p.acquire(id);
        p.release(id);
      }
      clock = clock.add(const Duration(seconds: 6));
      await p.sweep();
      expect(p.loaded.map((m) => m.id), ['a', 'b']);
      clock = clock.add(const Duration(hours: 1));
      await p.sweep();
      expect(p.loaded.map((m) => m.id), ['a', 'b']);
      options = options.copyWith(pinned: {}, idleById: {});
      await p.sweep();
      expect(p.loaded, isEmpty);
    });

    test(
      'per-model limit applies even when global idle unload is off',
      () async {
        options = options.copyWith(
          keepLoaded: true,
          idleById: {'a': const Duration(seconds: 5)},
        );
        final p = pool();
        addTearDown(p.close);
        for (final id in ['a', 'b']) {
          await p.acquire(id);
          p.release(id);
        }
        clock = clock.add(const Duration(seconds: 6));
        await p.sweep();
        expect(p.holds('a'), isFalse);
        expect(p.holds('b'), isTrue);
      },
    );

    test('idle models unload after the limit, busy ones stay', () async {
      options = const PoolOptions(jit: true, idleUnload: Duration(minutes: 10));
      final p = pool();
      addTearDown(p.close);
      await p.acquire('a');
      p.release('a');
      await p.acquire('b');
      clock = clock.add(const Duration(minutes: 11));
      await p.sweep();
      expect(p.holds('a'), false);
      expect(p.holds('b'), true);
    });

    test('the chat\'s copy answers instead of loading a second', () async {
      chat = _PoolEngine('chat');
      chatModel = 'a';
      final p = pool();
      addTearDown(p.close);
      expect(await p.acquire('a'), same(chat));
      expect(p.usingChat, true);
      expect(loads, isEmpty);
      await expectLater(p.acquire('a'), throwsA(isA<RouteRefusal>()));
      p.release('a');
      expect(p.usingChat, false);
      chat!.busy = true;
      await expectLater(p.acquire('a'), throwsA(isA<RouteRefusal>()));
      expect(loads, isEmpty);
    });

    test(
      'reserved chat cannot be borrowed before native generation starts',
      () async {
        var reserved = true;
        final engine = _PoolEngine('chat');
        final p = ModelPool(
          primary: 'primary',
          installed: () => [_model('a')],
          load: (_, _) async => fail('Do not load a duplicate chat model'),
          settingsOf: (_) => const InferenceSettings(),
          newEngine: () => engine,
          options: () => const PoolOptions(jit: true),
          chatEngineFor: (_) => engine,
          chatReserved: () => reserved,
        );
        addTearDown(p.close);
        await expectLater(p.acquire('a'), throwsA(isA<RouteRefusal>()));
        expect(p.usingChat, isFalse);
        reserved = false;
        expect(await p.acquire('a'), same(engine));
        p.release('a');
      },
    );

    test('a failed load refuses and leaves nothing behind', () async {
      final p = pool(onLoad: (_) async => throw StateError('Out of memory.'));
      addTearDown(p.close);
      await expectLater(
        p.acquire('a'),
        throwsA(
          isA<RouteRefusal>()
              .having((r) => r.status, 'status', 503)
              .having((r) => r.message, 'message', contains('Out of memory')),
        ),
      );
      expect(p.holds('a'), false);
      await Future<void>.delayed(Duration.zero);
      expect(engines['a']!.disposed, true);
    });

    test('two requests for one model share a single load', () async {
      final gate = Completer<void>();
      final p = pool(onLoad: (_) => gate.future);
      addTearDown(p.close);
      final first = p.acquire('a');
      final second = p.acquire('a');
      gate.complete();
      expect(await first, isNotNull);
      await expectLater(second, throwsA(isA<RouteRefusal>()));
      expect(loads, ['a']);
    });

    test('close frees every copy', () async {
      final p = pool();
      await p.acquire('a');
      await p.acquire('b');
      await p.close();
      expect(engines.values.every((e) => e.disposed), true);
      expect(await p.acquire('c'), isNull);
    });

    test('options survive a round trip', () {
      const o = PoolOptions(
        jit: true,
        maxLoaded: 3,
        idleUnload: null,
        pinned: {'a'},
        idleById: {'a': null, 'b': Duration(seconds: 42, microseconds: 123)},
      );
      final back = PoolOptions.fromJson(
        jsonDecode(jsonEncode(o.toJson())) as Map<String, dynamic>,
      );
      expect(back.pinned, {'a'});
      expect(back.idleById, o.idleById);
      final copied = back.copyWith(jit: false);
      expect(copied.pinned, back.pinned);
      expect(copied.idleById, back.idleById);
      final cleared = copied.copyWith(pinned: {}, idleById: {});
      expect(cleared.pinned, isEmpty);
      expect(cleared.idleById, isEmpty);
      final old = PoolOptions.fromJson({
        'jit': true,
        'maxLoaded': 4,
        'idleMinutes': 5,
      });
      expect(old.jit, isTrue);
      expect(old.maxLoaded, 4);
      expect(old.idleUnload, const Duration(minutes: 5));
      expect(old.pinned, isEmpty);
      expect(old.idleById, isEmpty);
      expect(back.jit, true);
      expect(back.maxLoaded, 3);
      expect(back.idleUnload, isNull);
      expect(PoolOptions.fromJson(const {}).idleUnload, isNotNull);
    });
  });
}
