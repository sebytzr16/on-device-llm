import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/utterance_audio.dart';

void main() {
  group('utterance WAV', () {
    test('a canonical 16-bit mono 16 kHz header', () {
      final bytes = wav16Bytes(Float32List.fromList([0.0, 1.0, -1.0]), 16000);
      final view = ByteData.sublistView(bytes);
      expect(bytes.length, 44 + 6);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(view.getUint32(4, Endian.little), 36 + 6);
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
      expect(view.getUint32(16, Endian.little), 16);
      expect(view.getUint16(20, Endian.little), 1);
      expect(view.getUint16(22, Endian.little), 1);
      expect(view.getUint32(24, Endian.little), 16000);
      expect(view.getUint32(28, Endian.little), 16000 * 2);
      expect(view.getUint16(32, Endian.little), 2);
      expect(view.getUint16(34, Endian.little), 16);
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
      expect(view.getUint32(40, Endian.little), 6);
      expect(view.getInt16(44, Endian.little), 0);
      expect(view.getInt16(46, Endian.little), 32767);
      expect(view.getInt16(48, Endian.little), -32767);
    });

    test('samples are clipped and written little-endian', () async {
      final dir = await Directory.systemTemp.createTemp('utterance-wav-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}utterance.wav';
      await writeWav16(Float32List.fromList([0.5, -0.5, 2.0]), 16000, path);
      final bytes = await File(path).readAsBytes();
      final view = ByteData.sublistView(bytes);
      expect(view.getUint32(40, Endian.little), 6);
      expect(view.getInt16(44, Endian.little), 16384);
      expect(view.getInt16(46, Endian.little), -16384);
      expect(view.getInt16(48, Endian.little), 32767);
    });
  });
}
