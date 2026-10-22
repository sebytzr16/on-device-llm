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
  @override
  Map<String, dynamic> get metrics => const {};
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
    yield 'Hello ';
    yield messages.last['content'] as String;
  }
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

  test('requires bearer authentication and exposes model metadata', () async {
    expect((await request('GET', '/v1/models')).statusCode, 401);
    final response = await request('GET', '/v1/models', auth: token);
    expect(response.statusCode, 200);
    final data = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect((data['data'] as List).first['id'], 'test-model');
  });

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

  test('rejects unsupported tool calls explicitly', () async {
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
            'function': {'name': 'lookup'},
          },
        ],
      }),
    );
    expect(response.statusCode, 400);
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect(body['error']['message'], contains('Tool calling'));
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
    // The fake engine reports no metrics: the streamed pieces are counted.
    expect(body['usage'], {
      'prompt_tokens': 0,
      'completion_tokens': 2,
      'total_tokens': 2,
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
    expect(events, contains('"choices":[],"usage":{"prompt_tokens":0'));
    await (await request('GET', '/v1/models', auth: 'wrong')).drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(served.map((r) => r.status), [200, 200, 401]);
    expect(served[0].ok && !served[0].stream, true);
    expect(served[1].stream, true);
    expect(served[1].completionTokens, 2);
    expect(served[2].ok, false);
    expect(served[2].client, '127.0.0.1');
  });

  test(
    'two requests at once: the second is refused, never run alongside',
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
      expect(codes, [200, 429]);
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
      expect(s.answered, 2);
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
