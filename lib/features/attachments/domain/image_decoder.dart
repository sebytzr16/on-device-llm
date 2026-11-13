import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes and downscales an image to a bounded size, with proper resource
/// cleanup on all exception paths. Returns PNG bytes.
///
/// The decoder acquires resources in nested try/finally blocks so that every
/// successfully created resource (buffer, descriptor, codec, frame, image)
/// is disposed even if a later step throws.
Future<Uint8List> decodeAndBoundImage(
  Uint8List bytes, {
  required int maxEdge,
  String? errorMessage,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final w = descriptor.width;
      final h = descriptor.height;
      final scale = w > h ? maxEdge / w : maxEdge / h;
      final codec = scale < 1
          ? await descriptor.instantiateCodec(
              targetWidth: (w * scale).round(),
              targetHeight: (h * scale).round(),
            )
          : await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png == null) {
            throw FormatException(
              errorMessage ?? 'Image could not be encoded as PNG.',
            );
          }
          return png.buffer.asUint8List();
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } on FormatException {
    rethrow;
  } on Exception catch (e) {
    throw FormatException(errorMessage ?? '$e');
  } finally {
    buffer.dispose();
  }
}
