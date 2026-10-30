import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/data/storage/system_downloads.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';

import 'download_test.dart' show Adapter;

class _System implements SystemDownloads {
  final Directory dir;
  final List<List<int>> bytes;
  final files = <String, String>{};
  final enqueued = <String>[];
  final cancelled = <String>[];
  final secondStarted = Completer<void>();
  bool waitOnSecond = true;
  _System(this.dir, this.bytes);
  @override
  Future<void> enqueue({
    required String id,
    required String url,
    required String fileName,
    required String sha256,
    required int size,
  }) async {
    files[id] = fileName;
    enqueued.add(id);
    if (id.endsWith(':2') && !secondStarted.isCompleted) {
      secondStarted.complete();
    }
  }

  @override
  Future<({String status, int received, String? error})> query(
    String id,
  ) async {
    final i = int.parse(id.split(':').last) - 1;
    if (!files.containsKey(id)) {
      return (status: 'failed', received: 0, error: null);
    }
    if (i == 1 && waitOnSecond) {
      return (status: 'running', received: 0, error: null);
    }
    return (status: 'complete', received: bytes[i].length, error: null);
  }

  @override
  Future<void> stage(String id) async {
    final i = int.parse(id.split(':').last) - 1;
    await File('${dir.path}/${files[id]}.part').writeAsBytes(bytes[i]);
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
  }
}

void main() {
  late Directory dir;
  final bytes = [
    for (var i = 1; i <= 3; i++)
      [71, 71, 85, 70, 3, 0, 0, 0, ...List.filled(1024, i)],
  ];
  late List<ModelDownloadPart> parts;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('split-download-');
    parts = [
      for (var i = 0; i < 3; i++)
        ModelDownloadPart(
          fileName: 'hub-model-0000${i + 1}-of-00003.gguf',
          downloadUrl: 'https://example.org/part${i + 1}',
          sha256: sha256.convert(bytes[i]).toString(),
          sizeBytes: bytes[i].length,
        ),
    ];
  });
  tearDown(() async => dir.delete(recursive: true));
  File file(int i, [String suffix = '']) =>
      File('${dir.path}/${parts[i].fileName}$suffix');
  DownloadManager manager(Adapter adapter, {int? available}) {
    final m = DownloadManager(
      dio: Dio()..httpClientAdapter = adapter,
      resolve: (name) async => File('${dir.path}/$name'),
      storage: () async => available == null
          ? null
          : DeviceStorage(totalBytes: available, availableBytes: available),
    );
    addTearDown(m.dispose);
    return m;
  }

  test(
    'restart skips verified parts and resumes the next shard with aggregate progress',
    () async {
      await file(0).writeAsBytes(bytes[0]);
      await file(1, '.part').writeAsBytes(bytes[1].take(20).toList());
      final requests = <String>[];
      final m = manager(
        Adapter((o) {
          requests.add(o.path);
          final index = int.parse(o.path.substring(o.path.length - 1)) - 1;
          if (index == 1) {
            expect(o.headers['Range'], 'bytes=20-');
            return ResponseBody.fromBytes(
              bytes[index].skip(20).toList(),
              206,
              headers: {
                'content-range': [
                  'bytes 20-${bytes[index].length - 1}/${bytes[index].length}',
                ],
              },
            );
          }
          expect(o.headers['Range'], isNull);
          return ResponseBody.fromBytes(bytes[index], 200);
        }),
      );
      final progress = <DownloadProgress>[];
      final sub = m.progressStream('split').listen(progress.add);
      addTearDown(sub.cancel);
      await m.downloadFiles(modelId: 'split', files: parts);
      expect(requests.map((s) => s.split('/').last), ['part2', 'part3']);
      for (var i = 0; i < 3; i++) {
        expect(await file(i).readAsBytes(), bytes[i]);
      }
      final total = bytes.fold(0, (sum, b) => sum + b.length);
      expect(progress.every((p) => p.total == total), true);
      expect(
        progress.where((p) => p.status == DownloadStatus.completed),
        hasLength(1),
      );
      expect(progress.last.received, total);
    },
  );

  test(
    'each shard is checksum checked; a bad later shard is never promoted',
    () async {
      final m = manager(
        Adapter((o) {
          final index = int.parse(o.path.substring(o.path.length - 1)) - 1;
          return ResponseBody.fromBytes(
            index == 1 ? bytes[0] : bytes[index],
            200,
          );
        }),
      );
      await expectLater(
        m.downloadFiles(modelId: 'split', files: parts),
        throwsException,
      );
      expect(await file(0).exists(), true);
      expect(await file(1).exists(), false);
      expect(await file(1, '.part').exists(), false);
      expect(await file(2).exists(), false);
    },
  );

  test('disk reservation uses all parts before fetching the first', () async {
    var requests = 0;
    final m = manager(
      Adapter((_) {
        requests++;
        return ResponseBody.fromBytes(bytes[0], 200);
      }),
      available: 128 * 1024 * 1024 + bytes[0].length + 1,
    );
    await expectLater(
      m.downloadFiles(modelId: 'split', files: parts),
      throwsException,
    );
    expect(requests, 0);
    expect(await file(0).exists(), false);
  });

  test(
    'completed and partial bytes do not require a second full reservation',
    () async {
      await file(0).writeAsBytes(bytes[0]);
      await file(1, '.part').writeAsBytes(bytes[1]);
      final m = manager(
        Adapter((o) {
          expect(o.path, endsWith('part3'));
          return ResponseBody.fromBytes(bytes[2], 200);
        }),
        available: 128 * 1024 * 1024 + bytes[2].length,
      );
      await m.downloadFiles(modelId: 'split', files: parts);
      expect(await file(2).exists(), true);
    },
  );

  test(
    'pause between shards prevents the next request and resume keeps the first',
    () async {
      final requested = <String>[];
      final m = manager(
        Adapter((o) {
          requested.add(o.path);
          final index = int.parse(o.path.substring(o.path.length - 1)) - 1;
          return ResponseBody.fromBytes(bytes[index], 200);
        }),
      );
      Future<void>? paused;
      final sub = m.progressStream('split').listen((p) {
        if (p.status == DownloadStatus.downloading &&
            p.received == bytes[0].length) {
          paused ??= m.pause('split');
        }
      });
      await expectLater(
        m.downloadFiles(modelId: 'split', files: parts),
        throwsException,
      );
      await paused;
      await sub.cancel();
      expect(await file(0).exists(), true);
      expect(requested, hasLength(1));
      await m.downloadFiles(modelId: 'split', files: parts);
      expect(await file(2).exists(), true);
      expect(requested, hasLength(3));
    },
  );
  test(
    'system downloads use distinct shard jobs and group pause cancels them',
    () async {
      final system = _System(dir, bytes);
      final m = DownloadManager(
        system: system,
        resolve: (name) async => File('${dir.path}/$name'),
        storage: () async => null,
        pollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(m.dispose);
      final stopped = expectLater(
        m.downloadFiles(modelId: 'split', files: parts),
        throwsException,
      );
      await system.secondStarted.future;
      await m.pause('split');
      await stopped;
      expect(
        system.cancelled,
        containsAll(['split:part:1', 'split:part:2', 'split:part:3']),
      );
      expect(await file(0).exists(), true);
      expect(await file(1).exists(), false);
      system.waitOnSecond = false;
      await m.downloadFiles(modelId: 'split', files: parts);
      expect(await file(2).readAsBytes(), bytes[2]);
      expect(system.enqueued.where((id) => id == 'split:part:1'), hasLength(1));
    },
  );

  test('retained model folders keep all shards beside the first', () async {
    final old = await Directory('${dir.path}/old').create();
    await File('${old.path}/${parts.first.fileName}').writeAsBytes(bytes[0]);
    final m = DownloadManager(
      dio: Dio()
        ..httpClientAdapter = Adapter((o) {
          final i = int.parse(o.path.substring(o.path.length - 1)) - 1;
          return ResponseBody.fromBytes(bytes[i], 200);
        }),
      resolve: (name) async =>
          File('${name == parts.first.fileName ? old.path : dir.path}/$name'),
      storage: () async => null,
    );
    addTearDown(m.dispose);
    await m.downloadFiles(modelId: 'split', files: parts);
    for (var i = 0; i < 3; i++) {
      expect(
        await File('${old.path}/${parts[i].fileName}').readAsBytes(),
        bytes[i],
      );
    }
    expect(await file(1).exists(), false);
  });
}
