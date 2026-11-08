import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/history_video.dart';

List<int> chunk(String tag, List<int> payload) => [
  ...ascii.encode(tag),
  ...(ByteData(
    4,
  )..setUint32(0, payload.length, Endian.little)).buffer.asUint8List(),
  ...payload,
  if (payload.length.isOdd) 0,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('history-video-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'reads frame chunks inside movi and skips AVI headers and index',
    () async {
      // PNG stands in for JPEG here: the frame decoder accepts encoded images.
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawColor(const ui.Color(0xffff0000), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(1, 1);
      picture.dispose();
      final frame = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      final file = File('${root.path}/clip.avi');
      await file.writeAsBytes(
        chunk('RIFF', [
          ...ascii.encode('AVI '),
          ...chunk('LIST', [
            ...ascii.encode('hdrl'),
            ...chunk('avih', List.filled(56, 0)),
          ]),
          ...chunk('LIST', [
            ...ascii.encode('movi'),
            ...chunk('00dc', frame),
            ...chunk('00dc', frame),
          ]),
          ...chunk('idx1', List.filled(32, 0)),
        ]),
      );
      final frames = await decodeHistoryVideo(file);
      expect(frames, hasLength(2));
      expect(frames.first.width, 1);
      for (final image in frames) {
        image.dispose();
      }
    },
  );
  test('rejects a truncated video without retaining decoded frames', () async {
    final file = File('${root.path}/broken.avi');
    await file.writeAsBytes([
      ...ascii.encode('RIFF'),
      8,
      0,
      0,
      0,
      ...ascii.encode('AVI '),
      ...ascii.encode('00dc'),
      100,
      0,
      0,
      0,
      1,
    ]);
    await expectLater(decodeHistoryVideo(file), throwsFormatException);
  });
}
