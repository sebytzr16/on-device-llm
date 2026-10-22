import 'package:intl/intl.dart';

import '../../../data/network/web_search/search_models.dart';

/// When the pages behind an answer about something that changes (prices,
/// versions, figures) say they were last updated: the app adds it to the
/// answer rather than refusing an older page (tester, 2026-10-19).
class SourceDates {
  /// The sources [answer] cites ([n]), or every read one when it cites
  /// none. Live instant answers (weather) and news stories carry their own
  /// time and are left out.
  static List<SearchResult> cited(String answer, List<SearchResult> sources) {
    final numbers = {
      for (final m in _citation.allMatches(answer))
        for (final n in m[1]!.split(',')) int.tryParse(n.trim()),
    }.whereType<int>();
    final picked = numbers.isEmpty
        ? sources
        : [
            for (final n in numbers)
              if (n >= 1 && n <= sources.length) sources[n - 1],
          ];
    return [
      for (final s in picked)
        if (!s.sponsored &&
            !s.newsItem &&
            s.pageText != null &&
            Uri.tryParse(s.finalUrl ?? s.url)?.host != 'duckduckgo.com')
          s,
    ];
  }

  /// The newest stated date among [sources] (last update, else
  /// publication); null when none states one.
  static DateTime? newest(Iterable<SearchResult> sources) {
    DateTime? best;
    for (final s in sources) {
      final d = s.updatedAt ?? s.publishedAt;
      if (d != null && (best == null || d.isAfter(best))) best = d;
    }
    return best;
  }

  /// [date] as a long local date in [locale] ("October 19, 2026"), or
  /// 2026-10-19 when that locale's date names are not loaded.
  static String format(DateTime date, String locale) {
    final local = date.toLocal();
    try {
      return DateFormat.yMMMMd(locale).format(local);
    } catch (_) {
      return DateFormat('yyyy-MM-dd').format(local);
    }
  }

  /// Whether [answer] already says when its figures are from: a year or a
  /// month name (EN/FR/ES).
  static bool dated(String answer) => _date.hasMatch(answer);

  static final _citation = RegExp(r'\[(\d+(?:\s*,\s*\d+)*)\]');
  static final _date = RegExp(
    r'(?<![\p{L}\p{N}])(?:(?:19|20)\d\d|january|february|march|april|june|july|august|september|october|november|december|janvier|f[ée]vrier|avril|mai|juin|juillet|ao[ûu]t|septembre|octobre|novembre|d[ée]cembre|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
}
