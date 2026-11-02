import 'dart:math' as math;

import '../../knowledge/knowledge_embedder.dart';
import '../../knowledge/document_embedding_cache.dart';
import '../../knowledge/knowledge_store.dart';
import '../../retrieval/domain/evidence.dart';

/// Keeps the parts of a long attachment that answer a focused question.
/// The complete extracted text remains stored with the attachment, so a later
/// question can choose different passages without re-reading the file.
class DocumentPassages {
  static const minChars = 12000;
  static const maxPassages = 8;

  static String select(String text, String question) {
    if (text.length < minChars || !_isQuestion(question)) return text;
    final query = EvidenceRanker.terms(question);
    if (query.isEmpty) return text;
    final chunks = EvidenceRanker.chunk(text, sourceIndex: 0);
    final ranked = EvidenceRanker.rank(
      question,
      chunks,
      perSource: maxPassages,
      maxChunks: maxPassages,
    );
    // A query with no lexical match needs broader context; the ordinary
    // tokenizer-based fit will handle that case.
    if (ranked.isEmpty || ranked.first.score <= 0) return text;
    final ordered = ranked.toList()
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return '[Selected passages from the attached file; other sections omitted. '
        'Ask a follow-up to inspect a different part.]\n'
        '${ordered.map((c) => '[Passage ${c.ordinal + 1}]\n${c.text}').join('\n[…]\n')}';
  }

  /// Keeps the passages of [text] that best match [request] within
  /// [maxChars], in document order, always with the opening passage (title
  /// and introduction). [embedder] (EmbeddingGemma) ranks by meaning; without
  /// it, or when it fails, the passages are ranked by shared words. Used when
  /// a file is longer than the context, instead of keeping only its start.
  static Future<({String text, int kept, int total})> fit(
    String text,
    String request,
    int maxChars, {
    TextEmbedder? embedder,
    DocumentEmbeddingCache? cache,
  }) async {
    final chunks = EvidenceRanker.chunk(text, sourceIndex: 0);
    if (chunks.length < 2) {
      final cut = text.substring(0, math.min(text.length, maxChars));
      return (text: cut, kept: 1, total: 1);
    }
    final scores =
        await _semantic(chunks, request, embedder, cache ?? _cache) ??
        _lexical(chunks, request);
    final order = [for (var i = 1; i < chunks.length; i++) i]
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final keep = <int>{0};
    var used = chunks[0].text.length;
    for (final i in order) {
      final size = chunks[i].text.length + 32;
      if (used + size > maxChars) continue;
      keep.add(i);
      used += size;
    }
    final kept = keep.toList()..sort();
    final out = StringBuffer(
      '[Selected passages from the attached file: ${kept.length} of '
      '${chunks.length}, the ones closest to the request; the rest did not '
      'fit the context.]\n',
    );
    for (var k = 0; k < kept.length; k++) {
      if (k > 0) out.write(kept[k] == kept[k - 1] + 1 ? '\n' : '\n[…]\n');
      out.write(chunks[kept[k]].text);
    }
    return (text: out.toString(), kept: kept.length, total: chunks.length);
  }

  static final _cache = DocumentEmbeddingCache();

  static Future<List<double>?> _semantic(
    List<EvidenceChunk> chunks,
    String request,
    TextEmbedder? embedder,
    DocumentEmbeddingCache cache,
  ) async {
    if (embedder == null || request.trim().isEmpty) return null;
    try {
      final texts = [for (final c in chunks) c.text];
      final vectors = await cache.vectors(
        embedder.modelId,
        texts,
        () => embedder.embedDocuments(texts),
      );
      if (vectors == null) return null;
      final query = await embedder.embedQueries([request]);
      if (query == null || query.isEmpty) return null;
      return [for (final v in vectors) KnowledgeStore.dot(query.first, v)];
    } catch (_) {
      return null;
    }
  }

  static List<double> _lexical(List<EvidenceChunk> chunks, String request) {
    final scores = List<double>.filled(chunks.length, 0);
    for (final c in EvidenceRanker.rank(
      request,
      chunks,
      perSource: chunks.length,
      maxChunks: chunks.length,
    )) {
      scores[c.ordinal] = c.score;
    }
    return scores;
  }

  static bool _isQuestion(String input) {
    final text = input.trim();
    if (text.isEmpty) return false;
    // Broad tasks need the document as a whole, including its introduction
    // and conclusions. Selection is for locating a specific answer.
    if (RegExp(
      r'\b(summari[sz]e|overview|outline|review|translate|rewrite|compare the (?:whole|entire)|entire document|whole document)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return false;
    }
    return text.contains('?') ||
        RegExp(
          r'^(what|which|who|when|where|why|how|find|locate|identify|explain)\b',
          caseSensitive: false,
        ).hasMatch(text);
  }
}
