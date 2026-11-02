import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_embedder.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence.dart';
import 'package:ondevice_llm/features/retrieval/overlap_prefill.dart';
import 'package:ondevice_llm/features/retrieval/semantic_rerank.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

class _Engine extends LlamaEngine {
  final batches = <List<Object>>[];
  final settled = Completer<void>();
  bool stopped = false;
  @override
  bool get isLoaded => true;
  @override
  Future<List<Float32List>> embed(List<Object> texts, {int dims = 0}) async {
    batches.add(texts);
    return [
      for (var i = 0; i < texts.length; i++)
        Float32List.fromList([batches.length.toDouble(), 0]),
    ];
  }

  @override
  void cancelPriming() {
    stopped = true;
    if (!settled.isCompleted) settled.complete();
  }
}

class _Embedder extends TextEmbedder {
  int passages = 0;
  @override
  String get modelId => 'round7-cap';
  @override
  Future<List<Float32List>?> embedDocuments(List<String> texts) async => null;
  @override
  Future<List<Float32List>?> embedQueries(List<String> texts) async => [
    Float32List.fromList([1, 0]),
  ];
  @override
  Future<Float32List?> embedPassageWithin(
    String text, {
    String? title,
    required bool Function() expired,
  }) async {
    passages++;
    return Float32List.fromList([1, 0]);
  }
}

void main() {
  test(
    'document calls batch eight passages and preserve their order',
    () async {
      final engine = _Engine();
      final embedder = LlamaEmbedder(engine, embeddingModel, () async => true);
      addTearDown(embedder.dispose);
      final vectors = await embedder.embedDocuments([
        for (var i = 0; i < 19; i++) 'passage $i',
      ]);
      expect(engine.batches.map((b) => b.length), [8, 8, 3]);
      expect(
        engine.batches.first.first,
        '${embeddingModel.documentPrefix}passage 0',
      );
      expect(vectors!.map((v) => v.first), [
        ...List.filled(8, 1),
        ...List.filled(8, 2),
        ...List.filled(3, 3),
      ]);
    },
  );

  test('batch boundaries observe cancellation', () async {
    final engine = _Engine();
    final embedder = LlamaEmbedder(engine, embeddingModel, () async => true);
    addTearDown(embedder.dispose);
    await expectLater(
      embedder.embedDocumentsWithin(
        List.filled(19, 'text'),
        () => engine.batches.isNotEmpty,
      ),
      throwsStateError,
    );
    expect(engine.batches.length, 1);
  });

  test('semantic ranking never embeds more than the top twenty', () async {
    final embedder = _Embedder();
    await SemanticRerank.rank(
      'warranty',
      [
        for (var i = 0; i < 80; i++)
          EvidenceChunk(
            sourceIndex: i,
            ordinal: 0,
            text: 'warranty passage $i',
            score: 0,
          ),
      ],
      embedder: embedder,
      candidates: 100,
      maxChunks: 30,
    );
    expect(embedder.passages, 20);
  });

  test(
    'retrieval starts before prefill and waits for prefill cancellation',
    () async {
      final engine = _Engine();
      final result = Completer<int>();
      var started = false;
      final work = overlapPrefill(
        retrieve: () {
          started = true;
          return result.future;
        },
        prefill: () {
          expect(started, isTrue);
          return engine.settled.future;
        },
        engine: engine,
      );
      result.complete(42);
      expect(await work, 42);
      expect(engine.stopped, isTrue);
    },
  );

  test(
    'prefill failure preserves retrieval and retrieval failure settles prefill',
    () async {
      final engine = _Engine();
      expect(
        await overlapPrefill(
          retrieve: () async => 42,
          prefill: () async => throw StateError('unsupported'),
          engine: engine,
        ),
        42,
      );
      final other = _Engine();
      await expectLater(
        overlapPrefill(
          retrieve: () async => throw StateError('retrieval'),
          prefill: () => other.settled.future,
          engine: other,
        ),
        throwsStateError,
      );
      expect(other.stopped, isTrue);
    },
  );
}
