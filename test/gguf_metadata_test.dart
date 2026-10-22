import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';

void _u32(BytesBuilder out, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  out.add(data.buffer.asUint8List());
}

void _u64(BytesBuilder out, int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.little);
  out.add(data.buffer.asUint8List());
}

void _string(BytesBuilder out, String value) {
  final bytes = utf8.encode(value);
  _u64(out, bytes.length);
  out.add(bytes);
}

void _kvString(BytesBuilder out, String key, String value) {
  _string(out, key);
  _u32(out, 8);
  _string(out, value);
}

void _kvUint32(BytesBuilder out, String key, int value) {
  _string(out, key);
  _u32(out, 4);
  _u32(out, value);
}

void _kvUint64(BytesBuilder out, String key, int value) {
  _string(out, key);
  _u32(out, 10);
  _u64(out, value);
}

void main() {
  test(
    'bounded GGUF inspection reads identity and architecture metadata',
    () async {
      final out = BytesBuilder()..add(ascii.encode('GGUF'));
      _u32(out, 3);
      _u64(out, 42);
      _u64(out, 7);
      _kvString(out, 'general.architecture', 'qwen2');
      _kvString(out, 'general.name', 'Qwen Test');
      _kvUint32(out, 'general.file_type', 15);
      _kvUint64(out, 'general.parameter_count', 2000000000);
      _kvUint32(out, 'qwen2.context_length', 32768);
      _kvUint32(out, 'qwen2.block_count', 28);
      _kvString(out, 'tokenizer.chat_template', '{{ messages }}');
      final dir = await Directory.systemTemp.createTemp('gguf-metadata-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/model.gguf');
      await file.writeAsBytes(out.takeBytes());

      final metadata = await GgufMetadata.inspect(file.path);
      expect(metadata.version, 3);
      expect(metadata.tensorCount, 42);
      expect(metadata.architecture, 'qwen2');
      expect(metadata.name, 'Qwen Test');
      expect(metadata.fileType, 15);
      expect(metadata.parameterCount, 2000000000);
      expect(metadata.contextLength, 32768);
      expect(metadata.blockCount, 28);
      expect(metadata.hasChatTemplate, true);
    },
  );

  test('unsafe declared metadata sizes are rejected', () async {
    final out = BytesBuilder()..add(ascii.encode('GGUF'));
    _u32(out, 3);
    _u64(out, 0);
    _u64(out, 100001);
    final dir = await Directory.systemTemp.createTemp('gguf-unsafe-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/bad.gguf');
    await file.writeAsBytes(out.takeBytes());
    await expectLater(
      GgufMetadata.inspect(file.path),
      throwsA(isA<FormatException>()),
    );
  });
}
