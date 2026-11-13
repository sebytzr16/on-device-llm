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
import 'support/hosting_secure_storage.dart';
import 'device_model_server_test.dart' show FakeEngine;

void main() {
  test('authenticated LAN APIs require the TLS port only when active', () {
    for (final address in ['192.168.1.5', '100.64.0.1', 'fd00::1', 'fe80::1']) {
      final remote = InternetAddress(address);
      expect(DeviceModelServer.requiresApiTls(remote, 8787, 8788), isTrue);
      expect(DeviceModelServer.requiresApiTls(remote, null, 8788), isTrue);
      expect(DeviceModelServer.requiresApiTls(remote, 8788, 8788), isFalse);
      expect(DeviceModelServer.requiresApiTls(remote, 8787, null), isFalse);
    }
    for (final address in ['127.0.0.1', '127.0.0.2', '::1']) {
      expect(
        DeviceModelServer.requiresApiTls(InternetAddress(address), 8787, 8788),
        isFalse,
      );
    }
  });

  final secrets = MemoryHostSecrets();
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
    identity = await HostingTls.load(directory: dir, storage: secrets);
  });
  tearDownAll(() async {
    HttpOverrides.global = offlineOverrides;
    await dir.delete(recursive: true);
  });

  Future<DeviceModelServer> host({InternetAddress? address}) async {
    final server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test',
      fallbackTemplate: '',
      accessToken: 'abcdefghijklmnopqrstuvwxyz0123456789',
      pairCode: '123456',
    );
    await server.start(address: address, tls: identity);
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
    'LAN HTTP refuses both API credentials but keeps bootstrap public',
    () async {
      // A LAN peer is never loopback, so authenticated API traffic from the
      // LAN requires the TLS port; loopback is exempt from that rule.
      final lan = InternetAddress('192.168.1.5');
      expect(DeviceModelServer.requiresApiTls(lan, 8787, 8788), isTrue);
      expect(DeviceModelServer.requiresApiTls(lan, 8788, 8788), isFalse);
      expect(
        DeviceModelServer.requiresApiTls(
          InternetAddress.loopbackIPv4,
          8787,
          8788,
        ),
        isFalse,
      );

      // Bind to loopback (no LAN interface needed) and prove loopback clients
      // still reach the API over plain HTTP with valid credentials.
      final s = await host(address: InternetAddress.loopbackIPv4);
      final http = Uri.parse('http://127.0.0.1:${s.port}/v1/');
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      // No credentials -> refused even on loopback.
      final request = await client.getUrl(http.resolve('models'));
      final unauthenticated = await request.close();
      expect(unauthenticated.statusCode, HttpStatus.unauthorized);
      await unauthenticated.transform(utf8.decoder).join();

      // Valid bearer token -> served over plain HTTP on loopback.
      final authed = await client.getUrl(http.resolve('models'));
      authed.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${s.accessToken}',
      );
      final response = await authed.close();
      expect(response.statusCode, HttpStatus.ok);
      final body = await response.transform(utf8.decoder).join();
      expect(body, contains('"test"'));
    },
  );

  test(
    'fingerprint and key survive identity reload and server restart',
    () async {
      final first = await host();
      final before = identity.fingerprint;
      await first.stop();
      final reloaded = await HostingTls.load(directory: dir, storage: secrets);
      expect(reloaded.fingerprint, before);
      expect(reloaded.privateKeyPem, identity.privateKeyPem);
      final second = await host();
      expect(
        await engine().listModels(settings(endpoint(second), before)),
        isNotEmpty,
      );
    },
  );

  test(
    'legacy TLS migration preserves pin and removes plaintext after vault verification',
    () async {
      final other = await Directory.systemTemp.createTemp('migrate-tls-');
      addTearDown(() => other.delete(recursive: true));
      final legacy = File('${other.path}/hosting-tls.json');
      final raw = jsonEncode({
        'cert': identity.certificatePem,
        'key': identity.privateKeyPem,
      });
      await legacy.writeAsString(raw);
      await File('${legacy.path}.pending').writeAsString(raw);
      final vault = MemoryHostSecrets()..failWrites = true;
      await expectLater(
        HostingTls.load(directory: other, storage: vault),
        throwsA(isA<HostingTlsException>()),
      );
      expect(await legacy.exists(), isTrue);
      vault.failWrites = false;
      final migrated = await HostingTls.load(directory: other, storage: vault);
      expect(migrated.fingerprint, identity.fingerprint);
      expect(await legacy.exists(), isFalse);
      expect(await File('${legacy.path}.pending').exists(), isFalse);
      expect(
        (await HostingTls.load(directory: other, storage: vault)).privateKeyPem,
        identity.privateKeyPem,
      );
      for (final file in other.listSync().whereType<File>()) {
        expect(await file.readAsString(), isNot(contains('PRIVATE KEY')));
      }
      vault.values.clear();
      await expectLater(
        HostingTls.load(directory: other, storage: vault),
        throwsA(isA<HostingTlsException>()),
      );
    },
  );

  test(
    'interrupted cleanup resumes from the verified vault identity',
    () async {
      final other = await Directory.systemTemp.createTemp('interrupted-tls-');
      addTearDown(() => other.delete(recursive: true));
      final legacy = File('${other.path}/hosting-tls.json');
      await legacy.writeAsString(
        jsonEncode({
          'cert': identity.certificatePem,
          'key': identity.privateKeyPem,
        }),
      );
      final blockedMarker = await Directory(
        '${other.path}/hosting-tls.fingerprint',
      ).create();
      final vault = MemoryHostSecrets();
      await expectLater(
        HostingTls.load(directory: other, storage: vault),
        throwsA(isA<HostingTlsException>()),
      );
      expect(vault.values, isNotEmpty);
      expect(await legacy.exists(), isTrue);
      await blockedMarker.delete();
      expect(
        (await HostingTls.load(directory: other, storage: vault)).fingerprint,
        identity.fingerprint,
      );
      expect(await legacy.exists(), isFalse);
    },
  );

  test('concurrent first loads retain one host identity', () async {
    final other = await Directory.systemTemp.createTemp('concurrent-tls-');
    addTearDown(() => other.delete(recursive: true));
    final vault = MemoryHostSecrets();
    final results = await Future.wait([
      HostingTls.load(directory: other, storage: vault),
      HostingTls.load(directory: other, storage: vault),
    ]);
    expect(results[0].fingerprint, results[1].fingerprint);
    expect(vault.values, hasLength(1));
  });

  test(
    'corrupt migration source fails closed and remains recoverable',
    () async {
      final other = await Directory.systemTemp.createTemp('invalid-tls-');
      addTearDown(() => other.delete(recursive: true));
      final file = File('${other.path}/hosting-tls.json');
      await file.writeAsString('{}');
      await expectLater(
        HostingTls.load(directory: other, storage: MemoryHostSecrets()),
        throwsA(anything),
      );
      expect(await file.readAsString(), '{}');
    },
  );

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
      tls: await HostingTls.load(directory: dir, storage: secrets),
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
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.postUrl(Uri.parse('${http}pair'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'code': s.pairCode!}));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.upgradeRequired);
    await response.drain<void>();
    await expectLater(
      PairingCode.redeem(http, s.pairCode!),
      throwsA(isA<PairingException>()),
    );
  });

  test(
    'loopback HTTP profile works alongside pinned API and streaming',
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

  test('reset deletes identity and next load generates a fresh one', () async {
    final dir = await Directory.systemTemp.createTemp('reset-tls-');
    addTearDown(() => dir.delete(recursive: true));
    final vault = MemoryHostSecrets();

    final first = await HostingTls.load(directory: dir, storage: vault);
    final firstFingerprint = first.fingerprint;
    expect(vault.values, isNotEmpty);
    expect(await File('${dir.path}/hosting-tls.fingerprint').exists(), isTrue);

    await HostingTls.reset(directory: dir, storage: vault);

    expect(vault.values, isEmpty);
    expect(await File('${dir.path}/hosting-tls.fingerprint').exists(), isFalse);
    expect(await File('${dir.path}/hosting-tls.json').exists(), isFalse);
    expect(
      await File('${dir.path}/hosting-tls.json.pending').exists(),
      isFalse,
    );

    final second = await HostingTls.load(directory: dir, storage: vault);
    expect(second.fingerprint, isNot(firstFingerprint));
    expect(vault.values, isNotEmpty);
    expect(await File('${dir.path}/hosting-tls.fingerprint').exists(), isTrue);
  });

  test(
    'load after deleting only vault key throws, but reset recovers',
    () async {
      final dir = await Directory.systemTemp.createTemp('vault-lost-');
      addTearDown(() => dir.delete(recursive: true));
      final vault = MemoryHostSecrets();

      await HostingTls.load(directory: dir, storage: vault);
      final fp = (await HostingTls.load(
        directory: dir,
        storage: vault,
      )).fingerprint;

      vault.values.clear();
      await expectLater(
        HostingTls.load(directory: dir, storage: vault),
        throwsA(isA<HostingTlsException>()),
      );

      await HostingTls.reset(directory: dir, storage: vault);
      final recovered = await HostingTls.load(directory: dir, storage: vault);
      expect(recovered.fingerprint, isNot(fp));
      expect(vault.values, isNotEmpty);
      expect(
        await File('${dir.path}/hosting-tls.fingerprint').exists(),
        isTrue,
      );
    },
  );
}
