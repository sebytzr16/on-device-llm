import 'dart:typed_data';

import '../../data/network/web_search/search_models.dart';
import '../../l10n/app_localizations.dart';
import '../knowledge/knowledge_embedder.dart';
import 'domain/claim_check.dart';
import 'semantic_rerank.dart';
import 'support_check.dart';

/// Runs [ClaimCheck] over an answer and its sources. Sentences that share
/// few words with every source are also compared by meaning (passage
/// vectors come from the ranking cache when the same passages were ranked),
/// within [budget]; without the embedding model the lexical verdict stands.
/// With the source-check model ([judge]), sentences still not placed are
/// asked against their closest passages within [judgeBudget].
class ClaimCheckRunner {
  /// Sentences the source-check model is asked about, at most.
  static const judged = 3;

  /// Sentences the word check placed ("supported") that the model reads
  /// too, weakest word match first: right words in a wrong claim.
  static const confirmed = 3;

  static Future<List<ClaimVerdict>> run(
    String answer,
    List<SearchResult> sources, {
    TextEmbedder? embedder,
    SupportJudge? judge,
    Duration budget = const Duration(seconds: 2),
    Duration judgeBudget = const Duration(seconds: 6),
  }) async {
    final verdicts = await _byMeaning(
      answer,
      sources,
      embedder: embedder,
      budget: budget,
    );
    if (judge == null) return verdicts;
    return _judged(verdicts, sources, judge, judgeBudget);
  }

  /// Uncertain and off-source sentences become supported when the model is
  /// sure a passage states them; anything else keeps its verdict. A
  /// sentence the word check placed is read against its passage too, and
  /// is flagged when the model finds that passage does not state it
  /// (support below [SupportCheck.unbacked]).
  static Future<List<ClaimVerdict>> _judged(
    List<ClaimVerdict> verdicts,
    List<SearchResult> sources,
    SupportJudge judge,
    Duration budget,
  ) async {
    final asked = [
      for (var i = 0; i < verdicts.length; i++)
        if (verdicts[i].status == ClaimStatus.uncertain ||
            verdicts[i].status == ClaimStatus.offSource)
          i,
    ].take(judged).toList();
    final placed = [
      for (var i = 0; i < verdicts.length; i++)
        if (verdicts[i].status == ClaimStatus.supported &&
            verdicts[i].support == null)
          i,
    ]..sort((a, b) => verdicts[a].share.compareTo(verdicts[b].share));
    final checked = placed.take(confirmed).toSet();
    if (asked.isEmpty && checked.isEmpty) return verdicts;
    final clock = Stopwatch()..start();
    bool expired() => clock.elapsed >= budget;
    final pairs = <({String claim, String passage})>[];
    final owners = <({int verdict, int source, String passage})>[];
    for (final i in asked) {
      for (final w in SupportCheck.windows(verdicts[i].sentence, sources)) {
        pairs.add((claim: verdicts[i].sentence, passage: w.passage));
        owners.add((verdict: i, source: w.source, passage: w.passage));
      }
    }
    // After the doubtful ones, so the budget never starves them.
    for (final i in checked) {
      final v = verdicts[i];
      final span = v.span;
      if (span != null && span.trim().isNotEmpty && v.source != null) {
        final passage = span.length > SupportCheck.maxPassage
            ? span.substring(0, SupportCheck.maxPassage)
            : span;
        pairs.add((claim: v.sentence, passage: passage));
        owners.add((verdict: i, source: v.source!, passage: passage));
        continue;
      }
      final w = SupportCheck.windows(v.sentence, sources, take: 1);
      if (w.isEmpty) continue;
      pairs.add((claim: v.sentence, passage: w.first.passage));
      owners.add((
        verdict: i,
        source: w.first.source,
        passage: w.first.passage,
      ));
    }
    List<double>? scores;
    try {
      scores = await judge.judge(pairs, expired: expired).timeout(budget);
    } catch (_) {
      // Best effort: the word check's verdicts stand.
    }
    if (scores == null || scores.isEmpty) return verdicts;
    final out = [...verdicts];
    final best = <int, double>{};
    for (var k = 0; k < scores.length; k++) {
      final o = owners[k];
      final p = scores[k];
      if (p > (best[o.verdict] ?? -1)) best[o.verdict] = p;
      final v = out[o.verdict];
      if (checked.contains(o.verdict) || v.status == ClaimStatus.supported) {
        continue;
      }
      if (p >= SupportCheck.supports) {
        out[o.verdict] = ClaimVerdict(
          v.sentence,
          ClaimStatus.supported,
          source: o.source,
          share: v.share,
          cosine: v.cosine,
          span: o.passage,
          support: p,
        );
      }
    }
    for (final e in best.entries) {
      final v = out[e.key];
      if (checked.contains(e.key)) {
        // Read by the model: kept when it agrees or is unsure, flagged
        // (uncertain, with the score) when it finds the passage does not
        // say it.
        out[e.key] = ClaimVerdict(
          v.sentence,
          e.value < SupportCheck.unbacked
              ? ClaimStatus.uncertain
              : ClaimStatus.supported,
          source: v.source,
          share: v.share,
          cosine: v.cosine,
          details: v.details,
          span: v.span,
          conflict: v.conflict,
          support: e.value,
        );
        continue;
      }
      if (v.status == ClaimStatus.supported) continue;
      out[e.key] = ClaimVerdict(
        v.sentence,
        v.status,
        source: v.source,
        share: v.share,
        cosine: v.cosine,
        details: v.details,
        span: v.span,
        conflict: v.conflict,
        support: e.value,
      );
    }
    return out;
  }

  static Future<List<ClaimVerdict>> _byMeaning(
    String answer,
    List<SearchResult> sources, {
    TextEmbedder? embedder,
    required Duration budget,
  }) async {
    final texts = [
      for (final s in sources)
        '${s.title}\n${s.snippet}\n${s.pageText ?? ''}\n${s.source}\n${Uri.tryParse(s.url)?.host ?? ''}',
    ];
    final sentences = ClaimCheck.sentences(answer);
    if (sentences.isEmpty || texts.isEmpty) return const [];
    final lexical = ClaimCheck.check(sentences, texts);
    final doubtful = [
      for (var i = 0; i < lexical.length; i++)
        if (lexical[i].status == ClaimStatus.offSource ||
            lexical[i].status == ClaimStatus.uncertain)
          i,
    ];
    if (embedder == null || doubtful.isEmpty) return lexical;
    final clock = Stopwatch()..start();
    bool expired() => clock.elapsed >= budget;
    final passages = <Float32List>[];
    final cosines = List<double?>.filled(sentences.length, null);
    try {
      final q = await embedder
          .embedQueriesWithin([for (final i in doubtful) sentences[i]], expired)
          .timeout(budget);
      if (q == null) return lexical;
      for (final s in sources) {
        final parts = (s.pageText?.isNotEmpty == true ? s.pageText! : s.snippet)
            .split('\n[…]\n')
            .where((p) => p.trim().isNotEmpty);
        for (final part in parts) {
          final left = budget - clock.elapsed;
          if (left <= Duration.zero) break;
          final v = await SemanticRerank.passageVector(
            embedder,
            part,
            title: s.title,
            expired: expired,
          ).timeout(left);
          if (v != null) passages.add(v);
        }
      }
      if (passages.isEmpty) return lexical;
      for (var k = 0; k < doubtful.length; k++) {
        cosines[doubtful[k]] = ClaimCheck.best(q[k], passages);
      }
    } catch (_) {
      if (passages.isEmpty) return lexical;
    }
    return ClaimCheck.check(sentences, texts, cosines: cosines);
  }

  /// The answer notice for flagged sentences; null when none is flagged.
  /// An uncertain sentence (words spread over passages) is flagged only
  /// when the source-check model read it and did not confirm it; the word
  /// check alone flags contradictions, names the sources lack and
  /// sentences far from every source (tester, 2026-10-19).
  static String? notice(List<ClaimVerdict> verdicts, AppLocalizations t) {
    final flagged = verdicts
        .where(
          (v) =>
              v.status != ClaimStatus.supported &&
              (v.status != ClaimStatus.uncertain || v.support != null),
        )
        .toList();
    if (flagged.isEmpty) return null;
    String quote(ClaimVerdict v) {
      final s = v.sentence.length <= 80
          ? v.sentence
          : '${v.sentence.substring(0, 77).trimRight()}…';
      return v.details.isEmpty
          ? '“$s”'
          : '“$s” (${t.noticeClaimsNames(v.details.join(', '))})';
    }

    return t.noticeClaimsNotInSources(
      flagged.take(2).map(quote).join('; '),
      flagged.length > 2 ? t.noticeAndMore(flagged.length - 2) : '',
    );
  }
}
