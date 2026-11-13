import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/l10n/l10n.dart';

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
  final int? embeddingLength, headCount, kvHeadCount, keyLength, valueLength;

  /// Sliding-window attention: window size, which layers use it (true =
  /// windowed), the SWA head widths, and how many trailing layers reuse an
  /// earlier layer's KV cache (Gemma 3n/4). All null for plain models.
  final int? slidingWindow, keyLengthSwa, valueLengthSwa, sharedKvLayers;
  final List<bool>? swaLayers;
  final int? weightsBytes;
  final bool hasChatTemplate;
  final bool supportsTools, supportsThinking, supportsVision, isEmbedding;
  final int nextnPredictLayers;
  final bool hasBlockZero;

  bool get isDFlash =>
      architecture == 'dflash' || architecture == 'dflash-draft';

  /// Mirrors the native policy; filenames and quantization are irrelevant.
  bool get isMtpOnly =>
      (architecture?.endsWith('-assistant') ?? false) ||
      (nextnPredictLayers > 0 && !hasBlockZero);

  String? mtpHeadIssueFor(GgufMetadata target, {AppLocalizations? strings}) {
    final t = strings ?? stringsFor('');
    if (!isMtpOnly) return t.mtpFullModel;
    if (architecture == 'gemma4-assistant' && target.architecture == 'gemma4') {
      return null;
    }
    if ((architecture == 'qwen35' || architecture == 'qwen35moe') &&
        architecture == target.architecture &&
        nextnPredictLayers == 1) {
      return null;
    }
    return t.mtpIncompatible('$architecture', '${target.architecture}');
  }

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
    this.embeddingLength,
    this.headCount,
    this.kvHeadCount,
    this.keyLength,
    this.valueLength,
    this.slidingWindow,
    this.keyLengthSwa,
    this.valueLengthSwa,
    this.sharedKvLayers,
    this.swaLayers,
    this.weightsBytes,
    this.hasChatTemplate = false,
    this.supportsTools = false,
    this.supportsThinking = false,
    this.supportsVision = false,
    this.isEmbedding = false,
    this.nextnPredictLayers = 0,
    this.hasBlockZero = false,
    this.sampling = const {},
  });

  /// Reads [path]'s header in an isolate. Results are kept per file
  /// (path, size and modified time), so a send or a dialog that asks again
  /// does not re-read a 262k-entry tokenizer (audit P1-01, P1-18).
  static Future<GgufMetadata> inspect(String path) async {
    final stat = await File(path).stat();
    final key = '$path|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final pending = _reading[key];
    if (pending != null) return pending;
    final read = Isolate.run(() => _GgufReader(path).read());
    _reading[key] = read;
    try {
      final value = await read;
      _cache.removeWhere((k, _) => k.startsWith('$path|'));
      if (_cache.length >= 64) _cache.remove(_cache.keys.first);
      return _cache[key] = value;
    } finally {
      unawaited(_reading.remove(key));
    }
  }

  /// Last inspected header, available without filesystem or native work.
  static GgufMetadata? cached(String path) => _cache.entries
      .where((entry) => entry.key.startsWith('$path|'))
      .map((entry) => entry.value)
      .firstOrNull;

  static final _cache = <String, GgufMetadata>{};
  static final _reading = <String, Future<GgufMetadata>>{};

  /// A per-layer flag array, or a period n (every n-th layer is full
  /// attention, the rest windowed). A window without a pattern means every
  /// layer is windowed.

  /// Public for tests.
  static List<bool>? swaPattern(Object? pattern, int? layers, int? window) {
    if (pattern is List<bool>) return pattern;
    if (layers == null || window == null || window <= 0) return null;
    if (pattern is int && pattern > 0) {
      return [for (var i = 0; i < layers; i++) (i + 1) % pattern != 0];
    }
    return List.filled(layers, true);
  }
}

/// Synchronous, buffered: it runs in its own isolate, and one read per
/// megabyte instead of three awaits per tokenizer string turns a 15 s
/// parse into well under a second (audit P1-01).
class _GgufReader {
  static const _maxMetadataEntries = 100000;
  static const _maxStringBytes = 16 * 1024 * 1024;
  static const _maxArrayEntries = 1000000;
  static const _chunk = 1 << 20;

  final String path;
  late RandomAccessFile _file;
  late int _length;

  /// Bytes from the file starting at [_bufferStart]; [_position] is the
  /// logical read position.
  Uint8List _buffer = Uint8List(0);
  int _bufferStart = 0;
  int _position = 0;

  _GgufReader(this.path);

  GgufMetadata read() {
    _file = File(path).openSync();
    _length = _file.lengthSync();
    try {
      final magic = _bytes(4);
      if (ascii.decode(magic, allowInvalid: true) != 'GGUF') {
        throw const FormatException('Not a GGUF file.');
      }
      final version = _u32();
      if (version < 2 || version > 3) {
        throw FormatException('Unsupported GGUF version $version.');
      }
      final tensorCount = _boundedU64('tensor count', 10000000);
      final metadataCount = _boundedU64('metadata count', _maxMetadataEntries);
      final values = <String, Object?>{};
      for (var i = 0; i < metadataCount; i++) {
        final key = _string(maxBytes: 4096);
        final type = _u32();
        if (_wanted(key) && type != 9) {
          values[key] = _scalar(type);
        } else if (type == 9 &&
            key.endsWith('.attention.sliding_window_pattern')) {
          values[key] = _flags();
        } else {
          _skip(type);
        }
      }
      final architecture = values['general.architecture'] as String?;
      int? architectureValue(String suffix) {
        if (architecture == null) return null;
        return _asInt(values['$architecture.$suffix']);
      }

      final nextn = architectureValue('nextn_predict_layers') ?? 0;
      final alignment = (_asInt(values['general.alignment']) ?? 32).clamp(
        1,
        1048576,
      );
      var hasBlockZero = false;
      // Metadata-only fixtures/headers remain readable. A complete file also
      // supplies the tensor directory, but payloads are never read.
      int? weightsBytes;
      if (nextn > 0 || _position < _length) {
        for (var i = 0; i < tensorCount; i++) {
          final name = _string(maxBytes: 4096);
          hasBlockZero |= name.startsWith('blk.0.');
          final dimensions = _u32();
          if (dimensions > 4) {
            throw const FormatException('Invalid tensor dimensions.');
          }
          _advance(dimensions * 8 + 4 + 8);
        }
        weightsBytes =
            (_length - ((_position + alignment - 1) ~/ alignment * alignment))
                .clamp(0, _length);
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
        embeddingLength: architectureValue('embedding_length'),
        headCount: architectureValue('attention.head_count'),
        kvHeadCount: architectureValue('attention.head_count_kv'),
        keyLength: architectureValue('attention.key_length'),
        valueLength: architectureValue('attention.value_length'),
        slidingWindow: architectureValue('attention.sliding_window'),
        keyLengthSwa: architectureValue('attention.key_length_swa'),
        valueLengthSwa: architectureValue('attention.value_length_swa'),
        sharedKvLayers: architectureValue('attention.shared_kv_layers'),
        swaLayers: GgufMetadata.swaPattern(
          values['$architecture.attention.sliding_window_pattern'],
          architectureValue('block_count'),
          architectureValue('attention.sliding_window'),
        ),
        weightsBytes: weightsBytes,
        nextnPredictLayers: nextn,
        hasBlockZero: hasBlockZero,
        hasChatTemplate:
            (values['tokenizer.chat_template'] as String?)?.isNotEmpty == true,
        supportsTools: RegExp(
          r'tool_calls|\btools\b|<tool_call>|<\|tool',
        ).hasMatch('${values['tokenizer.chat_template'] ?? ''}'),
        supportsThinking: RegExp(
          r'<think>|enable_thinking|thinking|<\|channel',
        ).hasMatch('${values['tokenizer.chat_template'] ?? ''}'),
        supportsVision: values.keys.any((key) => key.startsWith('clip.')),
        isEmbedding:
            values.entries.any(
              (e) =>
                  e.key.endsWith('.pooling_type') &&
                  e.value is num &&
                  (e.value as num) > 0,
            ) ||
            const {'bert', 'nomic-bert', 'jina-bert-v2'}.contains(architecture),
        sampling: {
          for (final e in values.entries)
            if (e.key.startsWith('general.sampling.')) e.key: e.value,
        },
      );
    } finally {
      _file.closeSync();
    }
  }

  static bool _wanted(String key) =>
      key == 'general.architecture' ||
      key == 'general.name' ||
      key == 'general.file_type' ||
      key == 'general.alignment' ||
      key == 'general.parameter_count' ||
      key == 'tokenizer.chat_template' ||
      key.startsWith('general.sampling.') ||
      key.endsWith('.context_length') ||
      key.endsWith('.block_count') ||
      key.endsWith('.embedding_length') ||
      key.endsWith('.attention.head_count') ||
      key.endsWith('.attention.head_count_kv') ||
      key.endsWith('.attention.key_length') ||
      key.endsWith('.attention.value_length') ||
      key.endsWith('.attention.sliding_window') ||
      key.endsWith('.attention.sliding_window_pattern') ||
      key.endsWith('.attention.key_length_swa') ||
      key.endsWith('.attention.value_length_swa') ||
      key.endsWith('.attention.shared_kv_layers') ||
      key.endsWith('.nextn_predict_layers') ||
      key.endsWith('.pooling_type') ||
      key.startsWith('clip.');

  static int? _asInt(Object? value) => value is int ? value : null;

  /// Numeric or boolean array as flags (non-zero = true); other arrays skip.
  List<bool>? _flags() {
    const widths = <int, int>{0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 7: 1};
    final elementType = _u32();
    final count = _boundedU64('array length', _maxArrayEntries);
    final width = widths[elementType];
    if (width == null || count > 4096) {
      if (width != null) {
        _advance(count * width);
        return null;
      }
      throw const FormatException('Unsupported sliding window pattern.');
    }
    return [
      for (var i = 0; i < count; i++)
        switch (width) {
          1 => _u8() != 0,
          2 => _number(2).getUint16(0, Endian.little) != 0,
          _ => _u32() != 0,
        },
    ];
  }

  Object? _scalar(int type) => switch (type) {
    0 => _u8(),
    1 => _number(1).getInt8(0),
    2 => _number(2).getUint16(0, Endian.little),
    3 => _number(2).getInt16(0, Endian.little),
    4 => _u32(),
    5 => _number(4).getInt32(0, Endian.little),
    6 => _number(4).getFloat32(0, Endian.little),
    7 => _u8() != 0,
    8 => _string(),
    10 => _boundedU64('integer value', 0x7fffffffffffffff),
    11 => _number(8).getInt64(0, Endian.little),
    12 => _number(8).getFloat64(0, Endian.little),
    _ => throw FormatException('Unknown GGUF metadata type $type.'),
  };

  void _skip(int type) {
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
      return _advance(_boundedU64('string length', _maxStringBytes));
    }
    if (type != 9) {
      throw FormatException('Unknown GGUF metadata type $type.');
    }
    final elementType = _u32();
    if (elementType == 9) {
      throw const FormatException('Nested GGUF arrays are unsupported.');
    }
    final count = _boundedU64('array length', _maxArrayEntries);
    final elementWidth = widths[elementType];
    if (elementWidth != null) return _advance(count * elementWidth);
    if (elementType == 8) {
      for (var i = 0; i < count; i++) {
        _advance(_boundedU64('string length', _maxStringBytes));
      }
      return;
    }
    throw FormatException('Unknown GGUF array type $elementType.');
  }

  String _string({int maxBytes = _maxStringBytes}) {
    final length = _boundedU64('string length', maxBytes);
    try {
      return utf8.decode(_bytes(length));
    } on FormatException {
      throw const FormatException('Invalid UTF-8 in GGUF metadata.');
    }
  }

  int _boundedU64(String label, int maximum) {
    final value = _u64();
    if (value < 0 || value > maximum) {
      throw FormatException('GGUF $label exceeds the safe limit.');
    }
    return value;
  }

  void _advance(int count) {
    final next = _position + count;
    if (count < 0 || next < _position || next > _length) {
      throw const FormatException('Truncated GGUF metadata.');
    }
    _position = next;
  }

  Uint8List _bytes(int count) {
    if (count < 0 || count > _length) {
      throw const FormatException('Invalid GGUF field length.');
    }
    if (_position + count > _length) {
      throw const FormatException('Truncated GGUF metadata.');
    }
    final offset = _position - _bufferStart;
    if (offset < 0 || offset + count > _buffer.length) {
      _file.setPositionSync(_position);
      _buffer = _file.readSync(count > _chunk ? count : _chunk);
      _bufferStart = _position;
      if (_buffer.length < count) {
        throw const FormatException('Truncated GGUF metadata.');
      }
    }
    final from = _position - _bufferStart;
    _position += count;
    return Uint8List.sublistView(_buffer, from, from + count);
  }

  ByteData _number(int count) => ByteData.sublistView(_bytes(count));
  int _u8() => _number(1).getUint8(0);
  int _u32() => _number(4).getUint32(0, Endian.little);
  int _u64() => _number(8).getUint64(0, Endian.little);
}
