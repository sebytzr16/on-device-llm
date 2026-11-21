import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/hosting_tls.dart';
import 'package:ondevice_llm/features/hosting/paired_devices.dart';
import 'package:ondevice_llm/features/hosting/windows_mdns.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/hosting/workspace_jobs.dart';
import 'package:ondevice_llm/features/hosting/workspace_uploads.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

import 'device_model_server_test.dart' show FakeEngine;
import 'support/hosting_secure_storage.dart';

/// A sink whose flush never completes, like a socket with a zero window.
class _StalledSink implements IOSink {
  final _never = Completer<void>();
  @override
  Future<void> flush() => _never.future;
  @override
  Future<void> get done => _never.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StalledSocket implements Socket {
  bool destroyed = false;
  @override
  void destroy() => destroyed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers with more than any socket buffer holds, so a peer that stops
/// reading stalls the handler's write.
class _FloodEngine extends FakeEngine {
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    for (var i = 0; i < 4000; i++) {
      yield 'x' * 4096;
    }
  }
}

class _HeldEngine extends FakeEngine {
  final started = Completer<void>();
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
    started.complete();
    await cancelled.future;
  }
}

Future<HttpClientResponse> _ask(
  int port,
  String token, {
  String path = DeviceModelServer.completionsPath,
  Map<String, Object?>? body,
  required HttpClient client,
}) async {
  final request = await client.openUrl(
    'POST',
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.write(
    jsonEncode(
      body ??
          {
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          },
    ),
  );
  return request.close();
}

void main() {
  const token = '0123456789abcdef0123456789abcdef';

  DeviceModelServer host({
    FakeEngine? engine,
    WorkspaceApi? workspace,
    PairedDevices? devices,
    void Function(ServedRequest)? onServed,
  }) => DeviceModelServer(
    engine: engine ?? FakeEngine(),
    settings: () => const InferenceSettings(),
    modelId: 'test',
    fallbackTemplate: '',
    accessToken: token,
    workspace: workspace,
    pairedDevices: devices,
    onServed: onServed,
  );

  Future<Socket> open(DeviceModelServer server, String headers) async {
    final socket = await Socket.connect('127.0.0.1', server.port!);
    addTearDown(socket.destroy);
    socket.write(headers);
    await socket.flush();
    return socket;
  }

  const limit = Duration(seconds: 5);

  test(
    '06a1-1: a streaming write to a peer that stopped reading times out',
    () async {
      final sink = _StalledSink();
      final socket = _StalledSocket();
      final clock = Stopwatch()..start();
      await expectLater(
        DeviceModelServer.flushWithin(
          sink,
          socket,
          const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(socket.destroyed, isTrue);
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    },
  );

  test(
    '06a1-1: a stalled stream frees the model for the next request',
    () async {
      final server = DeviceModelServer(
        engine: _FloodEngine(),
        settings: () => const InferenceSettings(),
        modelId: 'test',
        fallbackTemplate: '',
        accessToken: token,
        bodyTimeout: const Duration(seconds: 2),
      );
      final previous = DeviceModelServer.writeTimeout;
      DeviceModelServer.writeTimeout = const Duration(milliseconds: 200);
      addTearDown(() => DeviceModelServer.writeTimeout = previous);
      await server.start();
      addTearDown(server.stop);
      final stalled = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(stalled.destroy);
      final body = jsonEncode({
        'model': 'test',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      stalled.write(
        'POST ${DeviceModelServer.completionsPath} HTTP/1.1\r\n'
        'Host: localhost\r\nAuthorization: Bearer $token\r\n'
        'Content-Type: application/json\r\n'
        'Content-Length: ${utf8.encode(body).length}\r\n\r\n$body',
      );
      await stalled.flush();
      // The peer never reads: the answer cannot drain, so the handler has to
      // give up and release the model before its deadline.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      // The slot is granted only when the stalled handler released it.
      final next = await _ask(
        server.port!,
        token,
        client: client,
      ).timeout(const Duration(seconds: 5));
      expect(next.statusCode, HttpStatus.ok);
      await next.drain<void>();
    },
  );

  test('06a1-2: a refusal does not wait for the peer\'s unread body', () async {
    final server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test',
      fallbackTemplate: '',
      accessToken: token,
      bodyTimeout: const Duration(seconds: 10),
    );
    await server.start();
    addTearDown(server.stop);
    final sockets = <Socket>[];
    addTearDown(() {
      for (final socket in sockets) {
        socket.destroy();
      }
    });
    String stall(String path) =>
        'POST $path HTTP/1.1\r\nHost: localhost\r\n'
        'Authorization: Bearer $token\r\nContent-Length: 1048576\r\n\r\nx';
    for (var i = 0; i < 8; i++) {
      final socket = await Socket.connect('127.0.0.1', server.port!);
      sockets.add(socket);
      socket.write(stall(DeviceModelServer.completionsPath));
      await socket.flush();
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // The ninth connection is over the limit and still carries a body the
    // server will never read: its refusal must not wait for that body.
    final refused = await Socket.connect('127.0.0.1', server.port!);
    sockets.add(refused);
    refused.write(stall('/v1/models'));
    await refused.flush();
    final reply = await utf8.decoder
        .bind(refused)
        .first
        .timeout(const Duration(seconds: 2));
    expect(reply, contains('429'));
    // A released slot lets the same address through again.
    sockets.removeAt(0).destroy();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final served = await _ask(server.port!, token, client: client);
    expect(served.statusCode, HttpStatus.ok);
    await served.drain<void>();
  });

  test('06a1-2: guessing tokens cannot lock out a paired client', () async {
    final devices = PairedDevices(save: (_) async {});
    final pairedToken = await devices.issue('Phone');
    final server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test',
      fallbackTemplate: '',
      accessToken: token,
      pairedDevices: devices,
    );
    await server.start();
    addTearDown(server.stop);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    for (var i = 0; i < 22; i++) {
      final response = await _ask(
        server.port!,
        'not-the-token',
        client: client,
      );
      expect(
        response.statusCode,
        anyOf(HttpStatus.unauthorized, HttpStatus.tooManyRequests),
      );
      await response.drain<void>();
    }
    final paired = await _ask(server.port!, pairedToken, client: client);
    expect(paired.statusCode, HttpStatus.ok);
    await paired.drain<void>();
  });

  test(
    'invalid credentials leave the control quota available and cap failure history',
    () async {
      final devices = PairedDevices(save: (_) async {});
      final paired = await devices.issue('Phone');
      final workspace = WorkspaceApi(capabilities: [], run: (_, _) async {});
      final job = workspace.jobs.submit(
        requestId: 'control',
        fingerprint: 'control',
        run: (job) async {
          await job.approve('Continue?');
        },
      );
      workspace.debugAssignOwner(job.id, devices.principal(paired)!);
      final server = host(workspace: workspace, devices: devices);
      await server.start();
      addTearDown(server.stop);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final path = '/v1/workspace/jobs/${job.id}';
      for (var i = 1; i <= 70; i++) {
        final refused = await _ask(
          server.port!,
          'x' * 44,
          path: '$path/approval',
          client: client,
        );
        expect(
          refused.statusCode,
          i < DeviceModelServer.maxClientFailures ? 401 : 429,
        );
        await refused.drain<void>();
      }
      expect(
        server.debugAuthFailureCount('127.0.0.1'),
        DeviceModelServer.maxClientFailures,
      );
      final approved = await _ask(
        server.port!,
        paired,
        path: '$path/approval',
        client: client,
        body: {'id': job.pendingApprovals.single, 'allow': true},
      );
      expect(approved.statusCode, 200);
      await approved.drain<void>();
      final cancelled = await _ask(
        server.port!,
        paired,
        path: '$path/cancel',
        client: client,
      );
      expect(cancelled.statusCode, 200);
      await cancelled.drain<void>();
    },
  );

  test(
    'public preflight and TLS bootstrap close stalled connections',
    () async {
      final dir = await Directory.systemTemp.createTemp('hosting-bootstrap');
      addTearDown(() async {
        final marker = File('${dir.path}/hosting-tls.fingerprint');
        if (await marker.exists()) await marker.delete();
        await dir.delete();
      });
      final tls = await HostingTls.load(
        directory: dir,
        storage: MemoryHostSecrets(),
      );
      final previous = DeviceModelServer.writeTimeout;
      DeviceModelServer.writeTimeout = const Duration(milliseconds: 200);
      addTearDown(() => DeviceModelServer.writeTimeout = previous);
      final server = host();
      await server.start(tls: tls);
      addTearDown(server.stop);
      for (final line in ['OPTIONS /v1/models', 'GET /v1/pairing-tls']) {
        final stalled = await open(
          server,
          '$line HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4096\r\n\r\nx',
        );
        await stalled.drain<void>().timeout(limit);
      }
    },
  );

  test('workspace control refusals release slots with unread bodies', () async {
    final workspace = WorkspaceApi(capabilities: [], run: (_, _) async {});
    final server = host(workspace: workspace);
    await server.start();
    addTearDown(server.stop);
    for (var batch = 0; batch < 2; batch++) {
      await Future.wait(
        List.generate(4, (_) async {
          final stalled = await open(
            server,
            'POST /v1/workspace/jobs/unknown/approval HTTP/1.1\r\n'
            'Host: localhost\r\nAuthorization: Bearer $token\r\n'
            'Content-Length: 4096\r\n\r\nx',
          );
          final reply = await utf8.decoder.bind(stalled).join().timeout(limit);
          expect(reply, startsWith('HTTP/1.1 404'));
        }),
      );
    }
  });

  test(
    'an unexpected workspace failure answers 500 and is logged as 500',
    () async {
      final recorded = Completer<ServedRequest>();
      final workspace = WorkspaceApi(
        capabilities: [],
        run: (_, _) async {},
        uploads: WorkspaceUploads(
          createDirectory: () async {
            throw const FileSystemException('The disk is full.');
          },
        ),
      );
      final server = host(workspace: workspace, onServed: recorded.complete);
      await server.start();
      addTearDown(server.stop);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.openUrl(
        'POST',
        Uri.parse(
          'http://127.0.0.1:${server.port!}/v1/workspace/uploads?name=note.txt',
        ),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.contentLength = 1;
      request.add(const [120]);
      final reply = await request.close();
      expect(reply.statusCode, 500);
      expect(jsonDecode(await utf8.decoder.bind(reply).join()), {
        'error': 'Request failed.',
      });
      final served = await recorded.future.timeout(limit);
      expect(served.path, '/v1/workspace/uploads');
      expect(served.status, 500);
    },
  );

  test('a workspace event write deadline releases the subscription', () async {
    final handled = Completer<void>();
    final finish = Completer<void>();
    final workspace = WorkspaceApi(
      capabilities: [],
      run: (_, _) async {},
      jobs: WorkspaceJobs(maxActive: 1),
    );
    final job = workspace.jobs.submit(
      requestId: 'events',
      fingerprint: 'events',
      run: (_) => finish.future,
    );
    workspace.debugAssignOwner(job.id, 'legacy');
    final server = host(
      workspace: workspace,
      onServed: (_) => handled.complete(),
    );
    final previous = DeviceModelServer.writeTimeout;
    DeviceModelServer.writeTimeout = const Duration(milliseconds: 200);
    addTearDown(() => DeviceModelServer.writeTimeout = previous);
    await server.start();
    addTearDown(server.stop);
    addTearDown(() => finish.complete());
    final data = 'x' * (1024 * 1024);
    for (var i = 0; i < 7; i++) {
      job.emit('text', {'text': data});
    }
    await open(
      server,
      'GET /v1/workspace/jobs/${job.id}/events HTTP/1.1\r\n'
      'Host: localhost\r\nAuthorization: Bearer $token\r\n\r\n',
    );
    await handled.future.timeout(limit);
    expect(job.terminal, isFalse);
  });

  test(
    'stop closes detached peers and cancels inference before workspace disposal',
    () async {
      final finish = Completer<void>();
      final workspace = WorkspaceApi(capabilities: [], run: (_, _) async {});
      final job = workspace.jobs.submit(
        requestId: 'held',
        fingerprint: 'held',
        run: (_) => finish.future,
      );
      workspace.debugAssignOwner(job.id, 'legacy');
      final engine = _HeldEngine();
      final server = host(engine: engine, workspace: workspace);
      await server.start();
      final events = await open(
        server,
        'GET /v1/workspace/jobs/${job.id}/events HTTP/1.1\r\n'
        'Host: localhost\r\nAuthorization: Bearer $token\r\n\r\n',
      );
      final reading = StreamIterator(utf8.decoder.bind(events));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final requesting = _ask(server.port!, token, client: client);
      final completion = requesting
          .then((response) => response.drain<void>())
          .catchError((Object _) {});
      Future<void>? stopping;
      try {
        expect(await reading.moveNext().timeout(limit), isTrue);
        await engine.started.future.timeout(limit);
        stopping = server.stop();
        await engine.cancelled.future.timeout(limit);
        final rest = StringBuffer();
        while (await reading.moveNext().timeout(limit)) {
          rest.write(reading.current);
        }
        expect(rest.toString(), isNot(contains('"type":"cancelled"')));
        await completion.timeout(limit);
      } finally {
        finish.complete();
        await (stopping ?? server.stop());
        await reading.cancel();
      }
    },
  );

  test('a steady trickle cannot extend the upload deadline', () async {
    Directory? directory;
    final handled = Completer<void>();
    final uploads = WorkspaceUploads(
      receiveDeadline: const Duration(milliseconds: 400),
      createDirectory: () async =>
          directory = await Directory.systemTemp.createTemp('hosting-upload'),
    );
    final workspace = WorkspaceApi(
      capabilities: [],
      run: (_, _) async {},
      uploads: uploads,
    );
    final server = host(
      workspace: workspace,
      onServed: (_) => handled.complete(),
    );
    await server.start();
    addTearDown(server.stop);
    final socket = await open(
      server,
      'POST /v1/workspace/uploads HTTP/1.1\r\n'
      'Host: localhost\r\nAuthorization: Bearer $token\r\n'
      'Content-Length: 4096\r\n\r\nx',
    );
    final reply = utf8.decoder.bind(socket).join().timeout(limit);
    var chunks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      socket.write('x');
      chunks++;
    });
    try {
      // Cancelling Dart's request stream can close its connection immediately.
      expect(await reply, anyOf(isEmpty, startsWith('HTTP/1.1 408')));
    } finally {
      timer.cancel();
    }
    await handled.future.timeout(limit);
    expect(chunks, greaterThan(1));
    expect(await directory!.exists(), isFalse);
  });

  test(
    'Windows stop retains pending deregistration and cancels pending registration only',
    () async {
      var deregistered = 0, cancelled = 0;
      final previous = WindowsMdns.stopTimeout;
      WindowsMdns.stopTimeout = const Duration(milliseconds: 20);
      addTearDown(() => WindowsMdns.stopTimeout = previous);
      late void Function(int) registered, deregisterComplete;
      await WindowsMdns.debugAdvertise(
        register: (complete) {
          registered = complete;
          return 9506;
        },
        deregister: (complete) {
          deregisterComplete = complete;
          deregistered++;
          return 9506;
        },
        cancel: () => cancelled++,
      );
      registered(0);
      final clock = Stopwatch()..start();
      await WindowsMdns.stop();
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
      expect(deregistered, 1);
      expect(cancelled, 0);
      expect(WindowsMdns.debugHasCallback, isTrue);
      deregisterComplete(0);
      expect(WindowsMdns.debugHasCallback, isFalse);

      // A registration still waiting for Windows to confirm it is cancelled
      // rather than deregistered.
      var pendingCancelled = 0;
      await WindowsMdns.debugAdvertise(
        register: (complete) {
          registered = complete;
          return 9506;
        },
        deregister: (_) =>
            fail('A pending registration cannot be deregistered'),
        cancel: () => pendingCancelled++,
      );
      await WindowsMdns.stop();
      expect(pendingCancelled, 1);
      registered(1223);
      expect(WindowsMdns.debugHasCallback, isFalse);
    },
  );

  test(
    'Windows serializes concurrent advertisement replacements and stop',
    () async {
      final calls = <String>[];
      Future<void> advertise(String name) => WindowsMdns.debugAdvertise(
        register: (complete) {
          calls.add('register $name');
          scheduleMicrotask(() => complete(0));
          return 9506;
        },
        deregister: (complete) {
          calls.add('deregister $name');
          scheduleMicrotask(() => complete(0));
          return 9506;
        },
        cancel: () => fail('Registration should have completed'),
      );
      await Future.wait([
        advertise('one'),
        advertise('two'),
        WindowsMdns.stop(),
      ]);
      expect(calls, [
        'register one',
        'deregister one',
        'register two',
        'deregister two',
      ]);
      expect(WindowsMdns.debugHasCallback, isFalse);
    },
  );

  test('Windows skips a publication superseded during teardown', () async {
    final removing = Completer<void Function(int)>();
    await WindowsMdns.debugAdvertise(
      register: (complete) {
        scheduleMicrotask(() => complete(0));
        return 9506;
      },
      deregister: (complete) {
        removing.complete(complete);
        return 9506;
      },
      cancel: () => fail('Registration should have completed'),
    );
    var current = true;
    final replacing = WindowsMdns.debugAdvertise(
      register: (_) => fail('Superseded advertisement was published'),
      deregister: (_) => fail('Superseded advertisement was never registered'),
      cancel: () => fail('Superseded advertisement was never registered'),
      isCurrent: () => current,
    );
    final removed = await removing.future.timeout(limit);
    current = false;
    removed(0);
    await replacing;
    expect(WindowsMdns.debugHasCallback, isFalse);
  });

  for (final synchronous in [true, false]) {
    test(
      'Windows retries deregistration errors (synchronous=$synchronous)',
      () async {
        var attempts = 0;
        await WindowsMdns.debugAdvertise(
          register: (complete) {
            scheduleMicrotask(() => complete(0));
            return 9506;
          },
          deregister: (complete) {
            if (++attempts == 1) {
              if (synchronous) return 1;
              scheduleMicrotask(() => complete(1));
            } else {
              scheduleMicrotask(() => complete(0));
            }
            return 9506;
          },
          cancel: () => fail('Deregistration cannot be cancelled'),
        );
        await WindowsMdns.stop();
        expect(attempts, 2);
        expect(WindowsMdns.debugHasCallback, isFalse);
      },
    );
  }

  test(
    'an exhausted deregistration releases the record for the next advertisement',
    () async {
      final previousPending = WindowsMdns.maxPending;
      final previousTimeout = WindowsMdns.stopTimeout;
      WindowsMdns.stopTimeout = const Duration(milliseconds: 200);
      addTearDown(() {
        WindowsMdns.maxPending = previousPending;
        WindowsMdns.stopTimeout = previousTimeout;
      });
      // Windows rejects every deregistration, as after a network change.
      Future<void> leak() async {
        var attempts = 0;
        await WindowsMdns.debugAdvertise(
          register: (complete) {
            scheduleMicrotask(() => complete(0));
            return 9506;
          },
          deregister: (complete) {
            attempts++;
            scheduleMicrotask(() => complete(1));
            return 9506;
          },
          cancel: () => fail('Deregistration cannot be cancelled'),
        );
        await WindowsMdns.stop().timeout(limit);
        expect(attempts, 2);
        expect(WindowsMdns.debugHasCallback, isFalse);
      }

      for (var record = 0; record < previousPending; record++) {
        await leak();
      }
      // A record Windows never took over must not count against the limit.
      await WindowsMdns.debugAdvertise(
        register: (complete) {
          scheduleMicrotask(() => complete(0));
          return 9506;
        },
        deregister: (complete) {
          scheduleMicrotask(() => complete(0));
          return 9506;
        },
        cancel: () => fail('Deregistration cannot be cancelled'),
      );
      await WindowsMdns.stop().timeout(limit);
      expect(WindowsMdns.debugHasCallback, isFalse);
    },
  );

  test(
    'Windows closes the callback after synchronous registration failure',
    () async {
      await expectLater(
        WindowsMdns.debugAdvertise(
          register: (_) => 1,
          deregister: (_) => fail('There is no registration to remove'),
          cancel: () => fail('There is no pending registration'),
        ),
        throwsStateError,
      );
      expect(WindowsMdns.debugHasCallback, isFalse);
    },
  );

  test('06a2-1: awaitRelease reports whether Windows confirmed', () async {
    final released = Completer<void>();
    final waiting = WindowsMdns.awaitRelease(
      released.future,
      const Duration(seconds: 5),
    );
    released.complete();
    expect(await waiting, isTrue);
    expect(
      await WindowsMdns.awaitRelease(
        Completer<void>().future,
        const Duration(milliseconds: 20),
      ),
      isFalse,
    );
  });

  test(
    '06a2-2: unreadable paired-device data cannot re-enable the legacy token',
    () async {
      final vault = MemoryHostSecrets();
      Future<PairedDevices> load(String raw) {
        vault.values[PairedDevices.storageKey] = raw;
        return PairedDevices.load(storage: vault);
      }

      // A fresh install keeps the legacy token working.
      expect(
        (await PairedDevices.load(storage: MemoryHostSecrets())).legacyEnabled,
        isTrue,
      );

      // An existing record that cannot establish its state must not re-enable
      // a token that was revoked separately.
      final missing = await load('{"devices":[]}');
      expect(missing.legacyEnabled, isFalse);
      expect(missing.devices, isEmpty);

      final partial = await load(
        '{"legacyEnabled":"yes","devices":[{"id":7},'
        '{"id":"a","name":"Phone","hash":"h",'
        '"pairedAt":"2026-01-01T00:00:00Z"}]}',
      );
      expect(partial.legacyEnabled, isFalse);
      expect(partial.devices.single.name, 'Phone');

      final truncated = await load('{"legacyEnabled":false,');
      expect(truncated.legacyEnabled, isFalse);
      expect(truncated.devices, isEmpty);

      final disabled = await load('{"legacyEnabled":false,"devices":[]}');
      expect(disabled.legacyEnabled, isFalse);

      final enabled = await load('{"legacyEnabled":true,"devices":[]}');
      expect(enabled.legacyEnabled, isTrue);
    },
  );
}
