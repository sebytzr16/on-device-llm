import 'dart:io';
import 'dart:typed_data';

/// Writes mono [samples] (-1…1) as a 16-bit PCM WAV at [path], the format
/// libmtmd decodes for a model that can hear (llama.cpp audio projectors).
Future<void> writeWav16(
  Float32List samples,
  int sampleRate,
  String path,
) async {
  await File(path).writeAsBytes(wav16Bytes(samples, sampleRate), flush: true);
}

/// The bytes of a plain 16-bit mono WAV: a canonical 44-byte header and the
/// little-endian PCM data, clipped to the representable range.
Uint8List wav16Bytes(Float32List samples, int sampleRate) {
  final data = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(data);
  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i];
    final value = sample.isFinite ? sample.clamp(-1.0, 1.0) : 0.0;
    view.setInt16(i * 2, (value * 32767).round(), Endian.little);
  }
  final header = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...data]);
}
