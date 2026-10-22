import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/shared_providers.dart';
import '../../core/utils/priority_work_queue.dart';
import '../../core/utils/inference_admission.dart';
import '../../data/local/database/app_database.dart';
import '../../data/storage/model_storage.dart';
import '../../inference/engine/llama_engine.dart';
import '../models/domain/entities/model_catalog.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import 'knowledge_store.dart';

/// Turns text into vectors with the on-device embedding model (FX-02).
/// Null results mean "no semantic index available" (model not downloaded,
/// engine failed); callers fall back to lexical retrieval.
abstract class TextEmbedder {
  String get modelId;
  Future<List<Float32List>?> embedQueries(List<String> texts);
  Future<List<Float32List>?> embedDocuments(List<String> texts);
  Future<List<Float32List>?> embedDocumentsWithin(
    List<String> texts,
    bool Function() cancelled,
  ) async => cancelled() ? null : embedDocuments(texts);

  /// Photos and recordings in the text space; null when the model has no
  /// projector on disk (callers index such passages from their text).
  Future<List<Float32List>?> embedMedia(List<EmbedItem> items) async => null;
  Future<List<Float32List>?> embedMediaWithin(
    List<EmbedItem> items,
    bool Function() cancelled,
  ) async => cancelled() ? null : embedMedia(items);

  /// One passage with its page title (the document prefix's title slot).
  Future<Float32List?> embedPassage(String text, {String? title}) async =>
      (await embedDocuments([text]))?.first;

  /// Loads the model ahead of a search so the load overlaps the network.
  Future<void> warm() async {}
  Future<List<Float32List>?> embedQueriesWithin(
    List<String> texts,
    bool Function() expired,
  ) async => expired() ? null : embedQueries(texts);
  Future<Float32List?> embedPassageWithin(
    String text, {
    String? title,
    required bool Function() expired,
  }) async => expired() ? null : embedPassage(text, title: title);
}

/// The real embedder: loads the catalog embedding model into its own native
/// runtime on first use and applies the model's task prefixes.
class LlamaEmbedder implements TextEmbedder {
  final LlamaEngine engine;
  final EmbeddingModel model;
  final Future<bool> Function() available;
  final Future<bool> Function() mediaAvailable;
  final _queue = PriorityWorkQueue();
  Timer? _idle;
  bool _disposed = false;

  Future<T> _background<T>(
    Future<T> Function() action,
    bool Function() cancelled,
  ) async {
    bool stopped() => _disposed || cancelled();
    while (!stopped()) {
      await InferenceAdmission.shared.background(cancelled: stopped);
      // Recheck at the start of the native queue. A speech request arriving
      // after admission cannot trap interactive retrieval behind indexing.
      final next = await _queue.submit<({T? value, bool deferred})>(() async {
        if (InferenceAdmission.shared.interactive) {
          return (value: null, deferred: true);
        }
        return (value: await action(), deferred: false);
      }, cancelled: stopped);
      if (!next.deferred) return next.value as T;
    }
    throw StateError('Deferred embedding cancelled');
  }

  LlamaEmbedder(
    this.engine,
    this.model,
    this.available, [
    Future<bool> Function()? mediaAvailable,
  ]) : mediaAvailable = mediaAvailable ?? (() async => false);

  @override
  String get modelId =>
      '${model.id}:${model.sha256}:d${model.dimensions}:media-384-16k60-v2';

  /// Text needs only the model; photos and recordings also need the
  /// projector, which roughly triples the memory, so it is loaded only for
  /// media and kept until the idle release.
  Future<bool> _ready({bool media = false}) async {
    if (engine.isLoaded && (!media || engine.embedsMedia)) return true;
    if (!await available()) return false;
    final projector = model.projector;
    if (media && (projector == null || !await mediaAvailable())) return false;
    final file = await ModelStorage.modelFile(model.fileName);
    await engine.loadEmbedder(
      modelPath: file.path,
      mmprojPath: media
          ? (await ModelStorage.modelFile(projector!.fileName)).path
          : null,
    );
    return true;
  }

  Future<List<Float32List>?> _embed(List<Object> texts) async {
    if (texts.isEmpty) return const [];
    final media = texts.any((t) => t is EmbedItem);
    if (!await _ready(media: media)) return null;
    _idle?.cancel();
    try {
      return await engine.embed(texts, dims: model.dimensions);
    } finally {
      _idle = Timer(const Duration(minutes: 2), () => unawaited(release()));
    }
  }

  @override
  Future<List<Float32List>?> embedQueries(List<String> texts) => _queue.submit(
    () => _embed([for (final t in texts) '${model.queryPrefix}$t']),
    priority: 10,
  );

  @override
  Future<List<Float32List>?> embedDocuments(List<String> texts) =>
      embedDocumentsWithin(texts, () => false);

  @override
  Future<List<Float32List>?> embedDocumentsWithin(
    List<String> texts,
    bool Function() cancelled,
  ) async {
    final vectors = <Float32List>[];
    for (final t in texts) {
      final next = await _background(
        () => _embed(['${model.documentPrefix}$t']),
        cancelled,
      );
      if (next == null) return null;
      vectors.addAll(next);
    }
    return vectors;
  }

  @override
  Future<Float32List?> embedPassage(String text, {String? title}) async {
    final t = title?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final prefix = t == null || t.isEmpty
        ? model.documentPrefix
        : model.documentPrefix.replaceFirst('none', t);
    return (await _queue.submit(() => _embed(['$prefix$text'])))?.first;
  }

  @override
  Future<List<Float32List>?> embedQueriesWithin(
    List<String> texts,
    bool Function() expired,
  ) => _queue.submit(
    () => _embed([for (final t in texts) '${model.queryPrefix}$t']),
    priority: 10,
    cancelled: expired,
  );

  @override
  Future<Float32List?> embedPassageWithin(
    String text, {
    String? title,
    required bool Function() expired,
  }) async {
    final t = title?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final prefix = t == null || t.isEmpty
        ? model.documentPrefix
        : model.documentPrefix.replaceFirst('none', t);
    return (await _queue.submit(
      () => _embed(['$prefix$text']),
      priority: 5,
      cancelled: expired,
    ))?.first;
  }

  @override
  Future<void> warm() => _queue.submit(() async {
    try {
      if (await _ready()) {
        _idle?.cancel();
        _idle = Timer(const Duration(minutes: 2), () => unawaited(release()));
      }
    } catch (_) {}
  }, priority: 5);

  @override
  Future<List<Float32List>?> embedMedia(List<EmbedItem> items) =>
      embedMediaWithin(items, () => false);

  @override
  Future<List<Float32List>?> embedMediaWithin(
    List<EmbedItem> items,
    bool Function() cancelled,
  ) async {
    final vectors = <Float32List>[];
    for (final item in items) {
      final next = await _background(() => _embed([item]), cancelled);
      if (next == null) return null;
      vectors.addAll(next);
    }
    return vectors;
  }

  /// Frees the model's memory; the next call loads it again.
  Future<void> release() => _queue.submit(() async {
    _idle?.cancel();
    if (engine.isLoaded && !engine.isBusy) await engine.unload();
  }, priority: -1);
  void dispose() {
    _disposed = true;
    _idle?.cancel();
  }
}

final textEmbedderProvider = Provider<TextEmbedder>((ref) {
  final embedder = LlamaEmbedder(
    ref.watch(embeddingEngineProvider),
    embeddingModel,
    () async => ref.read(modelManagerProvider).embeddingReady,
    () async => ref.read(modelManagerProvider).embeddingMediaReady,
  );
  ref.onDispose(embedder.dispose);
  return embedder;
});

/// Progress of the semantic index: passages embedded / total per document
/// that is still being processed, plus the last error.
class KnowledgeIndexState {
  final bool running;
  final String? collection, error;
  final int done, total;
  const KnowledgeIndexState({
    this.running = false,
    this.collection,
    this.error,
    this.done = 0,
    this.total = 0,
  });
  KnowledgeIndexState copyWith({
    bool? running,
    String? collection,
    String? error,
    bool clearError = false,
    int? done,
    int? total,
  }) => KnowledgeIndexState(
    running: running ?? this.running,
    collection: collection ?? this.collection,
    error: clearError ? null : error ?? this.error,
    done: done ?? this.done,
    total: total ?? this.total,
  );
}

/// Embeds every passage of a collection that has no vector from the current
/// model yet, in small batches so a cancel or an error loses little.
class KnowledgeIndexer extends Notifier<KnowledgeIndexState> {
  bool _cancel = false;

  @override
  KnowledgeIndexState build() => const KnowledgeIndexState();

  static const batch = 8;

  Future<void> index(String collection) async {
    if (state.running) return;
    final db = ref.read(appDatabaseProvider);
    final embedder = ref.read(textEmbedderProvider);
    _cancel = false;
    final total = await db.countUnindexedKnowledgeChunks(
      collection,
      embedder.modelId,
    );
    state = KnowledgeIndexState(
      running: true,
      collection: collection,
      total: total,
    );
    var done = 0;
    try {
      while (!_cancel) {
        final chunks = await db.unindexedKnowledgeChunks(
          collection,
          embedder.modelId,
          limit: batch,
        );
        if (chunks.isEmpty) break;
        final vectors = await _embedChunks(embedder, collection, chunks);
        if (_cancel || !ref.mounted) break;
        if (vectors == null) {
          throw StateError(
            'The embedding model is not downloaded. Settings > Knowledge library.',
          );
        }
        await db.storeKnowledgeVectors({
          for (var i = 0; i < chunks.length; i++)
            chunks[i].id: KnowledgeStore.encodeVector(vectors[i]),
        }, embedder.modelId);
        done += chunks.length;
        state = state.copyWith(done: done);
      }
    } catch (e) {
      if (!_cancel && ref.mounted) state = state.copyWith(error: '$e');
    } finally {
      if (ref.mounted) state = state.copyWith(running: false, done: done);
      if (embedder is LlamaEmbedder) {
        // Indexing is a burst; do not hold ~350 MB (about 1.5 GB with the
        // photo and audio projector) for the rest of the day.
        unawaited(embedder.release());
      }
    }
  }

  void cancel() => _cancel = true;

  /// Text passages embed as documents; a photo's first passage and every
  /// voice-note segment embed from the media when the projector is there,
  /// otherwise from their text like the rest.
  Future<List<Float32List>?> _embedChunks(
    TextEmbedder embedder,
    String collection,
    List<KnowledgeChunk> chunks,
  ) async {
    final docs = {
      for (final d
          in await ref.read(appDatabaseProvider).knowledgeDocsIn(collection))
        d.id: d,
    };
    final store = ref.read(knowledgeStoreProvider);
    final mediaReady = ref.read(modelManagerProvider).embeddingMediaReady;
    final out = List<Float32List?>.filled(chunks.length, null);
    final text = <int>[];
    for (var i = 0; i < chunks.length; i++) {
      if (_cancel || !ref.mounted) throw StateError('Indexing cancelled');
      final doc = docs[chunks[i].docId];
      List<File>? files;
      if (mediaReady && doc != null) {
        try {
          files = await store.mediaFor(
            doc,
            chunks[i],
            cancelled: () => _cancel || !ref.mounted,
          );
        } catch (_) {
          files = null; // An unreadable original falls back to its text.
        }
      }
      if (files == null) {
        text.add(i);
        continue;
      }
      try {
        final v = await embedder.embedMediaWithin([
          EmbedItem([for (final f in files) f.path]),
        ], () => _cancel || !ref.mounted);
        if (v == null) {
          text.add(i);
        } else {
          out[i] = v.first;
        }
      } finally {
        for (final f in files) {
          if (await f.exists()) await f.delete();
        }
      }
    }
    if (text.isNotEmpty) {
      final v = await embedder.embedDocumentsWithin([
        for (final i in text) chunks[i].content,
      ], () => _cancel || !ref.mounted);
      if (v == null) return null;
      for (var k = 0; k < text.length; k++) {
        out[text[k]] = v[k];
      }
    }
    return [for (final v in out) v!];
  }
}

final knowledgeIndexerProvider =
    NotifierProvider<KnowledgeIndexer, KnowledgeIndexState>(
      KnowledgeIndexer.new,
    );

/// Vectors present per document for the current embedding model; refreshed
/// as the document list changes and as the indexer advances.
final knowledgeIndexedProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(knowledgeDocsProvider);
  ref.watch(knowledgeIndexerProvider.select((s) => s.done));
  ref.watch(knowledgeIndexerProvider.select((s) => s.running));
  return ref
      .watch(appDatabaseProvider)
      .knowledgeIndexedCounts(ref.watch(textEmbedderProvider).modelId);
});
