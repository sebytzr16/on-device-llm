import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';

void main() {
  test('P1-01: cold inspect skips a 262k-string tokenizer quickly', () async {
    final root = Directory.systemTemp.createTempSync('audit-gguf-');
    addTearDown(() => root.deleteSync(recursive: true));
    final bytes = BytesBuilder(copy: false);
    void number(int value, int width) {
      final data = ByteData(width);
      if (width == 4) {
        data.setUint32(0, value, Endian.little);
      } else {
        data.setUint64(0, value, Endian.little);
      }
      bytes.add(data.buffer.asUint8List());
    }

    void text(String value) {
      final encoded = utf8.encode(value);
      number(encoded.length, 8);
      bytes.add(encoded);
    }

    bytes.add(ascii.encode('GGUF'));
    number(3, 4);
    number(0, 8);
    number(2, 8);
    text('tokenizer.ggml.tokens');
    number(9, 4);
    number(8, 4);
    number(262144, 8);
    // Variable-size strings cross the reader's one-megabyte buffer boundary.
    for (var i = 0; i < 262144; i++) {
      text('token_${i}_abcdefghijklmnopqrstuvwxyz');
    }
    // Reading this value proves the array was traversed, not simply ignored.
    text('general.architecture');
    number(8, 4);
    text('gemma4');
    final file = File('${root.path}/large-header.gguf');
    file.writeAsBytesSync(bytes.takeBytes());
    final watch = Stopwatch()..start();
    final metadata = await GgufMetadata.inspect(
      file.path,
    ).timeout(const Duration(seconds: 8));
    watch.stop();
    expect(metadata.architecture, 'gemma4');
    expect(metadata.tensorCount, 0);
    // Generous CI margin, still below the former ~15 seconds per header.
    expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
  });
}
