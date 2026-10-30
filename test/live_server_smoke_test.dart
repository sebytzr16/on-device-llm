// Real-engine server smoke test: skipped unless OD_LIVE_MODEL (a chat GGUF)
// is set; OD_LIVE_EMBED (an embedding GGUF) adds the embeddings checks.
// Windows: put native/out/windows-x64 on PATH, then
//   flutter test test/live_server_smoke_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/served_vector_engine.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

void main() {
  final modelPath = Platform.environment['OD_LIVE_MODEL'];
  final embedPath = Platform.environment['OD_LIVE_EMBED'];
  final skip = modelPath == null ? 'OD_LIVE_MODEL not set' : null;
  final random = Random.secure();
  final token = List.generate(
    40,
    (_) => random.nextInt(36).toRadixString(36),
  ).join();
  const settings = InferenceSettings(
    backend: GpuBackend.cpu,
    contextSize: 4096,
    maxTokens: 64,
    temperature: 0,
    thinkingModeEnabled: false,
  );
  final engine = LlamaEngine();
  late DeviceModelServer server;
  final client = HttpClient();

  setUpAll(() async {
    if (skip != null) return;
    await engine.loadModel(modelPath: modelPath!, settings: settings);
    server = DeviceModelServer(
      engine: engine,
      settings: () => settings,
      modelId: 'live',
      fallbackTemplate: '',
      accessToken: token,
      vectors: embedPath == null
          ? null
          : LocalServedVectorEngine(
              (id) => id == 'embed' ? embedPath : null,
              availableModels: () => {'embed': 'embedding'},
            ),
    );
    await server.start();
  });
  tearDownAll(() async {
    if (skip != null) return;
    client.close(force: true);
    await server.stop();
    engine.dispose();
  });

  Future<HttpClientResponse> send(
    String method,
    String path, {
    Object? body,
    String? auth,
  }) async {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (auth != null) req.headers.set('authorization', 'Bearer $auth');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    return req.close();
  }

  Future<String> read(HttpClientResponse r) => utf8.decoder.bind(r).join();

  Map<String, Object> chat(String text, {bool stream = false}) => {
    'model': 'live',
    'messages': [
      {'role': 'user', 'content': text},
    ],
    'max_tokens': 32,
    'stream': stream,
  };

  test('auth: no token and a wrong token are refused', () async {
    expect((await send('GET', '/v1/models')).statusCode, 401);
    expect((await send('GET', '/v1/models', auth: 'x' * 40)).statusCode, 401);
    final ok = await send('GET', '/v1/models', auth: token);
    expect(ok.statusCode, 200);
    expect(await read(ok), contains('"live"'));
  }, skip: skip);

  test(
    'OpenAI chat answers a fact, plain and streamed',
    () async {
      final plain = await send(
        'POST',
        DeviceModelServer.completionsPath,
        auth: token,
        body: chat('What is the capital of France? One word.'),
      );
      expect(plain.statusCode, 200);
      final body = jsonDecode(await read(plain)) as Map;
      final text = body['choices'][0]['message']['content'] as String;
      expect(text.toLowerCase(), contains('paris'));
      expect(body['usage']['completion_tokens'], greaterThan(0));

      final streamed = await send(
        'POST',
        DeviceModelServer.completionsPath,
        auth: token,
        body: chat('Say hello.', stream: true),
      );
      final events = await read(streamed);
      expect(events, contains('"delta"'));
      expect(events.trim(), endsWith('data: [DONE]'));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'Anthropic messages answer',
    () async {
      final r = await send(
        'POST',
        DeviceModelServer.messagesPath,
        auth: token,
        body: {
          'model': 'live',
          'max_tokens': 32,
          'messages': [
            {'role': 'user', 'content': 'Compute 2+2.'},
          ],
        },
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(await read(r)) as Map;
      expect(body['content'][0]['text'], contains('4'));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a dropped stream frees the engine for the next request',
    () async {
      // A raw socket, so the drop really closes the connection.
      final socket = await Socket.connect('127.0.0.1', server.port!);
      final payload = utf8.encode(
        jsonEncode({
          ...chat('Count from 1 to 500.', stream: true),
          'max_tokens': 2000,
        }),
      );
      socket.write(
        'POST ${DeviceModelServer.completionsPath} HTTP/1.1\r\n'
        'Host: 127.0.0.1\r\nAuthorization: Bearer $token\r\n'
        'Content-Type: application/json\r\n'
        'Content-Length: ${payload.length}\r\n\r\n',
      );
      socket.add(payload);
      final seen = StringBuffer();
      final first = Completer<void>();
      socket.listen((data) {
        seen.write(utf8.decode(data, allowMalformed: true));
        if (seen.toString().contains('"delta"') && !first.isCompleted) {
          first.complete();
        }
      }, onError: (_) {});
      await first.future;
      socket.destroy();
      final dropped = DateTime.now();
      final next = await send(
        'POST',
        DeviceModelServer.completionsPath,
        auth: token,
        body: chat('Say yes.'),
      );
      expect(next.statusCode, 200);
      await read(next);
      // The dropped answer would run ~50 s to max_tokens if not cancelled.
      expect(DateTime.now().difference(dropped).inSeconds, lessThan(15));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'parallel requests queue and all finish',
    () async {
      final results = await Future.wait([
        for (var i = 0; i < 3; i++)
          send(
            'POST',
            DeviceModelServer.completionsPath,
            auth: token,
            body: chat('Say the number $i.'),
          ).then((r) async => (r.statusCode, await read(r))),
      ]);
      for (final (status, _) in results) {
        expect(status, 200);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'embeddings: vectors, and over-limit input refused',
    () async {
      final ok = await send(
        'POST',
        DeviceModelServer.embeddingsPath,
        auth: token,
        body: {
          'model': 'embed',
          'input': ['hello world'],
        },
      );
      expect(ok.statusCode, 200);
      final data = jsonDecode(await read(ok)) as Map;
      expect((data['data'][0]['embedding'] as List).length, greaterThan(100));
      final long = await send(
        'POST',
        DeviceModelServer.embeddingsPath,
        auth: token,
        body: {
          'model': 'embed',
          'input': ['word ' * 5000],
        },
      );
      expect(long.statusCode, 400);
      await read(long);
    },
    skip: skip ?? (embedPath == null ? 'OD_LIVE_EMBED not set' : null),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
