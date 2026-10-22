import 'dart:math';

import '../../../core/utils/search_terms.dart';
import 'source_quality.dart';

/// A passage of one fetched page (roadmap WEB-05/06). [sourceIndex] is the
/// position in the chat's source list, [ordinal] the passage's position in
/// the page, so selected passages can be re-emitted in reading order.
class EvidenceChunk {
  final int sourceIndex, ordinal;
  final String text;
  double score;
  EvidenceChunk({
    required this.sourceIndex,
    required this.ordinal,
    required this.text,
    this.score = 0,
  });
}

/// Splits extracted page text into passages and ranks them lexically against
/// the question. Passage sizes are character heuristics (~4 chars/token); the
/// exact fit is still decided by the native tokenizer preview in the chat.
class EvidenceRanker {
  /// Roughly 250 model tokens: enough for a fact and its context, small
  /// enough that six passages prefill in a few seconds on a phone CPU.
  static const targetChars = 1000;
  static const maxChars = 1600;

  static const _stop = {
    'the',
    'a',
    'an',
    'and',
    'or',
    'of',
    'to',
    'in',
    'on',
    'for',
    'is',
    'are',
    'was',
    'were',
    'be',
    'it',
    'its',
    'this',
    'that',
    'with',
    'as',
    'by',
    'at',
    'from',
    'what',
    'which',
    'who',
    'how',
    'when',
    'where',
    'why',
    'does',
    'do',
    'did',
    'about',
    'i',
    'you',
    'we',
    'they',
    'he',
    'she',
    'my',
    'your',
    'me',
    'please',
    'tell',
    'can',
    'could',
    'would',
    'should',
    'has',
    'have',
    'had',
    'not',
    'no',
    'but',
    'if',
    'so',
    'than',
    'then',
    'there',
    'their',
    'them',
    'into',
    'over',
    'up',
    'out',
    'any',
    'some',
    'all',
    'more',
    'most',
    'also',
    'le',
    'la',
    'les',
    'un',
    'une',
    'des',
    'du',
    'de',
    'et',
    'ou',
    'en',
    'dans',
    'pour',
    'sur',
    'est',
    'sont',
    'avec',
    'que',
    'qui',
    'quoi',
    'comment',
    'quand',
    'où',
    'pourquoi',
    'ce',
    'cette',
    'ces',
    'mon',
    'ma',
    'mes',
    'votre',
    'vos',
  };

  /// Whether the pages read so far mention every substantive term of the
  /// question (web-research overhaul phase 1): once they do, reading more
  /// pages only costs time and prompt tokens on the phone. Questions with a
  /// single term are never "covered"; one page is too little to stop on.
  static bool covers(String query, Iterable<String> texts) {
    final wanted = terms(query).toSet();
    if (wanted.length < 2) return false;
    final seen = <String>{};
    for (final t in texts) {
      seen.addAll(terms(t));
      if (seen.containsAll(wanted)) return true;
    }
    return false;
  }

  /// Words of [query] that none of [texts] mention (stop words left out),
  /// lower-cased, in question order: what a second search should look for.
  static List<String> missingWords(String query, Iterable<String> texts) {
    final seen = <String>{for (final t in texts) ...terms(t)};
    final out = <String>[];
    for (final word in unicodeWords(query)) {
      final t = RegExp(r'^[a-z0-9]+$').hasMatch(word) ? stem(word) : word;
      if (t.length < 2 || _stop.contains(t) || seen.contains(t)) continue;
      if (!out.contains(word)) out.add(word);
    }
    return out;
  }

  static List<String> terms(String text) => unicodeWords(text, cjkBigrams: true)
      .map((word) => RegExp(r'^[a-z0-9]+$').hasMatch(word) ? stem(word) : word)
      .where((t) => t.length > 1 && !_stop.contains(t))
      .toList();

  /// Light suffix stripping so "versions"/"version" and "released"/"release"
  /// count as the same term. Deliberately conservative: only common English
  /// inflections on words long enough that the stem stays distinctive.
  static String stem(String t) {
    if (t.length <= 4 || RegExp(r'\d').hasMatch(t)) return t;
    if (t.endsWith('ies') && t.length > 5) {
      return '${t.substring(0, t.length - 3)}y';
    }
    if (t.endsWith('sses')) {
      t = t.substring(0, t.length - 2);
    } else if (t.endsWith('ing') && t.length > 6) {
      t = t.substring(0, t.length - 3);
    } else if (t.endsWith('ed') && t.length > 5) {
      t = t.substring(0, t.length - 2);
    } else if (t.endsWith('es') && t.length > 5) {
      t = t.substring(0, t.length - 2);
    } else if (t.endsWith('s') && !t.endsWith('ss') && !t.endsWith('us')) {
      t = t.substring(0, t.length - 1);
    }
    // "release"/"releas(ed)"/"releas(es)" meet at the same stem.
    if (t.endsWith('e') && t.length > 4) t = t.substring(0, t.length - 1);
    return t;
  }

  /// Questions whose answer is a figure: passages carrying digits get a
  /// small edge over prose that merely discusses the topic.
  static final _wantsFigure = RegExp(
    r'\b(version|latest|newest|release[ds]?|price|cost|how (?:much|many|old|tall|far|long)|when|date|year|population|revenue|percent|number|rate|score|temperature|speed|size|weight|height|distance)\b',
    caseSensitive: false,
  );

  /// How-to questions: passages that read as steps or commands (numbered
  /// lines, bullets, a shell prompt, a command with flags) get the same edge
  /// (web-research overhaul phase 5, answer shape).
  static final _wantsSteps = RegExp(
    r'\b(how (?:do|can|to|should) (?:i|you|we|one)?|steps?|install|configure|set ?up|enable|disable|migrate|deploy|tutorial|guide|instructions?|command)\b',
    caseSensitive: false,
  );

  static final _stepLine = RegExp(
    r'^(\d{1,2}[.)]\s|step \d|[-*•]\s|\$ |> |sudo |git |npm |pip |adb |cd |flutter |[a-z][a-z0-9-]+ [a-z][a-z0-9-]* --?[a-z])',
    caseSensitive: false,
  );

  static bool looksLikeSteps(String text) {
    var hints = 0;
    for (final line in text.split('\n')) {
      final l = line.trimLeft();
      if (l.isEmpty) continue;
      if (_stepLine.hasMatch(l) || l.contains('```')) hints++;
      if (hints >= 2) return true;
    }
    return false;
  }

  /// Orders search results before any page is read: DuckDuckGo's order,
  /// nudged by how well the title and snippet match the question and by
  /// what is known about the host (SourceQuality): established outlets,
  /// reference works and official sources lead near-ties; filler hosts
  /// (video, social feeds, headline aggregators) go to the end; hosts whose
  /// pages cannot be read without a browser (Reuters, paywalls, MSN
  /// mirrors) move down so the read budget goes to pages that yield text;
  /// front pages and section indexes, which extract to a few lines of
  /// links, move down unless [navigational].
  /// [recent] (a timely question) rewards results whose snippet carries a
  /// date from the last year and demotes ones older than three years, and
  /// weighs the publisher's standing more.
  static List<T> rankResults<T>(
    String query,
    List<T> results, {
    required String Function(T) titleOf,
    required String Function(T) snippetOf,
    required String Function(T) urlOf,
    bool recent = false,
    bool navigational = false,
    DateTime? now,
  }) {
    if (results.length < 2) return results;
    final q = terms(query).toSet();
    final today = now ?? DateTime.now().toUtc();
    final scored = <(double, int, T)>[];
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final url = urlOf(r);
      final t = terms(titleOf(r)).toSet(), sn = terms(snippetOf(r)).toSet();
      final overlap = q.isEmpty
          ? 0.0
          : (t.intersection(q).length * 1.5 + sn.intersection(q).length) /
                q.length;
      // Rank 1 keeps a clear lead unless a later result matches far better.
      var score = 1.0 / (i + 1) + 0.35 * overlap;
      if (SourceQuality.lowValue(url)) score -= 2;
      score += (recent ? 0.45 : 0.3) * SourceQuality.authority(url);
      if (SourceQuality.unreadable(url)) score -= 0.6;
      if (!navigational && SourceQuality.isFrontPage(url)) score -= 0.35;
      if (recent) {
        final dated = snippetDate(snippetOf(r), now: today);
        if (dated != null) {
          final age = today.difference(dated).inDays;
          if (age <= 365) {
            score += 0.35;
          } else if (age > 3 * 365) {
            score -= 0.25;
          }
        }
      }
      scored.add((score, i, r));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
    });
    return [for (final e in scored) e.$3];
  }

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'sept': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// A date at the start of a search snippet ("Mar 4, 2025 — …",
  /// "4 March 2025", "2025-03-04"), the way engines prefix dated pages.
  /// Null when there is none or it is in the future.
  static DateTime? snippetDate(String snippet, {DateTime? now}) {
    final head = snippet.trimLeft();
    if (head.isEmpty) return null;
    final window = head.substring(0, head.length.clamp(0, 40));
    DateTime? found;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(window);
    if (iso != null) {
      found = DateTime.tryParse('${iso.group(0)}T00:00:00Z');
    }
    final mdy = RegExp(
      r'^([A-Za-z]{3,9})\.? (\d{1,2}),? (\d{4})',
    ).firstMatch(window);
    if (found == null && mdy != null) {
      final m = _months[mdy.group(1)!.toLowerCase().substring(0, 3)];
      if (m != null) {
        found = DateTime.utc(
          int.parse(mdy.group(3)!),
          m,
          int.parse(mdy.group(2)!),
        );
      }
    }
    final dmy = RegExp(
      r'^(\d{1,2}) ([A-Za-z]{3,9})\.? (\d{4})',
    ).firstMatch(window);
    if (found == null && dmy != null) {
      final m = _months[dmy.group(2)!.toLowerCase().substring(0, 3)];
      if (m != null) {
        found = DateTime.utc(
          int.parse(dmy.group(3)!),
          m,
          int.parse(dmy.group(1)!),
        );
      }
    }
    if (found == null) return null;
    final today = now ?? DateTime.now().toUtc();
    if (found.isAfter(today.add(const Duration(days: 1))) ||
        found.year < 1990) {
      return null;
    }
    return found;
  }

  /// Merges the extractor's one-line-per-block text into passages of about
  /// [targetChars]; a single oversized block is split at sentence ends.
  /// Wikipedia-style reference markers. Left in, small models copy them as
  /// citations ("[5]") that point at nothing (seen in the Qwen evaluation).
  static final _refMarkers = RegExp(
    r'\[(?:\d{1,3}|[a-z]|[ivx]{1,4}|citation needed|note \d+|clarification needed|when\?|who\?)\]',
    caseSensitive: false,
  );

  static String stripReferenceMarkers(String text) =>
      text.replaceAll(_refMarkers, '');

  static List<EvidenceChunk> chunk(String text, {required int sourceIndex}) {
    text = stripReferenceMarkers(text);
    final out = <EvidenceChunk>[];
    final buffer = StringBuffer();
    void flush() {
      final t = buffer.toString().trim();
      if (t.isNotEmpty) {
        out.add(
          EvidenceChunk(sourceIndex: sourceIndex, ordinal: out.length, text: t),
        );
      }
      buffer.clear();
    }

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.length > maxChars) {
        flush();
        for (final piece in _splitLong(line)) {
          buffer.write(piece);
          flush();
        }
        continue;
      }
      if (buffer.length + line.length + 1 > targetChars && buffer.isNotEmpty) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(line);
    }
    flush();
    return out;
  }

  static Iterable<String> _splitLong(String line) sync* {
    final sentences = line.split(RegExp(r'(?<=[.!?])\s+'));
    final buffer = StringBuffer();
    for (final s in sentences) {
      if (buffer.length + s.length + 1 > targetChars && buffer.isNotEmpty) {
        yield buffer.toString();
        buffer.clear();
      }
      if (s.length > maxChars) {
        // No sentence boundary in sight: hard split.
        for (var i = 0; i < s.length; i += targetChars) {
          yield s.substring(i, min(s.length, i + targetChars));
        }
        continue;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(s);
    }
    if (buffer.isNotEmpty) yield buffer.toString();
  }

  /// BM25 over every passage of every source, then the best passages with at
  /// most [perSource] from any one page so a single long article cannot crowd
  /// out the others. Ties fall back to reading order, so a query that matches
  /// nothing still yields each page's opening passages. Near-duplicate
  /// passages (syndicated text) are kept once.
  static List<EvidenceChunk> rank(
    String query,
    List<EvidenceChunk> chunks, {
    int perSource = 2,
    int maxChunks = 6,
    List<String> extraQueries = const [],
    Map<int, String> titles = const {},
  }) {
    if (chunks.isEmpty) return const [];
    final q = terms(query).toSet();
    // Model-written search queries name the same fact in other words; they
    // widen the match without outweighing the user's own terms.
    final extra = <String>{
      for (final e in extraQueries) ...terms(e),
    }.difference(q);
    final wantsFigure = _wantsFigure.hasMatch(query);
    final wantsSteps = !wantsFigure && _wantsSteps.hasMatch(query);
    final docs = [for (final c in chunks) terms(c.text)];
    final avg = docs.fold<int>(0, (s, d) => s + d.length) / docs.length;
    final df = <String, int>{};
    for (final d in docs) {
      for (final t in d.toSet()) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    const k1 = 1.2, b = 0.75;
    final n = docs.length;
    for (var i = 0; i < chunks.length; i++) {
      final d = docs[i];
      if (d.isEmpty) {
        chunks[i].score = 0;
        continue;
      }
      final tf = <String, int>{};
      for (final t in d) {
        if (q.contains(t) || extra.contains(t)) tf[t] = (tf[t] ?? 0) + 1;
      }
      var score = 0.0;
      tf.forEach((t, f) {
        final idf = log(1 + (n - df[t]! + 0.5) / (df[t]! + 0.5));
        final weight = q.contains(t) ? 1.0 : 0.6;
        score +=
            weight *
            idf *
            (f * (k1 + 1)) /
            (f + k1 * (1 - b + b * d.length / avg));
      });
      // A page whose title already names the subject is more likely to be
      // about it than one that mentions the terms in passing.
      final title = titles[chunks[i].sourceIndex];
      if (score > 0 && title != null && q.isNotEmpty) {
        final hits = terms(title).toSet().intersection(q).length;
        score *= 1 + 0.25 * hits / q.length;
      }
      if (score > 0 && wantsFigure && RegExp(r'\d').hasMatch(chunks[i].text)) {
        score *= 1.1;
      }
      if (score > 0 && wantsSteps && looksLikeSteps(chunks[i].text)) {
        score *= 1.1;
      }
      chunks[i].score = score;
    }
    final order = [...chunks]
      ..sort((a, c) {
        final byScore = c.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final bySource = a.sourceIndex.compareTo(c.sourceIndex);
        return bySource != 0 ? bySource : a.ordinal.compareTo(c.ordinal);
      });
    final taken = <int, int>{};
    final seen = <String>{};
    final out = <EvidenceChunk>[];
    for (final c in order) {
      if (out.length >= maxChunks) break;
      if ((taken[c.sourceIndex] ?? 0) >= perSource) continue;
      final key = c.text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (!seen.add(key)) continue;
      taken[c.sourceIndex] = (taken[c.sourceIndex] ?? 0) + 1;
      out.add(c);
    }
    return out;
  }

  /// The selected passages of one source in reading order, separated so the
  /// model can see they are excerpts.
  static String excerpt(Iterable<EvidenceChunk> selected, int sourceIndex) {
    final own = selected.where((c) => c.sourceIndex == sourceIndex).toList()
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return own.map((c) => c.text).join('\n[…]\n');
  }

  /// Figures in [answer] — versions, dates, prices, counts — that occur in
  /// none of the [evidence] texts (roadmap §7.7: this is the mechanical part
  /// of claim support). Citation markers, list numbering and small counts
  /// are ignored; comparison is on digits and separators only.
  /// A measurement unit right after a figure.
  static final _unit = RegExp(
    r'^\s?(?:mp|megapixels?|mégapixels?|megapíxeles|mah|mm|cm|kg|g|grams?|grammes?|gramos|gb|tb|mb|fps|i/s|hz|ghz|mhz|wh|w|km|lbs?|oz|nits|ms|mph|km/h|ev|stops?)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static List<String> unsupportedFigures(
    String answer,
    Iterable<String> evidence,
  ) {
    final haystack = evidence
        .map((e) => e.toLowerCase().replaceAll(',', ''))
        .join('\n');
    final body = answer
        .replaceAll(RegExp(r'\[\d+(?:\s*,\s*\d+)*\]'), ' ')
        .replaceAll(RegExp(r'^\s*\d+[.)]\s', multiLine: true), ' ')
        .replaceAll(RegExp(r'^#+\s', multiLine: true), ' ');
    final figures = RegExp(
      r'(?<![\w.])(?:v(?=\d))?\d[\d,]*(?:\.\d+)*%?(?![\w])',
    );
    final missing = <String>[];
    for (final m in figures.allMatches(body)) {
      var f = m.group(0)!.replaceFirst(RegExp(r'^v'), '').replaceAll(',', '');
      if (f.endsWith('%')) f = f.substring(0, f.length - 1);
      final digits = f.replaceAll(RegExp(r'\D'), '');
      // Single digits and small counts read as prose ("2 of the 3 sources"),
      // unless a unit follows: "21 MP" for a sensor the sources give as
      // 20.9 megapixels is a rounded figure, not prose (device run
      // 2026-10-01).
      if (!_unit.hasMatch(body.substring(m.end))) {
        if (digits.length < 2) continue;
        if (digits.length <= 2 && !f.contains('.') && int.parse(digits) <= 31) {
          continue;
        }
      }
      // A full stop after the figure ends the sentence ("It costs $699.");
      // only a decimal part makes it another number.
      final exact = RegExp(
        '(?<![\\d.])${RegExp.escape(f.toLowerCase())}(?!\\d|\\.\\d)',
      );
      if (exact.hasMatch(haystack) || missing.contains(f)) continue;
      // A major/minor family can be supported by a more precise version,
      // but never shorten a claimed patch version to excuse a mismatch.
      if (f.split('.').length == 2 &&
          RegExp(
            '(?<![\\d.])${RegExp.escape(f)}\\.\\d+(?!\\d)',
          ).hasMatch(haystack)) {
        continue;
      }
      missing.add(f);
    }
    return missing;
  }
}
