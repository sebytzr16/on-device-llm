import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

import 'device_model_server_test.dart' show FakeEngine;

class _OversizedRequest extends Stream<Uint8List> implements HttpRequest {
  bool listened = false;
  @override
  int get contentLength => 24 * 1024 * 1024 + 1;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listened = true;
    return Stream<Uint8List>.value(Uint8List.fromList([123])).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'M05: rotating IPv6 hosts share a /64 budget; mapped IPv4 shares IPv4',
    () {
      String key(String value) =>
          DeviceModelServer.clientLimitKey(InternetAddress(value));
      expect(key('fd12:3456:789a:1::1'), key('fd12:3456:789a:1:ffff::2'));
      expect(key('fe80::1%3'), key('fe80::2%3'));
      expect(key('fd12:3456:789a:1::1'), isNot(key('fd12:3456:789a:2::1')));
      expect(key('::ffff:192.168.1.2'), key('192.168.1.2'));
      expect(key('192.168.1.2'), isNot(key('192.168.1.3')));
    },
  );
  const token = '0123456789abcdef0123456789abcdef';
  late DeviceModelServer server;
  late HttpClient client;
  late WorkspaceApi workspace;
  late Completer<void> jobGate;
  final sockets = <Socket>[];
  final messages = [
    {'role': 'user', 'content': 'hi'},
  ];

  Future<HttpClientResponse> ask(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    bool apiKey = false,
    HttpClient? transport,
  }) async {
    final request = await (transport ?? client).openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    request.headers.set(
      apiKey ? 'x-api-key' : 'authorization',
      apiKey ? token : 'Bearer $token',
    );
    if (body != null) request.write(jsonEncode(body));
    return request.close().timeout(const Duration(seconds: 3));
  }

  setUp(() async {
    sockets.clear();
    client = HttpClient()..maxConnectionsPerHost = 32;
    jobGate = Completer<void>();
    workspace = WorkspaceApi(run: (_, _) => jobGate.future, capabilities: []);
    server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test',
      fallbackTemplate: '',
      accessToken: token,
      workspace: workspace,
      pairCode: '123456',
      bodyTimeout: const Duration(seconds: 2),
    );
    await server.start();
  });
  tearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    client.close(force: true);
    if (!jobGate.isCompleted) jobGate.complete();
    await server.stop();
  });

  test(
    'M05: declared oversized bodies are refused before subscribing',
    () async {
      final request = _OversizedRequest();
      await expectLater(
        DeviceModelServer.readBody(request, const Duration(seconds: 1)),
        throwsFormatException,
      );
      expect(request.listened, false);
    },
  );

  for (final path in ['/v1/chat/completions', '/v1/workspace/uploads']) {
    test(
      'M05/M07: $path has bounded admission before body buffering',
      () async {
        for (var i = 0; i < 8; i++) {
          final socket = await Socket.connect('127.0.0.1', server.port!);
          sockets.add(socket);
          socket.write(
            'POST $path HTTP/1.1\r\nHost: localhost\r\n'
            'Authorization: Bearer $token\r\nContent-Length: 1048576\r\n\r\nx',
          );
          await socket.flush();
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final response = await ask(
          path,
          method: 'POST',
          body: {'messages': messages},
        );
        expect(response.statusCode, 429);
        await response.drain<void>();
        sockets.removeLast().destroy();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final recovered = await ask('/v1/workspace/capabilities');
        expect(recovered.statusCode, 200);
        await recovered.drain<void>();
      },
    );
  }

  test(
    'M05/M07: global admission is bounded across different clients',
    () async {
      for (final source in ['127.0.0.2', '127.0.0.3']) {
        for (var i = 0; i < 8; i++) {
          final socket = await Socket.connect(
            '127.0.0.1',
            server.port!,
            sourceAddress: source,
          );
          sockets.add(socket);
          socket.write(
            'POST /v1/chat/completions HTTP/1.1\r\nHost: localhost\r\n'
            'Authorization: Bearer $token\r\nContent-Length: 1048576\r\n\r\nx',
          );
          await socket.flush();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final response = await ask('/v1/workspace/capabilities');
      expect(response.statusCode, 429);
      await response.drain<void>();
    },
  );

  test('M07: workspace requests share the per-client rate budget', () async {
    for (var i = 0; i < 20; i++) {
      final response = await ask('/v1/workspace/capabilities');
      expect(response.statusCode, 200);
      await response.drain<void>();
    }
    final response = await ask('/v1/workspace/capabilities');
    expect(response.statusCode, 429);
    await response.drain<void>();
    final chat = await ask(
      '/v1/chat/completions',
      method: 'POST',
      body: {'messages': messages},
    );
    expect(chat.statusCode, 429);
    await chat.drain<void>();
  });

  test(
    'M07: workspace SSE subscriptions hold admission until disconnected',
    () async {
      final job = workspace.jobs.submit(
        requestId: 'live',
        fingerprint: 'live',
        run: (_) => jobGate.future,
      );
      workspace.debugAssignOwner(job.id, 'legacy');
      final subscriptions = <StreamSubscription<List<int>>>[];
      final transports = <HttpClient>[];
      addTearDown(() async {
        for (final transport in transports) {
          transport.close(force: true);
        }
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });
      for (var i = 0; i < 8; i++) {
        final transport = HttpClient();
        transports.add(transport);
        final response = await ask(
          '/v1/workspace/jobs/${job.id}/events',
          transport: transport,
        );
        expect(response.statusCode, 200);
        subscriptions.add(response.listen((_) {}));
      }
      final blocked = await ask('/v1/workspace/jobs/${job.id}/events');
      expect(blocked.statusCode, 429);
      await blocked.drain<void>();
      final cancelled = subscriptions.removeLast().cancel();
      transports.removeLast().close(force: true);
      await cancelled;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final recovered = await ask('/v1/workspace/capabilities');
      expect(recovered.statusCode, 200);
      await recovered.drain<void>();
      expect(job.terminal, false);
    },
  );

  test(
    'CR-01: pairing rejects a declared body above 4 KB before reading',
    () async {
      final socket = await Socket.connect('127.0.0.1', server.port!);
      sockets.add(socket);
      socket.write(
        'POST /v1/pair HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4097\r\n\r\nx',
      );
      await socket.flush();
      final reply = await utf8.decoder
          .bind(socket)
          .first
          .timeout(const Duration(seconds: 1));
      expect(reply, contains('400'));
    },
  );

  test(
    'CR-01: typed lockout rejects before reading but QR remains usable',
    () async {
      for (var i = 0; i < 5; i++) {
        final response = await ask(
          '/v1/pair',
          method: 'POST',
          body: {'code': '000000'},
        );
        await response.drain<void>();
      }
      final socket = await Socket.connect('127.0.0.1', server.port!);
      sockets.add(socket);
      socket.write(
        'POST /v1/pair HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\nx',
      );
      await socket.flush();
      expect(
        await utf8.decoder
            .bind(socket)
            .first
            .timeout(const Duration(seconds: 1)),
        contains('429'),
      );
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/v1/pair'),
      );
      request.headers.set('X-Pairing-Mode', 'qr');
      request.write(
        jsonEncode({'hostId': server.hostId, 'secret': server.pairingSecret}),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();
    },
  );

  test('CR-01: pairing readers and QR request rate are bounded', () async {
    for (var i = 0; i < 4; i++) {
      final socket = await Socket.connect('127.0.0.1', server.port!);
      sockets.add(socket);
      socket.write(
        'POST /v1/pair HTTP/1.1\r\nHost: localhost\r\nX-Pairing-Mode: qr\r\nContent-Length: 100\r\n\r\nx',
      );
      await socket.flush();
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final full = await ask('/v1/pair', method: 'POST', body: {'secret': 'bad'});
    expect(full.statusCode, 429);
    await full.drain<void>();
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    var limited = false;
    for (var i = 0; i < 25; i++) {
      final response = await ask(
        '/v1/pair',
        method: 'POST',
        body: {'secret': 'bad'},
      );
      limited |= response.statusCode == 429;
      await response.drain<void>();
    }
    expect(limited, isTrue);
  });

  for (final saturateSubscriptions in [false, true]) {
    test(
      'CR-03: control works under saturation subscriptions=$saturateSubscriptions',
      () async {
        final job = workspace.jobs.submit(
          requestId: 'control',
          fingerprint: 'control',
          run: (_) => jobGate.future,
        );
        workspace.debugAssignOwner(job.id, 'legacy');
        final answer = job.approve('Allow this operation?');
        final approvalId = job.pendingApprovals.single;
        final transports = <HttpClient>[];
        addTearDown(() {
          for (final transport in transports) {
            transport.close(force: true);
          }
        });
        if (saturateSubscriptions) {
          for (var i = 0; i < 8; i++) {
            final transport = HttpClient();
            transports.add(transport);
            final response = await ask(
              '/v1/workspace/jobs/${job.id}/events',
              transport: transport,
            );
            response.listen((_) {});
          }
        } else {
          for (var i = 0; i < 20; i++) {
            final response = await ask('/v1/workspace/capabilities');
            await response.drain<void>();
          }
        }
        final approval = await ask(
          '/v1/workspace/jobs/${job.id}/approval',
          method: 'POST',
          body: {'id': approvalId, 'allow': true},
        );
        expect(approval.statusCode, 200);
        expect(await answer, isTrue);
        await approval.drain<void>();
        final cancelled = await ask(
          '/v1/workspace/jobs/${job.id}/cancel',
          method: 'POST',
        );
        expect(cancelled.statusCode, 200);
        await cancelled.drain<void>();
        expect(job.terminal, isTrue);
      },
    );
  }

  test(
    'N34/N61: invalid sampling and zero repeat penalty return 400',
    () async {
      for (final entry in {
        'temperature': 'hot',
        'max_tokens': -1,
        'repeat_penalty': 0,
      }.entries) {
        final response = await ask(
          '/v1/chat/completions',
          method: 'POST',
          body: {'messages': messages, entry.key: entry.value},
        );
        expect(response.statusCode, 400, reason: entry.key);
        final text = await utf8.decoder.bind(response).join();
        expect(text, contains(entry.key));
      }
    },
  );

  test('N58: streamed oversized body reports the actual 24 MB limit', () async {
    await expectLater(
      DeviceModelServer.readBody(
        Stream.value(List<int>.filled(24 * 1024 * 1024 + 1, 32)),
        const Duration(seconds: 2),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'limit',
          contains('24 MB'),
        ),
      ),
    );
  });

  test('N32: Anthropic x-api-key authentication works', () async {
    final response = await ask(
      '/v1/messages',
      method: 'POST',
      apiKey: true,
      body: {'messages': messages, 'max_tokens': 2},
    );
    expect(response.statusCode, 200);
    await response.drain<void>();
  });
}
