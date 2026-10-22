import 'dart:math';
import 'dart:typed_data';

import '../knowledge/knowledge_embedder.dart';
import '../knowledge/knowledge_store.dart';
import 'domain/evidence.dart';

/// Web passages ranked by meaning as well as by words: the lexical (BM25)
/// shortlist is embedded with the knowledge library's embedding model and
/// the two orders are fused with reciprocal rank fusion, so a passage that
/// answers the question in other words (or another language) can beat one
/// that only repeats its terms.
///
/// Embedding is the phone's slowest step here (~0.4 s for a 1,000-character
/// passage on a Galaxy S25+), so complete bounded shortlisted passages
/// are embedded, best lexical first, until [budget] runs out; passages left
/// without a vector keep their lexical rank. Any failure returns the
/// lexical selection unchanged.
class SemanticRerank {
  /// Most evidence chunks fit in this window, including late table rows.
  static const headChars = 2400;

  static Future<List<EvidenceChunk>> rank(
    String query,
    List<EvidenceChunk> chunks, {
    required TextEmbedder? embedder,
    int perSource = 2,
    int maxChunks = 6,
    List<String> extraQueries = const [],
    Map<int, String> titles = const {},
    int candidates = 10,
    Duration budget = const Duration(milliseconds: 2500),
  }) async {
    List<EvidenceChunk> lexical() => EvidenceRanker.rank(
      query,
      chunks,
      perSource: perSource,
      maxChunks: maxChunks,
      extraQueries: extraQueries,
      titles: titles,
    );
    if (embedder == null || chunks.length <= 1) return lexical();
    // A wider shortlist than the final selection, so meaning can promote a
    // passage the words ranked just below the cut.
    final shortlist = EvidenceRanker.rank(
      query,
      chunks,
      perSource: perSource + 1,
      maxChunks: max(candidates, maxChunks),
      extraQueries: extraQueries,
      titles: titles,
    );
    final clock = Stopwatch()..start();
    bool expired() => clock.elapsed >= budget;
    final cosine = <EvidenceChunk, double>{};
    try {
      final q = await embedder
          .embedQueriesWithin([query], expired)
          .timeout(budget);
      if (q == null || q.isEmpty) return lexical();
      for (final c in shortlist) {
        final left = budget - clock.elapsed;
        if (left <= Duration.zero) break;
        final v = await passageVector(
          embedder,
          c.text,
          title: titles[c.sourceIndex],
          expired: expired,
        ).timeout(left);
        if (v == null) break;
        cosine[c] = KnowledgeStore.dot(q.first, v);
      }
    } catch (_) {
      // Timeout or a broken embedder: whatever was scored still counts.
    }
    if (cosine.isEmpty) return lexical();
    return select(
      fuse(shortlist, cosine),
      perSource: perSource,
      maxChunks: maxChunks,
    );
  }

  /// Experiment (2026-10-11), off unless set: the share of each selected
  /// passage's sentences kept by [trimSentences]. Set by the research eval
  /// (`EVAL_TRIM`), never by the app.
  static double? trimShare;

  /// What the last [trimSentences] did, for the research eval.
  static Map<String, int>? lastTrim;

  /// Provence-style pruning with the embedder the app already has: each
  /// passage's sentences are embedded and only the [trimShare] closest to
  /// the question are kept, in page order, with "…" where sentences were
  /// dropped. Passages under four sentences, or left when [budget] runs
  /// out, stay whole.
  static Future<List<EvidenceChunk>> trimSentences(
    String query,
    List<EvidenceChunk> chunks, {
    required TextEmbedder? embedder,
    Duration budget = const Duration(milliseconds: 3000),
  }) async {
    final share = trimShare;
    if (share == null || embedder == null || chunks.isEmpty) return chunks;
    final clock = Stopwatch()..start();
    bool expired() => clock.elapsed >= budget;
    var before = 0, after = 0, trimmed = 0;
    final out = <EvidenceChunk>[];
    Float32List? q;
    try {
      q = (await embedder.embedQueriesWithin([query], expired).timeout(budget))
          ?.first;
    } catch (_) {}
    for (final c in chunks) {
      before += c.text.length;
      final units = c.text
          .split(RegExp(r'(?<=[.!?])\s+|\n+'))
          .map((u) => u.trim())
          .where((u) => u.isNotEmpty)
          .toList();
      List<Float32List>? vs;
      if (q != null && units.length >= 4 && !expired()) {
        try {
          vs = await embedder
              .embedDocumentsWithin([
                for (final u in units) u.length > 400 ? u.substring(0, 400) : u,
              ], expired)
              .timeout(budget - clock.elapsed);
        } catch (_) {}
      }
      if (vs == null || vs.length != units.length) {
        out.add(c);
        after += c.text.length;
        continue;
      }
      final order = List.generate(units.length, (i) => i)
        ..sort(
          (a, b) => KnowledgeStore.dot(
            q!,
            vs![b],
          ).compareTo(KnowledgeStore.dot(q, vs[a])),
        );
      final keep = order.take((units.length * share).ceil()).toSet();
      final text = StringBuffer();
      var gap = false;
      for (var i = 0; i < units.length; i++) {
        if (!keep.contains(i)) {
          gap = true;
          continue;
        }
        if (text.isNotEmpty || gap) {
          text.write(text.isEmpty ? '… ' : (gap ? ' … ' : ' '));
        }
        text.write(units[i]);
        gap = false;
      }
      if (gap) text.write(' …');
      trimmed++;
      after += text.length;
      out.add(
        EvidenceChunk(
          sourceIndex: c.sourceIndex,
          ordinal: c.ordinal,
          text: text.toString(),
          score: c.score,
        ),
      );
    }
    lastTrim = {
      'chunks': chunks.length,
      'trimmed': trimmed,
      'charsBefore': before,
      'charsAfter': after,
      'ms': clock.elapsedMilliseconds,
    };
    return out;
  }

  /// Vectors of recently embedded passages, so the claim check after
  /// the answer reuses what ranking already paid for.
  static final _vectors = <String, Float32List>{};

  /// The vector of the bounded passage (cached).
  static Future<Float32List?> passageVector(
    TextEmbedder embedder,
    String text, {
    String? title,
    bool Function()? expired,
  }) async {
    final head = text.length <= headChars ? text : text.substring(0, headChars);
    final key = '${embedder.modelId}|${title ?? ''}|$head';
    final hit = _vectors.remove(key);
    if (hit != null) return _vectors[key] = hit;
    final v = await embedder.embedPassageWithin(
      head,
      title: title,
      expired: expired ?? () => false,
    );
    if (expired?.call() == true) return null;
    if (v == null) return null;
    _vectors[key] = v;
    while (_vectors.length > 96) {
      _vectors.remove(_vectors.keys.first);
    }
    return v;
  }

  /// [lexical] (best first) fused with the cosine order of the passages
  /// that have one: score = Σ 1 / (k + rank) over both lists.
  static List<EvidenceChunk> fuse(
    List<EvidenceChunk> lexical,
    Map<EvidenceChunk, double> cosine,
  ) {
    final semantic = cosine.keys.toList()
      ..sort((a, b) => cosine[b]!.compareTo(cosine[a]!));
    final ids = KnowledgeStore.fuse([
      [for (final c in lexical) _id(c)],
      [for (final c in semantic) _id(c)],
    ]);
    final byId = {for (final c in lexical) _id(c): c};
    // Context fitting must remove the tail of this fused order, rather
    // than reverting to the lexical score that preceded semantic ranking.
    return [
      for (final (rank, id) in ids.indexed)
        if (byId[id] case final c?)
          EvidenceChunk(
            sourceIndex: c.sourceIndex,
            ordinal: c.ordinal,
            text: c.text,
            score: 1 / (rank + 1),
          ),
    ];
  }

  /// The first [maxChunks] of [order] with at most [perSource] per page.
  static List<EvidenceChunk> select(
    List<EvidenceChunk> order, {
    required int perSource,
    required int maxChunks,
  }) {
    final taken = <int, int>{};
    final out = <EvidenceChunk>[];
    for (final c in order) {
      if (out.length >= maxChunks) break;
      if ((taken[c.sourceIndex] ?? 0) >= perSource) continue;
      taken[c.sourceIndex] = (taken[c.sourceIndex] ?? 0) + 1;
      out.add(c);
    }
    return out;
  }

  static String _id(EvidenceChunk c) => '${c.sourceIndex}:${c.ordinal}';
}
