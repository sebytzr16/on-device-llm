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

  test('short fingerprint uses the first 16 hex digits in four groups', () {
    const fingerprint =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    expect(PairingCode.shortFingerprint(fingerprint), '0123 4567 89AB CDEF');
    expect(PairingCode.shortFingerprint('0' * 64), '0000 0000 0000 0000');
    for (final invalid in ['', '0123456789abcdef', 'g' * 64, 'A' * 64]) {
      expect(
        () => PairingCode.shortFingerprint(invalid),
        throwsFormatException,
      );
    }
  });

  test(
    'the right code returns the same connection the QR code holds',
    () async {
      await start();
      final pairing = jsonDecode(await PairingCode.redeem(endpoint, '482 913'));
      expect(pairing['key'], isNot(token));
      expect(
        server!.pairedDevices.principal(pairing['key'] as String),
        isNotNull,
      );
      expect(pairing, {
        'ondevice_llm': 'connection',
        'url': endpoint,
        'model': 'test-model',
        'key': pairing['key'],
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

  test(
    'guesses sent at once get at most five tries including reader admission',
    () async {
      await start();
      final results = await Future.wait([
        for (var i = 0; i < 20; i++)
          PairingCode.redeem(endpoint, '${100000 + i}').then<Object>(
            (v) => v,
            onError: (Object e) => (e as PairingException).failure,
          ),
      ]);
      // Reader admission can reject a request before it spends a code attempt.
      final wrongCodes = results
          .where((r) => r == PairingFailure.wrongCode)
          .length;
      expect(wrongCodes, inInclusiveRange(1, PairingCode.maxFailures));
      expect(
        results.where((r) => r == PairingFailure.lockedOut),
        hasLength(20 - wrongCodes),
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
    },
  );

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
