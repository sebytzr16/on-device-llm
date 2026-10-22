import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/domain/entities/model_catalog.dart';
import '../attachments/domain/scan_options.dart';

/// Photos and voice notes in the knowledge library: what the embedding
/// projector reads (a small PNG, 16 kHz mono WAV segments) is derived from
/// the stored original when a passage is indexed, then deleted.
class KnowledgeMedia {
  static const imageExtensions = {
    '.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.gif', '.bmp', //
  };
  static const audioExtensions = {
    '.m4a', '.aac', '.mp3', '.wav', '.ogg', '.opus', '.oga', '.amr', //
    '.flac', '.3gp', '.webm',
  };

  static bool isImage(String name) =>
      imageExtensions.contains(p.extension(name).toLowerCase());
  static bool isAudio(String name) =>
      audioExtensions.contains(p.extension(name).toLowerCase());
  static bool isMediaMime(String mime) =>
      mime.startsWith('image/') || mime.startsWith('audio/');

  static String mimeFor(String name) {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (isImage(name)) return 'image/${ext == 'jpg' ? 'jpeg' : ext}';
    if (isAudio(name)) return 'audio/${ext == 'm4a' ? 'mp4' : ext}';
    return 'application/octet-stream';
  }

  static const _audio = MethodChannel('ondevice_llm/audio');

  static Future<Directory> _scratch() async {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'knowledge-media'),
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// Decodes any platform-readable recording to 16 kHz mono 16-bit WAV.
  /// Returns the file and its length in seconds.
  static Future<(File, double)> decodeAudio(
    File source, {
    int maxSeconds = 3600,
    bool Function()? cancelled,
  }) async {
    final out = p.join((await _scratch()).path, '${const Uuid().v4()}.wav');
    final timer = cancelled == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 100), (_) {
            if (cancelled()) {
              unawaited(_audio.invokeMethod<void>('cancel', {'id': out}));
            }
          });
    try {
      if (cancelled?.call() == true) throw const ScanCancelled();
      final r = await _audio.invokeMapMethod<String, dynamic>('decode16k', {
        'path': source.path,
        'out': out,
        'maxSeconds': maxSeconds,
        'id': out,
      });
      if (cancelled?.call() == true) throw const ScanCancelled();
      if (r?['truncated'] == true) {
        throw FormatException(
          'Recording exceeds the $maxSeconds second import limit. Import shorter recordings.',
        );
      }
      return (File(out), (r?['seconds'] as num?)?.toDouble() ?? 0);
    } catch (_) {
      final file = File(out);
      if (await file.exists()) await file.delete();
      if (cancelled?.call() == true) throw const ScanCancelled();
      rethrow;
    } finally {
      timer?.cancel();
    }
  }

  /// The photo scaled so its longest side is [edge] px, as PNG (which the
  /// native image reader understands whatever the original format was).
  static Future<File> imageForEmbedding(
    Uint8List bytes, {
    int edge = EmbeddingModel.mediaImageEdge,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    final scale = edge / (w > h ? w : h);
    final codec = scale < 1
        ? await descriptor.instantiateCodec(
            targetWidth: (w * scale).round(),
            targetHeight: (h * scale).round(),
          )
        : await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    try {
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw const FormatException('Photo could not be read.');
      final file = File(
        p.join((await _scratch()).path, '${const Uuid().v4()}.png'),
      );
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file;
    } finally {
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// Segment [index] (each [seconds] long) of a 16-bit mono WAV, as its own
  /// WAV file; null past the end.
  static Future<File?> wavSegment(
    File wav,
    int index, {
    int seconds = EmbeddingModel.mediaAudioSeconds,
  }) async {
    // Derived files use the canonical header written by decode16k. Seek to
    // the segment, instead of reading a one-hour WAV for every minute.
    final reader = await wav.open();
    try {
      final header = await reader.read(44);
      if (header.length != 44 ||
          String.fromCharCodes(header.sublist(36, 40)) != 'data') {
        return null;
      }
      final h = ByteData.sublistView(header);
      if (h.getUint16(20, Endian.little) != 1 ||
          h.getUint16(22, Endian.little) != 1 ||
          h.getUint16(34, Endian.little) != 16) {
        return null;
      }
      final rate = h.getUint32(24, Endian.little),
          length = h.getUint32(40, Endian.little);
      final size = seconds * rate * 2;
      final start = index * size;
      if (index < 0 || seconds <= 0 || rate <= 0 || start >= length) {
        return null;
      }
      await reader.setPosition(44 + start);
      final data = await reader.read((length - start).clamp(0, size));
      final file = File(
        p.join((await _scratch()).path, '${const Uuid().v4()}.wav'),
      );
      await file.writeAsBytes(wavBytes(data, rate), flush: true);
      return file;
    } finally {
      await reader.close();
    }
  }

  static Future<Float32List> transcriptionSamples(File segment) async {
    final pcm = wavPcm(await segment.readAsBytes());
    if (pcm == null || pcm.$2 != 16000) {
      throw const FormatException('Expected 16 kHz mono WAV.');
    }
    final data = ByteData.sublistView(pcm.$1);
    return Float32List.fromList([
      for (var i = 0; i + 1 < data.lengthInBytes; i += 2)
        data.getInt16(i, Endian.little) / 32768,
    ]);
  }

  /// The PCM payload and sample rate of a plain 16-bit mono WAV.
  static (Uint8List, int)? wavPcm(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final view = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    var at = 12;
    int? rate;
    while (at + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(at, at + 4));
      final size = view.getUint32(at + 4, Endian.little);
      if (size > bytes.length - at - 8) return null;
      if (id == 'fmt ') {
        if (size < 16 ||
            view.getUint16(at + 8, Endian.little) != 1 ||
            view.getUint16(at + 10, Endian.little) != 1 ||
            view.getUint16(at + 22, Endian.little) != 16) {
          return null;
        }
        rate = view.getUint32(at + 12, Endian.little);
        if (rate == 0) return null;
      }
      if (id == 'data') {
        final end = at + 8 + size < bytes.length ? at + 8 + size : bytes.length;
        return rate == null
            ? null
            : (Uint8List.sublistView(bytes, at + 8, end), rate);
      }
      at += 8 + size + (size & 1);
    }
    return null;
  }

  static Uint8List wavBytes(Uint8List pcm, int rate) {
    final h = ByteData(44);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, 1, Endian.little);
    h.setUint32(24, rate, Endian.little);
    h.setUint32(28, rate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList([...h.buffer.asUint8List(), ...pcm]);
  }

  static String clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
