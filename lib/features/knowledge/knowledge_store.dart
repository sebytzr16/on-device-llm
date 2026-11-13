import 'dart:typed_data';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

import '../../data/local/database/app_database.dart';
import '../../data/network/web_search/search_models.dart';
import '../attachments/domain/document_text.dart';
import '../attachments/data/attachment_store.dart';
import '../retrieval/domain/evidence.dart';
import '../attachments/data/on_device_ocr.dart';
import '../attachments/domain/scan_options.dart';
import '../models/domain/entities/model_catalog.dart';
import 'knowledge_embedder.dart';
import 'knowledge_media.dart';
import '../../core/l10n/l10n.dart';
import '../settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

/// Knowledge library (FX-02): documents imported once, split into passages
/// and retrieved for any later question — lexically (FTS5 bm25) and, once
/// passages carry vectors from the embedding model, by meaning too, the two
/// rankings fused with reciprocal rank fusion. Retrieval returns
/// [SearchResult]s so the chat's evidence prompt, fit loop, citation and
/// figure checks apply unchanged.
class KnowledgeStore {
  final AppDatabase _db;
  final TextEmbedder? _embedder;
  final Future<Directory> Function()? _originalDirectory;
  final String Function()? _locale;
  AppLocalizations get _t => stringsFor(_locale?.call() ?? '');
  const KnowledgeStore(
    this._db, [
    this._embedder,
    this._originalDirectory,
    this._locale,
  ]);

  Future<Directory?> _directory() async => _originalDirectory != null
      ? _originalDirectory()
      : AttachmentStore.directory();

  Future<File?> original(KnowledgeDoc doc) async {
    final name = doc.originalFile;
    final dir = await _directory();
    if (name == null ||
        dir == null ||
        !_safeFileName(name) ||
        !_safeFileName(doc.id)) {
      return null;
    }
    final file = File(p.join(dir.path, name));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    if (p.dirname(await file.resolveSymbolicLinks()) !=
        await dir.resolveSymbolicLinks()) {
      return null;
    }
    return file;
  }

  static bool _safeFileName(String name) =>
      RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name) &&
      name != '.' &&
      name != '..';

  Future<void> activate(KnowledgeDoc doc) => _db.transaction(() async {
    if (await (_db.select(
          _db.knowledgeDocs,
        )..where((t) => t.id.equals(doc.id))).getSingleOrNull() ==
        null) {
      throw StateError(_t.knowledgeVersionMissing);
    }
    await (_db.update(_db.knowledgeDocs)..where(
          (t) => t.collection.equals(doc.collection) & t.name.equals(doc.name),
        ))
        .write(const KnowledgeDocsCompanion(active: drift.Value(false)));
    await (_db.update(_db.knowledgeDocs)..where((t) => t.id.equals(doc.id)))
        .write(const KnowledgeDocsCompanion(active: drift.Value(true)));
  });

  static const scheme = 'knowledge';

  /// Reciprocal-rank-fusion constant (Cormack et al.): small enough that the
  /// top few of either list dominate, large enough that a passage found by
  /// both beats one found by only one.
  static const rrfK = 60;

  static Uint8List encodeVector(Float32List v) =>
      v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes);

  static double dot(Float32List a, Float32List b) {
    var s = 0.0;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  /// Scores a stored float32 vector without copying its blob for every query.
  static double dotBytes(Float32List query, Uint8List bytes) {
    if (bytes.lengthInBytes % 4 != 0) return 0;
    final n = query.length < bytes.lengthInBytes ~/ 4
        ? query.length
        : bytes.lengthInBytes ~/ 4;
    final aligned = bytes.offsetInBytes % 4 == 0;
    if (aligned) {
      final vector = Float32List.view(bytes.buffer, bytes.offsetInBytes, n);
      return dot(query, vector);
    }
    final view = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    var score = 0.0;
    for (var i = 0; i < n; i++) {
      score += query[i] * view.getFloat32(i * 4, Endian.host);
    }
    return score;
  }

  /// Fuses ranked id lists: score = Σ 1 / (k + rank), best first.
  static List<String> fuse(List<List<String>> rankings, {int k = rrfK}) {
    final scores = <String, double>{};
    for (final list in rankings) {
      for (var i = 0; i < list.length; i++) {
        scores[list[i]] = (scores[list[i]] ?? 0) + 1 / (k + i + 1);
      }
    }
    final ids = scores.keys.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return ids;
  }

  static Future<String> contentHash(Uint8List bytes) =>
      Isolate.run(() => sha256.convert(bytes).toString());

  /// Adds one file's text to [collection]. [pdfText] is the platform PDF
  /// extractor (null in tests). Photos and voice notes are kept too: their
  /// passages carry the photo's recognised text or the recording's time
  /// span, and the indexer embeds the media itself when the projector is
  /// on disk. [ocr], [audioSeconds] and [transcribe] replace the platform
  /// readers in tests.
  Future<KnowledgeDoc> import({
    required String collection,
    required String name,
    required Uint8List bytes,
    String mime = 'text/plain',
    Future<String> Function(Uint8List)? pdfText,
    Future<String> Function(File)? ocr,
    Future<double> Function(File)? audioSeconds,
    Future<String?> Function(File)? transcribe,
    Future<String?> Function(File)? transcribeSegment,
    Future<String?> Function(File)? caption,
    bool Function()? cancelled,
  }) async {
    final hash = await contentHash(bytes);
    if (cancelled?.call() == true) throw const ScanCancelled();
    final existing = await _db.knowledgeDocsIn(collection.trim());
    final duplicate = existing.where((d) => d.contentHash == hash).firstOrNull;
    if (duplicate != null) {
      if (!duplicate.active) await activate(duplicate);
      return duplicate.copyWith(active: true);
    }
    final id = const Uuid().v4();
    final directory = await _directory();
    final derived = directory == null
        ? null
        : File(p.join(directory.path, '$id.audio.wav'));
    final media = KnowledgeMedia.isImage(name) || KnowledgeMedia.isAudio(name);
    final extracted = media
        ? await _mediaText(
            name,
            bytes,
            ocr,
            audioSeconds,
            transcribe,
            transcribeSegment: transcribeSegment,
            caption: caption,
            derived: derived,
            cancelled: cancelled,
          )
        : await DocumentText.extract(
            bytes,
            name,
            pdfText: pdfText,
            localeCode: _locale?.call() ?? '',
            cancelled: cancelled,
          );
    if (cancelled?.call() == true) throw const ScanCancelled();
    if (extracted.text.trim().isEmpty) {
      throw FormatException(_t.documentNoText);
    }
    if (media) mime = KnowledgeMedia.mimeFor(name);
    final chunks = <({String text, int? page})>[];
    final pageMarks = name.toLowerCase().endsWith('.pdf')
        ? RegExp(
            r'^--- Page (\d+)(?: \([^\n]*\))? ---\s*$',
            multiLine: true,
          ).allMatches(extracted.text).toList()
        : const <RegExpMatch>[];
    final segments = RegExp(
      r'^--- Part (\d+) [^\n]* ---\s*$',
      multiLine: true,
    ).allMatches(extracted.text).toList();
    if (media && KnowledgeMedia.isAudio(name) && segments.isNotEmpty) {
      // One passage per recording segment: the indexer embeds segment N of
      // the audio for passage N, so the two must stay aligned.
      for (var i = 0; i < segments.length; i++) {
        if (cancelled?.call() == true) throw const ScanCancelled();
        chunks.add((
          text: extracted.text
              .substring(
                segments[i].start,
                i + 1 < segments.length
                    ? segments[i + 1].start
                    : extracted.text.length,
              )
              .trim(),
          page: null,
        ));
      }
    } else if (media) {
      // A photo's first passage stands for the photo itself (it gets the
      // image vector); recognised text beyond it is split as usual.
      final body = extracted.text;
      final parts = EvidenceRanker.chunkDocument(body, sourceIndex: 0);
      chunks.addAll(
        parts.isEmpty
            ? [(text: body, page: null)]
            : parts.map((c) => (text: c.text, page: null)),
      );
    } else if (pageMarks.isEmpty) {
      chunks.addAll(
        EvidenceRanker.chunkDocument(
          extracted.text,
          sourceIndex: 0,
        ).map((c) => (text: c.text, page: null)),
      );
    } else {
      for (var i = 0; i < pageMarks.length; i++) {
        if (cancelled?.call() == true) throw const ScanCancelled();
        final mark = pageMarks[i];
        final pageText = extracted.text.substring(
          mark.end,
          i + 1 < pageMarks.length
              ? pageMarks[i + 1].start
              : extracted.text.length,
        );
        chunks.addAll(
          EvidenceRanker.chunkDocument(
            pageText,
            sourceIndex: 0,
          ).map((c) => (text: c.text, page: int.parse(mark[1]!))),
        );
      }
    }
    File? savedOriginal;
    if (directory != null) {
      if (cancelled?.call() == true) throw const ScanCancelled();
      await directory.create(recursive: true);
      savedOriginal = File(p.join(directory.path, '$id.original'));
      final staged = File('${savedOriginal.path}.part');
      try {
        await staged.writeAsBytes(bytes, flush: true);
        await staged.rename(savedOriginal.path);
      } catch (_) {
        if (await staged.exists()) await staged.delete();
        if (derived != null && await derived.exists()) await derived.delete();
        rethrow;
      }
    }
    if (cancelled?.call() == true) throw const ScanCancelled();
    final doc = KnowledgeDocsCompanion.insert(
      id: id,
      collection: collection.trim(),
      name: name,
      mime: drift.Value(mime),
      sizeBytes: drift.Value(bytes.length),
      chars: drift.Value(extracted.text.length),
      chunkCount: drift.Value(chunks.length),
      addedAt: DateTime.now(),
      contentHash: drift.Value(hash),
      extractionFormat: drift.Value(extracted.format),
      extractionWarning: drift.Value(
        extracted.text.contains(OcrUnavailable.notice)
            ? _t.documentOcrUnavailable
            : extracted.text.contains('[Text recognition failed:')
            ? _t.documentTextRecognitionFailed
            : media &&
                  (extracted.text.contains('[Audio not transcribed]') ||
                      extracted.text.contains(
                        '[Photo has no caption or readable text]',
                      ))
            ? _t.documentMediaNotTranscribed
            : extracted.text.length >= DocumentText.maxChars
            ? _t.documentTextLimitReached
            : null,
      ),
      originalFile: drift.Value(
        savedOriginal == null ? null : p.basename(savedOriginal.path),
      ),
    );
    if (cancelled?.call() == true) throw const ScanCancelled();
    try {
      await _db.transaction(() async {
        final current = await _db.knowledgeDocsIn(collection.trim());
        final previous = current
            .where((d) => d.name == name && d.active)
            .firstOrNull;
        await (_db.update(_db.knowledgeDocs)..where(
              (t) =>
                  t.collection.equals(collection.trim()) & t.name.equals(name),
            ))
            .write(const KnowledgeDocsCompanion(active: drift.Value(false)));
        await _db.insertKnowledgeDoc(
          doc.copyWith(previousVersionId: drift.Value(previous?.id)),
          [
            for (final (ordinal, c) in chunks.indexed)
              KnowledgeChunksCompanion.insert(
                id: const Uuid().v4(),
                docId: id,
                ordinal: ordinal,
                content: c.text,
                pageNumber: drift.Value(c.page),
              ),
          ],
        );
      });
    } catch (_) {
      if (savedOriginal != null && await savedOriginal.exists()) {
        await savedOriginal.delete();
      }
      if (derived != null && await derived.exists()) await derived.delete();
      rethrow;
    }
    return (await _db.knowledgeDocsIn(
      collection.trim(),
    )).firstWhere((d) => d.id == id);
  }

  Future<ExtractedDocument> _mediaText(
    String name,
    Uint8List bytes,
    Future<String> Function(File)? ocr,
    Future<double> Function(File)? audioSeconds,
    Future<String?> Function(File)? transcribe, {
    Future<String?> Function(File)? transcribeSegment,
    Future<String?> Function(File)? caption,
    File? derived,
    bool Function()? cancelled,
  }) async {
    final dir = await Directory.systemTemp.createTemp('knowledge-import');
    final file = File(p.join(dir.path, 'source${p.extension(name)}'));
    File? wav;
    try {
      if (cancelled?.call() == true) throw const ScanCancelled();
      await file.writeAsBytes(bytes, flush: true);
      if (KnowledgeMedia.isImage(name)) {
        var text = '';
        var ocrNotice = '';
        try {
          text = (await (ocr ?? _platformOcr)(file)).trim();
        } catch (error) {
          ocrNotice = error is OcrUnavailable
              ? _t.documentOcrUnavailable
              : _t.documentOcrFailed('$error');
        }
        final description = (await caption?.call(file))?.trim() ?? '';
        return ExtractedDocument(
          'Photo: $name${ocrNotice.isEmpty ? '' : '\n[$ocrNotice]'}${text.isEmpty ? '' : '\nText in the photo:\n$text'}${description.isEmpty ? '' : '\nPhoto caption (model generated):\n$description'}${text.isEmpty && description.isEmpty ? '\n[Photo has no caption or readable text]' : ''}',
          'Photo',
        );
      }
      double seconds;
      if (audioSeconds == null) {
        final decoded = await KnowledgeMedia.decodeAudio(
          file,
          cancelled: cancelled,
        );
        wav = decoded.$1;
        seconds = decoded.$2;
      } else {
        seconds = await audioSeconds(file);
      }
      if (seconds <= 0) {
        throw FormatException(_t.knowledgeNoAudio);
      }
      // Per-part transcripts replace the whole one: both would put the
      // first part's words in twice and transcribe the recording twice.
      final segmented = wav != null && transcribeSegment != null;
      String? transcript;
      if (!segmented) {
        try {
          transcript = (await transcribe?.call(file))?.trim();
        } catch (e, st) {
          quietFailure('knowledge_store:404', e, st);
        }
      }
      const step = EmbeddingModel.mediaAudioSeconds;
      final parts = (seconds / step).ceil();
      final buffer = StringBuffer();
      for (var i = 0; i < parts; i++) {
        if (cancelled?.call() == true) throw const ScanCancelled();
        final end = ((i + 1) * step).clamp(0, seconds.ceil());
        buffer.writeln(
          '--- Part ${i + 1} (${KnowledgeMedia.clock(i * step)}–${KnowledgeMedia.clock(end)}) ---',
        );
        buffer.writeln('Voice note: $name');
        String? segmentText;
        if (segmented) {
          final segment = await KnowledgeMedia.wavSegment(wav, i);
          if (segment != null) {
            try {
              segmentText = (await transcribeSegment(segment))?.trim();
            } finally {
              if (await segment.exists()) await segment.delete();
            }
          }
        }
        if (segmentText?.isNotEmpty == true) {
          buffer.writeln('Transcript:\n$segmentText');
        } else if (transcript == null || transcript.isEmpty) {
          buffer.writeln('[Audio not transcribed]');
        }
        if (i == 0 && transcript != null && transcript.isNotEmpty) {
          buffer.writeln('Transcript:\n$transcript');
        }
      }
      if (derived != null && wav != null) {
        await derived.parent.create(recursive: true);
        await wav.copy('${derived.path}.part');
        await File('${derived.path}.part').rename(derived.path);
      }
      return ExtractedDocument(buffer.toString(), 'Voice note');
    } finally {
      if (wav != null && await wav.exists()) await wav.delete();
      await dir.delete(recursive: true);
    }
  }

  static Future<String> _platformOcr(File file) async =>
      (await OnDeviceOcr.recognize(file.path, await ScanOptions.read())).text;

  /// What the projector reads for passage [chunk] of a photo or voice note
  /// (null for other documents, or when the original is gone). The caller
  /// deletes the returned files.
  Future<List<File>?> mediaFor(
    KnowledgeDoc doc,
    KnowledgeChunk chunk, {
    bool Function()? cancelled,
  }) async {
    if (cancelled?.call() == true) throw const ScanCancelled();
    if (!KnowledgeMedia.isMediaMime(doc.mime)) return null;
    final file = await original(doc);
    if (file == null) return null;
    if (doc.mime.startsWith('image/')) {
      if (chunk.ordinal != 0) return null;
      return [await KnowledgeMedia.imageForEmbedding(await file.readAsBytes())];
    }
    final derived = File(p.join(file.parent.path, '${doc.id}.audio.wav'));
    File wav;
    if (await derived.exists()) {
      wav = derived;
    } else {
      final decoded = await KnowledgeMedia.decodeAudio(
        file,
        cancelled: cancelled,
      );
      try {
        await decoded.$1.rename(derived.path);
      } catch (_) {
        if (await decoded.$1.exists()) await decoded.$1.delete();
        rethrow;
      }
      wav = derived;
    }
    // The bounded derived WAV is reused across segments and index runs.
    final segment = await KnowledgeMedia.wavSegment(wav, chunk.ordinal);
    return segment == null ? null : [segment];
  }

  Future<void> remove(String docId) async {
    final doc = await (_db.select(
      _db.knowledgeDocs,
    )..where((t) => t.id.equals(docId))).getSingleOrNull();
    if (doc == null) return;
    final file = await original(doc);
    await _db.transaction(() async {
      await _db.deleteKnowledgeDoc(docId);
      if (doc.active) {
        final remaining = (await _db.knowledgeDocsIn(
          doc.collection,
        )).where((d) => d.name == doc.name).toList();
        if (remaining.isNotEmpty) await activate(remaining.first);
      }
    });
    if (file != null) await file.delete();
    // The derived WAV stays beside the original; remove it even when the
    // original is already gone (S13).
    final directory = file?.parent ?? await _directory();
    if (directory != null) {
      final derived = File(p.join(directory.path, '${doc.id}.audio.wav'));
      if (await derived.exists()) await derived.delete();
    }
  }

  Future<void> removeCollection(String c) async {
    for (final doc in await _db.knowledgeDocsIn(c)) {
      await remove(doc.id);
    }
  }

  Future<List<String>> collections() => _db.knowledgeCollections();
  Future<List<KnowledgeDoc>> docsIn(String c) => _db.knowledgeDocsIn(c);

  /// The best passages for [query] as sources: one per document, its
  /// matching passages joined in reading order, `knowledge://<docId>` as
  /// the URL so the chat can tell them from web pages.
  Future<List<SearchResult>> search(
    String collection,
    String query, {
    int maxPassages = 8,
    int maxDocs = 4,
  }) async {
    if (maxPassages <= 0 || maxDocs <= 0) return const [];
    final lexical = await _db.searchKnowledge(
      collection,
      query,
      limit: maxPassages * 2,
    );
    final hits = await _hybrid(collection, query, lexical, maxPassages * 2);
    if (hits.isEmpty) return const [];
    // Group by document, keep document order of first appearance (best first).
    final byDoc = <String, List<KnowledgeChunk>>{};
    final docs = <String, KnowledgeDoc>{};
    var taken = 0;
    for (final (chunk, doc) in hits) {
      if (!doc.active) continue;
      if (taken >= maxPassages) break;
      if (!byDoc.containsKey(doc.id) && byDoc.length >= maxDocs) continue;
      byDoc.putIfAbsent(doc.id, () => []).add(chunk);
      docs[doc.id] = doc;
      taken++;
    }
    var rank = 0;
    return [
      for (final e in byDoc.entries)
        SearchResult(
          title: docs[e.key]!.name,
          url: '$scheme://${e.key}',
          snippet: '',
          source: 'Knowledge · ${docs[e.key]!.collection}',
          rank: ++rank,
          pageText: (e.value..sort((a, b) => a.ordinal.compareTo(b.ordinal)))
              .map(
                (c) =>
                    '${c.pageNumber == null ? 'Passage ${c.ordinal + 1}' : 'Page ${c.pageNumber}'}\n${c.content}',
              )
              .join('\n[…]\n'),
          finalUrl: '$scheme://${e.key}',
          fetchedAt: docs[e.key]!.addedAt.toUtc(),
        ),
    ];
  }

  /// Lexical hits merged with the semantic ranking when the collection has
  /// vectors and the embedder can embed the question; otherwise the lexical
  /// list as it came. Never throws: a broken embedder degrades to bm25.
  Future<List<(KnowledgeChunk, KnowledgeDoc)>> _hybrid(
    String collection,
    String query,
    List<(KnowledgeChunk, KnowledgeDoc)> lexical,
    int limit,
  ) async {
    final embedder = _embedder;
    if (embedder == null) return lexical;
    List<(String, String, Uint8List)> indexed;
    final docs = {for (final (_, d) in lexical) d.id: d};
    Float32List q;
    try {
      // One documents read per search; vectors without their text.
      for (final d in await _db.knowledgeDocsIn(collection)) {
        docs[d.id] = d;
      }
      indexed = await _db.knowledgeVectors([
        for (final d in docs.values)
          if (d.active) d.id,
      ], embedder.modelId);
      if (indexed.isEmpty) return lexical;
      final vectors = await embedder.embedQueries([query]);
      if (vectors == null || vectors.isEmpty) return lexical;
      q = vectors.first;
    } catch (_) {
      return lexical;
    }
    // Move the O(N×D) vector scan off the UI isolate (audit A13).
    final semantic = await _scanVectors(indexed, q, limit);
    final byId = <String, KnowledgeChunk>{
      for (final (c, _) in lexical) c.id: c,
    };
    try {
      for (final c in await _db.knowledgeChunksByIds([
        for (final (_, id) in semantic)
          if (!byId.containsKey(id)) id,
      ])) {
        byId[c.id] = c;
      }
    } catch (_) {
      return lexical;
    }
    final order = fuse([
      [for (final (c, _) in lexical) c.id],
      [for (final (_, id) in semantic) id],
    ]);
    return [
      for (final id in order.take(limit))
        if (byId[id] case final c? when docs[c.docId] != null)
          (c, docs[c.docId]!),
    ];
  }

  /// Scans vectors in a background isolate to avoid blocking the UI thread.
  /// Returns top-[limit] (score, chunkId) pairs sorted by score descending.
  static Future<List<(double, String)>> _scanVectors(
    List<(String, String, Uint8List)> indexed,
    Float32List query,
    int limit,
  ) async {
    // Prepare sendable data for the isolate.
    final embeddings = <Float32List>[];
    final ids = <String>[];
    for (final (id, _, embedding) in indexed) {
      if (embedding.lengthInBytes == query.lengthInBytes) {
        ids.add(id);
        embeddings.add(Float32List.fromList(embedding.buffer.asFloat32List()));
      }
    }
    if (embeddings.isEmpty) return const [];
    final queryVec = Float32List.fromList(query.buffer.asFloat32List());
    return Isolate.run(
      () => _scanVectorsSync(embeddings, ids, queryVec, limit),
    );
  }

  static List<(double, String)> _scanVectorsSync(
    List<Float32List> embeddings,
    List<String> ids,
    Float32List query,
    int limit,
  ) {
    final semantic = <(double, String)>[];
    for (var i = 0; i < embeddings.length; i++) {
      final embedding = embeddings[i];
      final score = _dot(query, embedding);
      if (semantic.length >= limit && score <= semantic.last.$1) continue;
      var position = 0;
      while (position < semantic.length && semantic[position].$1 >= score) {
        position++;
      }
      semantic.insert(position, (score, ids[i]));
      if (semantic.length > limit) semantic.removeLast();
    }
    return semantic;
  }

  static double _dot(Float32List a, Float32List b) {
    double sum = 0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static bool isKnowledgeUrl(String url) => url.startsWith('$scheme://');
}

final knowledgeStoreProvider = Provider<KnowledgeStore>(
  (ref) => KnowledgeStore(
    ref.watch(appDatabaseProvider),
    ref.watch(textEmbedderProvider),
    null,
    () => ref.read(settingsProvider).localeCode,
  ),
);

final knowledgeDocsProvider = StreamProvider<List<KnowledgeDoc>>(
  (ref) => ref.watch(appDatabaseProvider).watchKnowledgeDocs(),
);
