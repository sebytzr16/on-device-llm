import '../../retrieval/domain/evidence.dart';

/// Task-specific research instructions. These guide the bounded web tools;
/// they never enable web access or bypass the public-address policy.
class ResearchRecipe {
  final String id;
  final String instructions;
  final String? preferredDomain;
  const ResearchRecipe(this.id, this.instructions, {this.preferredDomain});

  static const general = ResearchRecipe(
    'general',
    'Search for the specific claim, read a relevant source, and verify '
        'important facts against an independent source. Prefer original '
        'documents when available. Check dates and state uncertainty.',
  );

  /// At most two publisher queries, each keeping the model named by the user.
  /// An unrelated official result does not satisfy coverage for that model.
  List<String> primaryQueries<T>(
    String question,
    List<T> results, {
    required String Function(T) urlOf,
    required String Function(T) textOf,
  }) {
    if (id != 'product') return const [];
    final found = <({int start, int end, String name, List<String> domains})>[];
    for (final entry in _makers.entries) {
      final pattern = RegExp(
        '(?<![\\p{L}\\p{N}])(?:${entry.key})(?![\\p{L}\\p{N}])',
        unicode: true,
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(question)) {
        found.add((
          start: match.start,
          end: match.end,
          name: match[0]!,
          domains: entry.value,
        ));
      }
    }
    found.sort((a, b) => a.start.compareTo(b.start));
    final queries = <String>[];
    final separators = RegExp(
      r'\b(vs\.?|versus|and|with|to|or|et|contre|avec|ou|y|contra|con|o|for|pour|para|specifications|specs|review|compare)\b|[?,;:()]',
      caseSensitive: false,
    );
    for (var i = 0; i < found.length && queries.length < 2; i++) {
      final maker = found[i];
      final tail = question
          .substring(
            maker.end,
            i + 1 < found.length ? found[i + 1].start : question.length,
          )
          .split(separators)
          .first
          .trim();
      final model = tail.split(RegExp(r'\s+')).take(5).join(' ').trim();
      // A brand alone is not an exact product: let broad search handle it.
      if (model.isEmpty || !RegExp(r'\d').hasMatch(model)) continue;
      final subject = '${maker.name} $model';
      final terms = EvidenceRanker.terms(model).toSet();
      final covered = results.any((r) {
        final host = Uri.tryParse(urlOf(r))?.host.toLowerCase() ?? '';
        return maker.domains.any((d) => host == d || host.endsWith('.$d')) &&
            EvidenceRanker.terms(
              '${textOf(r)} ${urlOf(r)}',
            ).toSet().containsAll(terms);
      });
      if (!covered) {
        queries.add('site:${maker.domains.first} $subject specifications');
      }
    }
    return queries.toSet().toList();
  }

  /// Source routing is a relevance tie-breaker, not proof that a claim is true.
  /// Never let a similarly named host impersonate an official domain.
  bool prefers(String url, String question) {
    final uri = Uri.tryParse(url);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) return false;
    final host = uri.host.toLowerCase();
    bool belongs(String domain) => host == domain || host.endsWith('.$domain');
    if (host == 'github.com') {
      return id == 'software' &&
          RegExp(
            r'\b(llama\.cpp|gguf)\b',
            caseSensitive: false,
          ).hasMatch(question) &&
          (uri.path == '/ggml-org/llama.cpp' ||
              uri.path.startsWith('/ggml-org/llama.cpp/'));
    }
    if (preferredDomain != null && belongs(preferredDomain!)) return true;
    if (primaryDomains(question).any(belongs)) return true;
    final government =
        RegExp(r'(^|\.)gov(?:\.[a-z]{2})?$').hasMatch(host) ||
        host.endsWith('.gc.ca') ||
        host == 'canada.ca';
    final university = host.endsWith('.edu') || host.endsWith('.ac.uk');
    return switch (id) {
      'law' || 'travel' || 'health' || 'finance' => government,
      'science' => university,
      _ => false,
    };
  }

  /// Promote primary sources only within the leading relevance candidates.
  /// Broadly irrelevant official pages cannot displace a matching result.
  List<T> order<T>(
    List<T> ranked,
    String question, {
    required String Function(T) urlOf,
    required String Function(T) textOf,
  }) {
    final leading = ranked.take(6).toList();
    final terms = EvidenceRanker.terms(question).toSet();
    bool primary(T r) {
      final hits = EvidenceRanker.terms(textOf(r)).toSet().intersection(terms);
      final subject = terms.difference({
        'actor',
        'actress',
        'biography',
        'filmography',
        'who',
        'is',
        'was',
        'born',
        'died',
        'biographie',
        'biografía',
        'qui',
        'quién',
      });
      final uri = Uri.tryParse(urlOf(r));
      final namedBiography =
          id == 'biography' &&
          preferredDomain != null &&
          uri != null &&
          (uri.host == preferredDomain ||
              uri.host.endsWith('.$preferredDomain')) &&
          subject.isNotEmpty &&
          EvidenceRanker.terms(
            Uri.decodeComponent(uri.path.replaceAll('_', ' ')),
          ).toSet().containsAll(subject);
      return prefers(urlOf(r), question) &&
          (terms.isEmpty ||
              hits.length / terms.length >= 0.5 ||
              namedBiography);
    }

    return [
      ...leading.where(primary),
      ...leading.where((r) => !primary(r)),
      ...ranked.skip(6),
    ];
  }

  /// Known manufacturer hosts grouped by maker, deduplicating brand aliases.
  /// Empty means publisher authority cannot be established from this registry.
  static List<List<String>> manufacturerDomainGroups(String question) {
    final groups = <List<String>>[];
    for (final entry in _makers.entries) {
      if (!RegExp(
        '(?<![\\p{L}\\p{N}])(?:${entry.key})(?![\\p{L}\\p{N}])',
        unicode: true,
        caseSensitive: false,
      ).hasMatch(question)) {
        continue;
      }
      if (!groups.any((group) => group.join('|') == entry.value.join('|'))) {
        groups.add(entry.value);
      }
    }
    return groups;
  }

  /// Known publishers are selected only when the question names their subject
  /// or jurisdiction. Unknown brands/places keep the broader relevance ranking.
  List<String> primaryDomains(String question) {
    final q = question.toLowerCase();
    bool names(String words) => RegExp(
      '(?<![\\p{L}\\p{N}])(?:$words)(?![\\p{L}\\p{N}])',
      unicode: true,
    ).hasMatch(q);
    return switch (id) {
      'health' => [
        'who.int',
        if (names('canada|canadian|canadien|canadiense')) 'canada.ca',
        if (names('united states|usa|u\\.s\\.')) 'cdc.gov',
        if (names('uk|united kingdom|britain|british')) 'nhs.uk',
      ],
      'law' => [
        if (names('ontario')) 'ontario.ca',
        if (names('canada|canadian|canadien|canadiense'))
          'laws-lois.justice.gc.ca',
        if (names('united states|usa|u\\.s\\.')) 'congress.gov',
        if (names('uk|united kingdom|britain')) 'legislation.gov.uk',
        if (names('european union|eu')) 'eur-lex.europa.eu',
      ],
      'finance' => [
        if (names('sec|10-k|10k|united states|usa')) 'sec.gov',
        if (names('bank of canada|canada interest')) 'bankofcanada.ca',
        if (names('federal reserve|fed rate')) 'federalreserve.gov',
      ],
      'weather' => [
        if (names('canada|toronto|montreal|vancouver|ottawa|quebec'))
          'weather.gc.ca',
        if (names('united states|usa|new york|chicago|seattle')) 'weather.gov',
        if (names('uk|united kingdom|london|manchester')) 'metoffice.gov.uk',
      ],
      'biography' => [
        'wikipedia.org',
        'wikidata.org',
        if (names('nobel|curie|einstein')) 'nobelprize.org',
      ],
      'science' => ['arxiv.org', 'pubmed.ncbi.nlm.nih.gov', 'doi.org'],
      'product' => [
        for (final MapEntry(key: maker, value: domains) in _makers.entries)
          if (names(maker)) ...domains,
      ],
      'software' => [
        if (names('flutter|dart')) ...['flutter.dev', 'dart.dev'],
        if (names('python')) 'python.org',
        if (names('postgresql|postgres')) 'postgresql.org',
        if (names('llama.cpp|gguf')) 'github.com',
        if (names('android|adb')) 'developer.android.com',
        if (names('git')) 'git-scm.com',
      ],
      'travel' => [
        if (names('canada|canadian|canadien')) ...['travel.gc.ca', 'canada.ca'],
        if (names('uk|united kingdom')) 'gov.uk',
      ],
      'sports' => [
        if (names('football|soccer|ifab')) 'theifab.com',
        if (names('fifa|world cup|coupe du monde|copa mundial')) 'fifa.com',
        if (names('nba')) 'nba.com',
        if (names('nhl')) 'nhl.com',
        if (names('nfl')) 'nfl.com',
        if (names('mlb')) 'mlb.com',
      ],
      _ => const [],
    };
  }

  static ResearchRecipe forQuestion(String question) {
    final q = question.toLowerCase();
    if (_local.hasMatch(q)) return general;
    if (_health.hasMatch(q)) {
      return const ResearchRecipe(
        'health',
        'For health information, first search current public-health or '
            'medical-institution guidance, then the underlying study when '
            'needed. Check publication and update dates. Distinguish evidence '
            'from treatment advice and report uncertainty.',
      );
    }
    if (_law.hasMatch(q)) {
      return const ResearchRecipe(
        'law',
        'Identify the jurisdiction and date. Search the current statute, '
            'regulation, court decision or official government guidance first; '
            'use commentary only to explain it. Cite the controlling source.',
      );
    }
    if (_money.hasMatch(q)) {
      return const ResearchRecipe(
        'finance',
        'For prices, rates and company figures, check the timestamp and '
            'currency. Search official filings, exchange or issuer data first, '
            'then independently confirm material figures. Never present an '
            'old quote as current.',
      );
    }
    if (_news.hasMatch(q)) {
      if (RegExp(
        r'\b(on what date|first|historical|history|in (?:19|20)\d{2})\b',
      ).hasMatch(q)) {
        return const ResearchRecipe(
          'news',
          'Use search_web for the original announcement or dated historical '
              'report. Check the event date against an independent source; '
              'current headlines do not establish a past event.',
        );
      }
      // No preferred domain: Reuters answers every plain client with 401
      // (measured 2026-09-23), so "Reuters first" meant unreadable first.
      return const ResearchRecipe(
        'news',
        'Call search_news first: it returns dated stories from established '
            'outlets. Read one or two of the most relevant stories with '
            'read_url for details, confirm the key fact with an independent '
            'outlet, separate the event date from the publication date and '
            'say when reports conflict.',
      );
    }
    if (_weather.hasMatch(q) &&
        !RegExp(r'weather[ -]*(?:seal|resistan)').hasMatch(q)) {
      return const ResearchRecipe(
        'weather',
        'Use the latest forecast from the relevant national weather service '
            'or official meteorological agency. State the location, forecast '
            'time and units. Do not treat an old article as a forecast.',
      );
    }
    if (_person.hasMatch(q)) {
      return const ResearchRecipe(
        'biography',
        'For a person, search Wikipedia or Wikidata first for identity, '
            'filmography and source leads; then verify key facts with an '
            'official biography, interview, credits database, or independent '
            'reporting. For current roles, use a current primary source.',
        preferredDomain: 'wikipedia.org',
      );
    }
    if (_science.hasMatch(q)) {
      return const ResearchRecipe(
        'science',
        'Search original research papers and university or research-institute '
            'explanations first. Compare review papers for consensus, report '
            'publication dates, and distinguish established results from '
            'preprints or hypotheses.',
      );
    }
    if (_product.hasMatch(q) ||
        _makers.keys.any(
          (maker) => RegExp(
            '(?<![\\p{L}\\p{N}])(?:$maker)(?![\\p{L}\\p{N}])[-a-z\\s]{0,20}\\d',
            unicode: true,
          ).hasMatch(q),
        )) {
      return const ResearchRecipe(
        'product',
        'Check manufacturer specifications and availability first, then '
            'independent reviews or measurements. Verify exact model and '
            'region, and date prices before comparing products. For comparisons, '
            'search each named model separately on its manufacturer site if the '
            'combined search lacks its specifications. A citation must support '
            'the exact model and feature; absent features remain unverified.',
      );
    }
    if (_software.hasMatch(q)) {
      return const ResearchRecipe(
        'software',
        'Search the project official documentation, release notes or source '
            'repository first. Confirm the version and date, then check '
            'issues or independent reports for known compatibility problems.',
      );
    }
    if (_travel.hasMatch(q)) {
      return const ResearchRecipe(
        'travel',
        'Check official transport, border, venue and tourism sources for '
            'schedules, entry rules and opening hours. State the date and '
            'location, then confirm practical details with another current '
            'source.',
      );
    }
    if (_sports.hasMatch(q)) {
      return const ResearchRecipe(
        'sports',
        'Check the league or team official schedule and results first. '
            'Verify scores and standings with a second current source, and '
            'state the season, date and time zone.',
      );
    }
    return general;
  }

  static final _local = RegExp(
    r'^(write|rewrite|draft|translate|proofread|summarize this|summarise this)\b',
  );
  static final _health = RegExp(
    r'\b(medical|medicine|drug|disease|symptoms?|treatment|vaccines?|diagnos\w*|health|santé|maladie|vaccin|salud|enfermedad|vacuna)\b',
  );
  static final _law = RegExp(
    r'\b(law|legal|statute|regulation|court|lawsuit|tax law|visa rules?|age of majority|accountability act|constitution|loi|juridique|tribunal|ley|leyes|reglamento)\b',
  );
  static final _money = RegExp(
    r'\b(stock|share price|exchange rate|interest rate|invest|earnings|market cap|inflation|financial|10-k|taux de change|taux d’intérêt|financier|tipo de cambio|financiero)\b',
  );
  static final _news = RegExp(
    r'\b(news|headline|breaking|latest event|current event|actualités|nouvelles|noticias|titulares)\b',
  );
  static final _weather = RegExp(
    r'\b(weather|forecast|temperature|rainfall|snowfall|météo|prévisions|pronóstico|clima)\b',
  );
  static final _person = RegExp(
    r'\b(actor|actress|filmography|biography|who is|who was|born|died|biographie|qui est|qui était|biografía|quién es|quién fue)\b',
  );
  static final _science = RegExp(
    r'\b(science|scientific|research paper|quantum|physics|chemistry|biology|study|studies|scientifique|quantique|ciencia|científico|cuántica)\b',
  );
  static final _product = RegExp(
    r'\b(buy|purchase|product|laptop|phone|camera|headphone|review|specifications|specs|megapixels|nikon|sony|samsung|iphone|ipad|macbook|fujifilm|panasonic|lumix|om system|leica|dji|gopro|garmin|bose|acheter|appareil photo|comprar|cámara)\b',
  );

  /// Makers whose own pages hold a product's specifications, by the names
  /// a question uses for them (review #7: maker pages first). Names
  /// that also mean something else (canon, Olympus, Galaxy, Pixel, Apple)
  /// pick the domains but do not make a question a product question.
  static const _makers = {
    'nikon': ['nikon.com', 'nikonusa.com', 'nikon.ca'],
    'sony': ['sony.com', 'sony.ca', 'sony.co.uk', 'sony.net'],
    'apple|iphone|ipad|macbook': ['apple.com'],
    'samsung|galaxy': ['samsung.com'],
    'canon': ['canon.com', 'canon.ca'],
    'fujifilm|fuji x': ['fujifilm.com', 'fujifilm-x.com'],
    'panasonic|lumix': ['panasonic.com'],
    'om system|olympus': ['omsystem.com'],
    'leica': ['leica-camera.com'],
    'dji': ['dji.com'],
    'gopro': ['gopro.com'],
    'pixel': ['store.google.com'],
    'garmin': ['garmin.com'],
    'bose': ['bose.com'],
  };
  static final _software = RegExp(
    r'\b(software|library|framework|api|flutter|python|postgresql|postgres|llama\.cpp|gguf|android|adb|git|release notes|version|logiciel|bibliothèque)\b',
  );
  static final _travel = RegExp(
    r'\b(travel|trip|flight|train|hotel|visa|border|opening hours|passport|voyage|passeport|viaje|pasaporte)\b',
  );
  static final _sports = RegExp(
    r'\b(score|standings|league|match|game|playoffs|tournament|fifa|world cup|nba|nhl|nfl|mlb|football|soccer|ifab|sport|ligue|deporte|liga)\b',
  );
}
