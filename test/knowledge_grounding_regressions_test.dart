import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_media.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_grounding.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';
import 'package:ondevice_llm/features/attachments/domain/scan_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ondevice_llm/audio');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          paths,
          (_) async => Directory.systemTemp.path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
  });
  test(
    'later segment facts reach the answer sources with one decode pass',
    () async {
      final dir = await Directory.systemTemp.createTemp('audio-index-');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var decodes = 0, heard = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'decode16k') {
              decodes++;
              await File(call.arguments['out'] as String).writeAsBytes(
                KnowledgeMedia.wavBytes(Uint8List(120 * 16000 * 2), 16000),
              );
              return {'seconds': 120.0};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final store = KnowledgeStore(db, null, () async => dir);
      final doc = await store.import(
        collection: 'Notes',
        name: 'meeting.m4a',
        bytes: Uint8List.fromList([1, 2, 3]),
        transcribeSegment: (file) async {
          heard++;
          expect(
            (await KnowledgeMedia.transcriptionSamples(file)).length,
            60 * 16000,
          );
          return heard == 1
              ? 'The meeting starts at nine.'
              : 'The cupboard access code is heron-4471.';
        },
      );
      final result = await store.search('Notes', 'cupboard access code');
      expect(result.single.pageText, contains('heron-4471'));
      expect(result.single.pageText, contains('1:00–2:00'));
      final chunks = await db.unindexedKnowledgeChunks('Notes', 'test');
      for (final chunk in chunks) {
        final media = await store.mediaFor(doc, chunk);
        for (final file in media!) {
          await file.delete();
        }
      }
      expect(decodes, 1);
      await store.remove(doc.id);
      expect(await File('${dir.path}/${doc.id}.audio.wav').exists(), isFalse);
    },
  );
  test('a caption makes a non-OCR photo fact retrievable', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final store = KnowledgeStore(db);
    await store.import(
      collection: 'Photos',
      name: 'drawer.jpg',
      bytes: Uint8List.fromList([1]),
      ocr: (_) async => '',
      caption: (_) async => 'A blue ceramic key is inside the drawer.',
    );
    final sources = await store.search(
      'Photos',
      'what colour is the key in the drawer',
    );
    expect(sources.single.pageText, contains('blue ceramic key'));
    expect(sources.single.pageText, contains('model generated'));
  });
  test('cancelled import never publishes an empty document', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(
      () => KnowledgeStore(db).import(
        collection: 'Notes',
        name: 'note.wav',
        bytes: Uint8List(0),
        cancelled: () => true,
      ),
      throwsA(isA<ScanCancelled>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(await db.knowledgeDocsIn('Notes'), isEmpty);
  });
  test(
    'ASR covers a fact near the end of a minute with bounded windows',
    () async {
      final dir = await Directory.systemTemp.createTemp('late-asr-');
      addTearDown(() => dir.delete(recursive: true));
      final data = ByteData(60 * 16000 * 2);
      for (var i = 52 * 16000; i < 55 * 16000; i++) {
        data.setInt16(i * 2, 2000, Endian.little);
      }
      final file = File('${dir.path}/late.wav');
      await file.writeAsBytes(
        KnowledgeMedia.wavBytes(data.buffer.asUint8List(), 16000),
      );
      final voice = _WindowVoice();
      expect(
        await KnowledgeGrounding.transcript(file, voice),
        contains('blue ceramic key'),
      );
      expect(voice.longest, lessThanOrEqualTo(20 * 16000));
    },
  );
}

class _WindowVoice extends SherpaVoice {
  var longest = 0;
  @override
  Future<Heard?> transcribe(Float32List samples, {String language = ''}) async {
    if (samples.length > longest) longest = samples.length;
    // Model its documented maximum: samples past 30s would be discarded.
    final inspected = samples.take(30 * 16000);
    return inspected.any((s) => s > .01)
        ? const Heard('A blue ceramic key is in the drawer.', 'en')
        : const Heard('', 'en');
  }
}
