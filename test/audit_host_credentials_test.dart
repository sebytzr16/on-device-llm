import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/paired_devices.dart';
import 'package:ondevice_llm/features/hosting/pairing_code.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

import 'device_model_server_test.dart' show FakeEngine;
import 'support/hosting_secure_storage.dart';

void main() {
  test(
    'device digests persist; failed writes cannot issue or revoke credentials',
    () async {
      final vault = MemoryHostSecrets();
      final devices = await PairedDevices.load(storage: vault);
      final first = await devices.issue('Phone');
      final second = await devices.issue('Tablet');
      expect(first, isNot(second));
      expect(vault.values.values.single, isNot(contains(first)));
      expect(vault.values.values.single, isNot(contains(second)));
      final id = devices.principal(first)!;
      vault.failWrites = true;
      await expectLater(devices.revoke(id), throwsStateError);
      await expectLater(devices.issue('Other'), throwsStateError);
      expect(devices.devices, hasLength(2));
      expect(devices.principal(first), id);
      vault.failWrites = false;
      await devices.revoke(id);
      await devices.revoke('legacy');
      final restored = await PairedDevices.load(storage: vault);
      expect(restored.principal(first), isNull);
      expect(restored.principal(second), isNotNull);
      expect(restored.legacyEnabled, isFalse);
      for (final bad in [
        '',
        first.substring(1),
        '$second!',
        'x' * second.length,
      ]) {
        expect(restored.principal(bad), isNull);
      }
      expect(PairedDevices.sameToken('abc', 'abc'), isTrue);
      expect(PairedDevices.sameToken('abc', 'abcd'), isFalse);
      expect(PairedDevices.sameToken('abcd', 'abc'), isFalse);
    },
  );

  test(
    'pairing issues independent credentials; host revocation isolates devices and workspace data',
    () async {
      const legacy = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final vault = MemoryHostSecrets();
      final devices = await PairedDevices.load(storage: vault);
      final api = WorkspaceApi(capabilities: const [], run: (_, _) async {});
      final server = DeviceModelServer(
        engine: FakeEngine(),
        settings: () => const InferenceSettings(),
        modelId: 'test',
        fallbackTemplate: '',
        accessToken: legacy,
        pairCode: '123456',
        pairedDevices: devices,
        workspace: api,
      );
      await server.start();
      addTearDown(server.stop);
      var endpoint = 'http://127.0.0.1:${server.port}/v1/';
      Future<String> pair() async {
        final connection =
            jsonDecode(
                  await PairingCode.redeemQr(
                    PairingQr(endpoint, server.hostId, server.pairingSecret),
                  ),
                )
                as Map;
        return connection['key'] as String;
      }

      final first = await pair(), second = await pair();
      expect(first, isNot(second));
      expect(first, isNot(legacy));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<(int, Map)> request(
        String token,
        String path, {
        Object? body,
      }) async {
        final r = await client.openUrl(
          body == null ? 'GET' : 'POST',
          Uri.parse(endpoint).resolve(path),
        );
        r.headers.set('Authorization', 'Bearer $token');
        if (body != null) {
          r.headers.contentType = ContentType.json;
          r.write(jsonEncode(body));
        }
        final response = await r.close();
        return (
          response.statusCode,
          jsonDecode(await response.transform(utf8.decoder).join()) as Map,
        );
      }

      expect((await request(legacy, 'models')).$1, 200);
      expect((await request(first, 'models')).$1, 200);
      expect((await request(second, 'models')).$1, 200);
      final job = await request(
        first,
        'workspace/jobs',
        body: {'requestId': 'same'},
      );
      final id = job.$2['jobId'];
      expect((await request(second, 'workspace/jobs/$id')).$1, 404);
      expect(
        (await request(second, 'workspace/jobs/$id/cancel', body: {})).$1,
        404,
      );
      expect(
        (await request(
          second,
          'workspace/jobs/$id/approval',
          body: {'id': 'x', 'allow': true},
        )).$1,
        404,
      );
      final otherJob = await request(
        second,
        'workspace/jobs',
        body: {'requestId': 'same'},
      );
      expect(otherJob.$2['jobId'], isNot(id));
      final upload = await client.postUrl(
        Uri.parse(endpoint).resolve('workspace/uploads?name=file.txt'),
      );
      upload.headers.set('Authorization', 'Bearer $first');
      upload.contentLength = 1;
      upload.add([65]);
      final uploadResponse = await upload.close();
      final uploadId =
          (jsonDecode(await uploadResponse.transform(utf8.decoder).join())
              as Map)['uploadId'];
      expect(
        (await request(
          second,
          'workspace/jobs',
          body: {
            'requestId': 'steal',
            'uploads': [
              {'uploadId': uploadId, 'message': 0},
            ],
          },
        )).$1,
        404,
      );
      await server.revokeDevice(devices.principal(first)!);
      expect((await request(first, 'models')).$1, 401);
      expect((await request(second, 'models')).$1, 200);
      expect((await request(legacy, 'models')).$1, 200);
      await server.revokeDevice('legacy');
      expect((await request(legacy, 'models')).$1, 401);
      expect((await request(second, 'models')).$1, 200);
      await server.stop();
      final restarted = DeviceModelServer(
        engine: FakeEngine(),
        settings: () => const InferenceSettings(),
        modelId: 'test',
        fallbackTemplate: '',
        accessToken: legacy,
        pairedDevices: await PairedDevices.load(storage: vault),
      );
      await restarted.start();
      addTearDown(restarted.stop);
      endpoint = 'http://127.0.0.1:${restarted.port}/v1/';
      expect((await request(first, 'models')).$1, 401);
      expect((await request(legacy, 'models')).$1, 401);
      expect((await request(second, 'models')).$1, 200);
    },
  );
}
