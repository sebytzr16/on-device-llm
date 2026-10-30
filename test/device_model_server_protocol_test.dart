import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/request_queue.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

import 'device_model_server_test.dart' show FakeEngine;

class _RawEngine extends FakeEngine implements RawCompletionEngine {
  String? rawPrompt;
  @override
  Stream<String> generateRaw({
    required String prompt,
    required InferenceSettings settings,
  }) async* {
    rawPrompt = prompt;
    received.add(settings);
    yield prompt;
  }
}

class _BrokenEngine extends FakeEngine {
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    yield 'first';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw StateError('failed after first token');
  }
}

class _Vectors extends ServedVectorEngine {
  bool called = false;
  final bool measurable;
  _Vectors({this.measurable = true});
  @override
  Map<String, String> get models => {'embed': 'embedding', 'rank': 'rerank'};
  @override
  Future<({List<int> counts, int limit})?> tokenCounts(
    String model,
    List<String> input,
  ) async => measurable
      ? (counts: [for (final text in input) text.length], limit: 10)
      : null;
  @override
  Future<List<List<double>>> embed(
    String model,
    List<String> input,
    int dims,
  ) async {
    called = true;
    return [
      for (final _ in input) [1.0, -2.5],
    ];
  }

  @override
  Future<List<double>> rerank(
    String model,
    String query,
    List<String> documents,
  ) async => [];
}

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  late DeviceModelServer server;
  late HttpClient client;
  late FakeEngine engine;
  late _Vectors vectors;
  final messages = [
    {'role': 'user', 'content': 'hi'},
  ];

  Future<void> start(FakeEngine next, {_Vectors? vectorEngine}) async {
    engine = next;
    server = DeviceModelServer(
      engine: engine,
      settings: () => const InferenceSettings(),
      modelId: 'test',
      fallbackTemplate: 'must-not-be-used-for-raw',
      accessToken: token,
      vectors: vectorEngine,
    );
    await server.start();
  }

  Future<HttpClientResponse> ask(
    String path, {
    Map<String, Object?>? body,
    String method = 'POST',
    bool auth = true,
    bool apiKey = false,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (auth) {
      request.headers.set(
        apiKey ? 'x-api-key' : 'authorization',
        apiKey ? token : 'Bearer $token',
      );
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    return request.close();
  }

  Future<Map> json(HttpClientResponse response) async =>
      jsonDecode(await utf8.decoder.bind(response).join()) as Map;

  setUp(() async {
    client = HttpClient();
    vectors = _Vectors();
    await start(_RawEngine(), vectorEngine: vectors);
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test(
    'preflight precedes auth; error responses carry CORS; loopback stays default',
    () async {
      final preflight = await ask(
        '/v1/messages',
        method: 'OPTIONS',
        auth: false,
      );
      expect(preflight.statusCode, 204);
      expect(preflight.headers.value('access-control-allow-origin'), '*');
      expect(
        preflight.headers.value('access-control-allow-methods'),
        contains('POST'),
      );
      expect(
        preflight.headers.value('access-control-allow-headers'),
        contains('X-API-Key'),
      );
      await preflight.drain<void>();
      final denied = await ask('/v1/models', method: 'GET', auth: false);
      expect(denied.statusCode, 401);
      expect(denied.headers.value('access-control-allow-origin'), '*');
      await denied.drain<void>();
      expect(server.address!.isLoopback, true);
    },
  );

  test('Anthropic x-api-key authenticates and overlays sampling', () async {
    final response = await ask(
      '/v1/messages',
      apiKey: true,
      body: {
        'messages': messages,
        'max_tokens': 8,
        'top_p': 0.3,
        'stop_sequences': ['END'],
      },
    );
    expect(response.statusCode, 200);
    await response.drain<void>();
    expect(engine.received.single.topP, 0.3);
    expect(engine.received.single.stopSequences, ['END']);
    final denied = await ask('/v1/models', apiKey: true, method: 'GET');
    expect(denied.statusCode, 401);
    await denied.drain<void>();
  });

  test(
    'sampling is request local for chat and raw completion, JSON and SSE',
    () async {
      for (final path in ['/v1/chat/completions', '/v1/completions']) {
        for (final stream in [false, true]) {
          final response = await ask(
            path,
            body: {
              if (path.endsWith('/chat/completions'))
                'messages': messages
              else
                'prompt': ['raw <|im_start|>\n'],
              'stream': stream,
              'temperature': 0,
              'top_p': 0.7,
              'top_k': 0,
              'min_p': 0.2,
              'seed': 42,
              'stop': ['STOP'],
              'presence_penalty': -0.5,
              'frequency_penalty': 1.5,
              'repeat_penalty': 1.2,
              'max_completion_tokens': 11,
            },
          );
          expect(response.statusCode, 200);
          final text = await utf8.decoder.bind(response).join();
          if (path == '/v1/completions') {
            expect((engine as _RawEngine).rawPrompt, 'raw <|im_start|>\n');
            expect(text, contains('text_completion'));
          }
          final settings = engine.received.last;
          expect(settings.temperature, 0);
          expect(settings.topP, 0.7);
          expect(settings.topK, 0);
          expect(settings.minP, 0.2);
          expect(settings.seed, 42);
          expect(settings.stopSequences, ['STOP']);
          expect(settings.presencePenalty, -0.5);
          expect(settings.frequencyPenalty, 1.5);
          expect(settings.repetitionPenalty, 1.2);
          expect(settings.maxTokens, 11);
        }
      }
      expect(const InferenceSettings().topP, 0.95);
    },
  );

  for (final cases in [
    <String, Object?>{
      'temperature': 'hot',
      'top_p': 2,
      'top_k': 1.5,
      'min_p': -1,
      'seed': -1,
      'max_tokens': 0,
      'max_completion_tokens': 1.2,
    },
    <String, Object?>{
      'temperature': 2.1,
      'top_p': [],
      'presence_penalty': 3,
      'frequency_penalty': 'a',
      'repeat_penalty': -1,
      'stop': [1],
      'stream_options': {'include_usage': 'yes'},
    },
  ]) {
    test(
      'invalid sampling returns field-specific 400: ${cases.keys.join(', ')}',
      () async {
        for (final entry in cases.entries) {
          final response = await ask(
            '/v1/chat/completions',
            body: {'messages': messages, entry.key: entry.value},
          );
          expect(response.statusCode, 400, reason: entry.key);
          final error = (await json(response))['error'] as Map;
          expect(error['type'], 'invalid_request_error');
          expect(error['message'], contains(entry.key));
        }
        expect(engine.received, isEmpty);
      },
    );
  }

  test(
    'finish length and measured usage propagate to all protocols and modes',
    () async {
      engine.reportedMetrics = {
        'finishReason': 'length',
        'promptTokens': 17,
        'tokens': 9,
      };
      for (final path in [
        '/v1/chat/completions',
        '/v1/messages',
        '/v1/completions',
      ]) {
        for (final stream in [false, true]) {
          final response = await ask(
            path,
            body: {
              if (path == '/v1/completions')
                'prompt': 'x'
              else
                'messages': messages,
              'stream': stream,
              'stream_options': {'include_usage': true},
            },
          );
          expect(response.statusCode, 200);
          final text = await utf8.decoder.bind(response).join();
          expect(
            text,
            contains(
              path == '/v1/messages'
                  ? '"stop_reason":"max_tokens"'
                  : '"finish_reason":"length"',
            ),
          );
          expect(
            text,
            contains(
              path == '/v1/messages'
                  ? '"output_tokens":9'
                  : '"completion_tokens":9',
            ),
          );
        }
      }
    },
  );

  test('midstream failures produce protocol errors and OpenAI DONE', () async {
    await server.stop();
    await start(_BrokenEngine());
    for (final path in [
      '/v1/chat/completions',
      '/v1/messages',
      '/v1/responses',
    ]) {
      final response = await ask(
        path,
        body: {
          if (path == '/v1/responses') 'input': 'hi' else 'messages': messages,
          'stream': true,
        },
      );
      final text = await utf8.decoder.bind(response).join();
      expect(text, contains('first'));
      expect(text, contains('"error":'));
      if (path == '/v1/chat/completions') {
        expect(text, endsWith('data: [DONE]\n\n'));
      } else {
        expect(text, contains('event: error'));
      }
    }
  });

  test(
    'Responses is a stateless chat adapter with text and completed events',
    () async {
      for (final stream in [false, true]) {
        for (final input in ['hi', messages]) {
          final response = await ask(
            '/v1/responses',
            body: {'input': input, 'stream': stream},
          );
          expect(response.statusCode, 200);
          final text = await utf8.decoder.bind(response).join();
          if (stream) {
            expect(text, contains('event: response.output_text.delta'));
            expect(text, contains('event: response.completed'));
          } else {
            expect((jsonDecode(text) as Map)['output_text'], 'Hello hi');
          }
        }
      }
    },
  );

  test('raw capability absence is explicit; invalid prompts are 400', () async {
    final bad = await ask(
      '/v1/completions',
      body: {
        'prompt': ['a', 'b'],
      },
    );
    expect(bad.statusCode, 400);
    await bad.drain<void>();
    await server.stop();
    await start(FakeEngine());
    final unavailable = await ask('/v1/completions', body: {'prompt': 'hello'});
    expect(unavailable.statusCode, 503);
    expect(
      (await json(unavailable))['error']['message'],
      contains('raw-prompt API'),
    );
    expect(engine.received, isEmpty);
  });

  test(
    'vector discovery, float32 base64 encoding and measured batch usage',
    () async {
      final models = await json(await ask('/v1/models', method: 'GET'));
      expect(models['data'], contains(containsPair('type', 'embedding')));
      for (final encoding in ['float', 'base64']) {
        final response = await ask(
          '/v1/embeddings',
          body: {
            'model': 'embed',
            'input': ['abc', 'xy'],
            'encoding_format': encoding,
          },
        );
        expect(response.statusCode, 200);
        final body = await json(response);
        expect(body['usage'], {'prompt_tokens': 5, 'total_tokens': 5});
        final vector = body['data'][0]['embedding'];
        if (encoding == 'base64') {
          final bytes = base64Decode(vector as String);
          expect(
            ByteData.sublistView(bytes).getFloat32(4, Endian.little),
            -2.5,
          );
        } else {
          expect(vector, [1.0, -2.5]);
        }
      }
    },
  );

  test(
    'oversize embeddings rejected before inference with exact count and limit',
    () async {
      final response = await ask(
        '/v1/embeddings',
        body: {'model': 'embed', 'input': '12345678901'},
      );
      expect(response.statusCode, 400);
      final error = (await json(response))['error']['message'];
      expect(error, contains('11 tokens'));
      expect(error, contains('10 tokens'));
      expect(vectors.called, false);
    },
  );

  test('unmeasurable embeddings fail closed, never truncate', () async {
    await server.stop();
    final unavailable = _Vectors(measurable: false);
    await start(FakeEngine(), vectorEngine: unavailable);
    final response = await ask(
      '/v1/embeddings',
      body: {'model': 'embed', 'input': 'hi'},
    );
    expect(response.statusCode, 503);
    expect(
      (await json(response))['error']['message'],
      contains('exact token counts'),
    );
    expect(unavailable.called, false);
  });

  test(
    'queue is FIFO, bounded to eight waiters, independent per model',
    () async {
      final queue = RequestQueue();
      await queue.acquire('a');
      final order = <int>[];
      final waiting = [
        for (var i = 0; i < 8; i++)
          queue.acquire('a').then((_) => order.add(i)),
      ];
      await expectLater(
        queue.acquire('a'),
        throwsA(isA<RouteRefusal>().having((e) => e.status, 'status', 429)),
      );
      await queue.acquire('b');
      queue.release('b');
      for (var i = 0; i < 8; i++) {
        queue.release('a');
        await waiting[i];
      }
      expect(order, List.generate(8, (i) => i));
      queue.release('a');
      await queue.acquire('a');
      final pending = queue.acquire('a');
      final stopped = expectLater(
        pending,
        throwsA(isA<RouteRefusal>().having((e) => e.status, 'status', 503)),
      );
      queue.close();
      await stopped;
    },
  );

  test('invalid embedding encoding and unknown models return 400', () async {
    for (final body in [
      {'model': 'embed', 'input': 'hi', 'encoding_format': 'hex'},
      {'model': 'missing', 'input': 'hi'},
      {'model': 'embed', 'input': 'hi', 'dimensions': 1.5},
    ]) {
      final response = await ask('/v1/embeddings', body: body);
      expect(response.statusCode, 400);
      await response.drain<void>();
    }
    expect(vectors.called, false);
  });

  test('missing vector runtime reports prerequisites in a 503', () async {
    await server.stop();
    await start(FakeEngine());
    final response = await ask(
      '/v1/embeddings',
      body: {'model': 'embed', 'input': 'hi'},
    );
    expect(response.statusCode, 503);
    final error = (await json(response))['error']['message'];
    expect(error, contains('independent vector runtime'));
    expect(error, contains('tokenizer/context-limit'));
  });

  test('retired thinkOnSearch key is tolerated but never persisted', () {
    final settings = InferenceSettings.fromJson({
      'thinkOnSearch': true,
      'explicitOverrides': ['thinkOnSearch', 'temperature'],
    });
    expect(settings.toJson().containsKey('thinkOnSearch'), false);
    expect(settings.explicitOverrides, {'temperature'});
    expect(
      InferenceSettings.fromJson({'thinkOnSearch': false}).explicitOverrides,
      isNot(contains('thinkOnSearch')),
    );
  });
}
