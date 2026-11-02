// Run explicitly with flutter test tool/round7_cache_benchmark.dart.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/knowledge/document_embedding_cache.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';

void main() {
  test(
    'downloaded EmbeddingGemma 2 cache benchmark',
    () async {
      final model = Platform.environment['ROUND7_EMBEDDING_MODEL'];
      final dll = Platform.environment['ROUND7_BRIDGE'];
      expect(model, isNotNull);
      expect(dll, isNotNull);
      final native = LlamaBindings(libraryPath: dll!);
      final options = '{}'.toNativeUtf8();
      final handle = native.create(options);
      calloc.free(options);
      final path = model!.toNativeUtf8();
      final settings = jsonEncode({
        'backend': 'cpu',
        'embedding': true,
        'contextSize': 4096,
        'effectiveThreads': 8,
        'effectiveBatchThreads': 8,
        'effectiveBatchSize': 512,
        'effectiveMicroBatchSize': 512,
      }).toNativeUtf8();
      final dir = await Directory.systemTemp.createTemp('round7-cache-bench-');
      try {
        expect(native.load(handle, path, settings), 0);
        final texts = [
          for (var i = 0; i < 24; i++)
            'title: none | text: ${'Section $i. The warranty covers repairs for two years. Keep the receipt. ' * 12}',
        ];
        Future<List<Float32List>?> embed(List<String> inputs, int batch) async {
          final out = <Float32List>[];
          for (var i = 0; i < inputs.length; i += batch) {
            final request = jsonEncode({
              'texts': inputs.skip(i).take(batch).toList(),
              'dims': 256,
            }).toNativeUtf8();
            try {
              final response = native.embed(handle, request);
              if (response == nullptr) {
                throw StateError(native.error(handle).toDartString());
              }
              final data = jsonDecode(response.toDartString()) as Map;
              out.addAll([
                for (final row in data['vectors'] as List)
                  Float32List.fromList(
                    (row as List).cast<num>().map((n) => n.toDouble()).toList(),
                  ),
              ]);
            } finally {
              calloc.free(request);
            }
          }
          return out;
        }

        await embed(texts.take(1).toList(), 1);
        Future<void> measure(
          String name,
          Future<Object?> Function() action,
        ) async {
          final clock = Stopwatch()..start();
          await action();
          // Printed numbers are measurements, never test assertions.
          stdout.writeln(
            jsonEncode({'case': name, 'ms': clock.elapsedMicroseconds / 1000}),
          );
        }

        await measure('before-24-single-calls', () => embed(texts, 1));
        var cache = DocumentEmbeddingCache(directory: () async => dir);
        Future<List<Float32List>?> compute() => embed(texts, 8);
        await measure(
          'after-cold-batches-and-disk-write',
          () => cache.vectors('eg2-q8-d256', texts, compute),
        );
        await measure(
          'after-memory-hit',
          () => cache.vectors('eg2-q8-d256', texts, compute),
        );
        cache = DocumentEmbeddingCache(directory: () async => dir);
        await measure(
          'after-disk-hit',
          () => cache.vectors('eg2-q8-d256', texts, compute),
        );
        await measure(
          'query-only',
          () => embed([
            'task: search result | query: What does the warranty cover?',
          ], 1),
        );
      } finally {
        native.destroy(handle);
        calloc.free(path);
        calloc.free(settings);
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
