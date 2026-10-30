import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/pairing_code.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

import 'device_model_server_test.dart' show FakeEngine;

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyz0123456789';
  DeviceModelServer? server;
  late String endpoint;

  Future<void> start({String? code = '482913'}) async {
    server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test-model',
      fallbackTemplate: '',
      accessToken: token,
      pairCode: code,
    );
    await server!.start();
    endpoint = 'http://127.0.0.1:${server!.port}/v1/';
  }

  tearDown(() async {
    await server?.stop();
    server = null;
  });

  test('codes are six digits; spaces and dashes are ignored', () {
    final code = PairingCode.generate(Random(1));
    expect(code, matches(RegExp(r'^\d{6}$')));
    expect(PairingCode.normalize(' 482-913 '), '482913');
  });

  test(
    'the right code returns the same connection the QR code holds',
    () async {
      await start();
      final pairing = jsonDecode(await PairingCode.redeem(endpoint, '482 913'));
      expect(pairing, {
        'ondevice_llm': 'connection',
        'url': endpoint,
        'model': 'test-model',
        'key': token,
      });
    },
  );

  test('wrong codes are refused, then pairing locks until restart', () async {
    await start();
    for (var i = 0; i < PairingCode.maxFailures; i++) {
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
    // Even the right code is refused once locked.
    await expectLater(
      PairingCode.redeem(endpoint, '482913'),
      throwsA(
        isA<PairingException>().having(
          (e) => e.failure,
          'failure',
          PairingFailure.lockedOut,
        ),
      ),
    );
  });

  test('guesses sent at once still get five tries in total', () async {
    await start();
    final results = await Future.wait([
      for (var i = 0; i < 20; i++)
        PairingCode.redeem(endpoint, '${100000 + i}').then<Object>(
          (v) => v,
          onError: (Object e) => (e as PairingException).failure,
        ),
    ]);
    expect(
      results.where((r) => r == PairingFailure.wrongCode),
      hasLength(PairingCode.maxFailures),
    );
    expect(
      results.where((r) => r == PairingFailure.lockedOut),
      hasLength(20 - PairingCode.maxFailures),
    );
    await expectLater(
      PairingCode.redeem(endpoint, '482913'),
      throwsA(
        isA<PairingException>().having(
          (e) => e.failure,
          'failure',
          PairingFailure.lockedOut,
        ),
      ),
    );
  });

  test('no code (loopback-only server) means no pairing', () async {
    await start(code: null);
    await expectLater(
      PairingCode.redeem(endpoint, '482913'),
      throwsA(
        isA<PairingException>().having(
          (e) => e.failure,
          'failure',
          PairingFailure.unreachable,
        ),
      ),
    );
  });
}
