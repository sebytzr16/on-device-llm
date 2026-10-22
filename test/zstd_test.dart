import 'dart:io';

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

  test('rejects other data', () {
    expect(
      () => Zstd.decode(File('${dir.path}/tiny.bin').readAsBytesSync()),
      throwsFormatException,
    );
  });
}
