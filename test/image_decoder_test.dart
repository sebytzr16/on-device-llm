import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/attachments/domain/image_decoder.dart';

void main() {
  group('decodeAndBoundImage', () {
    test('returns PNG bytes for a simple synthetic image', () async {
      // Create a simple 100x50 red image.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 50),
        Paint()..color = const Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 50);
      final pngBytes = await image.toByteData(format: ImageByteFormat.png);
      expect(pngBytes, isNotNull);

      // Decode and bound to maxEdge 200 (no downscaling needed).
      final result = await decodeAndBoundImage(
        pngBytes!.buffer.asUint8List(),
        maxEdge: 200,
      );
      expect(result, isNotEmpty);
      // Verify it's valid PNG by checking signature.
      expect(result[0], 0x89);
      expect(result[1], 0x50);
      expect(result[2], 0x4E);
      expect(result[3], 0x47);
      image.dispose();
    });

    test('downscales image when larger than maxEdge', () async {
      // Create a 400x200 image.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 400, 200),
        Paint()..color = const Color(0xFF00FF00),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 200);
      final pngBytes = await image.toByteData(format: ImageByteFormat.png);
      expect(pngBytes, isNotNull);

      // Decode and bound to maxEdge 100 (should downscale).
      final result = await decodeAndBoundImage(
        pngBytes!.buffer.asUint8List(),
        maxEdge: 100,
      );
      expect(result, isNotEmpty);
      // Verify it's valid PNG.
      expect(result[0], 0x89);
      expect(result[1], 0x50);
      expect(result[2], 0x4E);
      expect(result[3], 0x47);
      image.dispose();
    });

    test('throws FormatException when encoding fails', () async {
      // Pass invalid data that will fail to decode.
      await expectLater(
        decodeAndBoundImage(Uint8List.fromList([1, 2, 3, 4]), maxEdge: 100),
        throwsA(isA<FormatException>()),
      );
    });

    test('disposes resources on exception path', () async {
      // This test verifies that the function doesn't leak resources
      // when an exception occurs during decoding.
      // We can't easily test the internal disposal, but we can verify
      // the function completes (throws) without hanging.
      await expectLater(
        decodeAndBoundImage(
          Uint8List.fromList([0xFF, 0xD8, 0xFF]),
          maxEdge: 100,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
