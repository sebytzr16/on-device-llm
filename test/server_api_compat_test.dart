import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';

import 'device_model_server_test.dart' show FakeEngine;

/// Yields one chunk and then fails, so a terminal SSE error event can be
/// observed after normal streaming already began.
class _FailingEngine extends FakeEngine {
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    yield 'partial ';
    throw StateError('boom');
  }
}

/// Yields pieces forever until cancel() is called, so a non-streaming
/// client hang-up can be observed mid-generation.
class _HangEngine extends FakeEngine {
  final cancelled = Completer<void>();

  @override
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
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
    while (!cancelled.isCompleted) {
      yield 'piece';
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// Serves two vector model ids: one embedding, one rerank.
class _CompatVectors extends ServedVectorEngine {
  @override
  Map<String, String> get models => {
    'embed-model': 'embedding',
    'rerank-model': 'rerank',
  };

  @override
  Future<({List<int> counts, int limit})?> tokenCounts(
    String model,
    List<String> input,
  ) async => (counts: [for (final text in input) text.length], limit: 4096);

  @override
  Future<List<List<double>>> embed(
    String model,
    List<String> input,
    int dims,
  ) async => [
    for (final text in input) [text.length.toDouble(), text.length + 1.0],
  ];

  @override
  Future<List<double>> rerank(
    String model,
    String query,
    List<String> documents,
  ) async => [for (final text in documents) text.length.toDouble()];
}

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  late DeviceModelServer server;
  late HttpClient client;
  final messages = [
    {'role': 'user', 'content': 'hi'},
  ];

  Future<HttpClientResponse> ask(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
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
    return request.close().timeout(const Duration(seconds: 3));
  }

  Future<String> bodyOf(HttpClientResponse response) =>
      utf8.decoder.bind(response).join().timeout(const Duration(seconds: 3));

  setUp(() async {
    client = HttpClient()..maxConnectionsPerHost = 32;
    server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test-model',
      fallbackTemplate: '',
      accessToken: token,
      vectors: _CompatVectors(),
    );
    await server.start();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test(
    'N36: OPTIONS preflight answers 204 without a token, with CORS headers',
    () async {
      for (final path in [
        '/v1/models',
        '/v1/chat/completions',
        '/v1/embeddings',
        '/v1/messages',
      ]) {
        final response = await ask(path, method: 'OPTIONS', auth: false);
        expect(response.statusCode, HttpStatus.noContent, reason: path);
        expect(
          response.headers.value('access-control-allow-origin'),
          '*',
          reason: path,
        );
        expect(
          response.headers.value('access-control-allow-methods'),
          contains('OPTIONS'),
          reason: path,
        );
        final allowHeaders =
            (response.headers.value('access-control-allow-headers') ?? '')
                .toLowerCase();
        for (final header in [
          'authorization',
          'content-type',
          'x-api-key',
          'anthropic-version',
        ]) {
          expect(allowHeaders, contains(header), reason: '$path $header');
        }
        await response.drain<void>();
      }
    },
  );

  test(
    'N36: other responses carry CORS headers and token auth is unchanged',
    () async {
      final denied = await ask('/v1/models', auth: false);
      expect(denied.statusCode, HttpStatus.unauthorized);
      expect(denied.headers.value('access-control-allow-origin'), '*');
      await denied.drain<void>();
      final postDenied = await ask(
        '/v1/chat/completions',
        method: 'POST',
        auth: false,
        body: {'messages': messages},
      );
      expect(postDenied.statusCode, HttpStatus.unauthorized);
      await postDenied.drain<void>();
      final ok = await ask('/v1/models');
      expect(ok.statusCode, HttpStatus.ok);
      expect(ok.headers.value('access-control-allow-origin'), '*');
      await ok.drain<void>();
    },
  );

  test(
    'N37: OpenAI stream emits a terminal error frame then [DONE] mid-stream',
    () async {
      await server.stop();
      server = DeviceModelServer(
        engine: _FailingEngine(),
        settings: () => const InferenceSettings(),
        modelId: 'test-model',
        fallbackTemplate: '',
        accessToken: token,
      );
      await server.start();
      final response = await ask(
        '/v1/chat/completions',
        method: 'POST',
        body: {'messages': messages, 'stream': true},
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      expect(response.headers.value('access-control-allow-origin'), '*');
      final events = await bodyOf(response);
      expect(events, contains('"content":"partial "'));
      final errorAt = events.indexOf('data: {"error":');
      expect(errorAt, greaterThan(events.indexOf('"content":"partial "')));
      expect(events, contains('"type":"server_error"'));
      expect(events.trim(), endsWith('data: [DONE]'));
    },
  );

  test(
    'N37: Anthropic /v1/messages stream ends with event: error mid-stream',
    () async {
      await server.stop();
      server = DeviceModelServer(
        engine: _FailingEngine(),
        settings: () => const InferenceSettings(),
        modelId: 'test-model',
        fallbackTemplate: '',
        accessToken: token,
      );
      await server.start();
      final response = await ask(
        '/v1/messages',
        method: 'POST',
        apiKey: true,
        body: {'messages': messages, 'stream': true, 'max_tokens': 16},
      );
      expect(response.statusCode, HttpStatus.ok);
      final events = await bodyOf(response);
      expect(events, contains('event: message_start'));
      expect(events, contains('"text":"partial "'));
      expect(events, contains('event: error'));
      expect(events, contains('"type":"error","error":{'));
      expect(events, contains('"type":"server_error"'));
    },
  );

  test(
    'N40: /v1/models lists the chat model and every served vector model',
    () async {
      final response = await ask('/v1/models');
      expect(response.statusCode, HttpStatus.ok);
      final data = jsonDecode(await bodyOf(response)) as Map;
      final byId = <String, Map>{};
      for (final entry in data['data'] as List) {
        final model = entry as Map;
        byId[model['id'] as String] = model;
      }
      expect(byId.keys, {'test-model', 'embed-model', 'rerank-model'});
      expect(byId['test-model']!['type'], 'chat');
      expect(byId['embed-model'], {
        'id': 'embed-model',
        'object': 'model',
        'owned_by': 'device-vector',
        'type': 'embedding',
      });
      expect(byId['rerank-model']!['owned_by'], 'device-vector');
      expect(byId['rerank-model']!['type'], 'rerank');
    },
  );

  test(
    'N41: embeddings default to float arrays, base64 only when asked',
    () async {
      final plain = await ask(
        '/v1/embeddings',
        method: 'POST',
        body: {
          'model': 'embed-model',
          'input': ['ab', 'c'],
        },
      );
      expect(plain.statusCode, HttpStatus.ok);
      final decoded = jsonDecode(await bodyOf(plain)) as Map;
      expect(decoded['data'][0]['embedding'], [2.0, 3.0]);
      expect(decoded['data'][1]['embedding'], [1.0, 2.0]);

      final asFloat = await ask(
        '/v1/embeddings',
        method: 'POST',
        body: {
          'model': 'embed-model',
          'input': 'ab',
          'encoding_format': 'float',
        },
      );
      final floatBody = jsonDecode(await bodyOf(asFloat)) as Map;
      expect(floatBody['data'][0]['embedding'], [2.0, 3.0]);

      final asBase64 = await ask(
        '/v1/embeddings',
        method: 'POST',
        body: {
          'model': 'embed-model',
          'input': 'ab',
          'encoding_format': 'base64',
        },
      );
      final b64Body = jsonDecode(await bodyOf(asBase64)) as Map;
      final encoded = b64Body['data'][0]['embedding'] as String;
      final bytes = ByteData.sublistView(base64Decode(encoded));
      expect(bytes.getFloat32(0, Endian.little), 2.0);
      expect(bytes.getFloat32(4, Endian.little), 3.0);

      final bad = await ask(
        '/v1/embeddings',
        method: 'POST',
        body: {'model': 'embed-model', 'input': 'ab', 'encoding_format': 'hex'},
      );
      expect(bad.statusCode, HttpStatus.badRequest);
      await bad.drain<void>();
    },
  );

  test(
    'N29: /v1/messages accepts a system prompt given as text blocks',
    () async {
      final engine = server.engine as FakeEngine;
      final response = await ask(
        '/v1/messages',
        method: 'POST',
        apiKey: true,
        body: {
          'max_tokens': 16,
          'system': [
            {'type': 'text', 'text': 'Be terse.'},
            {'type': 'text', 'text': 'Always.'},
          ],
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
      );
      expect(response.statusCode, HttpStatus.ok);
      await bodyOf(response);
      expect(engine.lastMessages.first, {
        'role': 'system',
        'content': 'Be terse.\nAlways.',
      });
    },
  );

  test(
    'N29: tool_result content as an array of text blocks is accepted',
    () async {
      final engine = server.engine as FakeEngine;
      final response = await ask(
        '/v1/messages',
        method: 'POST',
        apiKey: true,
        body: {
          'max_tokens': 16,
          'messages': [
            {'role': 'user', 'content': 'hi'},
            {
              'role': 'assistant',
              'content': [
                {
                  'type': 'tool_use',
                  'id': 't1',
                  'name': 'lookup',
                  'input': {'k': 'v'},
                },
              ],
            },
            {
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': 't1',
                  'content': [
                    {'type': 'text', 'text': 'line1'},
                    {'type': 'text', 'text': 'line2'},
                  ],
                },
                {'type': 'text', 'text': 'Again'},
              ],
            },
          ],
        },
      );
      expect(response.statusCode, HttpStatus.ok);
      await bodyOf(response);
      expect(engine.lastMessages[1]['tool_calls'], isA<List>());
      final tool = engine.lastMessages[2];
      expect(tool['role'], 'tool');
      expect(tool['tool_call_id'], 't1');
      expect(tool['content'], 'line1\nline2');
      expect(engine.lastMessages.last, {'role': 'user', 'content': 'Again'});
    },
  );

  test(
    'N29: thinking blocks are skipped and image blocks reach the projector',
    () async {
      await server.stop();
      final engine = FakeEngine();
      server = DeviceModelServer(
        engine: engine,
        settings: () => const InferenceSettings(),
        modelId: 'test-model',
        fallbackTemplate: '',
        accessToken: token,
        hasProjector: (_) => true,
      );
      await server.start();
      final response = await ask(
        '/v1/messages',
        method: 'POST',
        apiKey: true,
        body: {
          'max_tokens': 16,
          'messages': [
            {
              'role': 'assistant',
              'content': [
                {'type': 'thinking', 'thinking': 'hmm', 'signature': 's'},
                {'type': 'text', 'text': 'ok'},
              ],
            },
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'See '},
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': 'image/png',
                    'data': 'AA==',
                  },
                },
              ],
            },
          ],
        },
      );
      expect(response.statusCode, HttpStatus.ok);
      await bodyOf(response);
      expect(engine.lastMessages[0], {'role': 'assistant', 'content': 'ok'});
      expect(
        engine.lastMessages[1]['content'],
        'See ${TextEngine.mediaMarker}',
      );
      expect(engine.lastMessages[1]['images'], hasLength(1));
    },
  );

  test(
    'N29: unsupported content blocks get a clear 400, not a crash or 500',
    () async {
      final engine = server.engine as FakeEngine;
      for (final block in [
        {
          'type': 'document',
          'source': {
            'type': 'base64',
            'media_type': 'application/pdf',
            'data': 'AA==',
          },
        },
        {
          'type': 'image',
          'source': {'type': 'url', 'url': 'https://example.com/x.png'},
        },
        {'type': 'web_search_tool_result', 'content': <Object>[]},
        'not-a-map',
      ]) {
        final response = await ask(
          '/v1/messages',
          method: 'POST',
          apiKey: true,
          body: {
            'max_tokens': 16,
            'messages': [
              {
                'role': 'user',
                'content': [block],
              },
            ],
          },
        );
        expect(response.statusCode, HttpStatus.badRequest, reason: '$block');
        final decoded = jsonDecode(await bodyOf(response)) as Map;
        expect(
          decoded['error']['type'],
          'invalid_request_error',
          reason: '$block',
        );
      }
      expect(engine.received, isEmpty);
    },
  );

  test(
    'N43: embedding usage reports the measured token counts, not zero',
    () async {
      final response = await ask(
        '/v1/embeddings',
        method: 'POST',
        body: {
          'model': 'embed-model',
          'input': ['ab', 'c'],
        },
      );
      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await bodyOf(response)) as Map;
      expect(body['usage'], {'prompt_tokens': 3, 'total_tokens': 3});
    },
  );

  test(
    'N60: a non-streaming client hang-up cancels generation promptly',
    () async {
      await server.stop();
      final engine = _HangEngine();
      final started = Completer<void>();
      server = DeviceModelServer(
        engine: engine,
        settings: () => const InferenceSettings(),
        modelId: 'test-model',
        fallbackTemplate: '',
        accessToken: token,
        onProgress: (_) {
          if (!started.isCompleted) started.complete();
        },
      );
      await server.start();
      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      addTearDown(engine.cancel);
      final body = jsonEncode({
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      socket.write(
        'POST /v1/chat/completions HTTP/1.1\r\n'
        'Host: localhost\r\n'
        'Authorization: Bearer $token\r\n'
        'Content-Type: application/json\r\n'
        'Content-Length: ${utf8.encode(body).length}\r\n\r\n'
        '$body',
      );
      await socket.flush();
      await started.future.timeout(const Duration(seconds: 2));
      socket.destroy();
      await engine.cancelled.future.timeout(const Duration(seconds: 2));
    },
  );
}
