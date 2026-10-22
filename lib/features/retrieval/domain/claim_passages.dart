import 'evidence.dart';

/// Why a passage that is about a claim says something else (audit R1,
/// 2026-10-08).
enum ClaimConflict {
  /// The passage negates what the claim affirms, or the reverse ("is not
  /// weather sealed" against "is weather sealed").
  negation,

  /// The same kind of figure with another value (405 g against 350 g).
  figure,

  /// The same number in another unit (405 g against 405 kg).
  unit,

  /// Another year or day (2025 against 2024, Oct 6 against Oct 5).
  date,
}

/// The passage of a source that states a claim, or that is about it and
/// says otherwise ([conflict]).
class PassageMatch {
  /// 0-based index of the source.
  final int source;
  final String span;

  /// Share of the claim's words the passage (and the page's names) hold.
  final double share;
  final ClaimConflict? conflict;
  const PassageMatch(this.source, this.span, this.share, {this.conflict});

  /// The passage states the claim: its words, every figure (with its unit
  /// and date) and the same polarity.
  bool get states => conflict == null;
}

class _Figure {
  /// The number as written without separators ("1299", "14.3").
  final String value;

  /// A known unit, canonical ("g", "CAD", "%", "°c"); null when none.
  final String? unit;

  /// The word counted when it is not a unit ("330 shots" → "shot").
  final String? noun;
  final bool year, date;
  const _Figure(
    this.value, {
    this.unit,
    this.noun,
    this.year = false,
    this.date = false,
  });
}

/// One passage of a source: a sentence, a clause between semicolons or a
/// line. Two neighbours are also read together unless a semicolon parts
/// them (a semicolon separates conditions: "405 g with battery; 350 g
/// body only").
class _Passage {
  final String text;
  final Set<String> terms;
  final List<_Figure> figures;
  final _Polarity polarity;
  final String compact;
  const _Passage(
    this.text,
    this.terms,
    this.figures,
    this.polarity,
    this.compact,
  );

  factory _Passage.of(String text) => _Passage(
    text,
    ClaimPassages._terms(text).toSet(),
    ClaimPassages._figures(text),
    _Polarity.of(text),
    ClaimPassages.compact(text),
  );

  _Passage join(_Passage next) => _Passage(
    '$text ${next.text}',
    {...terms, ...next.terms},
    [...figures, ...next.figures],
    polarity.join(next.polarity),
    '$compact${next.compact}',
  );
}

/// Negated words and words after "with"/"without", per clause.
class _Polarity {
  final Set<String> negated, without, withs;
  const _Polarity(this.negated, this.without, this.withs);

  _Polarity join(_Polarity o) => _Polarity(
    {...negated, ...o.negated},
    {...without, ...o.without},
    {...withs, ...o.withs},
  );

  static const _cues = {
    'not',
    'no',
    'never',
    'none',
    'cannot',
    'neither',
    'nor',
    'lacks',
    'lack',
    'lacking',
    'nothing',
    'ne',
    'pas',
    'jamais',
    'aucun',
    'aucune',
    'ni',
    'nunca',
    'ningún',
    'ninguno',
    'ninguna',
    'tampoco',
  };
  static const _withouts = {'without', 'sans', 'sin'};
  static const _withs = {'with', 'avec', 'con'};
  // A negation's reach ends at a conjunction ("has no viewfinder and
  // weighs 405 g" does not negate the weight).
  static const _stops = {
    'and',
    'but',
    'or',
    'et',
    'mais',
    'ou',
    'y',
    'pero',
    'o',
    'while',
    'whereas',
    'although',
    'though',
    'however',
    'yet',
    'than',
  };
  // "not only", "no matter", "no doubt" affirm.
  static const _affirming = {'only', 'just', 'matter', 'doubt', 'solo'};
  static final _clause = RegExp(r'[,;:.!?()\n—–]');
  static final _token = RegExp(
    r"[\p{L}\p{N}]+(?:['’][\p{L}]+)?",
    unicode: true,
  );

  static bool _isCue(String w) =>
      _cues.contains(w) ||
      w.endsWith("n't") ||
      w.endsWith('n’t') ||
      w.startsWith("n'") ||
      w.startsWith('n’');

  static _Polarity of(String text) {
    final negated = <String>{}, without = <String>{}, withs = <String>{};
    for (final clause in text.toLowerCase().split(_clause)) {
      final words = [for (final m in _token.allMatches(clause)) m[0]!];
      for (var i = 0; i < words.length; i++) {
        final w = words[i];
        final Set<String> into;
        if (_withouts.contains(w)) {
          into = without;
        } else if (_withs.contains(w)) {
          into = withs;
        } else if (_isCue(w)) {
          if (i + 1 < words.length && _affirming.contains(words[i + 1])) {
            continue;
          }
          into = negated;
          // "n'est" carries the verb: the next words are its scope.
        } else {
          continue;
        }
        for (var k = i + 1; k < words.length && k <= i + 4; k++) {
          if (_stops.contains(words[k])) break;
          into.addAll(EvidenceRanker.terms(words[k]));
        }
      }
    }
    return _Polarity(negated, without, withs);
  }

  /// Whether this (a claim) and [p] (a passage) disagree on a word both
  /// use: one negates it, the other does not; or one has it "without" and
  /// the other "with".
  bool flips(Set<String> claimTerms, _Polarity p, Set<String> passageTerms) {
    final plainClaim = claimTerms.difference(negated).difference(without);
    final plainPassage = passageTerms
        .difference(p.negated)
        .difference(p.without);
    return p.negated.intersection(plainClaim).isNotEmpty ||
        negated.intersection(plainPassage).isNotEmpty ||
        p.without.intersection(withs).isNotEmpty ||
        without.intersection(p.withs).isNotEmpty;
  }
}

class _Source {
  final List<_Passage> passages;
  final Set<String> terms;

  /// The title line (or the source's first line), compacted: where a
  /// model code may come from when its passage does not repeat it.
  final String title;
  const _Source(this.passages, this.terms, this.title);
}

class _Claim {
  /// Content words, figures left out.
  final Set<String> terms;

  /// Words of capitalised names: the page may supply them ("it weighs").
  final Set<String> names;

  /// Model codes ("z30", "a7iv"): the passage or the title must have them.
  final List<String> codes;
  final List<_Figure> figures;
  final _Polarity polarity;
  const _Claim(this.terms, this.names, this.codes, this.figures, this.polarity);
}

/// Whether one passage of a source states a sentence (audit R1,
/// 2026-10-08). Overlap of words with a whole page shows that the page
/// discusses the topic, not that it supports the sentence: "not weather
/// sealed" shares every word of "weather sealed". A passage supports a
/// sentence only when it holds its content words, every figure with its
/// unit and date, and the same polarity. A passage that is about the
/// sentence and negates it, or gives another value for the same figure,
/// contradicts it. Still mechanical: wording the passage does not share
/// stays uncertain, never supported.
abstract final class ClaimPassages {
  /// Every content term must occur in the supporting span (names may come
  /// from the source's context). Partial proposition overlap stays uncertain.
  static const stateShare = 1.0;

  /// Share needed before a passage is taken to contradict it: being
  /// about the same thing must be clear before a different figure counts.
  static const conflictShare = 0.6;

  static final _split = RegExp(
    r'(?<=[.!?])\s+(?=[\p{Lu}"“(\[])',
    unicode: true,
  );
  static final _capital = RegExp(
    r"(?<![\p{L}\d'’-])\p{Lu}[\p{L}’'-]+",
    unicode: true,
  );
  static final _code = RegExp(
    r'(?<![\p{L}\p{N}])\p{Lu}{1,4}-?\d{1,5}[\p{L}\d]*(?![\p{L}\p{N}])',
    unicode: true,
  );

  /// Lower case without spaces, hyphens and dots, so "Z 30" finds "Z30".
  static String compact(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[\s\-.·_/|]'), '');

  // A table's "Weight" label and the corresponding verb "weighs" name
  // the same property. Keep this equivalence narrow; general similarity
  // must not supply an absent proposition.
  //
  // Hedges carry no fact: "weighs approximately 405 g" against a page's
  // "Approx. 405 g" (app quality probe, 2026-10-19).
  static Iterable<String> _terms(String text) => EvidenceRanker.terms(
    text,
  ).where((t) => !_hedges.contains(t)).map((t) => t == 'weigh' ? 'weight' : t);

  static const _hedges = {
    'approximately',
    'approx',
    'around',
    'roughly',
    'circa',
    'ca',
    'nearly',
    'almost',
    'estimat',
    'environ',
    'aproximadament',
    'alrededor',
  };

  /// Model codes in [text]: a capital, then digits ("Z30", "A7IV").
  static List<String> codes(String text) =>
      {for (final m in _code.allMatches(text)) compact(m[0]!)}.toList();

  static _Source _index(String source) {
    final lines = source.split('\n');
    final passages = <_Passage>[];
    for (final line in lines) {
      final label = RegExp(
        r'^\s*([\p{L} ]{1,40}):',
        unicode: true,
      ).firstMatch(line)?[0];
      _Passage? previous;
      final clauses = line.split(';');
      for (var ci = 0; ci < clauses.length; ci++) {
        final clause = ci > 0 && label != null
            ? '$label ${clauses[ci]}'
            : clauses[ci];
        _Passage? last;
        for (final s in clause.split(_split)) {
          if (s.trim().isEmpty) continue;
          final p = _Passage.of(s.trim());
          passages.add(p);
          if (last != null) passages.add(last.join(p));
          last = p;
        }
        // A semicolon parts conditions: no pair across it.
        previous = last ?? previous;
      }
    }
    // A label line and its value ("Weight" / "Approx. 405 g") read
    // together: pairs across line ends, never across semicolons.
    final firstOfLine = <_Passage>[], lastOfLine = <_Passage?>[];
    for (final line in lines) {
      final clauses = line.split(';');
      final first = clauses.first
          .split(_split)
          .where((s) => s.trim().isNotEmpty);
      final last = clauses.last.split(_split).where((s) => s.trim().isNotEmpty);
      if (first.isEmpty) continue;
      firstOfLine.add(_Passage.of(first.first.trim()));
      // A line ending in a semicolon ("color: red;") has nothing after it
      // to pair with the next line.
      lastOfLine.add(last.isEmpty ? null : _Passage.of(last.last.trim()));
    }
    for (var i = 1; i < firstOfLine.length; i++) {
      final end = lastOfLine[i - 1];
      if (end != null) passages.add(end.join(firstOfLine[i]));
    }
    final firstLine = lines.firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    return _Source(passages, _terms(source).toSet(), compact(firstLine));
  }

  static _Claim _claim(String sentence) {
    final terms = _terms(
      sentence,
    ).where((t) => !RegExp(r'^\d+$').hasMatch(t)).toSet();
    final names = <String>{
      for (final m in _capital.allMatches(sentence))
        ...EvidenceRanker.terms(m[0]!),
      // Product codes are names too; the independently checked title may
      // identify the subject of an otherwise anonymous table row.
      ...codes(sentence),
    };
    return _Claim(
      terms,
      names,
      codes(sentence),
      _figures(sentence),
      _Polarity.of(sentence),
    );
  }

  /// Prepared sources for repeated checks ([best]).
  static List<Object> prepare(List<String> sources) => [
    for (final s in sources) _index(s),
  ];

  /// The best passage of [sources] (from [prepare]) for [sentence]: one
  /// that states it, else one that contradicts it, else null.
  static PassageMatch? best(String sentence, List<Object> sources) {
    final c = _claim(sentence);
    if (c.terms.isEmpty) return null;
    PassageMatch? stated, conflicting;
    for (var i = 0; i < sources.length; i++) {
      final m = _inSource(c, sources[i] as _Source, i);
      if (m == null) continue;
      if (m.states) {
        if (stated == null || m.share > stated.share) stated = m;
      } else if (conflicting == null || m.share > conflicting.share) {
        conflicting = m;
      }
    }
    return stated ?? conflicting;
  }

  static PassageMatch? _inSource(_Claim c, _Source s, int index) {
    PassageMatch? stated, conflicting;
    for (final p in s.passages) {
      final passageCodes = codes(p.text);
      if (c.codes.isNotEmpty && passageCodes.any((k) => !c.codes.contains(k))) {
        continue;
      }
      if (!c.codes.every(
        (k) =>
            p.compact.contains(k) ||
            (s.title.contains(k) && passageCodes.every(c.codes.contains)),
      )) {
        continue;
      }
      var shared = 0, own = 0;
      for (final t in c.terms) {
        if (p.terms.contains(t)) {
          shared++;
          if (!c.names.contains(t)) own++;
        } else if (c.names.contains(t) && s.terms.contains(t)) {
          shared++;
        }
      }
      // At least one word that is not a name must come from the passage.
      if (own == 0 && c.terms.length > c.names.length) continue;
      final share = shared / c.terms.length;
      if (share < conflictShare) continue;
      final flip = c.polarity.flips(c.terms, p.polarity, p.terms);
      ClaimConflict? figure;
      var missing = false;
      for (final f in c.figures) {
        final r = _compare(f, p.figures);
        if (r == _Fit.missing) missing = true;
        if (r is ClaimConflict) figure ??= r;
      }
      if (share >= stateShare && !flip && figure == null && !missing) {
        if (stated == null || share > stated.share) {
          stated = PassageMatch(index, p.text, share);
        }
      } else if ((flip || figure != null) && share >= conflictShare) {
        if (conflicting == null || share > conflicting.share) {
          conflicting = PassageMatch(
            index,
            p.text,
            share,
            conflict: flip ? ClaimConflict.negation : figure,
          );
        }
      }
    }
    return stated ?? conflicting;
  }

  static Object _compare(_Figure f, List<_Figure> found) {
    if (f.date || f.year) {
      if (found.any(
        (w) => w.date == f.date && w.year == f.year && w.value == f.value,
      )) {
        return _Fit.ok;
      }
      return found.any((w) => w.date == f.date && w.year == f.year)
          ? ClaimConflict.date
          : _Fit.missing;
    }
    final same = found.where(
      (w) => !w.date && !w.year && _equal(f.value, w.value),
    );
    if (f.unit != null) {
      if (same.any((w) => w.unit == f.unit)) return _Fit.ok;
      if (same.any((w) => w.unit != null)) return ClaimConflict.unit;
      if (found.any((w) => w.unit == f.unit)) return ClaimConflict.figure;
      return _Fit.missing;
    }
    if (same.isNotEmpty) return _Fit.ok;
    if (f.noun != null &&
        found.any((w) => w.unit == null && w.noun == f.noun)) {
      return ClaimConflict.figure;
    }
    return _Fit.missing;
  }

  /// Equal, or the claim rounds the source ("21" for "20.9"). Extra
  /// decimal precision invented by the claim is not source support.
  static bool _equal(String a, String b) {
    if (a == b) return true;
    final x = double.tryParse(a), y = double.tryParse(b);
    if (x == null || y == null) return false;
    if (x == y) return true;
    int places(String v) => v.contains('.') ? v.split('.').last.length : 0;
    if (places(a) >= places(b)) return false;
    return y.toStringAsFixed(places(a)) == x.toStringAsFixed(places(a));
  }

  static const _units = {
    'g': 'g',
    'gr': 'g',
    'gram': 'g',
    'grams': 'g',
    'gramme': 'g',
    'grammes': 'g',
    'gramos': 'g',
    'gramo': 'g',
    'kg': 'kg',
    'kilo': 'kg',
    'kilos': 'kg',
    'kilogram': 'kg',
    'kilograms': 'kg',
    'kilogramme': 'kg',
    'kilogrammes': 'kg',
    'kilogramos': 'kg',
    'lb': 'lb',
    'lbs': 'lb',
    'pound': 'lb',
    'pounds': 'lb',
    'oz': 'oz',
    'ounce': 'oz',
    'ounces': 'oz',
    'mm': 'mm',
    'cm': 'cm',
    'm': 'm',
    'meter': 'm',
    'meters': 'm',
    'metre': 'm',
    'metres': 'm',
    'mètre': 'm',
    'mètres': 'm',
    'metro': 'm',
    'metros': 'm',
    'km': 'km',
    'kilometer': 'km',
    'kilometers': 'km',
    'kilometre': 'km',
    'kilometres': 'km',
    'kilomètre': 'km',
    'kilomètres': 'km',
    'kilómetro': 'km',
    'kilómetros': 'km',
    'mi': 'mi',
    'mile': 'mi',
    'miles': 'mi',
    'inch': 'in',
    'inches': 'in',
    'pouces': 'in',
    'pulgadas': 'in',
    'ft': 'ft',
    'feet': 'ft',
    'foot': 'ft',
    'mph': 'mph',
    'km/h': 'km/h',
    'kmh': 'km/h',
    '%': '%',
    'percent': '%',
    'pourcent': '%',
    'porciento': '%',
    '°': '°',
    '°c': '°c',
    '°f': '°f',
    'ºc': '°c',
    'degrees': '°',
    'degree': '°',
    'degrés': '°',
    'grados': '°',
    'celsius': '°c',
    'fahrenheit': '°f',
    'degreescelsius': '°c',
    'degreecelsius': '°c',
    'degréscelsius': '°c',
    'gradoscelsius': '°c',
    'degreesfahrenheit': '°f',
    'degreefahrenheit': '°f',
    'degrésfahrenheit': '°f',
    'gradosfahrenheit': '°f',
    'aud': 'AUD',
    'mp': 'mp',
    'megapixel': 'mp',
    'megapixels': 'mp',
    'mégapixels': 'mp',
    'megapíxeles': 'mp',
    'mah': 'mah',
    'wh': 'wh',
    'kwh': 'kwh',
    'w': 'w',
    'watt': 'w',
    'watts': 'w',
    'kw': 'kw',
    'hp': 'hp',
    'hz': 'hz',
    'khz': 'khz',
    'mhz': 'mhz',
    'ghz': 'ghz',
    'kb': 'kb',
    'mb': 'mb',
    'gb': 'gb',
    'tb': 'tb',
    'fps': 'fps',
    'i/s': 'fps',
    'nits': 'nits',
    'ms': 'ms',
    'h': 'h',
    'hr': 'h',
    'hrs': 'h',
    'hour': 'h',
    'hours': 'h',
    'heure': 'h',
    'heures': 'h',
    'hora': 'h',
    'horas': 'h',
    'min': 'min',
    'mins': 'min',
    'minute': 'min',
    'minutes': 'min',
    'minuto': 'min',
    'minutos': 'min',
    'day': 'day',
    'days': 'day',
    'jour': 'day',
    'jours': 'day',
    'día': 'day',
    'días': 'day',
    'year': 'year',
    'years': 'year',
    'ans': 'year',
    'años': 'year',
    'usd': 'USD',
    'dollar': '\$',
    'dollars': '\$',
    'cad': 'CAD',
    'eur': '€',
    'euro': '€',
    'euros': '€',
    '€': '€',
    'gbp': '£',
    '£': '£',
  };

  static const _months = {
    'jan': 1,
    'january': 1,
    'janvier': 1,
    'enero': 1,
    'feb': 2,
    'february': 2,
    'février': 2,
    'fevrier': 2,
    'febrero': 2,
    'mar': 3,
    'march': 3,
    'mars': 3,
    'marzo': 3,
    'apr': 4,
    'april': 4,
    'avril': 4,
    'abril': 4,
    'may': 5,
    'mai': 5,
    'mayo': 5,
    'jun': 6,
    'june': 6,
    'juin': 6,
    'junio': 6,
    'jul': 7,
    'july': 7,
    'juillet': 7,
    'julio': 7,
    'aug': 8,
    'august': 8,
    'août': 8,
    'aout': 8,
    'agosto': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'septembre': 9,
    'septiembre': 9,
    'oct': 10,
    'october': 10,
    'octobre': 10,
    'octubre': 10,
    'nov': 11,
    'november': 11,
    'novembre': 11,
    'noviembre': 11,
    'dec': 12,
    'december': 12,
    'décembre': 12,
    'decembre': 12,
    'diciembre': 12,
  };

  static final _number = RegExp(
    r'(?<![\p{L}\p{N}.,])((?:US|CA|C|A|AU)?[$€£¥])?\s?([+-]?\d+(?:[.,]\d+)*)'
    r'(?:\s?(%|per ?cent|pour ?cent|por ?ciento|°\s?[CcFf]?|º[Cc]|(?:degrees?|degrés?|grados)\s+(?:celsius|fahrenheit)|[\p{L}][\p{L}/]*))?',
    unicode: true,
    caseSensitive: false,
  );
  static final _dayMonth = RegExp(
    r'(?<![\p{L}\p{N}])(\d{1,2})(?:st|nd|rd|th|er)?\s+(?:de\s+)?(\p{L}+)',
    unicode: true,
  );
  static final _monthDay = RegExp(
    r'(?<![\p{L}])(\p{L}+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?![\p{N}])',
    unicode: true,
  );

  /// The figures of [text]: amounts with their unit, years and dates.
  static List<_Figure> _figures(String text) {
    final out = <_Figure>[];
    final dates = <(int, int)>[];
    for (final m in _monthDay.allMatches(text)) {
      final month = _months[m[1]!.toLowerCase()];
      if (month != null) dates.add((m.start, m.end));
      if (month != null) {
        out.add(_Figure('$month-${int.parse(m[2]!)}', date: true));
      }
    }
    for (final m in _dayMonth.allMatches(text)) {
      final month = _months[m[2]!.toLowerCase()];
      if (month == null || dates.any((d) => m.start < d.$2 && d.$1 < m.end)) {
        continue;
      }
      dates.add((m.start, m.end));
      out.add(_Figure('$month-${int.parse(m[1]!)}', date: true));
    }
    for (final m in _number.allMatches(text)) {
      final start = m.start + (m[1]?.length ?? 0);
      if (dates.any((d) => start >= d.$1 && start < d.$2)) {
        continue;
      }
      final value = _value(m[2]!);
      if (value == null) continue;
      final currency = m[1];
      final word = m[3]?.toLowerCase().replaceAll(' ', '');
      final unit = currency != null
          ? (currency.endsWith('€')
                ? '€'
                : currency.endsWith('£')
                ? '£'
                : currency.endsWith('¥')
                ? '¥'
                : switch (currency.toUpperCase()) {
                    'US\$' => 'USD',
                    'CA\$' || 'C\$' => 'CAD',
                    'AU\$' || 'A\$' => 'AUD',
                    _ => '\$',
                  })
          : word == null
          ? null
          : _units[word] ?? (word.startsWith('°') ? '°' : null);
      final noun = unit == null && word != null && word.length >= 3
          ? EvidenceRanker.stem(word)
          : null;
      final n = double.parse(value);
      if (unit == null &&
          RegExp(r'^\d{4}$').hasMatch(value) &&
          n >= 1500 &&
          n < 2100) {
        out.add(_Figure(value, year: true));
        continue;
      }
      // Small whole numbers without a unit read as prose ("2 of the 3").
      if (unit == null && !value.contains('.') && n <= 31) continue;
      out.add(_Figure(value, unit: unit, noun: noun));
    }
    return out;
  }

  /// "1,299" → "1299", "14,3" → "14.3", "499.00" → "499".
  static String? _value(String raw) {
    var v = raw;
    if (RegExp(r'^\d{1,3}(?:,\d{3})+(?:\.\d+)?$').hasMatch(v)) {
      v = v.replaceAll(',', '');
    } else if (RegExp(r'^\d{1,3}(?:\.\d{3})+,\d+$').hasMatch(v)) {
      v = v.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d+,\d{1,2}$').hasMatch(v)) {
      v = v.replaceAll(',', '.');
    } else if (v.contains(',')) {
      v = v.replaceAll(',', '');
    }
    if (RegExp(r'\..*\.').hasMatch(v)) return null;
    if (v.contains('.')) {
      v = v.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return v.isEmpty ? null : v;
  }
}

enum _Fit { ok, missing }
