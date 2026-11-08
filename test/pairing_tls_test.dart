import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/inference/remote/workspace_client.dart';
import 'package:ondevice_llm/features/hosting/hosting_tls.dart';
import 'package:ondevice_llm/features/hosting/pairing_code.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_usage.dart';
import 'device_model_server_test.dart' show FakeEngine;

void main() {
  late Directory dir;
  HttpOverrides? offlineOverrides;
  late HostingTls identity;
  setUpAll(() async {
    // The suite's offline connectionFactory accepts every localhost certificate,
    // bypassing HttpClient.badCertificateCallback. Exercise the native handshake
    // here; every endpoint below is a server bound to localhost by this test.
    offlineOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    dir = await Directory.systemTemp.createTemp('pairing-tls-');
    identity = await HostingTls.load(directory: dir);
  });
  tearDownAll(() async {
    HttpOverrides.global = offlineOverrides;
    await dir.delete(recursive: true);
  });

  Future<DeviceModelServer> host() async {
    final server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test',
      fallbackTemplate: '',
      accessToken: 'abcdefghijklmnopqrstuvwxyz0123456789',
      pairCode: '123456',
    );
    await server.start(tls: identity);
    addTearDown(server.stop);
    return server;
  }

  String endpoint(DeviceModelServer s) => 'https://127.0.0.1:${s.tlsPort}/v1/';
  RemoteEngine engine() {
    final e = RemoteEngine(usage: RemoteUsageLog(prefs: () => null));
    addTearDown(e.dispose);
    return e;
  }

  InferenceSettings settings(String url, String? pin) => InferenceSettings(
    remoteEnabled: true,
    remoteProfileId: 'host',
    remoteProfiles: [
      RemoteProfile(
        id: 'host',
        name: 'Host',
        baseUrl: url,
        model: 'test',
        fingerprint: pin,
      ),
    ],
    remoteApiKeys: {'host': 'abcdefghijklmnopqrstuvwxyz0123456789'},
  );

  test(
    'fingerprint and key survive identity reload and server restart',
    () async {
      final first = await host();
      final before = identity.fingerprint;
      await first.stop();
      final reloaded = await HostingTls.load(directory: dir);
      expect(reloaded.fingerprint, before);
      expect(reloaded.privateKeyPem, identity.privateKeyPem);
      final second = await host();
      expect(
        await engine().listModels(settings(endpoint(second), before)),
        isNotEmpty,
      );
    },
  );

  test('corrupt identity is regenerated and then persists', () async {
    final other = await Directory.systemTemp.createTemp('invalid-tls-');
    addTearDown(() => other.delete(recursive: true));
    await File('${other.path}/hosting-tls.json').writeAsString('{}');
    final regenerated = await HostingTls.load(directory: other);
    expect(
      (await HostingTls.load(directory: other)).fingerprint,
      regenerated.fingerprint,
    );
  });

  test('mismatched private key is invalid and regenerated', () async {
    final other = await Directory.systemTemp.createTemp('mismatched-tls-');
    addTearDown(() => other.delete(recursive: true));
    final second = await HostingTls.load(directory: other);
    await File('${other.path}/hosting-tls.json').writeAsString(
      jsonEncode({
        'cert': identity.certificatePem,
        'key': second.privateKeyPem,
      }),
    );
    final repaired = await HostingTls.load(directory: other);
    expect(repaired.fingerprint, isNot(identity.fingerprint));
    expect(repaired.fingerprint, isNot(second.fingerprint));
    expect(
      (await HostingTls.load(directory: other)).fingerprint,
      repaired.fingerprint,
    );
  });

  test('TLS port is stable for a configured HTTP port', () async {
    // Reserve and release an available pair before testing a fixed-port restart.
    final first = await host();
    final port = first.port!;
    await first.stop();
    await first.start(port: port, tls: identity);
    final tlsPort = first.tlsPort;
    expect(tlsPort, port == 65535 ? port - 1 : port + 1);
    await first.stop();
    await first.start(
      port: port,
      tls: await HostingTls.load(directory: dir),
    );
    expect(first.tlsPort, tlsPort);
    expect(
      await engine().listModels(
        settings(endpoint(first), identity.fingerprint),
      ),
      isNotEmpty,
    );
  });

  test(
    'CL-1: occupied stable TLS port falls back and advertises actual port',
    () async {
      final s = await host();
      final port = s.port!;
      await s.stop();
      final blocked = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port == 65535 ? port - 1 : port + 1,
      );
      addTearDown(blocked.close);
      await s.start(port: port, tls: identity);
      expect(s.port, port);
      expect(s.tlsPort, isNot(blocked.port));
      final target = await PairingCode.tlsTarget('http://127.0.0.1:$port/v1/');
      expect(target.$1, endpoint(s));
      expect(
        await PairingCode.redeem(
          target.$1,
          s.pairCode!,
          fingerprint: target.$2,
        ),
        isNotEmpty,
      );
    },
  );

  test('QR pin accepted, returned connection persists pin', () async {
    final s = await host();
    final qr = PairingQr(
      endpoint(s),
      s.hostId,
      s.pairingSecret,
      fingerprint: identity.fingerprint,
    );
    final connection = await PairingCode.redeemQr(
      PairingQr.parse(qr.encode())!,
    );
    final p = RemoteProfile.fromPairing(connection, id: 'host')!.$1;
    expect(
      RemoteProfile.fromJson(p.toJson())!.fingerprint,
      identity.fingerprint,
    );
    expect(
      await engine().listModels(settings(p.baseUrl, p.fingerprint)),
      isNotEmpty,
    );
  });

  test('wrong pin refused for pairing and later API calls', () async {
    final s = await host();
    final bad = '0' * 64;
    await expectLater(
      PairingCode.redeemQr(
        PairingQr(endpoint(s), s.hostId, s.pairingSecret, fingerprint: bad),
      ),
      throwsA(isA<PairingException>()),
    );
    final e = engine();
    await expectLater(
      e.listModels(settings(endpoint(s), bad)),
      throwsA(anything),
    );
    // A failed profile must not poison another profile to the same endpoint.
    expect(
      await e.listModels(settings(endpoint(s), identity.fingerprint)),
      isNotEmpty,
    );
  });

  test('typed-code bootstrap sends code only over pinned TLS', () async {
    final s = await host();
    final http = 'http://127.0.0.1:${s.port}/v1/';
    final target = await PairingCode.tlsTarget(http);
    expect(target.$1, endpoint(s));
    expect(target.$2, identity.fingerprint);
    final result =
        jsonDecode(
              await PairingCode.redeem(
                target.$1,
                s.pairCode!,
                fingerprint: target.$2,
              ),
            )
            as Map;
    expect(result['fingerprint'], identity.fingerprint);
    await expectLater(
      PairingCode.redeem(http, s.pairCode!),
      throwsA(isA<PairingException>()),
    );
  });

  test(
    'legacy HTTP profile works alongside pinned API and streaming',
    () async {
      final s = await host();
      final legacy = settings('http://127.0.0.1:${s.port}/v1/', null);
      final e = engine();
      expect(await e.listModels(legacy), isNotEmpty);
      final secure = settings(endpoint(s), identity.fingerprint);
      expect(
        await e
            .generate(
              messages: [
                {'role': 'user', 'content': 'hi'},
              ],
              fallbackTemplate: '',
              settings: secure,
            )
            .toList(),
        isNotEmpty,
      );
      await expectLater(
        e
            .generate(
              messages: [
                {'role': 'user', 'content': 'hi'},
              ],
              fallbackTemplate: '',
              settings: settings(endpoint(s), '0' * 64),
            )
            .toList(),
        throwsA(anything),
      );
    },
  );

  test('workspace API and event streams honour the saved pin', () async {
    SharedPreferences.setMockInitialValues({});
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      identity.context,
    );
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/capabilities')) {
        response.write(
          jsonEncode({
            'version': 1,
            'capabilities': ['server_execution'],
          }),
        );
      } else if (request.uri.path.endsWith('/events')) {
        response.headers.contentType = ContentType('text', 'event-stream');
        final event = jsonEncode({
          'sequence': 1,
          'jobId': 'job',
          'type': 'done',
          'data': {},
        });
        response.write('data: $event\n\n');
      } else if (request.method == 'POST') {
        response.write(jsonEncode({'jobId': 'job'}));
      } else {
        response.write(jsonEncode({'pendingApprovals': [], 'sequence': 0}));
      }
      await response.close();
    });
    final url = 'https://127.0.0.1:${server.port}/v1/';
    final client = WorkspaceClient();
    addTearDown(client.dispose);
    final secure = settings(url, identity.fingerprint);
    expect(await client.supported(secure), isTrue);
    final events = <Map<String, dynamic>>[];
    await client.run(
      settings: secure,
      requestId: 'pin-test',
      messages: [
        {'role': 'user', 'content': 'hi'},
      ],
      event: events.add,
      approve: (_, _) async => false,
    );
    expect(events.single['type'], 'done');
    final wrong = settings(url, '0' * 64);
    await expectLater(client.supported(wrong), throwsA(anything));
    await expectLater(
      client
          .run(
            settings: wrong,
            requestId: 'wrong-pin',
            messages: [],
            event: events.add,
            approve: (_, _) async => false,
          )
          .timeout(const Duration(seconds: 3)),
      throwsA(isNot(isA<TimeoutException>())),
    );
    expect(
      events.length,
      1,
    ); // Certificate failures must not reconnect forever.
  });

  test('pin cannot be downgraded to HTTP or omitted from HTTPS QR', () {
    expect(
      RemoteProfile.fromPairing(
        jsonEncode({
          'ondevice_llm': 'connection',
          'url': 'http://127.0.0.1/v1/',
          'fingerprint': identity.fingerprint,
        }),
        id: 'host',
      ),
      isNull,
    );
    expect(
      PairingQr.parse(
        PairingQr(
          'https://127.0.0.1/v1/',
          'host',
          PairingCode.secret(),
        ).encode(),
      ),
      isNull,
    );
  });
}
