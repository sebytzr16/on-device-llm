import 'dart:convert';

import '../../../data/network/web_search/search_models.dart';
import '../../retrieval/domain/evidence.dart';

/// Small steps of a web search turn: reading the judge and query
/// replies, merging pages into the sources, the second query.
class SearchSteps {
  const SearchSteps._();

  static bool parseYes(String raw) =>
      RegExp(r'^\W*yes\b', caseSensitive: false).hasMatch(
        raw.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim(),
      );

  /// Cleans model output into at most two usable queries.
  static List<String> parseQueries(String raw, {required String fallback}) {
    final text = raw.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true),
      '',
    );
    final out = <String>[];
    for (final line in text.split('\n')) {
      var q = line
          .trim()
          .replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s*'), '')
          .replaceAll(RegExp(r'^["\x27`]+|["\x27`]+$'), '')
          .trim();
      if (q.endsWith('?')) q = q.substring(0, q.length - 1);
      final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (words < 2 || words > 12 || q.length > 120) continue;
      if (q.toLowerCase().startsWith('query')) continue;
      if (out.any((e) => e.toLowerCase() == q.toLowerCase())) continue;
      out.add(q);
      if (out.length == 2) break;
    }
    return out.isEmpty ? [fallback] : out;
  }

  /// A URL without its scheme, `www.`/`m.`, trailing slashes or escapes,
  /// so the same page found twice is read once.
  static String urlKey(String url) {
    var u = url;
    try {
      u = Uri.decodeFull(url);
    } catch (_) {}
    return u
        .replaceFirst(RegExp(r'^https?://(www\.|m\.)?'), '')
        .replaceFirst('.m.wikipedia.org', '.wikipedia.org')
        .replaceFirst(RegExp(r'/+$'), '')
        .toLowerCase();
  }

  /// [sources] with Wikipedia's [article] after the pages that were read,
  /// unless a read page is that article already; an unread search result
  /// for it gives up its place. Ranks follow the new order.
  static List<SearchResult> withArticle(
    List<SearchResult> sources,
    SearchResult? article,
  ) {
    if (article == null) return sources;
    final same = urlKey(article.url);
    bool isIt(SearchResult s) =>
        urlKey(s.url) == same ||
        (s.finalUrl != null && urlKey(s.finalUrl!) == same);
    if (sources.any((s) => s.pageText != null && isIt(s))) return sources;
    final rest = [
      for (final s in sources)
        if (!isIt(s)) s,
    ];
    final read = rest.where((s) => s.pageText != null && !s.sponsored).length;
    return [
      for (final (i, s) in [
        ...rest.take(read),
        article,
        ...rest.skip(read),
      ].indexed)
        s.withRank(i + 1),
    ];
  }

  /// [added] pages after the pages already read, before the unread ones.
  static List<SearchResult> withExtraPages(
    List<SearchResult> sources,
    List<SearchResult> added,
  ) {
    final read = sources.where((s) => s.pageText != null && !s.sponsored);
    final rest = sources.where((s) => s.pageText == null || s.sponsored);
    return [
      for (final (i, s) in [...read, ...added, ...rest].indexed)
        s.withRank(i + 1),
    ];
  }

  /// The second query of a turn whose pages left [missing] words of
  /// [question] unanswered: the subject's names plus those words ("Nikon
  /// Z30 weight"). Null when no narrower query can be written (no subject,
  /// or nothing was answered at all: the pages were off-topic), in which
  /// case there is no second search.
  static String? searchAgainQuery(
    String question,
    List<String> missing, {
    List<String> subject = const [],
  }) {
    final asked = EvidenceRanker.terms(question).toSet();
    if (subject.isEmpty || missing.isEmpty) return null;
    if (missing.length >= asked.length) return null;
    final names = subject.join(' ');
    final lower = names.toLowerCase();
    final extra = [
      for (final w in missing)
        if (!lower.contains(w)) w,
    ];
    if (extra.isEmpty) return null;
    final query = '$names ${extra.join(' ')}';
    return query.toLowerCase() == question.trim().toLowerCase() ? null : query;
  }

  static double resultCoverage(String question, List<SearchResult> results) {
    final wanted = EvidenceRanker.terms(question).toSet();
    if (wanted.isEmpty) return 1;
    final seen = <String>{};
    for (final result in results.where((r) => !r.sponsored).take(4)) {
      seen.addAll(EvidenceRanker.terms('${result.title} ${result.snippet}'));
    }
    return seen.intersection(wanted).length / wanted.length;
  }

  static double queryTermOverlap(String literal, String planned) {
    final plannedTerms = EvidenceRanker.terms(planned).toSet();
    if (plannedTerms.isEmpty) return 1;
    final literalTerms = EvidenceRanker.terms(literal).toSet();
    return plannedTerms.intersection(literalTerms).length / plannedTerms.length;
  }

  /// Stored sources back into results, excerpts standing in for page text,
  /// so a comparison answer sees exactly what the original saw.
  static List<SearchResult> sourcesFromJson(String json) => [
    for (final s in (jsonDecode(json) as List).cast<Map>())
      SearchResult(
        title: s['title'] as String? ?? '',
        url: s['url'] as String? ?? '',
        snippet: s['snippet'] as String? ?? '',
        source: Uri.tryParse(s['url'] as String? ?? '')?.host,
        rank: (s['number'] as num?)?.toInt() ?? 0,
        pageText: s['excerpt'] as String?,
        finalUrl: s['finalUrl'] as String?,
        fetchedAt: DateTime.tryParse(s['fetchedAt'] as String? ?? ''),
        readError: s['readError'] as String?,
        publishedAt: DateTime.tryParse(s['publishedAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(s['updatedAt'] as String? ?? ''),
        stale: s['stale'] == true,
        sponsored: s['sponsored'] == true,
        outlet: s['outlet'] as String?,
        newsItem: s['newsItem'] == true,
        remembered: s['remembered'] == true,
        archiveDate: s['archiveDate'] as String?,
        archiveLanguage: s['archiveLanguage'] as String?,
        archiveId: s['archiveId'] as String?,
      ),
  ];
}
