/// A question that asks for the news rather than a fact: "what's the latest
/// news?", "news in Canada today", "any news about the Blue Jays?", "tech
/// headlines". Such questions are answered from a news listing (dated,
/// attributed stories) instead of whatever pages a web search ranks first —
/// for "latest news" those are front pages and aggregators whose extracted
/// text is a few lines of links (measured on the S25+, 2026-09-23).
enum NewsCategory {
  world,
  national,
  politics,
  business,
  technology,
  science,
  health,
  sports,
  entertainment,
}

class NewsIntent {
  /// What the news should be about ("Toronto Blue Jays", "AI regulation");
  /// null for a general briefing.
  final String? topic;

  /// A section of the news rather than a topic ("tech news").
  final NewsCategory? category;

  /// A country or region the question names ("news in Canada"), as a
  /// DuckDuckGo region code (`ca-en`), or null for the user's own region.
  final String? place;

  /// DuckDuckGo's news window: `d` (last day) or `w` (last week).
  final String window;

  const NewsIntent({this.topic, this.category, this.place, this.window = 'd'});

  bool get general => topic == null;

  /// The news query for the search provider: the topic, else the section or
  /// place, else plain "news" (a mix of the day's top stories for the region).
  String query({String? placeName}) {
    if (topic != null) return topic!;
    final section = category == null ? '' : _categoryQuery[category]!;
    if (placeName != null && section.isNotEmpty) return '$placeName $section';
    if (placeName != null) return '$placeName news';
    return section.isEmpty ? 'news' : section;
  }

  static const _categoryQuery = {
    NewsCategory.world: 'world news',
    NewsCategory.national: 'national news',
    NewsCategory.politics: 'politics news',
    NewsCategory.business: 'business news',
    NewsCategory.technology: 'technology news',
    NewsCategory.science: 'science news',
    NewsCategory.health: 'health news',
    NewsCategory.sports: 'sports news',
    NewsCategory.entertainment: 'entertainment news',
  };

  @override
  String toString() =>
      'NewsIntent(topic: $topic, category: $category, place: $place, window: $window)';

  static final _newsWord = RegExp(
    r"\b(news|headlines?|top stor(?:y|ies)|breaking|current events|what'?s (?:going on|happening)|what is (?:going on|happening)|what happened (?:today|yesterday|this week|overnight)|actualit[ée]s?|nouvelles|manchettes|infos)\b",
    caseSensitive: false,
  );

  // Asking about the news business, or for writing, is not asking for news.
  static final _notNews = RegExp(
    r"\b(how (?:do|does|to|can|should)|explain|definition|define|write|draft|compose|history of|fake news|news ?(?:app|site|website|source|outlet|anchor|reader|letter|paper|room|agency|feed|article|report|story) (?:for|to|that|which|recommend)|recommend (?:a|some)? ?(?:good |reliable )?news|(?:best|good|reliable) news (?:apps?|sites?|sources?)|rss|api)\b",
    caseSensitive: false,
  );

  static final _timely = RegExp(
    r"\b(latest|today|tonight|this (?:morning|afternoon|evening|week)|yesterday|recent(?:ly)?|current|breaking|new|now|right now|top|any|what'?s|what is|aujourd'?hui|derni[èe]res?)\b",
    caseSensitive: false,
  );

  /// The news intent of [question], or null when it is not a news request.
  static NewsIntent? of(String question) {
    final q = question.trim();
    if (q.isEmpty ||
        !(_newsWord.hasMatch(q) || _newsWordIntl.hasMatch(q)) ||
        _notNews.hasMatch(q)) {
      return null;
    }
    if (RegExp(r'https?://').hasMatch(q)) return null;
    final words = q.split(RegExp(r'\s+')).length;
    // A long message that merely mentions the news is a task, not a request
    // for a briefing ("summarise this news article …").
    if (words > 16) return null;
    if (!_timely.hasMatch(q) && !_timelyIntl.hasMatch(q) && words > 7) {
      return null;
    }
    final rest = _residue(q);
    NewsCategory? category;
    String? place;
    final leftover = <String>[];
    for (final w in rest) {
      final lower = w.toLowerCase();
      final c = _categories[lower];
      final p = _places[lower];
      if (c != null && category == null) {
        category = c;
      } else if (p != null && place == null) {
        place = p;
      } else {
        leftover.add(w);
      }
    }
    // Two-word places ("united states", "new zealand").
    final joined = leftover.join(' ').toLowerCase();
    for (final entry in _placePhrases.entries) {
      if (place == null && joined.contains(entry.key)) {
        place = entry.value;
        leftover.removeWhere(
          (w) => entry.key.split(' ').contains(w.toLowerCase()),
        );
      }
    }
    final topic = leftover.join(' ').trim();
    final week = RegExp(
      r'\b(this week|week|recent(?:ly)?|lately|past few days)\b',
      caseSensitive: false,
    ).hasMatch(q);
    return NewsIntent(
      topic: topic.isEmpty ? null : topic,
      category: category,
      place: place,
      window: week || topic.isNotEmpty ? 'w' : 'd',
    );
  }

  /// The words that are left once the news wording, question words and
  /// fillers are gone, in order.
  static List<String> _residue(String q) {
    final cleaned = q
        .replaceAll(
          RegExp(r"\bwhat(?:[’']s| is) new\b", caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'\bU\.S\.(?=\s|$)'), 'US')
        .replaceAll(RegExp(r"[’']s\b"), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s.&+-]', unicode: true), ' ')
        .replaceAll(RegExp(r'[.]+(?=\s|$)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final words = cleaned.split(' ');
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;
      // "US news" is a place; "tell us" is filler.
      if (w == 'US') {
        out.add(w);
        continue;
      }
      // "New York" and "New Zealand" keep their "New".
      if (w.toLowerCase() == 'new') {
        final next = i + 1 < words.length ? words[i + 1] : '';
        if (next.isNotEmpty &&
            next[0] == next[0].toUpperCase() &&
            RegExp(r'^\p{Lu}', unicode: true).hasMatch(next)) {
          out.add(w);
        }
        continue;
      }
      final lower = w.toLowerCase();
      if (!_filler.contains(lower) && !_fillerIntl.contains(lower)) out.add(w);
    }
    return out;
  }

  // French and Spanish news requests (\b is ASCII-only in Dart, so accented
  // words are bounded by Unicode letter lookarounds).
  static final _newsWordIntl = RegExp(
    r"(?<![\p{L}\p{N}])(actualit[ée]s?|nouvelles|infos|les titres|quoi de neuf|que se passe-t-il|noticias|titulares|[úu]ltima hora|qu[ée] (?:est[áa] pasando|pas[óo]|hay de nuevo)|actualidad)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  static final _timelyIntl = RegExp(
    r"(?<![\p{L}\p{N}])(des nouvelles (?:de|du|des|sur)|aujourd'?hui|hier|ce (?:matin|soir)|cette semaine|derni[èe]res?|r[ée]centes?|en ce moment|hoy|ayer|esta (?:ma[ñn]ana|tarde|noche|semana)|[úu]ltim[oa]s?|recientes?|ahora|ahora mismo)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  static const _fillerIntl = {
    // French
    'quelles', 'quels', 'quelle', 'quel', 'sont', 'est', 'les', 'le', 'la',
    'des', 'de', 'du', 'en', 'sur', 'dernières', 'dernieres', 'dernière',
    'actualités', 'actualites', 'actualité', 'nouvelles', 'infos', 'titres',
    "aujourd'hui", 'aujourdhui', 'hier', 'cette', 'semaine', 'moment',
    // Spanish
    'cuáles', 'cuales', 'cuál', 'qué', 'que', 'son', 'es', 'las', 'los',
    'el', 'lo', 'del', 'sobre', 'últimas', 'ultimas', 'última', 'ultima',
    'últimos', 'ultimos', 'noticias', 'titulares', 'hora', 'hoy', 'ayer',
    'esta', 'semana', 'actualidad', 'ahora', 'hay', 'nuevo',
  };

  static const _filler = {
    'what',
    'whats',
    'what\'s',
    'is',
    'are',
    'was',
    'were',
    'the',
    'a',
    'an',
    'latest',
    'last',
    'news',
    'headline',
    'headlines',
    'top',
    'story',
    'stories',
    'breaking',
    'current',
    'currently',
    'events',
    'event',
    'today',
    'todays',
    'tonight',
    'yesterday',
    'this',
    'morning',
    'afternoon',
    'evening',
    'week',
    'weekend',
    'right',
    'now',
    'new',
    'recent',
    'recently',
    'lately',
    'past',
    'few',
    'days',
    'on',
    'about',
    'regarding',
    'around',
    'in',
    'at',
    'from',
    'for',
    'of',
    'with',
    'any',
    'some',
    'there',
    'tell',
    'give',
    'show',
    'get',
    'me',
    'us',
    'my',
    'please',
    'can',
    'could',
    'you',
    'would',
    'happening',
    'happened',
    'going',
    'go',
    'up',
    'update',
    'updates',
    'summary',
    'summarize',
    'summarise',
    'briefing',
    'brief',
    'rundown',
    'roundup',
    'overview',
    'main',
    'biggest',
    'big',
    'important',
    'major',
    'key',
    'and',
    'or',
    'do',
    'does',
    'did',
    'know',
    'actualite',
    'actualité',
    'actualites',
    'actualités',
    'nouvelles',
    'manchettes',
    'infos',
    'les',
    'la',
    'le',
    'des',
    'du',
    'de',
    'dernieres',
    'dernières',
    'derniere',
    'dernière',
    'aujourd',
    'hui',
    'quoi',
    'quelles',
    'sont',
    'en',
    'au',
    'aux',
  };

  static const _categories = {
    'world': NewsCategory.world,
    'international': NewsCategory.world,
    'global': NewsCategory.world,
    'monde': NewsCategory.world,
    'national': NewsCategory.national,
    'domestic': NewsCategory.national,
    'local': NewsCategory.national,
    'politics': NewsCategory.politics,
    'political': NewsCategory.politics,
    'politique': NewsCategory.politics,
    'business': NewsCategory.business,
    'economy': NewsCategory.business,
    'economic': NewsCategory.business,
    'financial': NewsCategory.business,
    'finance': NewsCategory.business,
    'market': NewsCategory.business,
    'markets': NewsCategory.business,
    'économie': NewsCategory.business,
    'tech': NewsCategory.technology,
    'technology': NewsCategory.technology,
    'techno': NewsCategory.technology,
    'science': NewsCategory.science,
    'scientific': NewsCategory.science,
    'space': NewsCategory.science,
    'health': NewsCategory.health,
    'medical': NewsCategory.health,
    'santé': NewsCategory.health,
    'sport': NewsCategory.sports,
    'sports': NewsCategory.sports,
    'entertainment': NewsCategory.entertainment,
    'celebrity': NewsCategory.entertainment,
    'showbiz': NewsCategory.entertainment,
    'arts': NewsCategory.entertainment,
    'culture': NewsCategory.entertainment,
  };

  /// Country and region words → DuckDuckGo region.
  static const _places = {
    'canada': 'ca-en',
    'canadian': 'ca-en',
    'quebec': 'ca-fr',
    'québec': 'ca-fr',
    'us': 'us-en',
    'usa': 'us-en',
    'america': 'us-en',
    'american': 'us-en',
    'uk': 'uk-en',
    'britain': 'uk-en',
    'british': 'uk-en',
    'england': 'uk-en',
    'australia': 'au-en',
    'australian': 'au-en',
    'india': 'in-en',
    'indian': 'in-en',
    'ireland': 'ie-en',
    'irish': 'ie-en',
    'france': 'fr-fr',
    'french': 'fr-fr',
    'germany': 'de-de',
    'german': 'de-de',
    'italy': 'it-it',
    'italian': 'it-it',
    'italia': 'it-it',
    'spain': 'es-es',
    'spanish': 'es-es',
    'mexico': 'mx-es',
    'brazil': 'br-pt',
    'japan': 'jp-jp',
    'japanese': 'jp-jp',
  };

  static const _placePhrases = {
    'united states': 'us-en',
    'united kingdom': 'uk-en',
    'great britain': 'uk-en',
    'new zealand': 'nz-en',
    'south africa': 'za-en',
  };

  /// The display name of a region for a provider query ("Canada news").
  static String? placeName(String? region) => switch (region) {
    'ca-en' || 'ca-fr' => 'Canada',
    'us-en' => 'US',
    'uk-en' => 'UK',
    'au-en' => 'Australia',
    'nz-en' => 'New Zealand',
    'in-en' => 'India',
    'ie-en' => 'Ireland',
    'za-en' => 'South Africa',
    'fr-fr' => 'France',
    'de-de' => 'Germany',
    'it-it' => 'Italy',
    'es-es' => 'Spain',
    'mx-es' => 'Mexico',
    'br-pt' => 'Brazil',
    'jp-jp' => 'Japan',
    _ => null,
  };
}
