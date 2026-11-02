import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';

void main() {
  test('accepts the boundary and reports 24 MB above it', () async {
    final bytes = Uint8List(24 * 1024 * 1024);
    expect(
      (await DeviceModelServer.readBody(
        Stream.value(bytes),
        const Duration(seconds: 5),
      )).length,
      bytes.length,
    );
    await expectLater(
      DeviceModelServer.readBody(
        Stream.fromIterable([
          bytes,
          [32],
        ]),
        const Duration(seconds: 5),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Request is larger than 24 MB.',
        ),
      ),
    );
  });
}
