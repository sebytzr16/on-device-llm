import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_usage.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  RequestOptions? last;
  String? lastBody;
  _Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    lastBody = options.data is String ? options.data as String : null;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

const settings = InferenceSettings(
  remoteEnabled: true,
  remoteProfiles: [
    RemoteProfile(
      id: 'home',
      name: 'Home PC',
      providerId: 'lmstudio',
      baseUrl: 'http://10.8.0.2:1234/v1/',
      model: 'qwen3-8b',
    ),
  ],
  remoteProfileId: 'home',
  remoteApiKeys: {'home': 'secret'},
  maxTokens: 256,
  contextSize: 8192,
);

/// An engine whose request log never touches SharedPreferences.
RemoteEngine engineWith(Dio dio, {DateTime Function()? now}) => RemoteEngine(
  dio: dio,
  usage: RemoteUsageLog(now: now, prefs: () => null),
);

String sse(List<Map<String, dynamic>> chunks) =>
    '${chunks.map((c) => 'data: ${jsonEncode(c)}').join('\n\n')}\n\ndata: [DONE]\n';

void main() {
  test('endpoint tolerates a trailing /v1 and slashes', () {
    expect(
      RemoteEngine.endpoint(
        Uri.parse('http://host:1234/v1/'),
        'chat/completions',
      ).toString(),
      'http://host:1234/v1/chat/completions',
    );
    expect(
      RemoteEngine.endpoint(
        Uri.parse('https://box.example'),
        'models',
      ).toString(),
      'https://box.example/v1/models',
    );
  });

  test(
    'streams content, wraps reasoning in think tags, reports usage',
    () async {
      final adapter = _Adapter(
        (_) => ResponseBody.fromString(
          sse([
            {
              'choices': [
                {
                  'delta': {'reasoning_content': 'Let me see. '},
                },
              ],
            },
            {
              'choices': [
                {
                  'delta': {'reasoning': 'Easy.'},
                },
              ],
            },
            {
              'choices': [
                {
                  'delta': {'content': 'The answer '},
                },
              ],
            },
            {
              'choices': [
                {
                  'delta': {'content': 'is 42.'},
                },
              ],
            },
            {
              'choices': [],
              'usage': {'prompt_tokens': 30, 'completion_tokens': 4},
            },
          ]),
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final engine = engineWith(dio);
      final out = await engine
          .generate(
            messages: const [
              {'role': 'user', 'content': 'hi'},
            ],
            fallbackTemplate: '',
            settings: settings,
          )
          .join();
      expect(out, '<think>Let me see. Easy.</think>The answer is 42.');
      expect(
        adapter.last!.uri.toString(),
        'http://10.8.0.2:1234/v1/chat/completions',
      );
      expect(adapter.last!.headers['Authorization'], 'Bearer secret');
      final body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
      expect(body['model'], 'qwen3-8b');
      expect(body['stream'], true);
      expect(body['max_tokens'], 256);
      expect(engine.metrics['tokens'], 4);
      expect(engine.metrics['promptTokens'], 30);
      expect(engine.metrics['backend'], 'Remote · LM Studio · 10.8.0.2');
    },
  );

  test('preserves UTF-8 characters split across network chunks', () async {
    final encoded = utf8.encode(
      'data: {"choices":[{"delta":{"content":"café ☕"}}]}\n\ndata: [DONE]\n',
    );
    final split = encoded.indexOf(0xC3) + 1;
    final adapter = _Adapter(
      (_) => ResponseBody(
        Stream.fromIterable([
          Uint8List.fromList(encoded.sublist(0, split)),
          Uint8List.fromList(encoded.sublist(split)),
        ]),
        200,
        headers: {
          'content-type': ['text/event-stream'],
        },
      ),
    );
    final engine = engineWith(Dio()..httpClientAdapter = adapter);
    final out = await engine
        .generate(
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          fallbackTemplate: '',
          settings: settings,
        )
        .join();
    expect(out, 'café ☕');
  });

  test('server errors become readable exceptions', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (_) => ResponseBody.fromString('{"error":"no model loaded"}', 404),
      );
    final engine = engineWith(dio);
    await expectLater(
      engine
          .generate(
            messages: const [
              {'role': 'user', 'content': 'hi'},
            ],
            fallbackTemplate: '',
            settings: settings,
          )
          .join(),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'message',
          contains('404'),
        ),
      ),
    );
  });

  test('lists models and estimates the prompt budget', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (_) => ResponseBody.fromString(
          '{"data":[{"id":"qwen3-8b","owned_by":"local","capabilities":["tool_use"]},{"id":"gemma-4-12b","capabilities":["vision"]}]}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
    final engine = engineWith(dio);
    final models = await engine.listModels(settings);
    expect(models.map((m) => m.id), ['qwen3-8b', 'gemma-4-12b']);
    expect(models.first.owner, 'local');
    expect(models.first.supports('tool'), true);
    expect(models.last.supports('vision'), true);
    final budget = await engine.previewPrompt(
      messages: [
        {'role': 'user', 'content': 'x' * 3500},
      ],
      fallbackTemplate: '',
      settings: settings,
    );
    expect(budget['fits'], true);
    expect(budget['promptTokens'], greaterThan(900));
    expect(budget['estimated'], true);
  });

  test(
    'probe reports optional health and tools without executing them',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) {
          if (options.uri.path.endsWith('/v1/models')) {
            return ResponseBody.fromString(
              '{"data":[{"id":"vision-model","capabilities":["vision"]}]}',
              200,
            );
          }
          if (options.uri.path.endsWith('/health')) {
            return ResponseBody.fromString('{"status":"ok"}', 200);
          }
          if (options.uri.path.endsWith('/tools')) {
            return ResponseBody.fromString(
              '{"tools":[{"name":"search"}]}',
              200,
            );
          }
          return ResponseBody.fromString('', 404);
        });
      final report = await engineWith(dio).probe(settings);
      expect(report.health, 'ok');
      expect(report.models.single.supports('vision'), true);
      expect(report.tools, ['search']);
      expect(report.summary, contains('1 server tool detected'));
    },
  );

  InferenceSettings hosted(
    String providerId, {
    String model = 'm',
    String url = '',
  }) => InferenceSettings(
    remoteEnabled: true,
    remoteProfiles: [
      RemoteProfile(
        id: 'p',
        name: 'Cloud',
        providerId: providerId,
        baseUrl: url.isEmpty
            ? RemoteProvider.byId(providerId).defaultBaseUrl
            : url,
        model: model,
        headers: const {'X-Title': 'OnDeviceLLM'},
      ),
    ],
    remoteProfileId: 'p',
    remoteApiKeys: const {'p': 'sk-test'},
    maxTokens: 512,
    contextSize: 8192,
    thinkingModeEnabled: true,
  );

  group('providers', () {
    test('append the version path only when it is missing', () {
      final openrouter = RemoteProvider.byId('openrouter');
      expect(
        openrouter
            .endpoint(Uri.parse(openrouter.defaultBaseUrl), 'chat/completions')
            .toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      final zhipu = RemoteProvider.byId('zhipu');
      expect(
        zhipu
            .endpoint(Uri.parse(zhipu.defaultBaseUrl), 'chat/completions')
            .toString(),
        'https://api.z.ai/api/paas/v4/chat/completions',
      );
      final perplexity = RemoteProvider.byId('perplexity');
      expect(
        perplexity
            .endpoint(Uri.parse(perplexity.defaultBaseUrl), 'chat/completions')
            .toString(),
        'https://api.perplexity.ai/chat/completions',
      );
      final openwebui = RemoteProvider.byId('openwebui');
      expect(
        openwebui.endpoint(Uri.parse('http://box:3000'), 'models').toString(),
        'http://box:3000/api/models',
      );
      expect(
        RemoteProvider.byId('gemini')
            .endpoint(
              Uri.parse('https://generativelanguage.googleapis.com'),
              'models',
            )
            .toString(),
        'https://generativelanguage.googleapis.com/v1beta/models',
      );
      expect(
        RemoteProvider.custom
            .serverEndpoint(Uri.parse('http://box:8080/v1'), 'health')
            .toString(),
        'http://box:8080/health',
      );
    });

    test('put the key in the header each API expects', () {
      expect(RemoteProvider.byId('openai').authHeaders('k'), {
        'Authorization': 'Bearer k',
      });
      expect(RemoteProvider.byId('anthropic').authHeaders('k'), {
        'x-api-key': 'k',
        'anthropic-version': '2023-06-01',
      });
      expect(RemoteProvider.byId('gemini').authHeaders('k'), {
        'x-goog-api-key': 'k',
      });
      expect(RemoteProvider.byId('azure').authHeaders('k'), {'api-key': 'k'});
      expect(RemoteProvider.byId('ollama').authHeaders(''), isEmpty);
      expect(RemoteProvider.byId('nope').id, 'custom');
    });

    test('profiles round-trip and refuse reserved headers', () {
      const p = RemoteProfile(
        id: 'a',
        name: 'A',
        providerId: 'openrouter',
        baseUrl: 'https://openrouter.ai/api',
        model: 'x/y',
        headers: {'HTTP-Referer': 'https://e.app'},
        limits: {'x/y': RemoteLimit(perMinute: 3, perDay: 100)},
      );
      final back = RemoteProfile.fromJson(p.toJson())!;
      expect(back.headers, p.headers);
      expect(back.limit.perDay, 100);
      expect(
        RemoteProfile.fromJson({
          'id': 'b',
          'headers': {'Authorization': 'Bearer leak', 'X-Ok': '1'},
        })!.headers,
        {'X-Ok': '1'},
      );
      expect(
        RemoteProfile.parseHeaders(
          'X-Title: My app\nx-api-key: leak\nbad line',
        ),
        {'X-Title': 'My app'},
      );
      expect(RemoteProfile.fromJson({'name': 'no id'}), isNull);
    });
  });

  test('Anthropic: Messages API body, thinking, tool_use and usage', () async {
    final adapter = _Adapter(
      (_) => ResponseBody.fromString(
        [
          'event: message_start',
          'data: {"type":"message_start","message":{"usage":{"input_tokens":12}}}',
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}',
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Hmm. "}}',
          'data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}',
          'data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Sure, "}}',
          'data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"web_search","input":{}}}',
          'data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":"}}',
          'data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\\"x\\"}"}}',
          'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}',
          'data: {"type":"message_stop"}',
          '',
        ].join('\n'),
        200,
      ),
    );
    final engine = engineWith(Dio()..httpClientAdapter = adapter);
    final out = await engine
        .generate(
          messages: const [
            {'role': 'system', 'content': 'Be brief.'},
            {'role': 'user', 'content': 'hi'},
            {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c1',
                  'name': 'web_search',
                  'arguments': '{"query":"a"}',
                },
              ],
            },
            {
              'role': 'tool',
              'tool_call_id': 'c1',
              'name': 'web_search',
              'content': 'r',
            },
          ],
          fallbackTemplate: '',
          settings: hosted('anthropic', model: 'claude-opus-5'),
          tools: const [
            ToolSpec(
              name: 'web_search',
              description: 'd',
              parameters: {'type': 'object'},
            ),
          ],
          toolChoice: 'required',
        )
        .join();
    expect(out, '<think>Hmm. </think>Sure, ');
    expect(
      adapter.last!.uri.toString(),
      'https://api.anthropic.com/v1/messages',
    );
    expect(adapter.last!.headers['x-api-key'], 'sk-test');
    expect(adapter.last!.headers['anthropic-version'], '2023-06-01');
    expect(adapter.last!.headers['X-Title'], 'OnDeviceLLM');
    final body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body['system'], 'Be brief.');
    expect(body['thinking'], {'type': 'adaptive', 'display': 'summarized'});
    expect(body.containsKey('temperature'), false);
    expect(body['tool_choice'], {'type': 'auto'});
    expect((body['tools'] as List).single['input_schema'], {'type': 'object'});
    final messages = body['messages'] as List;
    expect(messages.map((m) => m['role']), ['user', 'assistant', 'user']);
    expect((messages[1]['content'] as List).single['type'], 'tool_use');
    expect((messages[2]['content'] as List).single['tool_use_id'], 'c1');
    expect(engine.metrics['finishReason'], 'tool_calls');
    expect(engine.metrics['promptTokens'], 12);
    expect(engine.metrics['tokens'], 9);
    final calls = TextEngine.toolCallsOf(engine.metrics);
    expect(calls.single.id, 'toolu_1');
    expect(calls.single.args, {'query': 'x'});
  });

  test('Gemini: contents, thoughts, function calls and signatures', () async {
    final adapter = _Adapter(
      (_) => ResponseBody.fromString(
        [
          'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Thinking…","thought":true}]}}]}',
          'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":2,"thoughtsTokenCount":3}}',
          'data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"web_search","args":{"query":"q"}},"thoughtSignature":"sig1"}]},"finishReason":"STOP"}]}',
          '',
        ].join('\n'),
        200,
      ),
    );
    final engine = engineWith(Dio()..httpClientAdapter = adapter);
    final s = hosted('gemini', model: 'gemini-2.5-pro');
    final out = await engine
        .generate(
          messages: const [
            {'role': 'system', 'content': 'Be brief.'},
            {'role': 'user', 'content': 'hi'},
          ],
          fallbackTemplate: '',
          settings: s,
          tools: const [
            ToolSpec(
              name: 'web_search',
              description: 'd',
              parameters: {'type': 'object'},
            ),
          ],
          toolChoice: 'required',
        )
        .join();
    expect(out, '<think>Thinking…</think>Hello');
    expect(
      adapter.last!.uri.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:streamGenerateContent?alt=sse',
    );
    expect(adapter.last!.headers['x-goog-api-key'], 'sk-test');
    var body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body['systemInstruction']['parts'][0]['text'], 'Be brief.');
    expect(body['generationConfig']['thinkingConfig'], {
      'includeThoughts': true,
    });
    expect(body['generationConfig']['maxOutputTokens'], 512);
    expect(body['toolConfig']['functionCallingConfig']['mode'], 'ANY');
    expect(body['tools'][0]['functionDeclarations'][0]['name'], 'web_search');
    expect(engine.metrics['finishReason'], 'tool_calls');
    expect(engine.metrics['tokens'], 5);
    final call = TextEngine.toolCallsOf(engine.metrics).single;
    expect(call.name, 'web_search');
    expect(call.args, {'query': 'q'});
    // The next round echoes the call with its signature and the result.
    await engine
        .generate(
          messages: [
            const {'role': 'user', 'content': 'hi'},
            {
              'role': 'assistant',
              'content': '',
              'tool_calls': [call.toJson()],
            },
            {
              'role': 'tool',
              'tool_call_id': call.id,
              'name': 'web_search',
              'content': 'r',
            },
          ],
          fallbackTemplate: '',
          settings: s,
        )
        .join();
    body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    final contents = body['contents'] as List;
    expect(contents.map((c) => c['role']), ['user', 'model', 'user']);
    expect(contents[1]['parts'][0]['functionCall']['name'], 'web_search');
    expect(contents[1]['parts'][0]['thoughtSignature'], 'sig1');
    expect(contents[2]['parts'][0]['functionResponse']['name'], 'web_search');
  });

  test('lists Anthropic and Gemini models', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((o) {
        if (o.uri.host == 'api.anthropic.com') {
          expect(o.uri.path, '/v1/models');
          return ResponseBody.fromString(
            '{"data":[{"id":"claude-opus-5","display_name":"Claude Opus 5","max_input_tokens":1000000,"capabilities":{"thinking":{"types":{"adaptive":{"supported":true}}},"vision":{"supported":false}}}],"has_more":false}',
            200,
          );
        }
        expect(o.uri.path, '/v1beta/models');
        return ResponseBody.fromString(
          '{"models":[{"name":"models/gemini-2.5-flash","displayName":"Flash","inputTokenLimit":1048576,"supportedGenerationMethods":["generateContent"]},{"name":"models/embedding-001","supportedGenerationMethods":["embedContent"]}]}',
          200,
        );
      });
    final engine = engineWith(dio);
    final claude = await engine.listModels(hosted('anthropic'));
    expect(claude.single.id, 'claude-opus-5');
    expect(claude.single.contextWindow, 1000000);
    expect(claude.single.supports('thinking.types.adaptive'), true);
    expect(claude.single.supports('vision'), false);
    final gemini = await engine.listModels(hosted('gemini'));
    expect(gemini.map((m) => m.id), ['gemini-2.5-flash']);
    // Hosted APIs are not probed for health or tools.
    final report = await engine.probe(hosted('gemini'));
    expect(report.health, 'n/a');
    expect(report.summary, 'Connected · 1 model');
    expect(await engine.listModels(hosted('perplexity')), isEmpty);
  });

  test('request caps refuse before sending and count per model', () async {
    var sent = 0;
    final adapter = _Adapter((_) {
      sent++;
      return ResponseBody.fromString(
        sse([
          {
            'choices': [
              {
                'delta': {'content': 'ok'},
              },
            ],
          },
        ]),
        200,
      );
    });
    var clock = DateTime(2026, 9, 20, 10, 0, 0);
    final engine = engineWith(
      Dio()..httpClientAdapter = adapter,
      now: () => clock,
    );
    final capped = settings.copyWith(
      remoteProfiles: [
        settings.remoteProfiles.single.withLimit(
          const RemoteLimit(perMinute: 2, perDay: 3),
        ),
      ],
    );
    Future<String> ask() => engine
        .generate(
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          fallbackTemplate: '',
          settings: capped,
        )
        .join();
    expect(await ask(), 'ok');
    expect(await ask(), 'ok');
    await expectLater(
      ask(),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'message',
          contains('2/min'),
        ),
      ),
    );
    expect(sent, 2);
    clock = clock.add(const Duration(minutes: 2));
    expect(await ask(), 'ok');
    await expectLater(
      ask(),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'message',
          contains('3/day'),
        ),
      ),
    );
    expect(sent, 3);
    final counts = await engine.usage.counts('home', 'qwen3-8b');
    expect(counts.day, 3);
    // Another model on the same connection has its own counter.
    expect((await engine.usage.counts('home', 'other')).day, 0);
    clock = DateTime(2026, 9, 21, 0, 0, 1);
    expect(await ask(), 'ok');
  });

  test('Gemma on the Gemini API gets a reduced request', () async {
    final adapter = _Adapter(
      (_) => ResponseBody.fromString(
        'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hi"}]},"finishReason":"STOP"}]}\n',
        200,
      ),
    );
    final engine = engineWith(Dio()..httpClientAdapter = adapter);
    await engine
        .generate(
          messages: const [
            {'role': 'system', 'content': 'Be brief.'},
            {'role': 'user', 'content': 'hi'},
          ],
          fallbackTemplate: '',
          settings: hosted('gemini', model: 'gemma-3-27b-it'),
          tools: const [
            ToolSpec(
              name: 'web_search',
              description: 'd',
              parameters: {'type': 'object'},
            ),
          ],
          toolChoice: 'required',
        )
        .join();
    final body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body.containsKey('systemInstruction'), false);
    expect(body.containsKey('tools'), false);
    expect(body.containsKey('toolConfig'), false);
    // Gemma 4 thinks: Think on asks for thought summaries.
    expect(body['generationConfig']['thinkingConfig'], {
      'includeThoughts': true,
    });
    expect(body['contents'][0]['parts'][0]['text'], 'Be brief.\n\nhi');
  });

  test('a streamed error body is read into the notice', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (_) => ResponseBody.fromString(
          '{"error":{"code":500,"message":"Developer instruction is not enabled for models/gemma-3-27b-it","status":"INTERNAL"}}',
          500,
        ),
      );
    await expectLater(
      engineWith(dio)
          .generate(
            messages: const [
              {'role': 'user', 'content': 'hi'},
            ],
            fallbackTemplate: '',
            settings: hosted('gemini', model: 'gemini-2.5-flash'),
          )
          .join(),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'message',
          contains('Developer instruction is not enabled'),
        ),
      ),
    );
  });

  test('Gemini: Think off maps to each thinking-off knob', () async {
    final adapter = _Adapter(
      (_) => ResponseBody.fromString(
        'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"no"}]},"finishReason":"STOP"}]}\n',
        200,
      ),
    );
    final engine = engineWith(Dio()..httpClientAdapter = adapter);
    Future<Map<String, dynamic>> config(String model) async {
      await engine
          .generate(
            messages: const [
              {'role': 'user', 'content': 'hi'},
            ],
            fallbackTemplate: '',
            settings: hosted(
              'gemini',
              model: model,
            ).copyWith(thinkingModeEnabled: false),
          )
          .join();
      return (jsonDecode(adapter.lastBody!)
              as Map<String, dynamic>)['generationConfig']
          as Map<String, dynamic>;
    }

    expect((await config('gemini-2.5-flash'))['thinkingConfig'], {
      'thinkingBudget': 0,
    });
    expect((await config('gemini-3-pro-preview'))['thinkingConfig'], {
      'thinkingLevel': 'low',
    });
    expect((await config('gemini-3.6-flash'))['thinkingConfig'], {
      'thinkingLevel': 'minimal',
    });
    // 2.5 Pro cannot turn thinking off: its minimum budget.
    expect((await config('gemini-2.5-pro'))['thinkingConfig'], {
      'thinkingBudget': 128,
    });
    expect((await config('gemma-4-31b-it'))['thinkingConfig'], {
      'thinkingBudget': 0,
    });
  });

  for (final (status, message) in [
    (400, 'Not enough quota.'),
    (400, 'Not enough quota for the thinking configuration.'),
    (429, 'Daily quota exceeded. Try again tomorrow.'),
    (
      429,
      'Quota exceeded for metric: generate_content_free_tier_requests, '
          'quotaId: GenerateRequestsPerDayPerProjectPerModel-FreeTier',
    ),
  ]) {
    test(
      'quota exhaustion is surfaced without retries: $status $message',
      () async {
        var calls = 0;
        final adapter = _Adapter((_) {
          calls++;
          return ResponseBody.fromString(
            jsonEncode({
              'error': {'code': status, 'message': message},
            }),
            status,
          );
        });
        final engine = engineWith(Dio()..httpClientAdapter = adapter);
        addTearDown(engine.dispose);
        final settings = hosted('gemini', model: 'gemma-4-31b-it');
        await expectLater(
          engine
              .generate(
                messages: const [
                  {'role': 'user', 'content': 'hi'},
                ],
                fallbackTemplate: '',
                settings: settings,
              )
              .join(),
          throwsA(predicate((Object e) => e.toString().contains(message))),
        );
        expect(calls, 1);
      },
    );
  }

  test('a model that rejects thinkingConfig gets one retry without it', () async {
    var calls = 0;
    final adapter = _Adapter((_) {
      calls++;
      if (calls == 1) {
        return ResponseBody.fromString(
          '{"error":{"code":400,"message":"Thinking config is not supported for this model","status":"INVALID_ARGUMENT"}}',
          400,
        );
      }
      return ResponseBody.fromString(
        'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n',
        200,
      );
    });
    final engine = engineWith(Dio()..httpClientAdapter = adapter);
    final s = hosted(
      'gemini',
      model: 'gemma-4-31b-it',
    ).copyWith(thinkingModeEnabled: false);
    Future<String> ask() => engine
        .generate(
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          fallbackTemplate: '',
          settings: s,
        )
        .join();
    expect(await ask(), 'ok');
    expect(calls, 2);
    var body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body['generationConfig'].containsKey('thinkingConfig'), false);
    // Remembered for the session: no second probe.
    expect(await ask(), 'ok');
    expect(calls, 3);
    body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body['generationConfig'].containsKey('thinkingConfig'), false);
  });

  test('a model that rejects penalties gets one retry without them', () async {
    var calls = 0;
    final adapter = _Adapter((_) {
      calls++;
      if (calls == 1) {
        return ResponseBody.fromString(
          '{"error":{"code":400,"message":"Penalty is not enabled for this model","status":"INVALID_ARGUMENT"}}',
          400,
        );
      }
      return ResponseBody.fromString(
        'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n',
        200,
      );
    });
    final engine = engineWith(Dio()..httpClientAdapter = adapter);
    final s = hosted(
      'gemini',
      model: 'gemini-3.5-flash-lite',
    ).copyWith(presencePenalty: 1.5);
    Future<String> ask() => engine
        .generate(
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          fallbackTemplate: '',
          settings: s,
        )
        .join();
    expect(await ask(), 'ok');
    expect(calls, 2);
    var body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body['generationConfig'].containsKey('presencePenalty'), false);
    // Remembered for the session: no second refusal.
    expect(await ask(), 'ok');
    expect(calls, 3);
    body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body['generationConfig'].containsKey('presencePenalty'), false);
  });

  group("the Think pill maps to each provider's effort", () {
    ResponseBody ok(RequestOptions o) {
      final path = o.uri.path;
      if (path.endsWith('chat/completions')) {
        return ResponseBody.fromString(
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n',
          200,
        );
      }
      if (path.endsWith('messages')) {
        return ResponseBody.fromString(
          [
            'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}}',
            'data: {"type":"message_stop"}',
            '',
          ].join('\n'),
          200,
        );
      }
      return ResponseBody.fromString(
        'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n',
        200,
      );
    }

    ResponseBody refuse(String json) => ResponseBody.fromString(json, 400);

    Map<String, dynamic> sent(RequestOptions o) =>
        jsonDecode(o.data as String) as Map<String, dynamic>;

    Future<String> ask(RemoteEngine engine, InferenceSettings s) => engine
        .generate(
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          fallbackTemplate: '',
          settings: s,
        )
        .join();

    InferenceSettings at(InferenceSettings s, ThinkingLevel level) =>
        s.copyWith(
          thinkingModeEnabled: level != ThinkingLevel.off,
          thinkingBudgetTokens: level.budget,
        );

    test(
      'levels become reasoning_effort, effort and thinking config',
      () async {
        final adapter = _Adapter(ok);
        final engine = engineWith(Dio()..httpClientAdapter = adapter);
        Future<Map<String, dynamic>> body(InferenceSettings s) async {
          expect(await ask(engine, s), 'ok');
          return sent(adapter.last!);
        }

        final off = await body(at(settings, ThinkingLevel.off));
        expect(off['reasoning_effort'], 'none');
        expect(off['chat_template_kwargs'], {'enable_thinking': false});
        for (final level in [
          ThinkingLevel.low,
          ThinkingLevel.medium,
          ThinkingLevel.high,
        ]) {
          final b = await body(at(settings, level));
          expect(b['reasoning_effort'], level.name);
          expect(b.containsKey('chat_template_kwargs'), isFalse);
        }

        final claude = hosted('anthropic', model: 'claude-opus-5');
        final claudeOff = await body(at(claude, ThinkingLevel.off));
        expect(claudeOff.containsKey('thinking'), isFalse);
        expect(claudeOff.containsKey('output_config'), isFalse);
        final claudeLow = await body(at(claude, ThinkingLevel.low));
        expect(claudeLow['thinking'], {
          'type': 'adaptive',
          'display': 'summarized',
        });
        expect(claudeLow['output_config'], {'effort': 'low'});
        expect(
          (await body(at(claude, ThinkingLevel.medium)))['output_config'],
          {'effort': 'medium'},
        );
        // High is the API's default.
        expect(
          (await body(
            at(claude, ThinkingLevel.high),
          )).containsKey('output_config'),
          isFalse,
        );

        Future<Object?> gemini(String model, ThinkingLevel level) async =>
            (await body(
              at(hosted('gemini', model: model), level),
            ))['generationConfig']['thinkingConfig'];
        for (final level in [
          ThinkingLevel.low,
          ThinkingLevel.medium,
          ThinkingLevel.high,
        ]) {
          expect(await gemini('gemini-3.6-flash', level), {
            'includeThoughts': true,
            'thinkingLevel': level.name,
          });
        }
        expect(await gemini('gemini-2.5-flash', ThinkingLevel.low), {
          'includeThoughts': true,
          'thinkingBudget': 512,
        });
        expect(await gemini('gemini-2.5-flash', ThinkingLevel.high), {
          'includeThoughts': true,
          'thinkingBudget': 8192,
        });
      },
    );

    test('an OpenAI-style server teaches what it refuses, once', () async {
      var calls = 0;
      final adapter = _Adapter((o) {
        calls++;
        final b = sent(o);
        if (b.containsKey('top_k') || b.containsKey('chat_template_kwargs')) {
          return refuse(
            '{"error":{"message":"Unrecognized request arguments supplied: chat_template_kwargs, min_p, repeat_penalty, top_k","type":"invalid_request_error"}}',
          );
        }
        if (b.containsKey('max_tokens')) {
          return refuse(
            '{"error":{"message":"Unsupported parameter: \'max_tokens\' is not supported with this model. Use \'max_completion_tokens\' instead.","param":"max_tokens"}}',
          );
        }
        if (b['reasoning_effort'] == 'none') {
          return refuse(
            '{"error":{"message":"Unsupported value: \'reasoning_effort\' does not support \'none\' with this model. Supported values are: \'minimal\', \'low\', \'medium\', and \'high\'.","param":"reasoning_effort"}}',
          );
        }
        return ok(o);
      });
      final engine = engineWith(Dio()..httpClientAdapter = adapter);
      final s = at(hosted('openai', model: 'gpt-5'), ThinkingLevel.off);
      expect(await ask(engine, s), 'ok');
      expect(calls, 4);
      void check(Map<String, dynamic> b) {
        expect(b['reasoning_effort'], 'minimal');
        expect(b['max_completion_tokens'], 512);
        for (final gone in [
          'max_tokens',
          'top_k',
          'min_p',
          'repeat_penalty',
          'chat_template_kwargs',
        ]) {
          expect(b.containsKey(gone), isFalse, reason: gone);
        }
      }

      check(sent(adapter.last!));
      // Remembered for the session: no second probe.
      expect(await ask(engine, s), 'ok');
      expect(calls, 5);
      check(sent(adapter.last!));
      // Another level is asked for as it is.
      expect(await ask(engine, at(s, ThinkingLevel.low)), 'ok');
      expect(calls, 6);
      expect(sent(adapter.last!)['reasoning_effort'], 'low');
    });

    test('a refusal that names nothing drops the effort, once', () async {
      var calls = 0;
      final adapter = _Adapter((_) {
        calls++;
        return refuse('{"error":{"message":"Bad request"}}');
      });
      final engine = engineWith(Dio()..httpClientAdapter = adapter);
      final s = at(settings, ThinkingLevel.low);
      await expectLater(
        ask(engine, s),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'message',
            contains('Bad request'),
          ),
        ),
      );
      expect(calls, 2);
      expect(sent(adapter.last!).containsKey('reasoning_effort'), isFalse);
      await expectLater(ask(engine, s), throwsA(isA<InferenceException>()));
      expect(calls, 3);
    });

    test('a Claude model without effort or adaptive thinking is learned', () async {
      var calls = 0;
      final adapter = _Adapter((o) {
        calls++;
        final b = sent(o);
        if ((b['output_config'] as Map?)?.containsKey('effort') ?? false) {
          return refuse(
            '{"type":"error","error":{"type":"invalid_request_error","message":"output_config.effort: Extra inputs are not permitted"}}',
          );
        }
        if ((b['thinking'] as Map?)?['type'] == 'adaptive') {
          return refuse(
            '{"type":"error","error":{"type":"invalid_request_error","message":"thinking.type: Input tag \'adaptive\' found using \'type\' does not match any of the expected tags: \'disabled\', \'enabled\'"}}',
          );
        }
        return ok(o);
      });
      final engine = engineWith(Dio()..httpClientAdapter = adapter);
      final s = at(
        hosted('anthropic', model: 'claude-haiku-4-5'),
        ThinkingLevel.low,
      );
      expect(await ask(engine, s), 'ok');
      expect(calls, 3);
      void check(Map<String, dynamic> b) {
        expect(b['thinking'], {'type': 'enabled', 'budget_tokens': 1024});
        expect(b['max_tokens'], 512 + 1024);
        expect(b.containsKey('output_config'), isFalse);
      }

      check(sent(adapter.last!));
      expect(await ask(engine, s), 'ok');
      expect(calls, 4);
      check(sent(adapter.last!));
    });

    test('a Gemini level a model refuses steps to the next one', () async {
      var calls = 0;
      final adapter = _Adapter((o) {
        calls++;
        final config = sent(o)['generationConfig'] as Map;
        if ((config['thinkingConfig'] as Map?)?['thinkingLevel'] == 'medium') {
          return refuse(
            '{"error":{"code":400,"message":"Thinking level MEDIUM is not supported for this model.","status":"INVALID_ARGUMENT"}}',
          );
        }
        return ok(o);
      });
      final engine = engineWith(Dio()..httpClientAdapter = adapter);
      final s = at(
        hosted('gemini', model: 'gemini-3-pro-preview'),
        ThinkingLevel.medium,
      );
      const high = {'includeThoughts': true, 'thinkingLevel': 'high'};
      expect(await ask(engine, s), 'ok');
      expect(calls, 2);
      expect(sent(adapter.last!)['generationConfig']['thinkingConfig'], high);
      expect(await ask(engine, s), 'ok');
      expect(calls, 3);
      expect(sent(adapter.last!)['generationConfig']['thinkingConfig'], high);
    });
  });

  test('legacy single-server settings migrate into one profile', () {
    final s = InferenceSettings.fromJson({
      'remoteEnabled': true,
      'remoteBaseUrl': 'http://10.0.0.5:11434',
      'remoteModel': 'llama3',
    });
    expect(s.usesRemote, true);
    expect(s.activeRemoteProfile!.providerId, 'ollama');
    expect(s.remoteModel, 'llama3');
    expect(s.remoteUri!.port, 11434);
    final again = InferenceSettings.fromJson(s.toJson());
    expect(again.remoteProfiles.single.id, 'legacy');
    expect(again.toJson().containsKey('remoteApiKeys'), false);
    expect(again.toJson().containsKey('remoteApiKey'), false);
  });
}
