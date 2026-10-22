/// A person's age from the birth date the sources give, computed by the
/// app. Small models get date arithmetic wrong even with the right page in
/// front of them (phone, 2026-09-24: "how old is Justin Bieber" was
/// searched, read Wikipedia, and still answered with the birthday "March 1,
/// 2026"). The evidence prompt carries the computed line; the model only
/// has to repeat it.
class LifeDates {
  static const _monthsEn = {
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
  };
  static const _monthsFr = {
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
  };
  static const _monthsEs = {
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
  static final Map<String, int> _months = {
    ..._monthsEn,
    ..._monthsFr,
    ..._monthsEs,
  };

  static final _monthWord = '(${_months.keys.join('|')})\\.?';

  /// "born March 1, 1994", "born 1 March 1994", "(born 1994-03-01)",
  /// "Born: March 1, 1994", "né le 1er mars 1994", "nació el 1 de marzo de
  /// 1994".
  static final _patterns = [
    RegExp(
      // A letter lookahead, not \b: \b is ASCII-only, so "nació " and
      // "née " never ended a word.
      '(?<![\\p{L}])(?:born|n[ée]e?|naci[óo])(?![\\p{L}])[^.;\\n\\d]{0,30}?$_monthWord\\s+(\\d{1,2}),?\\s+(\\d{4})',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      '(?<![\\p{L}])(?:born|n[ée]e?|naci[óo])(?![\\p{L}])[^.;\\n\\d]{0,30}?(\\d{1,2})(?:er|st|nd|rd|th)?\\s+(?:de\\s+)?$_monthWord\\s+(?:de\\s+)?(\\d{4})',
      caseSensitive: false,
      unicode: true,
    ),
    RegExp(
      r'\b(?:born|date of birth|birth date)\b[^.;\n\d]{0,20}?(\d{4})-(\d{2})-(\d{2})',
      caseSensitive: false,
    ),
  ];

  /// A question about someone's age or birthday.
  static final _asks = RegExp(
    r"how old|['’]s age\b|\bage of\b|birthday|born|date of birth|quel [âa]ge|anniversaire|n[ée]e? |date de naissance|cu[áa]ntos a[ñn]os|qu[ée] edad|cumplea[ñn]os|naci[óo]|fecha de nacimiento",
    caseSensitive: false,
  );

  static bool asksAge(String question) => _asks.hasMatch(question);

  /// Birth dates in [text].
  static List<DateTime> birthDates(String text) {
    final out = <DateTime>[];
    for (final m in _patterns[0].allMatches(text)) {
      final month = _months[m[1]!.toLowerCase()];
      final d = _date(int.parse(m[3]!), month, int.parse(m[2]!));
      if (d != null) out.add(d);
    }
    for (final m in _patterns[1].allMatches(text)) {
      final month = _months[m[2]!.toLowerCase()];
      final d = _date(int.parse(m[3]!), month, int.parse(m[1]!));
      if (d != null) out.add(d);
    }
    for (final m in _patterns[2].allMatches(text)) {
      final d = _date(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      if (d != null) out.add(d);
    }
    return out;
  }

  static DateTime? _date(int year, int? month, int day) {
    if (month == null || month < 1 || month > 12) return null;
    if (day < 1 || day > 31 || year < 1000) return null;
    final d = DateTime(year, month, day);
    return d.month == month ? d : null;
  }

  /// Whole years between [born] and [on].
  static int ageOn(DateTime born, DateTime on) {
    var age = on.year - born.year;
    if (on.month < born.month ||
        (on.month == born.month && on.day < born.day)) {
      age--;
    }
    return age;
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The line for the evidence prompt: the birth date most sources agree
  /// on (with their numbers), the age today and the next birthday. Null
  /// when the question is not about age or no source gives a date. [texts]
  /// are the sources in citation order.
  static String? note(List<String> texts, String question, DateTime now) {
    if (!asksAge(question)) return null;
    final votes = <DateTime, List<int>>{};
    for (var i = 0; i < texts.length; i++) {
      for (final d in birthDates(texts[i]).toSet()) {
        if (d.isAfter(now)) continue;
        (votes[d] ??= []).add(i + 1);
      }
    }
    if (votes.isEmpty) return null;
    final best = votes.entries.reduce(
      (a, b) => b.value.length > a.value.length ? b : a,
    );
    final born = best.key;
    final today = DateTime(now.year, now.month, now.day);
    var next = DateTime(today.year, born.month, born.day);
    if (next.isBefore(today)) {
      next = DateTime(today.year + 1, born.month, born.day);
    }
    final others = votes.keys.where((d) => d != born).map(_iso).toList();
    final age = ageOn(born, today);
    // "32 years old today (2026-10-20)" came back as "he turns 32 today"
    // (Conversation probe, 2026-10-20): the line says when the age began.
    final when = next == today
        ? 'turns $age today (${_iso(today)})'
        : '$age years old on ${_iso(today)}: turned $age on '
              '${_iso(DateTime(next.year - 1, born.month, born.day))}, not '
              'today; next birthday ${_iso(next)}';
    return 'Computed by the app from source${best.value.length > 1 ? 's' : ''} '
        '${best.value.map((n) => '[$n]').join('')}: born ${_iso(born)}, so '
        '$when.'
        '${others.isEmpty ? '' : ' Other sources give ${others.join(', ')}.'}'
        ' Use this rather than your own arithmetic.';
  }
}
