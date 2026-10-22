import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';

/// A worker whose request blocks its isolate, like a long Whisper window;
/// its close writes a marker, standing in for freeing Kokoro or Whisper.
void _slowMain(SendPort boot) {
  String? marker;
  serveSherpaWorker(boot, (m) {
    marker = m['marker'] as String;
    sleep(Duration(milliseconds: m['ms'] as int));
    return const {};
  }, () => File(marker!).writeAsStringSync('freed'));
}

void main() {
  test(
    'a worker released mid-call frees its model after the call, then exits',
    () async {
      final dir = await Directory.systemTemp.createTemp('sherpa_worker');
      addTearDown(() => dir.delete(recursive: true));
      final marker = '${dir.path}/freed';
      final worker = await SherpaWorker.spawn(_slowMain);
      final exited = ReceivePort();
      worker.isolate.addOnExitListener(exited.sendPort);

      // Longer than the old two-second kill, which landed as the call
      // returned and skipped the free.
      final reply = worker.call({'marker': marker, 'ms': 3000});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      worker.dispose();

      expect(await reply, {'error': 'closed'});
      await exited.first.timeout(const Duration(seconds: 15));
      exited.close();
      expect(File(marker).readAsStringSync(), 'freed');
    },
  );
}
