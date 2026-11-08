import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes our engine's MJPG AVI for the existing frame preview player.
/// Compressed frames are read individually rather than loading the AVI at once.
Future<List<ui.Image>> decodeHistoryVideo(File file) async {
  final input = await file.open();
  final frames = <ui.Image>[];
  try {
    final length = await input.length();
    final header = await input.read(12);
    if (header.length != 12 ||
        ascii.decode(header.sublist(0, 4)) != 'RIFF' ||
        ascii.decode(header.sublist(8, 12)) != 'AVI ') {
      throw const FormatException('Invalid AVI');
    }
    Future<void> chunks(int start, int end) async {
      var position = start;
      while (position + 8 <= end) {
        await input.setPosition(position);
        final header = await input.read(8);
        if (header.length != 8) throw const FormatException('Truncated AVI');
        final tag = ascii.decode(header.sublist(0, 4));
        final size = ByteData.sublistView(header).getUint32(4, Endian.little);
        final next = position + 8 + size;
        if (next > end) throw const FormatException('Truncated AVI chunk');
        if (tag == 'LIST' && size >= 4) {
          final type = ascii.decode(await input.read(4));
          if (type == 'movi' || type == 'rec ') {
            await chunks(position + 12, next);
          }
        } else if (tag == '00dc' || tag == '00db') {
          final codec = await ui.instantiateImageCodec(await input.read(size));
          try {
            frames.add((await codec.getNextFrame()).image);
          } finally {
            codec.dispose();
          }
        }
        position = next + (size & 1);
      }
    }

    await chunks(12, length);
    if (frames.isEmpty) throw const FormatException('AVI has no frames');
    return frames;
  } catch (_) {
    for (final frame in frames) {
      frame.dispose();
    }
    rethrow;
  } finally {
    await input.close();
  }
}
