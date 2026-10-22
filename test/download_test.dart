import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';

class Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);
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
  Future<void> run(Adapter adapter, {String? hash}) async {
    final dio = Dio()..httpClientAdapter = adapter;
    final manager = DownloadManager(
      dio: dio,
      resolve: (name) async => File('${dir.path}/$name'),
    );
    addTearDown(manager.dispose);
    await manager.download(
      modelId: 'test',
      url: 'https://example.org/model.gguf',
      fileName: 'model.gguf',
      expectedSha256: hash ?? sha256.convert(bytes).toString(),
      expectedSize: bytes.length,
    );
  }

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
