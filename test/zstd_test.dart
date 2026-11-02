import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/zim/zstd.dart';

// Fixtures come from the Python zstandard package (levels 1, 3 and 19).
void main() {
  final dir = Directory('test/fixtures/zstd');
  final frames =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.zst'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('fixtures exist', () => expect(frames, isNotEmpty));

  for (final f in frames) {
    final name = f.uri.pathSegments.last;
    test('decodes $name', () {
      final expected = File(
        '${dir.path}/${name.substring(0, name.lastIndexOf('-'))}.bin',
      ).readAsBytesSync();
      final got = Zstd.decode(f.readAsBytesSync());
      expect(got.length, expected.length);
      expect(got, expected);
    });
  }

  test('actual zstd output is bounded across concatenated frames', () {
    final frame = File('${dir.path}/text-3.zst').readAsBytesSync();
    expect(
      () => Zstd.decode(
        Uint8List.fromList([...frame, ...frame]),
        maxOutputBytes: File('${dir.path}/text.bin').lengthSync(),
      ),
      throwsFormatException,
    );
  });

  test('zstd rejects an oversized RLE block before expansion', () {
    final header = (128 * 1024 + 1) << 3 | 3;
    final frame = Uint8List.fromList([
      0x28,
      0xb5,
      0x2f,
      0xfd,
      0x20,
      0,
      header & 255,
      (header >> 8) & 255,
      header >> 16,
      42,
    ]);
    expect(() => Zstd.decode(frame), throwsFormatException);
  });

  test('rejects other data', () {
    expect(
      () => Zstd.decode(File('${dir.path}/tiny.bin').readAsBytesSync()),
      throwsFormatException,
    );
  });
}
