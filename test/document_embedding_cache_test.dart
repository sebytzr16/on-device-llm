import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/knowledge/document_embedding_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late Directory dir;
  late DocumentEmbeddingCache cache;
  var calls = 0;
  Future<List<Float32List>?> compute() async {
    calls++;
    return [
      Float32List.fromList([0.5, 0.5]),
    ];
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('document_vectors_');
    calls = 0;
    cache = DocumentEmbeddingCache(directory: () async => dir);
  });
  tearDown(() => dir.delete(recursive: true));

  test('memory and disk reuse vectors; content and model invalidate', () async {
    await cache.vectors('eg2', ['first'], compute);
    await cache.vectors('eg2', ['first'], compute);
    cache = DocumentEmbeddingCache(directory: () async => dir);
    final restored = await cache.vectors('eg2', ['first'], compute);
    expect(restored!.single, [0.5, 0.5]);
    expect(calls, 1);
    await cache.vectors('other', ['first'], compute);
    await cache.vectors('eg2', ['changed'], compute);
    expect(calls, 3);
  });

  test('concurrent requests compute a document once', () async {
    final gate = Completer<List<Float32List>?>();
    Future<List<Float32List>?> work() {
      calls++;
      return gate.future;
    }

    final a = cache.vectors('eg2', ['first'], work);
    final b = cache.vectors('eg2', ['first'], work);
    gate.complete([
      Float32List.fromList([1, 0]),
    ]);
    await Future.wait([a, b]);
    expect(calls, 1);
  });

  test('corrupt files are recomputed and replaced', () async {
    await cache.vectors('eg2', ['first'], compute);
    final file = (await dir.list().toList()).whereType<File>().single;
    await file.writeAsString('broken');
    cache = DocumentEmbeddingCache(directory: () async => dir);
    await cache.vectors('eg2', ['first'], compute);
    expect(calls, 2);
    expect(await file.readAsString(), '[[0.5,0.5]]');
  });

  test(
    'byte caps evict disk and memory; oversized entries are not stored',
    () async {
      cache = DocumentEmbeddingCache(
        directory: () async => dir,
        memoryBytes: 0,
        diskBytes: 20,
      );
      await cache.vectors('eg2', ['first'], compute);
      await cache.vectors('eg2', ['second'], compute);
      expect((await dir.list().toList()).length, 1);
      await cache.vectors('eg2', ['first'], compute);
      expect(calls, 3);
      cache = DocumentEmbeddingCache(
        directory: () async => dir,
        memoryBytes: 0,
        diskBytes: 1,
      );
      await cache.vectors('eg2', ['oversized'], compute);
      expect((await dir.list().toList()).length, 1);
    },
  );

  test(
    'failed directory and invalid results do not poison the cache',
    () async {
      cache = DocumentEmbeddingCache(
        directory: () async => throw const FileSystemException(),
      );
      expect(await cache.vectors('eg2', ['first'], compute), isNotNull);
      expect(await cache.vectors('eg2', ['bad'], () async => []), isNull);
      expect(await cache.vectors('eg2', ['bad'], compute), isNotNull);
      expect(calls, 2);
    },
  );
}
