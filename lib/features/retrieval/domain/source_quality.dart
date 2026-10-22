/// What the app knows about a web host before reading it: the publisher's
/// name, how established it is, whether its pages can be read without a
/// browser, and whether it is filler. Search engines rank by relevance;
/// this is the prior that puts BBC, CBC or Wikipedia ahead of an aggregator
/// that happens to match the words (report 2026-09-23: "latest news in
/// Canada" read latestcanada.com and canadanewsmedia.ca).
class SourceQuality {
  /// Host without a leading `www.`/`m.`/`amp.`, lower case.
  static String hostOf(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host.replaceFirst(RegExp(r'^(www\d?|m|amp|mobile)\.'), '');
  }

  /// The known outlet a host belongs to (subdomains included), or null.
  static Outlet? outletOf(String url) {
    var host = hostOf(url);
    while (host.contains('.')) {
      final hit = _outlets[host];
      if (hit != null) return hit;
      host = host.substring(host.indexOf('.') + 1);
    }
    return null;
  }

  /// The tier of a publisher named in a news listing ("CBC", "The Canadian
  /// Press", "Daily Mail"), matched against the known outlets' names.
  static OutletTier? tierByName(String name) {
    final key = _nameKey(name);
    if (key.isEmpty) return null;
    return _byName[key] ?? _extraNames[key];
  }

  static String _nameKey(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'^the\s+'), '')
      .replaceAll(RegExp(r'\b(news|online|\.com|\.ca|\.co\.uk)\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static final Map<String, OutletTier> _byName = {
    for (final o in _outlets.values) _nameKey(o.name): o.tier,
  };

  static const _extraNames = {
    'associatedpress': OutletTier.top,
    'ap': OutletTier.top,
    'canadianpress': OutletTier.top,
    'cp': OutletTier.top,
    'agencefrancepresse': OutletTier.top,
    'bbc': OutletTier.top,
    'cbc': OutletTier.top,
    'ctv': OutletTier.major,
    'global': OutletTier.major,
    'globeandmail': OutletTier.top,
    'torontostar': OutletTier.major,
    'nationalpost': OutletTier.major,
    'guardian': OutletTier.top,
    'newyorktimes': OutletTier.top,
    'washingtonpost': OutletTier.top,
    'wallstreetjournal': OutletTier.top,
    'bloomberg': OutletTier.top,
    'reuters': OutletTier.top,
    'npr': OutletTier.top,
    'pbs': OutletTier.top,
    'aljazeera': OutletTier.major,
    'cnn': OutletTier.major,
    'abc': OutletTier.major,
    'cbs': OutletTier.major,
    'nbc': OutletTier.major,
    'sky': OutletTier.major,
    'foxbusiness': OutletTier.minor,
    'rawstory': OutletTier.minor,
    'alternet': OutletTier.minor,
    'dailybeast': OutletTier.minor,
    'huffpost': OutletTier.minor,
    'huffingtonpost': OutletTier.minor,
    'mediaite': OutletTier.minor,
    'thewrap': OutletTier.minor,
    'yahoo': OutletTier.minor,
    'yahoonews': OutletTier.minor,
    'msn': OutletTier.minor,
    'benzinga': OutletTier.minor,
    'fool': OutletTier.minor,
    'motleyfool': OutletTier.minor,
  };

  /// 0 (filler) to 1 (wire service, public broadcaster, reference work,
  /// official source); unknown hosts sit at 0.35.
  static double authority(String url) {
    final host = hostOf(url);
    if (host.isEmpty) return 0;
    if (lowValue(url)) return 0;
    final outlet = outletOf(url);
    if (outlet != null) return outlet.tier.weight;
    if (_official.hasMatch(host)) return 0.9;
    if (_docsHost.hasMatch(host)) return 0.75;
    return 0.35;
  }

  /// Hosts whose pages never yield text to a plain HTTP client: bot walls
  /// (Reuters answers 401 to every client, measured 2026-09-23), hard
  /// paywalls and script-only shells (MSN's syndicated copies). Their
  /// search snippets and news ledes are still usable; reading is skipped.
  static bool unreadable(String url) {
    final host = hostOf(url);
    return _unreadable.any((h) => host == h || host.endsWith('.$h'));
  }

  /// Social feeds, video, Q&A farms and news aggregators that repackage
  /// other outlets' headlines.
  static bool lowValue(String url) {
    final host = hostOf(url);
    if (_lowValue.any((h) => host == h || host.endsWith('.$h'))) return true;
    return _aggregatorName.hasMatch(host) && outletOf(url) == null;
  }

  /// A front page or section index ("/", "/news", "/world/", "/local/")
  /// rather than an article: a list of headlines whose text extraction is a
  /// few lines of links.
  static bool isFrontPage(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return true;
    if (segments.length > 2) return false;
    final last = segments.last.toLowerCase().replaceAll(
      RegExp(r'\.(html?|php|aspx?)$'),
      '',
    );
    if (segments.length == 2 && !_section.hasMatch(segments.first)) {
      return false;
    }
    return _section.hasMatch(last);
  }

  static final _section = RegExp(
    r'^(index|home|news|world|latest|live|local|canada|us|uk|national|international|politics|business|economy|markets|sport|sports|tech|technology|science|health|entertainment|culture|opinion|breaking(-news)?|top-?stories|headlines|actualites?|nouvelles|en|fr|sections?|topics?|category|tag)$',
    caseSensitive: false,
  );

  static final _official = RegExp(
    r'(\.gov|\.gouv\.[a-z]{2}|\.gc\.ca|\.canada\.ca|\.gov\.[a-z]{2}|\.europa\.eu|\.int|\.edu|\.ac\.[a-z]{2}|\.mil)$|^(canada\.ca|gov\.uk|europa\.eu)$',
  );

  static final _docsHost = RegExp(
    r'^(docs|developer|developers|documentation|learn|reference|support|help)\.',
  );

  static final _aggregatorName = RegExp(
    r'(latest|daily|breaking|today|247|24x7|trending|viral|buzz)[a-z-]*news|news(media|now|hub|wire|daily|today|break|point|feed|online|24|365|express)|^(latest|news)[a-z]+\.(ca|com|net|org|info|co)$',
  );

  static const _unreadable = [
    'reuters.com',
    'nytimes.com',
    'wsj.com',
    'ft.com',
    'bloomberg.com',
    'economist.com',
    'washingtonpost.com',
    'theathletic.com',
    'msn.com',
    'barrons.com',
    'businessinsider.com',
    'newyorker.com',
    'scribd.com',
    'coursehero.com',
    'chegg.com',
    'statista.com',
    'instagram.com',
    'facebook.com',
    'x.com',
    'twitter.com',
    'tiktok.com',
  ];

  static const _lowValue = [
    'youtube.com',
    'youtu.be',
    'facebook.com',
    'instagram.com',
    'tiktok.com',
    'x.com',
    'twitter.com',
    'pinterest.com',
    'pinterest.ca',
    'linkedin.com',
    'threads.net',
    'snapchat.com',
    'quora.com',
    'answers.com',
    'ask.com',
    'ehow.com',
    'canadanewsmedia.ca',
    'latestcanada.com',
    'newsbreak.com',
    'newsnow.co.uk',
    'newsnow.com',
    'ground.news',
    'flipboard.com',
    'inkl.com',
    'headtopics.com',
    'newsbreakapp.com',
    'dailyhunt.in',
    'opera.com',
    'ampproject.org',
  ];

  static const _outlets = <String, Outlet>{
    // Wires and public broadcasters.
    'reuters.com': Outlet('Reuters', OutletTier.top, OutletKind.news),
    'apnews.com': Outlet('AP News', OutletTier.top, OutletKind.news),
    'afp.com': Outlet('AFP', OutletTier.top, OutletKind.news),
    'bbc.com': Outlet('BBC News', OutletTier.top, OutletKind.news),
    'bbc.co.uk': Outlet('BBC News', OutletTier.top, OutletKind.news),
    'npr.org': Outlet('NPR', OutletTier.top, OutletKind.news),
    'pbs.org': Outlet('PBS NewsHour', OutletTier.top, OutletKind.news),
    'cbc.ca': Outlet('CBC News', OutletTier.top, OutletKind.news),
    'radio-canada.ca': Outlet('Radio-Canada', OutletTier.top, OutletKind.news),
    'thecanadianpress.com': Outlet(
      'The Canadian Press',
      OutletTier.top,
      OutletKind.news,
    ),
    'abc.net.au': Outlet(
      'ABC News (Australia)',
      OutletTier.top,
      OutletKind.news,
    ),
    'dw.com': Outlet('DW', OutletTier.top, OutletKind.news),
    'france24.com': Outlet('France 24', OutletTier.top, OutletKind.news),
    'rfi.fr': Outlet('RFI', OutletTier.top, OutletKind.news),
    'francetvinfo.fr': Outlet('franceinfo', OutletTier.top, OutletKind.news),
    'nhk.or.jp': Outlet('NHK', OutletTier.top, OutletKind.news),
    'aljazeera.com': Outlet('Al Jazeera', OutletTier.major, OutletKind.news),
    // Papers of record and major networks.
    'theguardian.com': Outlet('The Guardian', OutletTier.top, OutletKind.news),
    'nytimes.com': Outlet(
      'The New York Times',
      OutletTier.top,
      OutletKind.news,
    ),
    'washingtonpost.com': Outlet(
      'The Washington Post',
      OutletTier.top,
      OutletKind.news,
    ),
    'wsj.com': Outlet(
      'The Wall Street Journal',
      OutletTier.top,
      OutletKind.news,
    ),
    'ft.com': Outlet('Financial Times', OutletTier.top, OutletKind.news),
    'economist.com': Outlet('The Economist', OutletTier.top, OutletKind.news),
    'bloomberg.com': Outlet('Bloomberg', OutletTier.top, OutletKind.news),
    'theglobeandmail.com': Outlet(
      'The Globe and Mail',
      OutletTier.top,
      OutletKind.news,
    ),
    'lemonde.fr': Outlet('Le Monde', OutletTier.top, OutletKind.news),
    'ledevoir.com': Outlet('Le Devoir', OutletTier.top, OutletKind.news),
    'lapresse.ca': Outlet('La Presse', OutletTier.top, OutletKind.news),
    'elpais.com': Outlet('El País', OutletTier.top, OutletKind.news),
    'spiegel.de': Outlet('Der Spiegel', OutletTier.top, OutletKind.news),
    'tagesschau.de': Outlet('tagesschau', OutletTier.top, OutletKind.news),
    'ansa.it': Outlet('ANSA', OutletTier.top, OutletKind.news),
    'corriere.it': Outlet(
      'Corriere della Sera',
      OutletTier.major,
      OutletKind.news,
    ),
    'thehindu.com': Outlet('The Hindu', OutletTier.major, OutletKind.news),
    'indianexpress.com': Outlet(
      'The Indian Express',
      OutletTier.major,
      OutletKind.news,
    ),
    'smh.com.au': Outlet(
      'The Sydney Morning Herald',
      OutletTier.major,
      OutletKind.news,
    ),
    'cnn.com': Outlet('CNN', OutletTier.major, OutletKind.news),
    'cbsnews.com': Outlet('CBS News', OutletTier.major, OutletKind.news),
    'nbcnews.com': Outlet('NBC News', OutletTier.major, OutletKind.news),
    'abcnews.go.com': Outlet('ABC News', OutletTier.major, OutletKind.news),
    'usatoday.com': Outlet('USA Today', OutletTier.major, OutletKind.news),
    'latimes.com': Outlet(
      'Los Angeles Times',
      OutletTier.major,
      OutletKind.news,
    ),
    'politico.com': Outlet('Politico', OutletTier.major, OutletKind.news),
    'politico.eu': Outlet('Politico Europe', OutletTier.major, OutletKind.news),
    'axios.com': Outlet('Axios', OutletTier.major, OutletKind.news),
    'theatlantic.com': Outlet(
      'The Atlantic',
      OutletTier.major,
      OutletKind.news,
    ),
    'time.com': Outlet('TIME', OutletTier.major, OutletKind.news),
    'independent.co.uk': Outlet(
      'The Independent',
      OutletTier.major,
      OutletKind.news,
    ),
    'telegraph.co.uk': Outlet(
      'The Telegraph',
      OutletTier.major,
      OutletKind.news,
    ),
    'news.sky.com': Outlet('Sky News', OutletTier.major, OutletKind.news),
    'euronews.com': Outlet('Euronews', OutletTier.major, OutletKind.news),
    'cnbc.com': Outlet('CNBC', OutletTier.major, OutletKind.news),
    'marketwatch.com': Outlet('MarketWatch', OutletTier.major, OutletKind.news),
    'ctvnews.ca': Outlet('CTV News', OutletTier.major, OutletKind.news),
    'globalnews.ca': Outlet('Global News', OutletTier.major, OutletKind.news),
    'thestar.com': Outlet('Toronto Star', OutletTier.major, OutletKind.news),
    'nationalpost.com': Outlet(
      'National Post',
      OutletTier.major,
      OutletKind.news,
    ),
    'financialpost.com': Outlet(
      'Financial Post',
      OutletTier.major,
      OutletKind.news,
    ),
    'cp24.com': Outlet('CP24', OutletTier.major, OutletKind.news),
    'citynews.ca': Outlet('CityNews', OutletTier.major, OutletKind.news),
    'macleans.ca': Outlet("Maclean's", OutletTier.major, OutletKind.news),
    'montrealgazette.com': Outlet(
      'Montreal Gazette',
      OutletTier.major,
      OutletKind.news,
    ),
    'vancouversun.com': Outlet(
      'Vancouver Sun',
      OutletTier.major,
      OutletKind.news,
    ),
    'ottawacitizen.com': Outlet(
      'Ottawa Citizen',
      OutletTier.major,
      OutletKind.news,
    ),
    'calgaryherald.com': Outlet(
      'Calgary Herald',
      OutletTier.major,
      OutletKind.news,
    ),
    'thehill.com': Outlet('The Hill', OutletTier.major, OutletKind.news),
    'foxnews.com': Outlet('Fox News', OutletTier.minor, OutletKind.news),
    'nypost.com': Outlet('New York Post', OutletTier.minor, OutletKind.news),
    'dailymail.co.uk': Outlet('Daily Mail', OutletTier.minor, OutletKind.news),
    'newsweek.com': Outlet('Newsweek', OutletTier.minor, OutletKind.news),
    'torontosun.com': Outlet('Toronto Sun', OutletTier.minor, OutletKind.news),
    'hindustantimes.com': Outlet(
      'Hindustan Times',
      OutletTier.minor,
      OutletKind.news,
    ),
    'timesofindia.indiatimes.com': Outlet(
      'The Times of India',
      OutletTier.minor,
      OutletKind.news,
    ),
    'yahoo.com': Outlet('Yahoo News', OutletTier.minor, OutletKind.news),
    // Technology press.
    'theverge.com': Outlet('The Verge', OutletTier.major, OutletKind.news),
    'arstechnica.com': Outlet(
      'Ars Technica',
      OutletTier.major,
      OutletKind.news,
    ),
    'wired.com': Outlet('WIRED', OutletTier.major, OutletKind.news),
    'techcrunch.com': Outlet('TechCrunch', OutletTier.major, OutletKind.news),
    'engadget.com': Outlet('Engadget', OutletTier.major, OutletKind.news),
    'gsmarena.com': Outlet('GSMArena', OutletTier.major, OutletKind.reference),
    'rtings.com': Outlet('RTINGS', OutletTier.major, OutletKind.reference),
    'tomshardware.com': Outlet(
      "Tom's Hardware",
      OutletTier.major,
      OutletKind.news,
    ),
    'anandtech.com': Outlet('AnandTech', OutletTier.major, OutletKind.news),
    // Sport.
    'espn.com': Outlet('ESPN', OutletTier.major, OutletKind.sports),
    'mlb.com': Outlet('MLB.com', OutletTier.top, OutletKind.sports),
    'nhl.com': Outlet('NHL.com', OutletTier.top, OutletKind.sports),
    'nba.com': Outlet('NBA.com', OutletTier.top, OutletKind.sports),
    'nfl.com': Outlet('NFL.com', OutletTier.top, OutletKind.sports),
    'mlssoccer.com': Outlet('MLS', OutletTier.top, OutletKind.sports),
    'fifa.com': Outlet('FIFA', OutletTier.top, OutletKind.sports),
    'uefa.com': Outlet('UEFA', OutletTier.top, OutletKind.sports),
    'olympics.com': Outlet('Olympics', OutletTier.top, OutletKind.sports),
    'sportsnet.ca': Outlet('Sportsnet', OutletTier.major, OutletKind.sports),
    'tsn.ca': Outlet('TSN', OutletTier.major, OutletKind.sports),
    'cbssports.com': Outlet('CBS Sports', OutletTier.major, OutletKind.sports),
    'si.com': Outlet('Sports Illustrated', OutletTier.major, OutletKind.sports),
    'skysports.com': Outlet('Sky Sports', OutletTier.major, OutletKind.sports),
    // Reference works and institutions.
    'wikipedia.org': Outlet('Wikipedia', OutletTier.top, OutletKind.reference),
    'britannica.com': Outlet(
      'Britannica',
      OutletTier.top,
      OutletKind.reference,
    ),
    'who.int': Outlet(
      'World Health Organization',
      OutletTier.top,
      OutletKind.reference,
    ),
    'mayoclinic.org': Outlet(
      'Mayo Clinic',
      OutletTier.top,
      OutletKind.reference,
    ),
    'clevelandclinic.org': Outlet(
      'Cleveland Clinic',
      OutletTier.top,
      OutletKind.reference,
    ),
    'nhs.uk': Outlet('NHS', OutletTier.top, OutletKind.reference),
    'webmd.com': Outlet('WebMD', OutletTier.major, OutletKind.reference),
    'nature.com': Outlet('Nature', OutletTier.top, OutletKind.reference),
    'science.org': Outlet('Science', OutletTier.top, OutletKind.reference),
    'arxiv.org': Outlet('arXiv', OutletTier.top, OutletKind.reference),
    'pubmed.ncbi.nlm.nih.gov': Outlet(
      'PubMed',
      OutletTier.top,
      OutletKind.reference,
    ),
    'imdb.com': Outlet('IMDb', OutletTier.major, OutletKind.reference),
    'investopedia.com': Outlet(
      'Investopedia',
      OutletTier.major,
      OutletKind.reference,
    ),
    'merriam-webster.com': Outlet(
      'Merriam-Webster',
      OutletTier.top,
      OutletKind.reference,
    ),
    'nationalgeographic.com': Outlet(
      'National Geographic',
      OutletTier.major,
      OutletKind.reference,
    ),
    'history.com': Outlet(
      'History.com',
      OutletTier.major,
      OutletKind.reference,
    ),
    // Software.
    'github.com': Outlet('GitHub', OutletTier.major, OutletKind.reference),
    'stackoverflow.com': Outlet(
      'Stack Overflow',
      OutletTier.major,
      OutletKind.reference,
    ),
    'developer.mozilla.org': Outlet(
      'MDN',
      OutletTier.top,
      OutletKind.reference,
    ),
    'docs.python.org': Outlet(
      'Python docs',
      OutletTier.top,
      OutletKind.reference,
    ),
    'learn.microsoft.com': Outlet(
      'Microsoft Learn',
      OutletTier.top,
      OutletKind.reference,
    ),
    'developer.android.com': Outlet(
      'Android Developers',
      OutletTier.top,
      OutletKind.reference,
    ),
    'developer.apple.com': Outlet(
      'Apple Developer',
      OutletTier.top,
      OutletKind.reference,
    ),
    'docs.flutter.dev': Outlet(
      'Flutter docs',
      OutletTier.top,
      OutletKind.reference,
    ),
    'dart.dev': Outlet('Dart docs', OutletTier.top, OutletKind.reference),
    'pub.dev': Outlet('pub.dev', OutletTier.major, OutletKind.reference),
    'pypi.org': Outlet('PyPI', OutletTier.major, OutletKind.reference),
    'npmjs.com': Outlet('npm', OutletTier.major, OutletKind.reference),
    // Weather and markets.
    'weather.gc.ca': Outlet(
      'Environment Canada',
      OutletTier.top,
      OutletKind.reference,
    ),
    'weather.gov': Outlet(
      'National Weather Service',
      OutletTier.top,
      OutletKind.reference,
    ),
    'metoffice.gov.uk': Outlet(
      'Met Office',
      OutletTier.top,
      OutletKind.reference,
    ),
    'theweathernetwork.com': Outlet(
      'The Weather Network',
      OutletTier.major,
      OutletKind.reference,
    ),
    'accuweather.com': Outlet(
      'AccuWeather',
      OutletTier.major,
      OutletKind.reference,
    ),
    'weather.com': Outlet(
      'The Weather Channel',
      OutletTier.major,
      OutletKind.reference,
    ),
    'finance.yahoo.com': Outlet(
      'Yahoo Finance',
      OutletTier.major,
      OutletKind.reference,
    ),
    'bankofcanada.ca': Outlet(
      'Bank of Canada',
      OutletTier.top,
      OutletKind.reference,
    ),
    'federalreserve.gov': Outlet(
      'Federal Reserve',
      OutletTier.top,
      OutletKind.reference,
    ),
    'xe.com': Outlet('XE', OutletTier.major, OutletKind.reference),
  };
}

enum OutletTier {
  /// Wire services, public broadcasters, papers of record, reference works.
  top(1.0),

  /// Established national outlets and specialist publications.
  major(0.75),

  /// Tabloids, partisan outlets and syndication portals.
  minor(0.3);

  final double weight;
  const OutletTier(this.weight);
}

enum OutletKind { news, sports, reference }

class Outlet {
  final String name;
  final OutletTier tier;
  final OutletKind kind;
  const Outlet(this.name, this.tier, this.kind);
}
