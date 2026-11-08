import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';

void main() {
  for (final repo in [
    '../models',
    './models',
    'owner/.',
    'owner/..',
    '.../models',
    'owner/...',
  ]) {
    test('CR-09: rejects $repo before any request', () async {
      final adapter = _Adapter(repo);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      await expectLater(
        HuggingFace.files(repo, client: dio),
        throwsFormatException,
      );
      await expectLater(
        HuggingFace.generationConfig(repo, client: dio),
        throwsFormatException,
      );
      expect(adapter.paths, isEmpty);
    });
    test('CR-09: does not follow dot-only base_model $repo', () async {
      final adapter = _Adapter(repo);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      expect(
        await HuggingFace.generationConfig('owner/model', client: dio),
        isNull,
      );
      expect(adapter.paths, [
        '/owner/model/resolve/main/generation_config.json',
        '/api/models/owner/model',
      ]);
    });
  }
  test(
    'M03: hugging face repo id with path traversal or query injection is rejected',
    () async {
      expect(
        () => HuggingFace.files('bad/repo/../../etc'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => HuggingFace.files('repo?query=1'),
        throwsA(isA<FormatException>()),
      );
    },
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.base);
  final String base;
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.uri.path);
    return ResponseBody.fromString(
      options.uri.path == '/api/models/owner/model'
          ? '{"cardData":{"base_model":"$base"}}'
          : '{}',
      options.uri.path.endsWith('generation_config.json') ? 404 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
