import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';

void main() {
  final library = Platform.environment['OD_SIDE_TEST_LIBRARY'];
  final model = Platform.environment['OD_SIDE_TEST_MODEL'];
  test(
    'native second worker batches four, queues excess and cancels queued work',
    () async {
      final api = LlamaBindings(libraryPath: library!);
      final options = '{}'.toNativeUtf8();
      final runtime = api.create(options);
      calloc.free(options);
      final path = model!.toNativeUtf8();
      final settings = jsonEncode({
        // CPU bridges need OD_SIDE_TEST_BACKEND=cpu (stale CPU DLLs, owner, 2026-11-02).
        'backend': Platform.environment['OD_SIDE_TEST_BACKEND'] ?? 'cuda',
        'nGpuLayers': Platform.environment['OD_SIDE_TEST_BACKEND'] == 'cpu'
            ? 0
            : 999,
        'contextSize': 4096,
        'kvCacheType': 'q8_0',
        'vCacheType': 'q8_0',
        'effectiveThreads': 8,
        'effectiveBatchThreads': 8,
      }).toNativeUtf8();
      final events = ReceivePort();
      final ready = Completer<SendPort>(),
          closed = Completer<void>(),
          done = Completer<void>(),
          lateDone = Completer<void>();
      SendPort? commandPort;
      var submittedLate = false, overlapped = false;
      Map<String, Object> submit(String id) => {
        'type': 'submit',
        'id': id,
        'request': jsonEncode({
          'messages': [
            {'role': 'user', 'content': 'Write twenty practical tips for $id.'},
          ],
          'settings': {
            'temperature': 0.3,
            'maxTokens': 32,
            'thinkingModeEnabled': false,
          },
        }),
      };
      final active = <String>{}, finished = <String>{};
      final bytes = <String, List<int>>{};
      var peak = 0;
      events.listen((dynamic value) {
        if (value is SendPort) {
          ready.complete(value);
          return;
        }
        final event = value as Map;
        if (event['type'] == 'closed') {
          closed.complete();
          return;
        }
        expect(event['type'], isNot('error'), reason: '$event');
        final id = event['id'] as String;
        if (event['type'] == 'started') {
          active.add(id);
          if (active.length > peak) peak = active.length;
          expect(active.length, lessThanOrEqualTo(4));
        }
        if (event['bytes'] case final List values) {
          bytes.putIfAbsent(id, () => []).addAll(values.cast<int>());
        }
        // Reuse allocated slots to prove the worker admits after decoding starts (owner, 2026-11-02).
        if (id == 'late-0' && event['metrics'] != null && !submittedLate) {
          submittedLate = true;
          commandPort!.send(submit('late-1'));
          commandPort.send(submit('late-2'));
        }
        if (id == 'late-1' && event['metrics'] != null) {
          overlapped |= active.contains('late-0');
        }
        if (event['done'] == true) {
          active.remove(id);
          finished.add(id);
          if (id == '5') expect(event['error'], 'cancelled');
          if (finished.length == 6) done.complete();
          if (finished.length == 9) lateDone.complete();
        }
      });
      try {
        expect(
          api.load(runtime, path, settings),
          0,
          reason: api.error(runtime).toDartString(),
        );
        await Isolate.spawn(llamaSideWorker, [
          events.sendPort,
          runtime.address,
          library,
        ]);
        final commands = await ready.future;
        commandPort = commands;
        for (var i = 0; i < 6; ++i) {
          commands.send({
            'type': 'submit',
            'id': '$i',
            'request': jsonEncode({
              'messages': [
                {
                  'role': 'user',
                  'content':
                      'Write twenty practical document writing tips for section $i.',
                },
              ],
              'settings': {
                'temperature': 0.3,
                'maxTokens': 32,
                'thinkingModeEnabled': false,
              },
            }),
          });
        }
        commands.send({'type': 'cancel', 'id': '5'});
        await done.future;
        expect(peak, 4);
        for (var i = 0; i < 5; ++i) {
          expect(utf8.decode(bytes['$i']!).trim(), isNotEmpty);
        }
        commands.send(submit('late-0'));
        await lateDone.future;
        expect(overlapped, isTrue);
        commands.send({'type': 'close'});
        await closed.future;
      } finally {
        events.close();
        calloc.free(path);
        calloc.free(settings);
        api.destroy(runtime);
      }
    },
    // Larger models share VRAM with a running app and need longer than 30 s.
    timeout: const Timeout(Duration(minutes: 3)),
    skip: library == null || model == null
        ? 'Set OD_SIDE_TEST_LIBRARY and OD_SIDE_TEST_MODEL for offline GPU integration.'
        : false,
  );
}
