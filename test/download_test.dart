import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';

class Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  int callCount = 0;
  Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late List<int> bytes;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('odllm-download-test-');
    bytes = [
      71,
      71,
      85,
      70,
      3,
      0,
      0,
      0,
      ...List.generate(1024, (i) => i % 256),
    ];
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> run(
    Adapter adapter, {
    String? hash,
    String modelId = 'test',
    String fileName = 'model.gguf',
  }) async {
    final dio = Dio()..httpClientAdapter = adapter;
    final manager = DownloadManager(
      dio: dio,
      resolve: (name) async => File('${dir.path}/$name'),
    );
    addTearDown(manager.dispose);
    await manager.download(
      modelId: modelId,
      url: 'https://example.org/model.gguf',
      fileName: fileName,
      expectedSha256: hash ?? sha256.convert(bytes).toString(),
      expectedSize: bytes.length,
    );
  }

  group('destination deduplication', () {
    test(
      'second request for same destination joins in-flight transfer',
      () async {
        final adapter = Adapter((_) => ResponseBody.fromBytes(bytes, 200));
        final dio = Dio()..httpClientAdapter = adapter;
        final manager = DownloadManager(
          dio: dio,
          resolve: (name) async => File('${dir.path}/$name'),
        );
        addTearDown(manager.dispose);

        // Start two concurrent downloads for the same file.
        final f1 = manager.download(
          modelId: 'model-a',
          url: 'https://example.org/model.gguf',
          fileName: 'shared.gguf',
          expectedSha256: sha256.convert(bytes).toString(),
          expectedSize: bytes.length,
        );
        final f2 = manager.download(
          modelId: 'model-b',
          url: 'https://example.org/model.gguf',
          fileName: 'shared.gguf',
          expectedSha256: sha256.convert(bytes).toString(),
          expectedSize: bytes.length,
        );

        await Future.wait([f1, f2]);

        // Only one HTTP request should have been made.
        expect(adapter.callCount, 1);
        expect(await File('${dir.path}/shared.gguf').readAsBytes(), bytes);
      },
    );

    test('conflicting size for same destination fails fast', () async {
      final adapter = Adapter((_) => ResponseBody.fromBytes(bytes, 200));
      final dio = Dio()..httpClientAdapter = adapter;
      final manager = DownloadManager(
        dio: dio,
        resolve: (name) async => File('${dir.path}/$name'),
      );
      addTearDown(manager.dispose);

      // Start first download.
      final f1 = manager.download(
        modelId: 'model-a',
        url: 'https://example.org/model.gguf',
        fileName: 'shared.gguf',
        expectedSha256: sha256.convert(bytes).toString(),
        expectedSize: bytes.length,
      );

      // Try to start second download with different expected size.
      final f2 = manager.download(
        modelId: 'model-b',
        url: 'https://example.org/model.gguf',
        fileName: 'shared.gguf',
        expectedSha256: sha256.convert(bytes).toString(),
        expectedSize: bytes.length + 100, // Different size!
      );

      final conflictCheck = expectLater(f2, throwsA(isA<DownloadException>()));
      await Future.wait([f1, conflictCheck]);
      // A conflict must clear request bookkeeping so pause cannot hang.
      await manager.pause('model-b');
      expect(adapter.callCount, 1);
    });

    test('conflicting hash for same destination fails fast', () async {
      final adapter = Adapter((_) => ResponseBody.fromBytes(bytes, 200));
      final dio = Dio()..httpClientAdapter = adapter;
      final manager = DownloadManager(
        dio: dio,
        resolve: (name) async => File('${dir.path}/$name'),
      );
      addTearDown(manager.dispose);

      // Start first download.
      final f1 = manager.download(
        modelId: 'model-a',
        url: 'https://example.org/model.gguf',
        fileName: 'shared.gguf',
        expectedSha256: sha256.convert(bytes).toString(),
        expectedSize: bytes.length,
      );

      // Try to start second download with different expected hash.
      final f2 = manager.download(
        modelId: 'model-b',
        url: 'https://example.org/model.gguf',
        fileName: 'shared.gguf',
        expectedSha256: '0' * 64, // Different hash!
        expectedSize: bytes.length,
      );

      final conflictCheck = expectLater(f2, throwsA(isA<DownloadException>()));
      await Future.wait([f1, conflictCheck]);
      // A conflict must clear request bookkeeping so pause cannot hang.
      await manager.pause('model-b');
      expect(adapter.callCount, 1);
    });
  });

  group('destination lifecycle', () {
    late DownloadManager manager;
    late Adapter adapter;
    late StreamController<Uint8List> body;
    late Completer<void> started;

    setUp(() {
      body = StreamController<Uint8List>();
      started = Completer<void>();
      adapter = Adapter((_) {
        if (!started.isCompleted) {
          started.complete();
          return ResponseBody(body.stream, 200);
        }
        return ResponseBody.fromBytes(bytes, 200);
      });
      manager = DownloadManager(
        dio: Dio()..httpClientAdapter = adapter,
        resolve: (name) async => File('${dir.path}/$name'),
        storage: () async => null,
      );
      addTearDown(manager.dispose);
    });

    Future<void> shared(String id) => manager.download(
      modelId: id,
      url: 'https://example.org/shared.gguf',
      fileName: 'shared.gguf',
      expectedSha256: sha256.convert(bytes).toString(),
      expectedSize: bytes.length,
    );

    test(
      'joined pause completes without cancelling the first caller',
      () async {
        final owner = shared('owner');
        await started.future;
        final joined = shared('joined');
        final check = expectLater(joined, throwsA(isA<DioException>()));
        // Let the second request reach the destination wait.
        await Future<void>.delayed(Duration.zero);
        await manager.pause('joined');
        await check;
        expect(adapter.callCount, 1);
        body.add(Uint8List.fromList(bytes));
        await body.close();
        await owner;
        expect(await File('${dir.path}/shared.gguf').readAsBytes(), bytes);
      },
    );

    test('owner failure reaches joiners and permits a fresh attempt', () async {
      final owner = shared('owner');
      final ownerCheck = expectLater(
        owner,
        throwsA(isA<ChecksumMismatchException>()),
      );
      await started.future;
      final joined = shared('joined');
      final joinCheck = expectLater(
        joined,
        throwsA(isA<ChecksumMismatchException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final corrupt = [...bytes]..[20] = 42;
      body.add(Uint8List.fromList(corrupt));
      await body.close();
      await Future.wait([ownerCheck, joinCheck]);
      expect(adapter.callCount, 1);
      await shared('joined');
      expect(adapter.callCount, 2);
      expect(await File('${dir.path}/shared.gguf').readAsBytes(), bytes);
    });

    test(
      'overlapping batches still download their unique components',
      () async {
        final owner = shared('owner');
        await started.future;
        final batch = manager.downloadFiles(
          modelId: 'batch',
          files: [
            for (final name in ['shared.gguf', 'unique.gguf'])
              ModelDownloadPart(
                fileName: name,
                downloadUrl: 'https://example.org/$name',
                sha256: sha256.convert(bytes).toString(),
                sizeBytes: bytes.length,
              ),
          ],
        );
        await Future<void>.delayed(Duration.zero);
        expect(adapter.callCount, 1);
        body.add(Uint8List.fromList(bytes));
        await body.close();
        await Future.wait([owner, batch]);
        expect(adapter.callCount, 2);
        for (final name in ['shared.gguf', 'unique.gguf']) {
          expect(await File('${dir.path}/$name').readAsBytes(), bytes);
          expect(await File('${dir.path}/$name.part').exists(), isFalse);
        }
      },
    );
  });

  group('size-mismatch readiness', () {
    test('existing wrong-size file is rejected before network access', () async {
      // Write a truncated but valid GGUF header so validateAndHash returns a hash
      // instead of throwing FormatException. The existing-file check should then
      // fail on size mismatch and throw DownloadException.
      await File(
        '${dir.path}/model.gguf',
      ).writeAsBytes(bytes.take(100).toList());

      final adapter = Adapter((_) => ResponseBody.fromBytes(bytes, 200));
      final dio = Dio()..httpClientAdapter = adapter;
      final manager = DownloadManager(
        dio: dio,
        resolve: (name) async => File('${dir.path}/$name'),
      );
      addTearDown(manager.dispose);

      // The file exists but has wrong size - should fail with
      // "unverified model already exists" error (real readiness behavior).
      await expectLater(
        manager.download(
          modelId: 'test',
          url: 'https://example.org/model.gguf',
          fileName: 'model.gguf',
          expectedSha256: sha256.convert(bytes).toString(),
          expectedSize: bytes.length,
        ),
        throwsA(isA<DownloadException>()),
      );
      expect(adapter.callCount, 0);
      expect(await File('${dir.path}/model.gguf.part').exists(), isFalse);
      await manager.pause('test');
    });

    test('existing same-size file with wrong hash is rejected', () async {
      // Write a file with valid GGUF header but different data (wrong hash).
      final wrongContent = [
        71, 71, 85, 70, 3, 0, 0, 0, // Valid GGUF header
        ...List.generate(
          bytes.length - 8,
          (i) => (i + 100) % 256,
        ), // Different data
      ];
      await File('${dir.path}/model.gguf').writeAsBytes(wrongContent);

      final adapter = Adapter((_) => ResponseBody.fromBytes(bytes, 200));
      final dio = Dio()..httpClientAdapter = adapter;
      final manager = DownloadManager(
        dio: dio,
        resolve: (name) async => File('${dir.path}/$name'),
      );
      addTearDown(manager.dispose);

      // The file exists with correct size but wrong hash - should fail with
      // "unverified model already exists" error.
      await expectLater(
        manager.download(
          modelId: 'test',
          url: 'https://example.org/model.gguf',
          fileName: 'model.gguf',
          expectedSha256: sha256.convert(bytes).toString(),
          expectedSize: bytes.length,
        ),
        throwsA(isA<DownloadException>()),
      );
      expect(adapter.callCount, 0);
      expect(await File('${dir.path}/model.gguf.part').exists(), isFalse);
      await manager.pause('test');
    });
  });

  test('resumes only when Content-Range agrees with local offset', () async {
    await File(
      '${dir.path}/model.gguf.part',
    ).writeAsBytes(bytes.take(20).toList());
    await run(
      Adapter((o) {
        expect(o.headers['Range'], 'bytes=20-');
        return ResponseBody.fromBytes(
          bytes.skip(20).toList(),
          206,
          headers: {
            'content-range': ['bytes 20-${bytes.length - 1}/${bytes.length}'],
          },
        );
      }),
    );
    expect(await File('${dir.path}/model.gguf').readAsBytes(), bytes);
  });
  test(
    'server ignoring Range restarts without appending full response',
    () async {
      await File(
        '${dir.path}/model.gguf.part',
      ).writeAsBytes(bytes.take(20).toList());
      await run(Adapter((_) => ResponseBody.fromBytes(bytes, 200)));
      expect(await File('${dir.path}/model.gguf').readAsBytes(), bytes);
    },
  );
  test('416 on resume (re-uploaded asset) restarts from zero', () async {
    await File(
      '${dir.path}/model.gguf.part',
    ).writeAsBytes(bytes.take(20).toList());
    final ranges = <Object?>[];
    await run(
      Adapter((o) {
        ranges.add(o.headers['Range']);
        return o.headers['Range'] == null
            ? ResponseBody.fromBytes(bytes, 200)
            : ResponseBody.fromBytes(const [], 416);
      }),
    );
    expect(ranges, ['bytes=20-', null]);
    expect(await File('${dir.path}/model.gguf').readAsBytes(), bytes);
  });
  test('invalid resume offsets cannot promote a file', () async {
    await File(
      '${dir.path}/model.gguf.part',
    ).writeAsBytes(bytes.take(20).toList());
    await expectLater(
      run(
        Adapter(
          (_) => ResponseBody.fromBytes(
            bytes,
            206,
            headers: {
              'content-range': ['bytes 0-${bytes.length - 1}/${bytes.length}'],
            },
          ),
        ),
      ),
      throwsException,
    );
    expect(await File('${dir.path}/model.gguf').exists(), false);
  });
  test('checksum mismatch removes corrupted partial file', () async {
    await expectLater(
      run(Adapter((_) => ResponseBody.fromBytes(bytes, 200)), hash: '0' * 64),
      throwsException,
    );
    expect(await File('${dir.path}/model.gguf').exists(), false);
    expect(await File('${dir.path}/model.gguf.part').exists(), false);
  });
  test('HTML and truncated responses cannot become models', () async {
    await expectLater(
      run(
        Adapter(
          (_) => ResponseBody.fromBytes(List.filled(bytes.length, 60), 200),
        ),
      ),
      throwsException,
    );
    expect(await File('${dir.path}/model.gguf').exists(), false);
    expect(await File('${dir.path}/model.gguf.part').exists(), false);
  });
}
