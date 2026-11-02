import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_usage.dart';

class FakeEngine implements TextEngine {
  final received = <InferenceSettings>[];
  List<Map<String, Object>> lastMessages = [];
  List<ToolSpec> lastTools = [];
  String lastToolChoice = '';
  Map<String, dynamic> reportedMetrics = {};
  @override
  Map<String, dynamic> get metrics => reportedMetrics;
  @override
  void cancel() {}
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => const {};
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
    lastMessages = messages;
    lastTools = tools;
    lastToolChoice = toolChoice;
    yield 'Hello ';
    yield messages.last['content'] as String;
  }
}

class _SlowEngine extends FakeEngine implements RawCompletionEngine {
  final cancelled = Completer<void>();

  @override
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }

  Stream<String> _pieces() async* {
    if (cancelled.isCompleted) {
      yield 'recovered';
      return;
    }
    while (!cancelled.isCompleted) {
      yield 'slow piece';
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    reportedMetrics = {'tokens': 1};
  }

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) => _pieces();

  @override
  Stream<String> generateRaw({
    required String prompt,
    required InferenceSettings settings,
  }) => _pieces();
}

/// Holds every answer until [gate] opens, counting how many run at once.
class _GatedEngine extends FakeEngine {
  final Completer<void> gate;
  final void Function() onStart, onEnd;
  _GatedEngine(this.gate, this.onStart, this.onEnd);

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    onStart();
    try {
      await gate.future;
      yield 'ok';
    } finally {
      onEnd();
    }
  }
}

class _FakeVectors extends ServedVectorEngine {
  @override
  Map<String, String> get models => {'vector': 'embedding'};
  @override
  Future<({List<int> counts, int limit})?> tokenCounts(
    String model,
    List<String> input,
  ) async => (counts: [for (final text in input) text.length], limit: 32);

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
  late List<ServedRequest> served;

  setUp(() async {
    served = [];
    server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test-model',
      fallbackTemplate: '',
      accessToken: token,
      onServed: served.add,
    );
    client = HttpClient();
    await server.start();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<HttpClientResponse> request(
    String method,
    String path, {
    String? body,
    String? auth,
  }) async {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (auth != null) req.headers.set('authorization', 'Bearer $auth');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(body);
    }
    return req.close();
  }

  test(
    'response_format is request-local for streaming and normal completions',
    () async {
      await server.stop();
      final engine = FakeEngine();
      const saved = InferenceSettings(
        responseFormat: ResponseFormat.gbnf,
        grammar: 'root ::= "yes"',
      );
      server = DeviceModelServer(
        engine: engine,
        settings: () => saved,
        modelId: 'test-model',
        fallbackTemplate: '',
        accessToken: token,
      );
      await server.start();
      for (final streaming in [false, true]) {
        for (final (format, expected) in [
          ({'type': 'text'}, ResponseFormat.text),
          ({'type': 'json_object'}, ResponseFormat.json),
          (
            {
              'type': 'json_schema',
              'json_schema': {
                'name': 'answer',
                'schema': {'type': 'object'},
                'strict': true,
              },
            },
            ResponseFormat.jsonSchema,
          ),
        ]) {
          final response = await request(
            'POST',
            DeviceModelServer.completionsPath,
            auth: token,
            body: jsonEncode({
              'messages': [
                {'role': 'user', 'content': 'hi'},
              ],
              'response_format': format,
              'stream': streaming,
            }),
          );
          expect(response.statusCode, 200);
          await response.drain<void>();
          expect(engine.received.last.responseFormat, expected);
          expect(engine.received.last.grammar, isEmpty);
          if (expected == ResponseFormat.jsonSchema) {
            expect(jsonDecode(engine.received.last.jsonSchema), {
              'type': 'object',
            });
          }
          expect(server.settings(), same(saved));
        }
      }
      final response = await request(
        'POST',
        DeviceModelServer.completionsPath,
        auth: token,
        body: jsonEncode({
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );
      await response.drain<void>();
      expect(engine.received.last.responseFormat, saved.responseFormat);
      expect(engine.received.last.grammar, saved.grammar);
    },
  );

  for (final invalid in [
    null,
    'json',
    [],
    {},
    {'type': 'other'},
    {'type': 'json_schema'},
    {
      'type': 'json_schema',
      'json_schema': {'name': '', 'schema': {}},
    },
    {
      'type': 'json_schema',
      'json_schema': {'name': 'answer', 'schema': []},
    },
    {
      'type': 'json_schema',
      'json_schema': {'name': 'answer', 'schema': {}, 'strict': 'true'},
    },
  ]) {
    test('rejects malformed response_format: $invalid', () async {
      final response = await request(
        'POST',
        DeviceModelServer.completionsPath,
        auth: token,
        body: jsonEncode({
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'response_format': invalid,
        }),
      );
      expect(response.statusCode, 400);
      final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      expect(body['error']['type'], 'invalid_request_error');
      expect(body['error']['param'], 'response_format');
      expect(body['error']['message'], startsWith('response_format'));
      expect((server.engine as FakeEngine).received, isEmpty);
    });
  }

  test('requires bearer authentication and exposes model metadata', () async {
    expect((await request('GET', '/v1/models')).statusCode, 401);
    final response = await request('GET', '/v1/models', auth: token);
    expect(response.statusCode, 200);
    final data = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect((data['data'] as List).first['id'], 'test-model');
  });

  for (final path in [
    '/v1/chat/completions',
    '/v1/completions',
    '/v1/responses',
    '/v1/messages',
  ]) {
    test(
      'cancels generation when the streaming peer disconnects: $path',
      () async {
        await server.stop();
        final engine = _SlowEngine();
        final finished = Completer<void>();
        server = DeviceModelServer(
          engine: engine,
          settings: () => const InferenceSettings(),
          modelId: 'test-model',
          fallbackTemplate: '',
          accessToken: token,
          onServed: (entry) {
            served.add(entry);
            if (!finished.isCompleted) finished.complete();
          },
        );
        await server.start();
        final socket = await Socket.connect('127.0.0.1', server.port!);
        addTearDown(socket.destroy);
        addTearDown(engine.cancel);
        final firstDelta = Completer<void>();
        final received = StringBuffer();
        socket.listen((bytes) {
          received.write(utf8.decode(bytes));
          if (received.toString().contains('slow piece') &&
              !firstDelta.isCompleted) {
            firstDelta.complete();
          }
        });
        final body = jsonEncode({
          'model': 'test-model',
          'stream': true,
          'max_tokens': 1000,
          if (path == '/v1/completions')
            'prompt': 'hi'
          else if (path == '/v1/responses')
            'input': 'hi'
          else
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
        });
        socket.write(
          'POST $path HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'Authorization: Bearer $token\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: ${utf8.encode(body).length}\r\n\r\n'
          '$body',
        );
        await socket.flush();
        await firstDelta.future.timeout(const Duration(seconds: 2));
        socket.destroy();
        await engine.cancelled.future.timeout(const Duration(seconds: 2));
        await finished.future.timeout(const Duration(seconds: 2));
        expect(served.single.stream, true);
        expect(served.single.completion, true);
        expect(served.single.completionTokens, 1);

        final next = await request(
          'POST',
          '/v1/chat/completions',
          auth: token,
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          }),
        ).timeout(const Duration(seconds: 2));
        expect(next.statusCode, HttpStatus.ok);
        expect(await utf8.decoder.bind(next).join(), contains('recovered'));
      },
    );
  }

  test(
    'streaming timeout cancels generation and closes with an error',
    () async {
      await server.stop();
      final engine = _SlowEngine();
      server = DeviceModelServer(
        engine: engine,
        settings: () => const InferenceSettings(),
        modelId: 'test-model',
        fallbackTemplate: '',
        accessToken: token,
        generationTimeout: const Duration(milliseconds: 50),
        onServed: served.add,
      );
      await server.start();
      final response = await request(
        'POST',
        '/v1/messages',
        auth: token,
        body: jsonEncode({
          'max_tokens': 1000,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'stream': true,
        }),
      );
      final events = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 2));
      expect(engine.cancelled.isCompleted, true);
      expect(events, contains('event: error'));
      expect(events, contains('Request timed out.'));
      expect(served.single.error, 'Request timed out.');
    },
  );

  test('streams OpenAI-compatible content and completion', () async {
    final response = await request(
      'POST',
      '/v1/chat/completions',
      auth: token,
      body: jsonEncode({
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'world'},
        ],
        'stream': true,
      }),
    );
    expect(response.statusCode, 200);
    final events = await utf8.decoder.bind(response).join();
    expect(events, contains('"content":"Hello "'));
    expect(events, contains('"content":"world"'));
    expect(events, contains('data: [DONE]'));
  });

  test('returns a normal completion when stream is omitted', () async {
    final response = await request(
      'POST',
      '/v1/chat/completions',
      auth: token,
      body: jsonEncode({
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'world'},
        ],
      }),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect(body['object'], 'chat.completion');
    expect(
      (body['choices'] as List).first['message']['content'],
      'Hello world',
    );
  });

  test('keeps serving after its model moves to another runtime', () async {
    final first = server.engine as FakeEngine;
    final second = FakeEngine();
    server.useEngine(second);
    final response = await request(
      'POST',
      '/v1/chat/completions',
      auth: token,
      body: jsonEncode({
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'world'},
        ],
      }),
    );
    expect(response.statusCode, 200);
    await utf8.decoder.bind(response).join();
    expect(first.received, isEmpty);
    expect(second.received, hasLength(1));
  });

  test('rejects malformed tool definitions', () async {
    final response = await request(
      'POST',
      '/v1/chat/completions',
      auth: token,
      body: jsonEncode({
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'world'},
        ],
        'stream': true,
        'tools': [
          {
            'type': 'function',
            'function': {'name': 'lookup', 'description': 123},
          },
        ],
      }),
    );
    expect(response.statusCode, 400);
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect(body['error']['message'], contains('tools require'));
  });

  test('returns tool calls and accepts their result in history', () async {
    final engine = server.engine as FakeEngine;
    engine.reportedMetrics = {
      'toolCalls': [
        {'id': 'call_1', 'name': 'lookup', 'arguments': '{"key":"a"}'},
      ],
    };
    final response = await request(
      'POST',
      DeviceModelServer.completionsPath,
      auth: token,
      body: jsonEncode({
        'messages': [
          {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'old',
                'type': 'function',
                'function': {'name': 'lookup', 'arguments': '{}'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'old', 'content': 'done'},
          {'role': 'user', 'content': 'next'},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': 'lookup',
              'description': 'Look up a key',
              'parameters': {'type': 'object'},
            },
          },
        ],
        'tool_choice': {
          'type': 'function',
          'function': {'name': 'lookup'},
        },
      }),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect(body['choices'][0]['finish_reason'], 'tool_calls');
    expect(body['choices'][0]['message']['tool_calls'][0]['function'], {
      'name': 'lookup',
      'arguments': '{"key":"a"}',
    });
    expect(engine.lastTools.single.name, 'lookup');
    expect(engine.lastToolChoice, 'required');
    expect(engine.lastMessages[0]['tool_calls'], isA<List>());
    expect(engine.lastMessages[1]['tool_call_id'], 'old');
  });

  test('streams OpenAI tool call deltas', () async {
    (server.engine as FakeEngine).reportedMetrics = {
      'toolCalls': [
        {'id': 'call_1', 'name': 'lookup', 'arguments': '{}'},
      ],
    };
    final response = await request(
      'POST',
      DeviceModelServer.completionsPath,
      auth: token,
      body: jsonEncode({
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      }),
    );
    final events = await utf8.decoder.bind(response).join();
    expect(events, contains('"tool_calls":[{"index":0,"id":"call_1"'));
    expect(events, contains('"finish_reason":"tool_calls"'));
    expect(events, contains('data: [DONE]'));
  });

  test('refuses remote image URLs without fetching them', () async {
    final response = await request(
      'POST',
      DeviceModelServer.completionsPath,
      auth: token,
      body: jsonEncode({
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'https://example.com/a.png'},
              },
            ],
          },
        ],
      }),
    );
    expect(response.statusCode, 400);
    expect((server.engine as FakeEngine).received, isEmpty);
  });

  test(
    'passes image data through the desktop media path and removes it',
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
      final response = await request(
        'POST',
        DeviceModelServer.completionsPath,
        auth: token,
        body: jsonEncode({
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'See this '},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url':
                        'data:image/png;base64,${base64Encode([137, 80, 78, 71])}',
                  },
                },
              ],
            },
          ],
        }),
      );
      expect(response.statusCode, 200);
      await response.drain<void>();
      expect(
        engine.lastMessages.single['content'],
        'See this ${TextEngine.mediaMarker}',
      );
      final path =
          (engine.lastMessages.single['images'] as List).single as String;
      expect(File(path).existsSync(), isFalse);
    },
  );

  test('embeddings and rerank use the vector engine', () async {
    await server.stop();
    server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test-model',
      fallbackTemplate: '',
      accessToken: token,
      vectors: _FakeVectors(),
    );
    await server.start();
    final embedding = await request(
      'POST',
      DeviceModelServer.embeddingsPath,
      auth: token,
      body: jsonEncode({
        'model': 'vector',
        'input': ['a', 'bb'],
      }),
    );
    expect(embedding.statusCode, 200);
    final data = jsonDecode(await utf8.decoder.bind(embedding).join()) as Map;
    expect(data['data'][1]['embedding'], [2.0, 3.0]);
    final rerank = await request(
      'POST',
      DeviceModelServer.rerankPath,
      auth: token,
      body: jsonEncode({
        'model': 'vector',
        'query': 'q',
        'documents': ['a', 'bbb'],
      }),
    );
    final ranked = jsonDecode(await utf8.decoder.bind(rerank).join()) as Map;
    expect(ranked['results'][0]['index'], 1);
  });

  test('Anthropic stream orders message and tool events', () async {
    (server.engine as FakeEngine).reportedMetrics = {
      'toolCalls': [
        {'id': 'call_1', 'name': 'lookup', 'arguments': '{}'},
      ],
    };
    final response = await request(
      'POST',
      DeviceModelServer.messagesPath,
      auth: token,
      body: jsonEncode({
        'model': 'test-model',
        'max_tokens': 16,
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'tools': [
          {
            'name': 'lookup',
            'description': 'Find',
            'input_schema': {'type': 'object'},
          },
        ],
      }),
    );
    expect(response.statusCode, 200);
    final events = await utf8.decoder.bind(response).join();
    final names = RegExp(
      r'event: ([a-z_]+)',
    ).allMatches(events).map((m) => m.group(1)).toList();
    expect(names, [
      'message_start',
      'content_block_start',
      'content_block_delta',
      'content_block_delta',
      'content_block_stop',
      'content_block_start',
      'content_block_delta',
      'content_block_stop',
      'message_delta',
      'message_stop',
    ]);
    expect(events, contains('"stop_reason":"tool_use"'));
  });

  test('Anthropic tool result history and nonstream tool block', () async {
    final engine = server.engine as FakeEngine;
    engine.reportedMetrics = {
      'toolCalls': [
        {'id': 'next', 'name': 'lookup', 'arguments': '{"key":"b"}'},
      ],
    };
    final response = await request(
      'POST',
      DeviceModelServer.messagesPath,
      auth: token,
      body: jsonEncode({
        'model': 'test-model',
        'max_tokens': 16,
        'messages': [
          {
            'role': 'assistant',
            'content': [
              {'type': 'tool_use', 'id': 'old', 'name': 'lookup', 'input': {}},
            ],
          },
          {
            'role': 'user',
            'content': [
              {'type': 'tool_result', 'tool_use_id': 'old', 'content': 'found'},
              {'type': 'text', 'text': 'Again'},
            ],
          },
        ],
      }),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect(body['stop_reason'], 'tool_use');
    expect(body['content'][1], {
      'type': 'tool_use',
      'id': 'next',
      'name': 'lookup',
      'input': {'key': 'b'},
    });
    expect(engine.lastMessages[0]['tool_calls'], isA<List>());
    expect(engine.lastMessages[1]['tool_call_id'], 'old');
  });

  test('the app remote engine can use a hosted device model', () async {
    final remote = RemoteEngine(usage: RemoteUsageLog(prefs: () => null));
    final settings = InferenceSettings(
      remoteEnabled: true,
      remoteProfiles: [
        RemoteProfile(
          id: 'device',
          name: 'Other device',
          providerId: 'custom',
          baseUrl: 'http://127.0.0.1:${server.port}/v1/',
          model: 'test-model',
        ),
      ],
      remoteProfileId: 'device',
      remoteApiKeys: const {'device': token},
    );
    final answer = await remote
        .generate(
          messages: const [
            {'role': 'user', 'content': 'world'},
          ],
          fallbackTemplate: '',
          settings: settings,
        )
        .join();
    expect(answer, 'Hello world');
  });

  test('only local-network and VPN clients are served', () {
    bool ok(String a) => DeviceModelServer.allowedClient(InternetAddress(a));
    for (final a in [
      '127.0.0.1',
      '192.168.1.20',
      '10.0.0.5',
      '172.20.1.1',
      '169.254.3.4',
      '100.101.102.103',
      'fd7a:115c:a1e0::1',
      'fe80::1',
      '::1',
      '::ffff:192.168.1.9',
    ]) {
      expect(ok(a), isTrue, reason: a);
    }
    for (final a in [
      '8.8.8.8',
      '172.32.0.1',
      '100.128.0.1',
      '192.0.0.2',
      '2001:4860::8888',
      '::ffff:8.8.8.8',
    ]) {
      expect(ok(a), isFalse, reason: a);
    }
  });

  test('answers carry usage and every request reaches the dashboard', () async {
    final plain = await request(
      'POST',
      '/v1/chat/completions',
      auth: token,
      body: jsonEncode({
        'messages': [
          {'role': 'user', 'content': 'world'},
        ],
      }),
    );
    final body = jsonDecode(await utf8.decoder.bind(plain).join()) as Map;
    // The fake reports no tokenizer metrics: usage is explicitly unavailable.
    expect(body['usage'], {
      'prompt_tokens': null,
      'completion_tokens': null,
      'total_tokens': null,
    });
    final streamed = await request(
      'POST',
      '/v1/chat/completions',
      auth: token,
      body: jsonEncode({
        'messages': [
          {'role': 'user', 'content': 'world'},
        ],
        'stream': true,
        'stream_options': {'include_usage': true},
      }),
    );
    final events = await utf8.decoder.bind(streamed).join();
    expect(events, contains('"finish_reason":null'));
    expect(events, contains('"choices":[],"usage":{"prompt_tokens":null'));
    await (await request('GET', '/v1/models', auth: 'wrong')).drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(served.map((r) => r.status), [200, 200, 401]);
    expect(served[0].ok && !served[0].stream, true);
    expect(served[1].stream, true);
    expect(served[1].completionTokens, 0);
    expect(served[2].ok, false);
    expect(served[2].client, '127.0.0.1');
  });

  test(
    'two requests at once: the second queues, never run alongside',
    () async {
      await server.stop();
      final gate = Completer<void>();
      var running = 0, most = 0;
      server = DeviceModelServer(
        engine: _GatedEngine(gate, () {
          most = ++running > most ? running : most;
        }, () => running--),
        settings: () => const InferenceSettings(),
        modelId: 'test-model',
        fallbackTemplate: '',
        accessToken: token,
        onServed: served.add,
      );
      await server.start();
      Future<int> ask() async {
        final r = await request(
          'POST',
          '/v1/chat/completions',
          auth: token,
          body: jsonEncode({
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          }),
        );
        await r.drain<void>();
        return r.statusCode;
      }

      final first = ask(), second = ask();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      gate.complete();
      final codes = [await first, await second]..sort();
      expect(codes, [200, 200]);
      expect(most, 1);
      // Released afterwards: the next request is answered.
      expect(await ask(), 200);
      // A model listing is logged but is not an answer.
      await (await request('GET', '/v1/models', auth: token)).drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final s = served.fold(
        const DeviceHostingState(running: true),
        (DeviceHostingState acc, r) => acc.withServed(r),
      );
      expect(s.answered, 3);
    },
  );

  test('a copied connection becomes a profile and its key', () {
    const state = DeviceHostingState(
      running: true,
      endpoint: 'http://192.168.1.5:8787/v1/',
      token: token,
      modelId: 'qwen35-2b-iq4nl',
    );
    final (profile, key) = RemoteProfile.fromPairing(state.pairing!, id: 'p1')!;
    expect(profile.baseUrl, 'http://192.168.1.5:8787/v1');
    expect(profile.model, 'qwen35-2b-iq4nl');
    expect(profile.providerId, 'custom');
    expect(profile.label, 'Phone at 192.168.1.5');
    expect(key, token);
    expect(RemoteProfile.fromPairing('hello', id: 'x'), isNull);
    expect(
      RemoteProfile.fromPairing(
        '{"ondevice_llm":"connection","url":"file:///etc","key":"k"}',
        id: 'x',
      ),
      isNull,
    );
    // Pairing again finds the saved connection, slash or not.
    final saved = [
      const RemoteProfile(
        id: 'lm',
        name: 'LM Studio',
        providerId: 'lmstudio',
        baseUrl: 'http://192.168.1.5:8787/v1',
      ),
      profile.copyWith(baseUrl: 'http://192.168.1.5:8787/v1/'),
    ];
    expect(RemoteProfile.savedServer(saved, profile.baseUrl)?.id, 'p1');
    expect(
      RemoteProfile.savedServer(saved, 'http://192.168.1.6:8787/v1'),
      isNull,
    );
  });

  test('dashboard counters and the battery/heat guards', () {
    var s = const DeviceHostingState(running: true);
    ServedRequest r(int status, {int tokens = 0, String client = 'a'}) =>
        ServedRequest(
          at: DateTime(2026),
          client: client,
          status: status,
          completion: true,
          completionTokens: tokens,
          tokensPerSecond: tokens > 0 ? 20 : 0,
        );
    s = s.withServed(r(200, tokens: 50));
    s = s.withServed(r(429, client: 'b'));
    s = s.withServed(r(401, client: 'intruder'));
    s = s.withServed(r(500));
    expect((s.answered, s.refused, s.failed), (1, 2, 1));
    expect(s.completionTokens, 50);
    expect(s.clients, {'a', 'b'}, reason: 'a wrong token is not a device');
    expect(s.averageTokensPerSecond, 20);
    expect(s.log.first.status, 500, reason: 'most recent first');

    const guards = HostingGuards(minBattery: 20);
    String? why(int level, {bool charging = false, int heat = 0}) =>
        DeviceHostingNotifier.stopReason(
          DevicePower(level: level, charging: charging, thermalStatus: heat),
          guards,
        );
    expect(why(50), isNull);
    expect(why(15), contains('battery below 20%'));
    expect(why(15, charging: true), isNull);
    expect(why(80, heat: 3), contains('too hot (severe)'));
    expect(
      DeviceHostingNotifier.stopReason(
        const DevicePower(level: 5, charging: false),
        const HostingGuards(minBattery: null),
      ),
      isNull,
    );
  });
}
