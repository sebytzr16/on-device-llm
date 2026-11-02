import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/zim/zim_wikipedia.dart';

void _crash(SendPort boot) => throw StateError('startup failed');
void _healthy(SendPort boot) => serveSherpaWorker(boot, (_) => {}, () {});

void main() {
  test('a failed ZIM open can be retried after the file is repaired', () async {
    final dir = await Directory.systemTemp.createTemp('zim-retry-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/wiki.zim';
    final wiki = ZimWikipedia(path);
    addTearDown(wiki.close);
    await expectLater(wiki.name(), throwsA(isA<FileSystemException>()));
    await File('test/fixtures/zim/mini.zim').copy(path);
    expect(await wiki.name(), 'Wikipedia test');
  });

  test(
    'a crashed voice startup settles and a fresh worker can start',
    () async {
      await expectLater(SherpaWorker.spawn(_crash), throwsStateError);
      final worker = await SherpaWorker.spawn(_healthy);
      addTearDown(worker.dispose);
      expect(await worker.call({'cmd': 'warm'}), containsPair('id', 0));
    },
  );
}
