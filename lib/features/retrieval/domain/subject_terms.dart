/// The names a request is about — products, models, versions, people,
/// places, organisations — read from its wording, and the checks that keep
/// a small model on them. A near-miss name is drift: a different thing
/// with a similar name that small models swap in from memory, then research
/// and report. Seen on the tester's phone (2026-09-24 Goals, Nikon Z30 vs
/// Sony ZV-E10): step after step researched the "ZV-E10 II", a different
/// camera, and the report mixed their specifications. Also "Galaxy S24"
/// for "Galaxy S25", "Qwen3" for "Qwen3.5", "iPhone 16" for "iPhone 17".
class SubjectTerms {
  /// The names, as the user wrote them.
  final List<String> terms;
  const SubjectTerms(this.terms);

  static const none = SubjectTerms([]);

  bool get isEmpty => terms.isEmpty;
  bool get isNotEmpty => terms.isNotEmpty;

  /// Most names kept from a request.
  static const maxTerms = 6;

  static final _tokenPattern = RegExp(
    r"[\p{L}\p{N}][\p{L}\p{N}.+\-_'’]*",
    unicode: true,
  );
  static final _upper = RegExp(r'^\p{Lu}', unicode: true);
  static final _anyLetter = RegExp(r'\p{L}', unicode: true);
  static final _digit = RegExp(r'\d');
  static final _number = RegExp(r'^\d+(?:\.\d+)*$');
  static final _year = RegExp(r'^(?:19|20)\d\d$');
  static final _letters = RegExp(r'^\p{L}+$', unicode: true);

  /// A model code with its number: "s25" → (s, 25), "qwen3.5" → (qwen,
  /// 3.5), "zv-e10" → (zv-e, 10), "a7iv" → (a, 7, iv), "gpt-5" → (gpt, 5).
  static final _fused = RegExp(
    r'^((?:\p{L}[\p{L}\p{N}\-]*)?\p{L})[-_]?(\d+(?:\.\d+)*)\+?(\p{L}*)$',
    unicode: true,
  );

  /// Words after a model number that make it another generation ("ZV-E10
  /// II", "EOS R5 Mark II", "Pixel 9 2nd gen"). "v" is left out: people
  /// write it for "versus".
  static const _generations = {
    'ii',
    'iii',
    'iv',
    'vi',
    'vii',
    'viii',
    'mkii',
    'mkiii',
    'mkiv',
    'mk2',
    'mk3',
    'mk4',
    '2nd',
    '3rd',
    '4th',
    '5th',
  };

  /// Words that start or join sentences rather than name things, in the
  /// app's languages (English, French, Spanish).
  static const _stop = {
    // English
    'a', 'an', 'the', 'and', 'or', 'but', 'of', 'for', 'in', 'on', 'at',
    'to', 'from', 'with', 'about', 'by', 'as', 'into', 'than', 'vs',
    'versus', 'between', 'is', 'are', 'was', 'were', 'be', 'do', 'does',
    'did', 'can', 'could', 'should', 'would', 'will', 'what', "what's",
    'which', 'who', 'whom', 'whose', 'when', 'where', 'why', 'how', "how's",
    'i', "i'm", 'me', 'my', 'we', 'our', 'you', 'your', 'it', 'its', 'this',
    'that', 'these', 'those', 'there', 'please', 'compare', 'comparison',
    'summarise', 'summarize', 'summary', 'explain', 'find', 'research',
    'investigate', 'analyse', 'analyze', 'analysis', 'list', 'give', 'tell',
    'write', 'make', 'plan', 'look', 'show', 'describe', 'review', 'reviews',
    'check', 'best', 'top', 'latest', 'new', 'current', 'recent', 'today',
    'overview', 'report', 'guide', 'pros', 'cons', 'under', 'over', 'all',
    'any', 'some', 'has', 'have', 'get', 'buy', 'choose', 'pick', 'need',
    'want', 'help', 'create', 'build', 'fix', 'solve', 'prove', 'calculate',
    'learn', 'understand', 'evaluate', 'assess', 'recommend', 'price',
    'prices', 'cost', 'costs', 'news', 'update', 'updates', 'step', 'steps',
    'etc', 'if', 'then', 'also', 'not', 'no', 'yes', 'up', 'out',
    // French
    'le', 'la', 'les', 'un', 'une', 'des', 'du', 'de', 'et', 'ou', 'pour',
    'dans', 'sur', 'avec', 'sans', 'est', 'sont', 'quel', 'quelle',
    'quels', 'quelles', 'qui', 'quoi', 'comment', 'pourquoi', 'quand', 'où',
    'je', 'mon', 'ma', 'mes', 'nous', 'vous', 'votre', 'comparer',
    'résume', 'résumer', 'explique', 'expliquer', 'trouve', 'trouver',
    'recherche', 'analyser', 'meilleur', 'meilleure', 'dernier',
    'dernière', 'nouveau', 'nouvelle', 'prix', 'entre',
    // Spanish
    'el', 'los', 'las', 'unos', 'unas', 'del', 'al', 'y', 'o', 'para', 'por',
    'en', 'con', 'sin', 'es', 'son', 'qué', 'que', 'cuál', 'cual', 'cuáles',
    'quién', 'cómo', 'como', 'cuándo', 'dónde', 'yo', 'mi', 'mis', 'compara',
    'resume', 'resumir', 'explica', 'explicar', 'encuentra', 'buscar',
    'investiga', 'analiza', 'mejor', 'último', 'última', 'nuevo', 'nueva',
    'precio', 'precios',
  };

  /// Small words that belong inside a capitalised name ("Bank of Canada",
  /// "Universidad de Chile").
  static const _connectors = {
    'of',
    'de',
    'la',
    'del',
    'du',
    'des',
    'von',
    'van',
    'der',
    'di',
    'da',
    '&',
    'y',
  };

  /// Lower-case words that finish a model name after its number.
  static const _suffixes = {
    'pro',
    'max',
    'ultra',
    'plus',
    'mini',
    'lite',
    'air',
    'se',
    'fe',
    'xl',
    'edge',
    'fold',
    'flip',
    'turbo',
    'nano',
    'flash',
    'instruct',
    'it',
    ..._generations,
  };

  static String _trim(String t) => t
      .replaceFirst(RegExp(r"[.\-_'’]+$"), '')
      .replaceFirst(RegExp(r"['’]s$", caseSensitive: false), '');

  static List<_Token> _tokens(String text) => [
    for (final m in _tokenPattern.allMatches(text))
      if (_trim(m[0]!).isNotEmpty)
        _Token(_trim(m[0]!), m.start, m.start + _trim(m[0]!).length, m[0]!),
  ];

  /// The names in [text]: quoted phrases, runs of capitalised words, and
  /// model or version names (a word with a number: "iphone 17 pro",
  /// "Qwen3.5 2B", "nikon z30"). Sentence-initial words ("Compare",
  /// "Summarise") and years are left out; at most [max], in order.
  static SubjectTerms of(String text, {int max = maxTerms}) {
    final out = <String>[];
    void add(String term) {
      final t = term.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.length < 2 || t.length > 80) return;
      final lower = t.toLowerCase();
      if (_stop.contains(lower)) return;
      // A shorter name inside a longer one is the same subject.
      if (out.any((o) => o.toLowerCase().contains(lower))) return;
      out.removeWhere((o) => lower.contains(o.toLowerCase()));
      out.add(t);
    }

    // Quoted phrases first: an error message or a title, word for word.
    final quoted = <(int, int)>[];
    for (final m in RegExp(
      r'''(?:^|[\s(\[:])(?:["“«]([^"”»\n]{2,80})["”»]|['‘]([^'’\n]{2,80})['’](?=[\s.,;:!?)\]]|$))''',
    ).allMatches(text)) {
      final phrase = (m[1] ?? m[2])!.trim();
      if (phrase.split(RegExp(r'\s+')).length <= 12) {
        add(phrase);
        quoted.add((m.start, m.end));
      }
    }
    bool inQuote(int at) => quoted.any((q) => at >= q.$1 && at < q.$2);

    final tokens = <({String text, String raw, bool start, bool quoted})>[];
    for (final m in _tokenPattern.allMatches(text)) {
      final before = text.substring(0, m.start).trimRight();
      tokens.add((
        text: _trim(m[0]!),
        raw: m[0]!,
        start: before.isEmpty || RegExp(r'[.!?:;\n¿¡]$').hasMatch(before),
        quoted: inQuote(m.start),
      ));
    }
    final run = <String>[];
    var runStartsSentence = false;
    void flush() {
      bool drop(String w) =>
          _stop.contains(w.toLowerCase()) ||
          _connectors.contains(w.toLowerCase());
      while (run.isNotEmpty && drop(run.first)) {
        run.removeAt(0);
        runStartsSentence = false;
      }
      while (run.isNotEmpty && drop(run.last)) {
        run.removeLast();
      }
      if (run.isNotEmpty && !run.every(_number.hasMatch)) {
        final w = run.first;
        final keep =
            run.length > 1 ||
            (_digit.hasMatch(w) && _anyLetter.hasMatch(w)) ||
            (w.length >= 2 && w == w.toUpperCase() && _letters.hasMatch(w)) ||
            (!runStartsSentence && _upper.hasMatch(w));
        if (keep) add(run.join(' '));
      }
      run.clear();
      runStartsSentence = false;
    }

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.quoted || t.text.isEmpty) {
        flush();
        continue;
      }
      final bare = t.text;
      final lower = bare.toLowerCase();
      final next = i + 1 < tokens.length && !tokens[i + 1].quoted
          ? tokens[i + 1].text
          : '';
      final year = _year.hasMatch(bare);
      final digit = _digit.hasMatch(bare) && !year;
      final cap = _upper.hasMatch(bare);
      final sentenceStop = t.start && _stop.contains(lower);
      final nameLike = (digit || cap) && !sentenceStop && !year;
      final connector =
          run.isNotEmpty &&
          _connectors.contains(lower) &&
          next.isNotEmpty &&
          _upper.hasMatch(next);
      final suffix =
          run.isNotEmpty &&
          _suffixes.contains(lower) &&
          run.any(_digit.hasMatch);
      // A lower-case word before a number or a model code is its brand or
      // product line: "iphone 17", "nikon z30", "sony zv-e10".
      final leadsNumber =
          !_stop.contains(lower) &&
          !year &&
          _letters.hasMatch(bare) &&
          _digit.hasMatch(next) &&
          !_year.hasMatch(next);
      if (nameLike || connector || suffix || leadsNumber) {
        if (run.isEmpty) runStartsSentence = t.start;
        run.add(bare);
        // A sentence ends inside the run ("… Galaxy S25. Then …").
        if (RegExp(r'[.!?]$').hasMatch(t.raw) && !_number.hasMatch(bare)) {
          flush();
        }
      } else {
        flush();
      }
    }
    flush();
    return SubjectTerms(out.take(max).toList());
  }

  /// Where [tokens] name a model: fused ("S24", "ZV-E10") or apart
  /// ("iPhone 16"), with a generation word after it ("II") and, for a short
  /// prefix, the word before it as context ("Galaxy" for "S").
  static List<_Hit> _hits(List<_Token> tokens) {
    final out = <_Hit>[];
    for (var i = 0; i < tokens.length; i++) {
      final w = tokens[i].lower;
      String word, number, marker = '';
      var end = i;
      final f = _fused.firstMatch(w);
      if (f != null && !_year.hasMatch(w) && !_number.hasMatch(w)) {
        word = f[1]!;
        number = f[2]!;
        if (_generations.contains(f[3])) marker = f[3]!;
      } else if (_letters.hasMatch(w) &&
          !_stop.contains(w) &&
          i + 1 < tokens.length &&
          _number.hasMatch(tokens[i + 1].lower) &&
          !_year.hasMatch(tokens[i + 1].lower)) {
        word = w;
        number = tokens[i + 1].lower;
        end = i + 1;
      } else {
        continue;
      }
      if (marker.isEmpty && end + 1 < tokens.length) {
        final next = tokens[end + 1].lower;
        if (_generations.contains(next)) {
          marker = next;
          end++;
        } else if ((next == 'mark' || next == 'mk') &&
            end + 2 < tokens.length) {
          marker = 'mark ${tokens[end + 2].lower}';
          end += 2;
        }
      }
      out.add(
        _Hit(
          word: word,
          number: number,
          marker: marker,
          start: i,
          end: end,
          context: i > 0 ? tokens[i - 1].lower : null,
          context2: i > 1 ? tokens[i - 2].lower : null,
        ),
      );
    }
    return out;
  }

  /// The model anchors of a name ("Sony ZV-E10" → zv-e 10, context
  /// "sony"), with how the name spells them.
  static List<({_Hit hit, String display})> _anchors(String term) {
    final tokens = _tokens(term);
    return [
      for (final h in _hits(tokens))
        (
          hit: h,
          display: term.substring(tokens[h.start].start, tokens[h.end].end),
        ),
    ];
  }

  static bool _sameNumber(String found, String wanted) =>
      found == wanted || found.startsWith('$wanted.');

  /// Whether [h] in the text refers to [a]'s model line: same word, and
  /// for a one- or two-letter code ("S", "A") the brand word next to it.
  static bool _sameLine(_Hit h, _Hit a) {
    if (h.word != a.word) return false;
    if (a.word.length >= 3) return true;
    final brand = a.context;
    return brand != null && (h.context == brand || h.context2 == brand);
  }

  /// Every name in [text] that shares a term's model line but is another
  /// model: another number ("Galaxy S24" for "Galaxy S25", "Qwen3" for
  /// "Qwen3.5") or another generation ("ZV-E10 II" for "ZV-E10"). Names
  /// that [allowed] (the request, the user's rules) mentions are fine: a
  /// comparison the user asked for is not drift.
  List<String> drift(String text, {String allowed = ''}) => [
    for (final d in _drifts(text, allowed: allowed)) d.shown,
  ];

  /// Whether [text] puts another model in place of one of the terms: it
  /// names a drifted model of a term's line and never that term itself —
  /// "Nikon Z30 vs Sony ZV-E10 II" for a Z30-vs-ZV-E10 goal. Such a page
  /// names the goal (the Z30), so [mentionsAny] alone kept it, and its
  /// ZV-E10 II figures ended up in the ZV-E10 column (phone, 2026-09-24).
  bool replacesTerm(String text, {String allowed = ''}) {
    for (final term in terms) {
      if (names(text, term)) continue;
      if (SubjectTerms([term]).drift(text, allowed: allowed).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  List<({String shown, int from, int to, String display})> _drifts(
    String text, {
    String allowed = '',
  }) {
    if (terms.isEmpty || text.isEmpty) return const [];
    final tokens = _tokens(text);
    final hits = _hits(tokens);
    final permitted = allowed.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final seen = <String>{};
    final out = <({String shown, int from, int to, String display})>[];
    for (final term in terms) {
      for (final a in _anchors(term)) {
        for (final h in hits) {
          if (!_sameLine(h, a.hit)) continue;
          if (_sameNumber(h.number, a.hit.number) && h.marker == a.hit.marker) {
            continue;
          }
          final from = tokens[h.start].start, to = tokens[h.end].end;
          final shown = text.substring(from, to);
          final key = shown.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          if (permitted.contains(key) ||
              permitted.contains('${h.word}${h.number}') ||
              permitted.contains('${h.word} ${h.number}') ||
              permitted.contains('${h.word}-${h.number}')) {
            // "ZV-E10" allowed does not allow "ZV-E10 II".
            if (h.marker.isEmpty || permitted.contains(key)) continue;
          }
          if (seen.add(key)) {
            out.add((
              shown: shown,
              from: from,
              to: to,
              display: _fix(shown, h, a.hit, a.display),
            ));
          }
        }
      }
    }
    return out;
  }

  /// [shown] (a drifted name as the text spells it) turned into the
  /// term's model: the generation word dropped or the number put back,
  /// keeping the text's own spelling ("Sony ZV-E10 II" → "Sony ZV-E10").
  static String _fix(String shown, _Hit h, _Hit a, String termSpelling) {
    if (a.marker.isNotEmpty) return termSpelling;
    var out = shown;
    if (h.marker.isNotEmpty) {
      final plain = h.marker.replaceFirst('mark ', '');
      out = out.replaceFirst(
        RegExp(
          r'[\s\-]*(?:mark\s+|mk\s*)?' + RegExp.escape(plain) + r'$',
          caseSensitive: false,
        ),
        '',
      );
    }
    if (!_sameNumber(h.number, a.number)) {
      final i = out.toLowerCase().lastIndexOf(h.number);
      if (i >= 0) out = out.replaceRange(i, i + h.number.length, a.number);
    }
    return out;
  }

  static final _wordSplit = RegExp(r'[^\p{L}\p{N}.+\-]+', unicode: true);

  /// Whether [text] names [term]: one of its model anchors with the same
  /// number and generation, or most of a plain name's words (its last word
  /// included: "Blue Jays" names "Toronto Blue Jays").
  static bool names(String text, String term) {
    final anchors = _anchors(term);
    if (anchors.isNotEmpty) {
      final hits = _hits(_tokens(text));
      return anchors.any(
        (a) => hits.any(
          (h) =>
              _sameLine(h, a.hit) &&
              _sameNumber(h.number, a.hit.number) &&
              h.marker == a.hit.marker,
        ),
      );
    }
    final bag = {
      for (final w in text.toLowerCase().split(_wordSplit))
        if (w.isNotEmpty) _trim(w),
    };
    final parts = [
      for (final w in term.toLowerCase().split(_wordSplit))
        if (w.length >= 3 && !_stop.contains(w)) _trim(w),
    ];
    if (parts.isEmpty) {
      return text.toLowerCase().contains(term.toLowerCase());
    }
    final present = parts.where(bag.contains).length;
    return bag.contains(parts.last) && present * 2 >= parts.length;
  }

  /// The terms [text] names.
  List<String> mentioned(String text) => [
    for (final t in terms)
      if (names(text, t)) t,
  ];

  bool mentionsAny(String text) => terms.any((t) => names(text, t));

  /// [question] with drifted names put back to the request's names, and
  /// the main names added when it names none of them — so a planned
  /// question or a rewritten search query cannot wander to a neighbouring
  /// product ("Determine the maximum video resolutions of each camera"
  /// searched webcams on the phone).
  String repair(
    String question, {
    String allowed = '',
    bool addSubject = true,
  }) {
    if (terms.isEmpty) return question;
    var q = question;
    for (final d in _drifts(
      question,
      allowed: allowed,
    ).reversed.toList()..sort((a, b) => b.from.compareTo(a.from))) {
      q = q.replaceRange(d.from, d.to, d.display);
    }
    // Only a question without a subject of its own gets the goal's names:
    // "range of the Tesla Model Y" is about a name already.
    if (addSubject && !mentionsAny(q) && SubjectTerms.of(q).isEmpty) {
      q = '${q.trimRight()} (${terms.take(2).join(', ')})';
    }
    return q;
  }

  /// [items] without sources about a neighbouring model (a drifted name
  /// in place of a term, see [replacesTerm]), those naming a term first,
  /// then the rest — which are dropped once at least [enough] name a term.
  List<T> focus<T>(
    List<T> items,
    String Function(T) textOf, {
    String allowed = '',
    int enough = 2,
  }) {
    if (terms.isEmpty || items.isEmpty) return items;
    final on = <T>[], neutral = <T>[];
    for (final item in items) {
      final text = textOf(item);
      if (replacesTerm(text, allowed: allowed)) continue;
      if (mentionsAny(text)) {
        on.add(item);
      } else if (drift(text, allowed: allowed).isEmpty) {
        neutral.add(item);
      }
    }
    return on.length >= enough ? on : [...on, ...neutral];
  }
}

class _Token {
  final String text, raw;
  final int start, end;
  const _Token(this.text, this.start, this.end, this.raw);
  String get lower => text.toLowerCase();
}

class _Hit {
  final String word, number, marker;
  final int start, end;
  final String? context, context2;
  const _Hit({
    required this.word,
    required this.number,
    required this.marker,
    required this.start,
    required this.end,
    this.context,
    this.context2,
  });
}
