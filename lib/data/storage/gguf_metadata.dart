import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Bounded metadata read from a GGUF v2/v3 header. Tensor payloads are never
/// touched, and large tokenizer arrays are skipped rather than materialized.
class GgufMetadata {
  final int version;
  final int tensorCount;
  final String? architecture;
  final String? name;
  final int? fileType;
  final int? parameterCount;
  final int? contextLength;
  final int? blockCount;
  final bool hasChatTemplate;

  /// `general.sampling.*` keys (the maker's sampling defaults, written by
  /// llama.cpp's converter from generation_config.json).
  final Map<String, Object?> sampling;

  const GgufMetadata({
    required this.version,
    required this.tensorCount,
    this.architecture,
    this.name,
    this.fileType,
    this.parameterCount,
    this.contextLength,
    this.blockCount,
    this.hasChatTemplate = false,
    this.sampling = const {},
  });

  static Future<GgufMetadata> inspect(String path) =>
      Isolate.run(() => _GgufReader(path).read());
}

class _GgufReader {
  static const _maxMetadataEntries = 100000;
  static const _maxStringBytes = 16 * 1024 * 1024;
  static const _maxArrayEntries = 1000000;

  final String path;
  late RandomAccessFile _file;
  late int _length;

  _GgufReader(this.path);

  Future<GgufMetadata> read() async {
    _file = await File(path).open();
    _length = await _file.length();
    try {
      final magic = await _bytes(4);
      if (ascii.decode(magic, allowInvalid: true) != 'GGUF') {
        throw const FormatException('Not a GGUF file.');
      }
      final version = await _u32();
      if (version < 2 || version > 3) {
        throw FormatException('Unsupported GGUF version $version.');
      }
      final tensorCount = await _boundedU64('tensor count', 10000000);
      final metadataCount = await _boundedU64(
        'metadata count',
        _maxMetadataEntries,
      );
      final values = <String, Object?>{};
      for (var i = 0; i < metadataCount; i++) {
        final key = await _string(maxBytes: 4096);
        final type = await _u32();
        if (_wanted(key) && type != 9) {
          values[key] = await _scalar(type);
        } else {
          await _skip(type);
        }
      }
      final architecture = values['general.architecture'] as String?;
      int? architectureValue(String suffix) {
        if (architecture == null) return null;
        return _asInt(values['$architecture.$suffix']);
      }

      return GgufMetadata(
        version: version,
        tensorCount: tensorCount,
        architecture: architecture,
        name: values['general.name'] as String?,
        fileType: _asInt(values['general.file_type']),
        parameterCount: _asInt(values['general.parameter_count']),
        contextLength: architectureValue('context_length'),
        blockCount: architectureValue('block_count'),
        hasChatTemplate:
            (values['tokenizer.chat_template'] as String?)?.isNotEmpty == true,
        sampling: {
          for (final e in values.entries)
            if (e.key.startsWith('general.sampling.')) e.key: e.value,
        },
      );
    } finally {
      await _file.close();
    }
  }

  static bool _wanted(String key) =>
      key == 'general.architecture' ||
      key == 'general.name' ||
      key == 'general.file_type' ||
      key == 'general.parameter_count' ||
      key == 'tokenizer.chat_template' ||
      key.startsWith('general.sampling.') ||
      key.endsWith('.context_length') ||
      key.endsWith('.block_count');

  static int? _asInt(Object? value) => value is int ? value : null;

  Future<Object?> _scalar(int type) => switch (type) {
    0 => _u8(),
    1 => _i8(),
    2 => _u16(),
    3 => _i16(),
    4 => _u32(),
    5 => _i32(),
    6 => _f32(),
    7 => _u8().then((value) => value != 0),
    8 => _string(),
    10 => _boundedU64('integer value', 0x7fffffffffffffff),
    11 => _i64(),
    12 => _f64(),
    _ => throw FormatException('Unknown GGUF metadata type $type.'),
  };

  Future<void> _skip(int type) async {
    const widths = <int, int>{
      0: 1,
      1: 1,
      2: 2,
      3: 2,
      4: 4,
      5: 4,
      6: 4,
      7: 1,
      10: 8,
      11: 8,
      12: 8,
    };
    final width = widths[type];
    if (width != null) return _advance(width);
    if (type == 8) {
      final length = await _boundedU64('string length', _maxStringBytes);
      return _advance(length);
    }
    if (type != 9) {
      throw FormatException('Unknown GGUF metadata type $type.');
    }
    final elementType = await _u32();
    if (elementType == 9) {
      throw const FormatException('Nested GGUF arrays are unsupported.');
    }
    final count = await _boundedU64('array length', _maxArrayEntries);
    final elementWidth = widths[elementType];
    if (elementWidth != null) return _advance(count * elementWidth);
    if (elementType == 8) {
      for (var i = 0; i < count; i++) {
        final length = await _boundedU64('string length', _maxStringBytes);
        await _advance(length);
      }
      return;
    }
    throw FormatException('Unknown GGUF array type $elementType.');
  }

  Future<String> _string({int maxBytes = _maxStringBytes}) async {
    final length = await _boundedU64('string length', maxBytes);
    try {
      return utf8.decode(await _bytes(length));
    } on FormatException {
      throw const FormatException('Invalid UTF-8 in GGUF metadata.');
    }
  }

  Future<int> _boundedU64(String label, int maximum) async {
    final value = await _u64();
    if (value < 0 || value > maximum) {
      throw FormatException('GGUF $label exceeds the safe limit.');
    }
    return value;
  }

  Future<void> _advance(int count) async {
    final position = await _file.position();
    final next = position + count;
    if (count < 0 || next < position || next > _length) {
      throw const FormatException('Truncated GGUF metadata.');
    }
    await _file.setPosition(next);
  }

  Future<Uint8List> _bytes(int count) async {
    if (count < 0 || count > _length) {
      throw const FormatException('Invalid GGUF field length.');
    }
    final value = await _file.read(count);
    if (value.length != count) {
      throw const FormatException('Truncated GGUF metadata.');
    }
    return value;
  }

  Future<ByteData> _number(int count) async =>
      ByteData.sublistView(await _bytes(count));
  Future<int> _u8() async => (await _number(1)).getUint8(0);
  Future<int> _i8() async => (await _number(1)).getInt8(0);
  Future<int> _u16() async => (await _number(2)).getUint16(0, Endian.little);
  Future<int> _i16() async => (await _number(2)).getInt16(0, Endian.little);
  Future<int> _u32() async => (await _number(4)).getUint32(0, Endian.little);
  Future<int> _i32() async => (await _number(4)).getInt32(0, Endian.little);
  Future<int> _u64() async => (await _number(8)).getUint64(0, Endian.little);
  Future<int> _i64() async => (await _number(8)).getInt64(0, Endian.little);
  Future<double> _f32() async =>
      (await _number(4)).getFloat32(0, Endian.little);
  Future<double> _f64() async =>
      (await _number(8)).getFloat64(0, Endian.little);
}
