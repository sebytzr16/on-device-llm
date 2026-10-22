import 'life_dates.dart';

/// Where the dates around a question fall relative to today, computed by
/// the app for the evidence prompt. Qwen3.5 0.8B has the clock line and
/// still answers from sources as if the calendar did not exist (D1
/// benchmark, 2026-10-11): "the next total solar eclipse visible from
/// Spain is on August 12, 2026" two months after it happened, a closing
/// price "on 3 March 2043" copied from a 2026 table, and "the weather in
/// Toronto on 1 January 2031 will be hot and dry". Like the age line, the
/// note states the arithmetic so the model only has to follow it.
class DateCheck {
  static const _months = {
    'january': 1,
    'february': 2,
    'march': 3,
    'april': 4,
    'may': 5,
    'june': 6,
    'july': 7,
    'august': 8,
    'september': 9,
    'october': 10,
    'november': 11,
    'december': 12,
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'sept': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
    'janvier': 1,
    'février': 2,
    'fevrier': 2,
    'mars': 3,
    'avril': 4,
    'mai': 5,
    'juin': 6,
    'juillet': 7,
    'août': 8,
    'aout': 8,
    'septembre': 9,
    'octobre': 10,
    'novembre': 11,
    'décembre': 12,
    'decembre': 12,
    'enero': 1,
    'febrero': 2,
    'marzo': 3,
    'abril': 4,
    'mayo': 5,
    'junio': 6,
    'julio': 7,
    'agosto': 8,
    'septiembre': 9,
    'setiembre': 9,
    'octubre': 10,
    'noviembre': 11,
    'diciembre': 12,
  };

  // Longest names first, so "sept" is not read as "sep" + "t".
  static final _monthWord =
      '(${(_months.keys.toList()..sort((a, b) => b.length - a.length)).join('|')})\\.?';

  // \b is ASCII-only in Dart; letter lookarounds keep "août" and "mai"
  // whole and stop "mar" matching inside "marzo" or "Omar".
  static const _l = '(?<![\\p{L}])';
  static const _r = '(?![\\p{L}])';

  /// "March 3, 2043", "March 3rd 2043".
  static final _monthDayYear = RegExp(
    '$_l$_monthWord$_r\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})(?!\\d)',
    caseSensitive: false,
    unicode: true,
  );

  /// "3 March 2043", "1er janvier 2031", "1 de enero de 2031".
  static final _dayMonthYear = RegExp(
    '(?<!\\d)(\\d{1,2})(?:er|st|nd|rd|th|º|°)?\\s+(?:de\\s+)?$_monthWord$_r\\s+(?:de\\s+|del\\s+)?(\\d{4})(?!\\d)',
    caseSensitive: false,
    unicode: true,
  );

  /// "2031-01-01".
  static final _iso = RegExp(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)');

  /// "March 2043", "mars 2043", "marzo de 2043": a month, no day.
  static final _monthYear = RegExp(
    '$_l$_monthWord$_r\\s+(?:de\\s+|del\\s+)?(\\d{4})(?!\\d)',
    caseSensitive: false,
    unicode: true,
  );

  // A sentence may end on the year ("…in 2030."), but "2030.5" is no year.
  static final _year = RegExp(r'(?<![\d.,/-])(1\d{3}|2\d{3})(?![\d,/-]|\.\d)');

  /// A year on its own counts only in a question about an outcome: "Who
  /// will win the 2034 World Cup?" is unknowable, "What is Agenda 2030?"
  /// is not.
  static final _outcome = RegExp(
    r"\b(?:will|going to|win|wins|winner|won|result|score|price|weather|forecast)\b|gagner|gagnera|vainqueur|résultat|prix|météo|ganar[áa]?|ganador|resultado|precio|tiempo|clima",
    caseSensitive: false,
  );

  /// A question that asks for the next or upcoming occurrence.
  static final _asksNext = RegExp(
    '$_l(?:next|upcoming|prochaine?s?|pr[óo]xim[oa]s?|siguientes?)$_r',
    caseSensitive: false,
    unicode: true,
  );
  static final _asksWhen = RegExp(
    '$_l(?:when|date|dates|what day|quand|cu[áa]ndo|fecha|fechas)$_r',
    caseSensitive: false,
    unicode: true,
  );

  static DateTime? _date(int year, int? month, int day) {
    if (month == null || month < 1 || month > 12) return null;
    if (day < 1 || day > 31 || year < 1000) return null;
    final d = DateTime(year, month, day);
    return d.month == month ? d : null;
  }

  /// Full dates (day, month and year) in [text], in order of appearance.
  static List<DateTime> fullDates(String text) {
    final found = <(int, DateTime)>[];
    for (final m in _monthDayYear.allMatches(text)) {
      final d = _date(
        int.parse(m[3]!),
        _months[m[1]!.toLowerCase()],
        int.parse(m[2]!),
      );
      if (d != null) found.add((m.start, d));
    }
    for (final m in _dayMonthYear.allMatches(text)) {
      final d = _date(
        int.parse(m[3]!),
        _months[m[2]!.toLowerCase()],
        int.parse(m[1]!),
      );
      if (d != null) found.add((m.start, d));
    }
    for (final m in _iso.allMatches(text)) {
      final d = _date(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      if (d != null) found.add((m.start, d));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }

  static String _isoDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _span(DateTime from, DateTime to) {
    final days = to.difference(from).inDays;
    if (days < 60) return '$days days';
    final months = (to.year - from.year) * 12 + to.month - from.month;
    if (months < 24) return '$months months';
    return '${LifeDates.ageOn(from, to)} years';
  }

  /// The first date the question names that lies after [now], as written
  /// and as the first day it covers; null when none does.
  static (String, DateTime)? _futureInQuestion(String question, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final taken = <(int, int)>[];
    bool overlaps(Match m) => taken.any((t) => m.start < t.$2 && t.$1 < m.end);
    (String, DateTime)? first;
    void consider(Match m, DateTime? d) {
      if (d == null || overlaps(m)) return;
      taken.add((m.start, m.end));
      if (d.isAfter(today) && (first == null)) first = (m[0]!, d);
    }

    for (final m in _monthDayYear.allMatches(question)) {
      consider(
        m,
        _date(int.parse(m[3]!), _months[m[1]!.toLowerCase()], int.parse(m[2]!)),
      );
    }
    for (final m in _dayMonthYear.allMatches(question)) {
      consider(
        m,
        _date(int.parse(m[3]!), _months[m[2]!.toLowerCase()], int.parse(m[1]!)),
      );
    }
    for (final m in _iso.allMatches(question)) {
      consider(m, _date(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
    }
    for (final m in _monthYear.allMatches(question)) {
      final month = _months[m[1]!.toLowerCase()];
      final d = month == null ? null : DateTime(int.parse(m[2]!), month, 1);
      // A month counts from its first day, but the current month is not
      // the future.
      if (d != null && !(d.year == today.year && d.month == today.month)) {
        consider(m, d);
      } else if (d != null) {
        taken.add((m.start, m.end));
      }
    }
    if (_outcome.hasMatch(question)) {
      for (final m in _year.allMatches(question)) {
        final year = int.parse(m[1]!);
        // "2500 shares" is a count, not a year.
        if (year > today.year + 30) continue;
        if (year > today.year) {
          consider(m, DateTime(year));
        } else {
          taken.add((m.start, m.end));
        }
      }
    }
    return first;
  }

  /// The answer to a "when is the next…" question gives, as its first full
  /// date, one that has already passed: Qwen3.5 0.8B answered the next
  /// total solar eclipse in Spain with "August 12, 2026" in October 2026,
  /// with the date note in its prompt (speed set, 2026-10-20).
  static bool passedNext(String answer, String question, DateTime now) {
    if (!_asksNext.hasMatch(question) || !_asksWhen.hasMatch(question)) {
      return false;
    }
    final dates = fullDates(answer);
    return dates.isNotEmpty &&
        dates.first.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// The note for the evidence prompt, or null when there is nothing to
  /// say. [texts] are the sources in citation order. It goes last, after
  /// the instructions: the phone run of 2026-10-11 showed the 0.8B model
  /// reading a note placed before the question and answering past it.
  static String? note(List<String> texts, String question, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final lines = <String>[];
    final future = _futureInQuestion(question, now);
    if (future != null) {
      lines.add(
        '"${future.$1}" is in the future, ${_span(today, future.$2)} after '
        'today, so what happens then cannot be known yet. Start your answer '
        'by saying so. After that, give only a forecast or prediction the '
        'sources state for that date, and call it a forecast; never give a '
        'figure from another date as its result.',
      );
    }
    if (future == null &&
        _asksNext.hasMatch(question) &&
        _asksWhen.hasMatch(question)) {
      // Small models pick a date far better than they compare dates, so
      // the app sorts the sources' dates into passed and still ahead.
      final past = <DateTime, Set<int>>{};
      final ahead = <DateTime, Set<int>>{};
      for (var i = 0; i < texts.length; i++) {
        for (final d in fullDates(texts[i])) {
          ((d.isBefore(today) ? past : ahead)[d] ??= {}).add(i + 1);
        }
      }
      String listed(Map<DateTime, Set<int>> dates, {required bool newest}) {
        final sorted = dates.keys.toList()
          ..sort((a, b) => newest ? b.compareTo(a) : a.compareTo(b));
        return [
          for (final d in sorted.take(3))
            '${_isoDay(d)} ${dates[d]!.map((n) => '[$n]').join('')}',
        ].join(', ');
      }

      if (past.isNotEmpty) {
        lines.add(
          'These dates in the sources have already passed, so none of them '
          'is the next one: ${listed(past, newest: true)}.',
        );
        lines.add(
          ahead.isEmpty
              ? 'No date in the sources is after today: say the sources do '
                    'not give the next date.'
              : 'Dates in the sources still ahead: '
                    '${listed(ahead, newest: false)}. Answer with the first '
                    'of these that the sources give for what the question '
                    'asks.',
        );
      }
    }
    if (lines.isEmpty) return null;
    return 'Date check by the app (today is ${_isoDay(today)}): '
        '${lines.join(' ')}';
  }
}
