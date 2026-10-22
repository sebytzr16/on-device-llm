import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The microphone's frames come through an EventChannel. Its envelope puts a
// status byte first, so the PCM bytes start at an odd offset: an Int16List
// view of them throws (the Conversation screen heard nothing, 2026-10-07).
void main() {
  test('event channel bytes can start at an odd offset', () {
    const codec = StandardMethodCodec();
    final pcm = Uint8List(1024);
    final decoded =
        codec.decodeEnvelope(codec.encodeSuccessEnvelope(pcm)) as Uint8List;
    expect(decoded.offsetInBytes.isOdd, isTrue);
    expect(
      () => decoded.buffer.asInt16List(decoded.offsetInBytes, 512),
      throwsA(anything),
    );
    final data = ByteData.sublistView(decoded);
    expect(data.getInt16(0, Endian.little), 0);
  });
}
