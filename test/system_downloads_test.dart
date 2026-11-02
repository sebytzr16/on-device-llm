import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/data/storage/system_downloads.dart';

import 'download_test.dart' show Adapter;

class FakeSystem implements SystemDownloads {
  final Directory directory;
  final List<int> bytes;
  bool complete = true;
  int enqueues = 0, cancels = 0, received = 0;
  final started = Completer<void>();
  FakeSystem(this.directory, this.bytes);
  @override
  Future<void> enqueue({
    required String id,
    required String url,
    required String fileName,
    required String sha256,
    required int size,
  }) async {
    enqueues++;
    if (!started.isCompleted) started.complete();
  }

  @override
  Future<({String status, int received, String? error})> query(
    String id,
  ) async => (
    status: complete ? 'complete' : 'running',
    received: complete ? bytes.length : received,
    error: null,
  );
  @override
  Future<void> stage(String id) async {
    await File('${directory.path}/test.gguf.part').writeAsBytes(bytes);
  }

  @override
  Future<void> pause(String id) async {
    cancels++;
    if (received > 0) {
      await File(
        '${directory.path}/test.gguf.part',
      ).writeAsBytes(bytes.take(received).toList());
    }
  }

  @override
  Future<void> cancel(String id) async {
    cancels++;
  }
}

void main() {
  late Directory directory;
  final bytes = [71, 71, 85, 70, 3, 0, 0, 0, ...List.filled(100, 42)];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('system-download-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  DownloadManager manager(FakeSystem system) => DownloadManager(
    system: system,
    resolve: (name) async => File('${directory.path}/$name'),
    pollInterval: const Duration(milliseconds: 1),
  );
  Future<void> download(DownloadManager m, {String? hash}) => m.download(
    modelId: 'test',
    url: 'https://example.com/test.gguf',
    fileName: 'test.gguf',
    expectedSha256: hash ?? sha256.convert(bytes).toString(),
    expectedSize: bytes.length,
  );
  test('OS completion still requires GGUF and checksum verification', () async {
    final system = FakeSystem(directory, bytes);
    final m = manager(system);
    addTearDown(m.dispose);
    await expectLater(download(m, hash: '0' * 64), throwsException);
    expect(await File('${directory.path}/test.gguf').exists(), false);
    expect(await File('${directory.path}/test.gguf.part').exists(), false);
  });
  test(
    'disposing inside a progress callback closes safely and preserves OS job',
    () async {
      final system = FakeSystem(directory, bytes)..complete = false;
      final m = manager(system);
      addTearDown(m.dispose);
      final errors = <Object>[];
      final closed = Completer<void>();
      final subscription = m.progressStream('test').listen((progress) {
        if (progress.status != DownloadStatus.downloading) return;
        try {
          m.dispose();
        } catch (error) {
          errors.add(error);
        }
      }, onDone: closed.complete);
      addTearDown(subscription.cancel);
      await expectLater(download(m), throwsException);
      expect(errors, isEmpty);
      await closed.future.timeout(const Duration(seconds: 1));
      expect(system.cancels, 0);
      expect(await File('${directory.path}/test.gguf').exists(), false);
    },
  );
  test(
    'detaching preserves OS transfer; reopening verifies and promotes it',
    () async {
      final system = FakeSystem(directory, bytes)..complete = false;
      final first = manager(system);
      final result = download(first);
      final expectation = expectLater(result, throwsException);
      await system.started.future;
      first.dispose();
      await expectation;
      expect(system.cancels, 0);
      system.complete = true;
      final second = manager(system);
      addTearDown(second.dispose);
      await download(second);
      expect(await File('${directory.path}/test.gguf').readAsBytes(), bytes);
    },
  );
  test('explicit pause preserves OS bytes without promoting them', () async {
    final system = FakeSystem(directory, bytes)
      ..complete = false
      ..received = 32;
    final m = manager(system);
    addTearDown(m.dispose);
    final expectation = expectLater(download(m), throwsException);
    await system.started.future;
    await m.pause('test');
    await expectation;
    expect(system.cancels, greaterThanOrEqualTo(1));
    expect(
      await File('${directory.path}/test.gguf.part').readAsBytes(),
      bytes.take(32).toList(),
    );
    expect(await File('${directory.path}/test.gguf').exists(), false);
  });
  test(
    'Android paused bytes resume with Range and pass verification',
    () async {
      final system = FakeSystem(directory, bytes)
        ..complete = false
        ..received = 32;
      final dio = Dio()
        ..httpClientAdapter = Adapter((options) {
          expect(options.headers['Range'], 'bytes=32-');
          return ResponseBody.fromBytes(
            bytes.skip(32).toList(),
            206,
            headers: {
              'content-range': ['bytes 32-${bytes.length - 1}/${bytes.length}'],
            },
          );
        });
      final m = DownloadManager(
        dio: dio,
        system: system,
        resolve: (name) async => File('${directory.path}/$name'),
        pollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(m.dispose);
      final paused = expectLater(download(m), throwsException);
      await system.started.future;
      await m.pause('test');
      await paused;
      await download(m);
      expect(system.enqueues, 1);
      expect(await File('${directory.path}/test.gguf').readAsBytes(), bytes);
    },
  );
  test('pause completes cancellation before an immediate resume', () async {
    final system = FakeSystem(directory, bytes)..complete = false;
    final m = DownloadManager(
      system: system,
      resolve: (name) async => File('${directory.path}/$name'),
      pollInterval: const Duration(milliseconds: 80),
    );
    addTearDown(m.dispose);
    final stopped = expectLater(download(m), throwsException);
    await system.started.future;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await m.pause('test');
    system.complete = true;
    await download(m);
    expect(await File('${directory.path}/test.gguf').exists(), true);
    await stopped;
  });
}
