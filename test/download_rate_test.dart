import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/data/storage/system_downloads.dart';

/// The OS download behaves like Android's: it already holds a staged prefix
/// and its poll reports a steady byte count, then a stalled one.
class _System implements SystemDownloads {
  _System(this.dir, this.bytes);
  final Directory dir;
  final List<int> bytes;
  final polls = <({String status, int received, String? error})>[
    (status: 'failed', received: 0, error: null), // batch progress probe
    (status: 'failed', received: 0, error: null), // part progress probe
    (status: 'running', received: 1000, error: null),
    (status: 'running', received: 2000, error: null),
    (status: 'running', received: 2000, error: null),
    (status: 'running', received: 2000, error: null),
    (status: 'complete', received: 4096, error: null),
  ];
  int _at = 0;
  String? fileName;

  @override
  Future<void> enqueue({
    required String id,
    required String url,
    required String fileName,
    required String sha256,
    required int size,
  }) async {
    this.fileName = fileName;
  }

  @override
  Future<({String status, int received, String? error})> query(
    String id,
  ) async {
    final poll = polls[_at < polls.length ? _at : polls.length - 1];
    _at++;
    return poll;
  }

  @override
  Future<void> stage(String id) async {
    await File('${dir.path}/$fileName.part').writeAsBytes(bytes);
  }

  @override
  Future<void> pause(String id) async {}

  @override
  Future<void> cancel(String id) async {}
}

void main() {
  test(
    'a rate is only shown from the second poll and eases to a stall',
    () async {
      final dir = await Directory.systemTemp.createTemp('download-rate-');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = [
        71, 71, 85, 70, 3, 0, 0, 0, // Valid GGUF v3 header
        ...List.generate(4088, (i) => i % 256),
      ];
      final system = _System(dir, bytes);
      final manager = DownloadManager(
        system: system,
        resolve: (name) async => File('${dir.path}/$name'),
        storage: () async => null,
        pollInterval: const Duration(milliseconds: 5),
      );
      addTearDown(manager.dispose);
      final rates = <double?>[];
      final sub = manager.progressStream('sys').listen((p) {
        if (p.status == DownloadStatus.downloading) rates.add(p.bytesPerSecond);
      });
      await manager.download(
        modelId: 'sys',
        url: 'https://example.org/model.gguf',
        fileName: 'model.gguf',
        expectedSha256: sha256.convert(bytes).toString(),
        expectedSize: bytes.length,
      );
      await sub.cancel();
      expect(rates, hasLength(4));
      // A rate computed from the staged prefix would read as a spike.
      expect(rates.first, isNull);
      expect(rates.skip(1).every((r) => r != null), isTrue);
      // The raw delta is 0 once a poll brings no new bytes; the smoothed rate
      // keeps showing the transfer instead of dropping to 0.
      expect(rates[2], greaterThan(0));
      expect(rates[3], greaterThan(0));
    },
  );
}
