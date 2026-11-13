import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/pairing_code.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'device_model_server_test.dart' show FakeEngine;
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';

void main() {
  test('M06: connection QR never exports the persistent access token', () {
    const state = DeviceHostingState(
      endpoint: 'http://192.168.1.2:8787/v1/',
      token: 'persistent-access-token',
    );
    expect(state.pairing ?? '', isNot(contains('persistent-access-token')));
  });
  test('M02: scanned QR is exchanged using its endpoint and host identity', () {
    final source = File(
      'lib/features/settings/presentation/screens/remote_server_page.dart',
    ).readAsStringSync();
    expect(source, contains('PairingQr.parse'));
    expect(source, contains('redeemQr'));
    for (final locale in ['en', 'fr', 'es']) {
      final arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map;
      expect(arb['remotePairCodeMessage'], contains('{name}'));
      expect(arb['remotePairTrustNote'], isNotEmpty);
    }
  });
  Future<DeviceModelServer> host({
    Duration ttl = const Duration(minutes: 10),
    void Function()? changed,
  }) async {
    final server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test',
      fallbackTemplate: '',
      accessToken: 'abcdefghijklmnopqrstuvwxyz0123456789',
      pairCode: '482913',
      pairingLifetime: ttl,
      onPairingChanged: changed,
    );
    await server.start();
    addTearDown(server.stop);
    return server;
  }

  PairingQr qr(DeviceModelServer server) => PairingQr(
    'http://127.0.0.1:${server.port}/v1/',
    server.hostId,
    server.pairingSecret,
  );

  test(
    'M06: QR secret has 256 bits, redeems once, leaves access token usable',
    () async {
      final server = await host();
      final original = qr(server);
      final state = DeviceHostingState(
        endpoint: original.endpoint,
        token: server.accessToken,
        pairingSecret: original.secret,
        hostId: original.hostId,
      );
      final encoded = state.pairing!;
      expect(encoded, isNot(contains(server.accessToken)));
      expect(base64Url.decode(original.secret), hasLength(32));
      expect(PairingQr.parse(encoded)!.hostId, server.hostId);
      final results = await Future.wait(
        List.generate(2, (_) async {
          try {
            return jsonDecode(await PairingCode.redeemQr(original))['key'];
          } on PairingException {
            return null;
          }
        }),
      );
      expect(results.whereType<String>(), hasLength(1));
      expect(
        server.pairedDevices.principal(results.whereType<String>().single),
        isNotNull,
      );
      expect(server.pairingSecret, isNot(original.secret));
      expect(server.pairCode, isNot('482913'));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse(original.endpoint).resolve('models'),
      );
      request.headers.set('Authorization', 'Bearer ${server.accessToken}');
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();
    },
  );
  test('M02: QR host mismatch cannot exchange a secret', () async {
    final server = await host();
    final original = qr(server);
    await expectLater(
      PairingCode.redeemQr(
        PairingQr(original.endpoint, 'forged-host', original.secret),
      ),
      throwsA(isA<PairingException>()),
    );
    expect(
      jsonDecode(await PairingCode.redeemQr(original))['key'],
      isNot(server.accessToken),
    );
  });
  test(
    'N59: expiry rotates both credentials live and reports expired, not lockout',
    () async {
      final rotated = Completer<void>();
      final server = await host(
        ttl: const Duration(seconds: 1),
        changed: () {
          if (!rotated.isCompleted) rotated.complete();
        },
      );
      final original = qr(server);
      final until = server.pairExpiresAt;
      await rotated.future.timeout(const Duration(seconds: 5));
      expect(server.pairExpiresAt.isAfter(until), isTrue);
      expect(server.pairCode, isNot('482913'));
      expect(server.pairingSecret, isNot(original.secret));
      await expectLater(
        PairingCode.redeemQr(original),
        throwsA(
          isA<PairingException>().having(
            (e) => e.failure,
            'failure',
            PairingFailure.expired,
          ),
        ),
      );
      expect(
        jsonDecode(await PairingCode.redeemQr(qr(server)))['key'],
        isNot(server.accessToken),
      );
    },
  );
  test('CL-4: QR rotation preserves four previous typed failures', () async {
    final server = await host();
    final original = qr(server);
    for (var i = 0; i < 4; i++) {
      await expectLater(
        PairingCode.redeem(original.endpoint, '000000'),
        throwsA(isA<PairingException>()),
      );
    }
    await PairingCode.redeemQr(original);
    await expectLater(
      PairingCode.redeem(original.endpoint, '000000'),
      throwsA(isA<PairingException>()),
    );
    await expectLater(
      PairingCode.redeem(original.endpoint, server.pairCode!),
      throwsA(
        isA<PairingException>().having(
          (e) => e.failure,
          'failure',
          PairingFailure.lockedOut,
        ),
      ),
    );
  });

  test('CR-08: fresh credentials clear only the localized lockout error', () {
    for (final locale in ['en', 'fr', 'es']) {
      final arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map;
      final locked = DeviceHostingState(error: arb['hostPairLocked'] as String);
      expect(locked.copyWith(pairCode: '123456').error, isNull);
      expect(
        const DeviceHostingState(
          error: 'disk failure',
        ).copyWith(pairCode: '123456').error,
        'disk failure',
      );
      for (final key in ['hostPairLocked', 'remotePairLocked']) {
        expect(arb[key] as String, isNot(contains('?')));
        expect(
          (arb[key] as String).toLowerCase(),
          isNot(matches('restart|red\u00e9marr|reinici')),
        );
      }
    }
  });

  test('typed-code lockout survives QR redemption and rotation', () async {
    final server = await host();
    final original = qr(server);
    for (var i = 0; i < PairingCode.maxFailures; i++) {
      await expectLater(
        PairingCode.redeem(original.endpoint, '000000'),
        throwsA(isA<PairingException>()),
      );
    }
    await PairingCode.redeemQr(original);
    await expectLater(
      PairingCode.redeem(original.endpoint, server.pairCode!),
      throwsA(
        isA<PairingException>().having(
          (e) => e.failure,
          'failure',
          PairingFailure.lockedOut,
        ),
      ),
    );
  });
  test('M09: expiry rotation restores the typed-code failure budget', () async {
    final rotated = Completer<void>();
    final server = await host(
      ttl: const Duration(seconds: 2),
      changed: () {
        if (!rotated.isCompleted) rotated.complete();
      },
    );
    final endpoint = qr(server).endpoint;
    for (var i = 0; i < PairingCode.maxFailures; i++) {
      await expectLater(
        PairingCode.redeem(endpoint, '000000'),
        throwsA(isA<PairingException>()),
      );
    }
    await rotated.future.timeout(const Duration(seconds: 5));
    // A fresh session still permits all but its final failed attempt.
    for (var i = 0; i < PairingCode.maxFailures - 1; i++) {
      await expectLater(
        PairingCode.redeem(endpoint, '000000'),
        throwsA(
          isA<PairingException>().having(
            (e) => e.failure,
            'failure',
            PairingFailure.wrongCode,
          ),
        ),
      );
    }
    expect(
      jsonDecode(await PairingCode.redeem(endpoint, server.pairCode!))['key'],
      isNot(server.accessToken),
    );
  });
  test(
    'M09: a body crossing expiry reserves against the fresh session',
    () async {
      final rotated = Completer<void>();
      final server = await host(
        ttl: const Duration(seconds: 2),
        changed: () {
          if (!rotated.isCompleted) rotated.complete();
        },
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(
        Uri.parse(qr(server).endpoint).resolve('pair'),
      );
      request.write('{');
      await request.flush();
      await rotated.future.timeout(const Duration(seconds: 5));
      request.write('"code":"${server.pairCode}"}');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
    },
  );
  test('M02: client refuses a response with a different host id', () async {
    final fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => fake.close(force: true));
    fake.listen((request) async {
      await request.drain<void>();
      request.response.write(jsonEncode({'key': 'stolen', 'hostId': 'wrong'}));
      await request.response.close();
    });
    await expectLater(
      PairingCode.redeemQr(
        PairingQr(
          'http://127.0.0.1:${fake.port}/v1/',
          'qr-host',
          PairingCode.secret(),
        ),
      ),
      throwsA(isA<PairingException>()),
    );
  });
  test('N01: scheduled notifications resolve saved ids and rate limit intake', () {
    final schedule = File(
      'android/app/src/main/kotlin/app/ondevicellm/ondevice_llm/ScheduledPrompts.kt',
    ).readAsStringSync();
    final inbox = File(
      'android/app/src/main/kotlin/app/ondevicellm/ondevice_llm/ShareInbox.kt',
    ).readAsStringSync();
    expect(schedule, contains('.putExtra(EXTRA_ID, id)'));
    expect(schedule, isNot(contains('.putExtra(EXTRA_PROMPT, item.optString')));
    expect(inbox, contains('ScheduledPrompts.find('));
    expect(inbox, contains('allowScheduledRun'));
    expect(inbox, isNot(contains('"scheduled" to (intent.getStringExtra')));
  });
}
