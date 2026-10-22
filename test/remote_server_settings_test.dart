import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_usage.dart';
import 'package:ondevice_llm/features/chat/domain/turn_prompts.dart';
import 'package:ondevice_llm/features/chat/domain/turn_policy.dart';

/// Decision 2026-10-18: a remote connection keeps its own sampling,
/// answer length and context, and its model plans the research.
class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  _Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> sent(RequestOptions o) =>
    jsonDecode(o.data as String) as Map<String, dynamic>;

ResponseBody answer(RequestOptions o) {
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

InferenceSettings connection(
  String providerId, {
  required String id,
  String model = 'm',
  String url = '',
  bool serverSettings = true,
}) => InferenceSettings(
  remoteEnabled: true,
  remoteProfiles: [
    RemoteProfile(
      id: id,
      name: 'Test',
      providerId: providerId,
      baseUrl: url.isEmpty
          ? RemoteProvider.byId(providerId).defaultBaseUrl
          : url,
      model: model,
      serverSettings: serverSettings,
    ),
  ],
  remoteProfileId: id,
  remoteApiKeys: {id: 'sk-test'},
  maxTokens: 512,
  contextSize: 4096,
  temperature: 1.0,
  topP: 0.95,
  topK: 20,
  presencePenalty: 1.5,
);

RemoteEngine engineWith(HttpClientAdapter adapter) => RemoteEngine(
  dio: Dio()..httpClientAdapter = adapter,
  usage: RemoteUsageLog(prefs: () => null),
);

Future<String> ask(
  RemoteEngine engine,
  InferenceSettings s, {
  List<ToolSpec> tools = const [],
}) => engine
    .generate(
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
      fallbackTemplate: '',
      settings: s,
      tools: tools,
    )
    .join();

const _search = ToolSpec(
  name: 'search_web',
  description: 'Search the web.',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string'},
    },
  },
);

void main() {
  test('profiles keep the server settings unless turned off', () {
    final old = RemoteProfile.fromJson({'id': 'a', 'name': 'Old'})!;
    expect(old.serverSettings, isTrue);
    final off = RemoteProfile.fromJson(
      const RemoteProfile(id: 'b', name: 'B', serverSettings: false).toJson(),
    )!;
    expect(off.serverSettings, isFalse);
  });

  test(
    'a call that sets its own length or temperature uses the app limits',
    () {
      final turn = connection(
        'lmstudio',
        id: 'x',
      ).copyWith(serverSampling: true);
      expect(turn.serverSampling, isTrue);
      expect(turn.copyWith(thinkingBudgetTokens: 1024).serverSampling, isTrue);
      // A judge, a title, a Goal's budget.
      expect(turn.copyWith(maxTokens: 8).serverSampling, isFalse);
      expect(turn.copyWith(temperature: 0).serverSampling, isFalse);
      expect(turn.withinOutput(300).serverSampling, isFalse);
    },
  );

  test('grounded answers keep a remote model on its own sampling', () {
    final turn = connection('lmstudio', id: 'g').copyWith(serverSampling: true);
    final grounded = TurnPolicy.groundedSettings(turn, grounded: true);
    expect(grounded.serverSampling, isTrue);
    expect(grounded.temperature, 1.0);
    final app = TurnPolicy.groundedSettings(
      connection('lmstudio', id: 'g2'),
      grounded: true,
    );
    expect(app.temperature, TurnPolicy.groundedTemperature);
  });

  test(
    'OpenAI-style: no sampling or max_tokens with the server settings',
    () async {
      final adapter = _Adapter(answer);
      final engine = engineWith(adapter);
      final s = connection('lmstudio', id: 'o', url: 'http://10.0.0.2:1234/v1');
      expect(await ask(engine, s.copyWith(serverSampling: true)), 'ok');
      var body = sent(adapter.requests.last);
      for (final gone in [
        'temperature',
        'top_p',
        'top_k',
        'max_tokens',
        'max_completion_tokens',
        'presence_penalty',
      ]) {
        expect(body.containsKey(gone), isFalse, reason: gone);
      }
      // The app's own call (a judge) still sends its limits.
      expect(await ask(engine, s), 'ok');
      body = sent(adapter.requests.last);
      expect(body['temperature'], 1.0);
      expect(body['max_tokens'], 512);
    },
  );

  test('Gemini: the model default sampling and output length', () async {
    final adapter = _Adapter(answer);
    final engine = engineWith(adapter);
    final s = connection('gemini', id: 'gm', model: 'gemini-3.5-flash');
    expect(await ask(engine, s.copyWith(serverSampling: true)), 'ok');
    final config =
        sent(adapter.requests.last)['generationConfig'] as Map<String, dynamic>;
    for (final gone in [
      'temperature',
      'topP',
      'topK',
      'maxOutputTokens',
      'presencePenalty',
    ]) {
      expect(config.containsKey(gone), isFalse, reason: gone);
    }
  });

  test('Claude asks for a large ceiling and learns a smaller one', () async {
    var calls = 0;
    final adapter = _Adapter((o) {
      calls++;
      if (sent(o)['max_tokens'] == RemoteEngine.anthropicServerCeiling) {
        return ResponseBody.fromString(
          '{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: 32000 > 8192, which is the maximum allowed number of output tokens for claude-3-5-haiku"}}',
          400,
        );
      }
      return answer(o);
    });
    final engine = engineWith(adapter);
    final s = connection(
      'anthropic',
      id: 'c',
      model: 'claude-3-5-haiku',
    ).copyWith(serverSampling: true);
    expect(await ask(engine, s), 'ok');
    expect(calls, 2);
    expect(sent(adapter.requests.last)['max_tokens'], 8192);
    expect(await ask(engine, s), 'ok');
    expect(calls, 3, reason: 'remembered for the session');
  });

  test('LM Studio reports the context it loaded the model with', () async {
    final adapter = _Adapter((o) {
      if (o.uri.path == '/api/v0/models') {
        return ResponseBody.fromString(
          jsonEncode({
            'data': [
              {'id': 'other', 'loaded_context_length': 2048},
              {
                'id': 'qwen3-32b',
                'loaded_context_length': 32768,
                'max_context_length': 131072,
              },
            ],
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      }
      return answer(o);
    });
    final engine = engineWith(adapter);
    final s = connection(
      'lmstudio',
      id: 'lms',
      model: 'qwen3-32b',
      url: 'http://10.0.0.3:1234/v1',
    );
    final preview = await engine.previewPrompt(
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
      fallbackTemplate: '',
      settings: s,
    );
    expect(preview['contextSize'], 32768);
    expect(RemoteEngine.contextFor(s), 32768);
    // Turned off: the phone's setting.
    final off = connection(
      'lmstudio',
      id: 'lms-off',
      model: 'qwen3-32b',
      url: 'http://10.0.0.3:1234/v1',
      serverSettings: false,
    );
    await engine.learnWindow(off);
    expect(RemoteEngine.contextFor(off), 4096);
  });

  test('a hosted model is budgeted against its listed window', () async {
    final adapter = _Adapter((o) {
      if (o.method == 'GET') {
        return ResponseBody.fromString(
          jsonEncode({
            'models': [
              {
                'name': 'models/gemini-3.5-flash',
                'inputTokenLimit': 1048576,
                'supportedGenerationMethods': ['generateContent'],
              },
            ],
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      }
      return answer(o);
    });
    final engine = engineWith(adapter);
    final s = connection('gemini', id: 'gw', model: 'gemini-3.5-flash');
    await engine.learnWindow(s);
    expect(RemoteEngine.contextFor(s), 1048576);
  });

  test('a model without tool support falls back to the app planning', () async {
    var calls = 0;
    final adapter = _Adapter((o) {
      calls++;
      if (sent(o).containsKey('tools')) {
        return ResponseBody.fromString(
          '{"error":{"message":"registry.ollama.ai/library/gemma2:2b does not support tools","type":"api_error"}}',
          400,
        );
      }
      return answer(o);
    });
    final engine = engineWith(adapter);
    final s = connection(
      'ollama',
      id: 'ol',
      model: 'gemma2:2b',
      url: 'http://10.0.0.4:11434/v1',
    );
    expect(RemoteEngine.acceptsTools(s), isTrue);
    expect(await ask(engine, s, tools: const [_search]), 'ok');
    expect(calls, 2);
    expect(RemoteEngine.acceptsTools(s), isFalse);
  });

  test('Gemma on the Gemini API keeps the app planning', () {
    expect(
      RemoteEngine.acceptsTools(
        connection('gemini', id: 'gemma', model: 'gemma-4-31b-it'),
      ),
      isFalse,
    );
    expect(
      RemoteEngine.acceptsTools(
        connection('gemini', id: 'gem', model: 'gemini-3.5-flash'),
      ),
      isTrue,
    );
  });

  test('the remote brain is told it decides and has more rounds', () {
    expect(TurnPrompts.remoteBrainText, contains('You decide'));
    expect(TurnPrompts.remoteBrainRounds, greaterThan(4));
  });
}
