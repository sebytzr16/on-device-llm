import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/l10n/l10n.dart';
import '../../data/network/web_search/duckduckgo_scraper.dart';
import '../../data/network/web_search/news_feed_parser.dart';
import '../../data/network/web_search/search_models.dart';
import '../../data/network/web_search/web_page_reader.dart';
import 'domain/evidence.dart';
import 'domain/news_intent.dart';
import 'domain/source_quality.dart';

/// A publisher feed the news desk may read.
class NewsFeed {
  final String outlet;
  final String url;
  final NewsCategory section;
  const NewsFeed(this.outlet, this.url, this.section);
}

/// What the news desk gathered for one question.
class NewsBriefing {
  /// Distinct stories, most important first: headline, publisher, time and
  /// lede. Each is its own source so answers cite story by story.
  final List<SearchResult> items;

  /// Full articles read for a topic question (a few, for depth).
  final List<SearchResult> articles;

  /// Why the provider listing is missing, when it is (feeds still count).
  final Object? providerError;
  final int feedsRead, feedsFailed;
  final Duration elapsed;
  const NewsBriefing({
    required this.items,
    this.articles = const [],
    this.providerError,
    this.feedsRead = 0,
    this.feedsFailed = 0,
    this.elapsed = Duration.zero,
  });

  bool get isEmpty => items.isEmpty && articles.isEmpty;
}

/// Answers "what's the news" fast and from outlets people know: DuckDuckGo's
/// news listing and a handful of publisher feeds are fetched in parallel
/// (about a second), the same story from several outlets is merged — and
/// counts as more important — and stories are ranked by recency, coverage
/// and the publisher's standing. A general briefing reads no article pages
/// (the ledes are the briefing); a topic question reads the two best
/// articles for depth. Everything goes through the public-web policy.
class NewsDesk {
  final DuckDuckGoScraper scraper;
  final WebPageReader reader;
  final DateTime Function() clock;

  NewsDesk({
    required this.scraper,
    required this.reader,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  Future<NewsBriefing> gather(
    NewsIntent intent, {
    String localeCode = '',
    String? region,
    String language = 'en-US,en;q=0.9',
    CancelToken? cancelToken,
    int maxItems = 12,
    int maxArticles = 2,
    Duration budget = const Duration(seconds: 7),
    void Function(String)? progress,
    AppLocalizations? strings,
  }) async {
    final t = strings ?? AppLocalizationsEn();
    final started = clock();
    final home = region ?? DuckDuckGoScraper.regionFor(localeCode);
    final target = intent.place ?? home;
    final placeName = intent.place != null && intent.place != home
        ? NewsIntent.placeName(intent.place)
        : null;
    final feeds = feedsFor(target, intent);
    Object? providerError;
    var feedsRead = 0, feedsFailed = 0;

    // Everything starts at once; the slowest source is cut at the budget.
    final listing = scraper
        .news(
          intent.query(placeName: placeName),
          window: intent.window,
          cancelToken: cancelToken,
          region: target,
          limit: 25,
        )
        .timeout(budget)
        .catchError((Object e) {
          providerError = e;
          return <SearchResult>[];
        });
    final feedReads = [
      for (final f in feeds)
        reader
            .readFeed(
              Uri.parse(f.url),
              cancelToken: cancelToken,
              timeout: budget,
              language: language,
            )
            .then((items) {
              feedsRead++;
              return [for (final i in items) _fromFeed(i, f)];
            })
            .catchError((Object _) {
              feedsFailed++;
              return <SearchResult>[];
            }),
    ];
    // A topic question also gets ordinary results: publisher pages that
    // can be read in full, which listings from syndication mirrors cannot.
    final webSearch = intent.topic == null
        ? Future.value(<SearchResult>[])
        : scraper
              .search(
                intent.topic!,
                limit: 8,
                cancelToken: cancelToken,
                region: target,
                dateFilter: 'w',
              )
              .timeout(budget)
              .catchError((Object _) => <SearchResult>[]);
    progress?.call(t.newsCollecting(feeds.length));
    final all = await Future.wait([listing, ...feedReads]);
    final web = await webSearch;
    final items = <SearchResult>[for (final list in all) ...list];
    final stories = rank(
      items,
      intent,
      now: clock().toUtc(),
      maxItems: maxItems,
      home: target,
    );

    // Depth for a topic: the best readable pages, in parallel, bounded.
    final articles = <SearchResult>[];
    if (intent.topic != null && maxArticles > 0) {
      final candidates = <SearchResult>[
        for (final s in stories)
          if (_readable(s.url)) s,
        ...EvidenceRanker.rankResults<SearchResult>(
          intent.topic!,
          web.where((r) => !r.sponsored && _readable(r.url)).toList(),
          titleOf: (r) => r.title,
          snippetOf: (r) => r.snippet,
          urlOf: (r) => r.url,
          recent: true,
          now: clock().toUtc(),
        ),
      ];
      final seen = <String>{};
      final picks = <SearchResult>[
        for (final c in candidates)
          if (seen.add(SourceQuality.hostOf(c.url) + Uri.parse(c.url).path)) c,
      ].take(maxArticles + 1).toList();
      final left = budget - clock().difference(started);
      if (picks.isNotEmpty && left > const Duration(milliseconds: 800)) {
        progress?.call(t.newsReadingArticles(min(picks.length, maxArticles)));
        final reads = await Future.wait([
          for (final p in picks)
            reader
                .read(
                  Uri.parse(p.url),
                  cancelToken: cancelToken,
                  timeout: left < const Duration(seconds: 5)
                      ? left
                      : const Duration(seconds: 5),
                  language: language,
                )
                .then<SearchResult?>(
                  (page) => SearchResult(
                    title: page.title.isEmpty ? p.title : page.title,
                    url: p.url,
                    snippet: p.snippet,
                    source: Uri.tryParse(p.url)?.host,
                    rank: 0,
                    pageText: page.text,
                    finalUrl: page.finalUri.toString(),
                    fetchedAt: page.fetchedAt,
                    publishedAt: page.publishedAt ?? p.publishedAt,
                    outlet: p.outlet ?? SourceQuality.outletOf(p.url)?.name,
                  ),
                )
                .catchError((Object _) => null),
        ]);
        for (final r in reads) {
          if (r != null && articles.length < maxArticles) articles.add(r);
        }
      }
    }
    return NewsBriefing(
      items: stories,
      articles: articles,
      providerError: stories.isEmpty ? providerError : null,
      feedsRead: feedsRead,
      feedsFailed: feedsFailed,
      elapsed: clock().difference(started),
    );
  }

  static bool _readable(String url) =>
      !SourceQuality.unreadable(url) &&
      !SourceQuality.lowValue(url) &&
      Uri.tryParse(url)?.hasScheme == true;

  static SearchResult _fromFeed(FeedItem i, NewsFeed f) => SearchResult(
    title: i.title,
    url: i.link,
    snippet: i.summary,
    source: Uri.tryParse(i.link)?.host,
    rank: 0,
    pageText: i.summary.isEmpty ? i.title : i.summary,
    publishedAt: i.published,
    outlet: f.outlet,
    newsItem: true,
  );

  /// Merges one story told by several outlets, drops stale and off-topic
  /// items and orders what is left by importance.
  static List<SearchResult> rank(
    List<SearchResult> items,
    NewsIntent intent, {
    required DateTime now,
    int maxItems = 12,
    String home = '',
  }) {
    final topicTerms = intent.topic == null
        ? const <String>{}
        : EvidenceRanker.terms(intent.topic!).toSet();
    final window = intent.window == 'w'
        ? const Duration(days: 8)
        : const Duration(hours: 36);
    final fresh = <SearchResult>[];
    for (final item in items) {
      if (item.title.trim().isEmpty) continue;
      final date = item.publishedAt;
      if (date != null && now.difference(date) > window) continue;
      if (SourceQuality.lowValue(item.url) && item.outlet == null) continue;
      if (topicTerms.isNotEmpty) {
        final have = EvidenceRanker.terms(
          '${item.title} ${item.snippet}',
        ).toSet().intersection(topicTerms).length;
        final need = topicTerms.length <= 2
            ? topicTerms.length
            : (topicTerms.length * 0.6).ceil();
        if (have < need) continue;
      }
      fresh.add(item);
    }
    // Best-known publishers first, so a cluster's representative is theirs.
    double tier(SearchResult r) =>
        (r.outlet == null ? null : SourceQuality.tierByName(r.outlet!))
            ?.weight ??
        SourceQuality.authority(r.url);
    fresh.sort((a, b) {
      final t = tier(b).compareTo(tier(a));
      if (t != 0) return t;
      return (b.publishedAt ?? DateTime(2000)).compareTo(
        a.publishedAt ?? DateTime(2000),
      );
    });
    final stories = <_Story>[];
    for (final item in fresh) {
      final terms = EvidenceRanker.terms(item.title).toSet();
      _Story? same;
      for (final s in stories) {
        if (_sameStory(terms, s.terms)) {
          same = s;
          break;
        }
      }
      if (same == null) {
        stories.add(_Story(item, terms));
      } else {
        same.add(item);
      }
    }
    for (final s in stories) {
      final age = s.newest == null
          ? 30.0
          : max(0, now.difference(s.newest!).inMinutes) / 60.0;
      s.score =
          exp(-age / 18) +
          0.3 * min(s.outlets.length - 1, 3) +
          0.5 * tier(s.best) +
          (s.best.snippet.length > 60 ? 0.1 : 0);
    }
    stories.sort((a, b) => b.score.compareTo(a.score));
    final perOutlet = <String, int>{};
    final out = <SearchResult>[];
    for (final s in stories) {
      if (out.length >= maxItems) break;
      final key = (s.best.outlet ?? s.best.source ?? '').toLowerCase();
      if ((perOutlet[key] ?? 0) >= 4) continue;
      perOutlet[key] = (perOutlet[key] ?? 0) + 1;
      out.add(s.render(out.length + 1));
    }
    return out;
  }

  /// Two headlines tell the same story when they share most of their
  /// content words (three at least).
  static bool _sameStory(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return false;
    final shared = a.intersection(b).length;
    if (shared < 3) return false;
    return shared / min(a.length, b.length) >= 0.6 ||
        shared / a.union(b).length >= 0.45;
  }

  /// The feeds for a briefing in [region]: two national and two world feeds
  /// for a general question, the section's feeds for a category, the
  /// national and world feeds (filtered by topic later) for a topic.
  static List<NewsFeed> feedsFor(String region, NewsIntent intent) {
    final set = _regional[region] ?? _regional[_languageOf(region)] ?? const [];
    final world = _world[_languageOf(region)] ?? _world['en']!;
    final category = intent.category;
    if (category != null &&
        category != NewsCategory.national &&
        category != NewsCategory.world) {
      final local = set.where((f) => f.section == category).toList();
      final global = _sections[category] ?? const <NewsFeed>[];
      final picked = <NewsFeed>[...local.take(2), ...global.take(3)];
      if (picked.isNotEmpty) return picked.take(4).toList();
    }
    final national = set.where((f) => f.section == NewsCategory.national);
    if (category == NewsCategory.world) {
      return [...world.take(4)];
    }
    // "News in Canada": that country's outlets only; world feeds filled
    // half the briefing with other countries' stories (phone run
    // 2026-09-23).
    if (category == NewsCategory.national ||
        (intent.place != null && national.isNotEmpty)) {
      return [...national.take(4)];
    }
    return [...national.take(2), ...world.take(2)];
  }

  static String _languageOf(String region) {
    final lang = region.split('-').last;
    return switch (lang) {
      'tzh' => 'zh',
      _ => lang,
    };
  }

  static const _world = <String, List<NewsFeed>>{
    'en': [
      NewsFeed(
        'BBC News',
        'https://feeds.bbci.co.uk/news/world/rss.xml',
        NewsCategory.world,
      ),
      NewsFeed(
        'Al Jazeera',
        'https://www.aljazeera.com/xml/rss/all.xml',
        NewsCategory.world,
      ),
      NewsFeed(
        'The Guardian',
        'https://www.theguardian.com/world/rss',
        NewsCategory.world,
      ),
      NewsFeed('NPR', 'https://feeds.npr.org/1001/rss.xml', NewsCategory.world),
    ],
    'fr': [
      NewsFeed(
        'Le Monde',
        'https://www.lemonde.fr/rss/une.xml',
        NewsCategory.world,
      ),
      NewsFeed(
        'France 24',
        'https://www.france24.com/fr/rss',
        NewsCategory.world,
      ),
      NewsFeed('RFI', 'https://www.rfi.fr/fr/rss', NewsCategory.world),
    ],
    'de': [
      NewsFeed(
        'tagesschau',
        'https://www.tagesschau.de/xml/rss2',
        NewsCategory.world,
      ),
      NewsFeed(
        'Der Spiegel',
        'https://www.spiegel.de/schlagzeilen/index.rss',
        NewsCategory.world,
      ),
    ],
    'it': [
      NewsFeed(
        'ANSA',
        'https://www.ansa.it/sito/ansait_rss.xml',
        NewsCategory.world,
      ),
    ],
    'es': [
      NewsFeed(
        'El País',
        'https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada',
        NewsCategory.world,
      ),
    ],
  };

  static const _regional = <String, List<NewsFeed>>{
    'ca-en': [
      NewsFeed(
        'CBC News',
        'https://www.cbc.ca/webfeed/rss/rss-canada',
        NewsCategory.national,
      ),
      NewsFeed(
        'Global News',
        'https://globalnews.ca/canada/feed/',
        NewsCategory.national,
      ),
      NewsFeed(
        'CTV News',
        'https://www.ctvnews.ca/arc/outboundfeeds/rss/?outputType=xml',
        NewsCategory.national,
      ),
      NewsFeed(
        'National Post',
        'https://nationalpost.com/feed/',
        NewsCategory.national,
      ),
      NewsFeed(
        'CBC News',
        'https://www.cbc.ca/webfeed/rss/rss-politics',
        NewsCategory.politics,
      ),
      NewsFeed(
        'CBC News',
        'https://www.cbc.ca/webfeed/rss/rss-business',
        NewsCategory.business,
      ),
      NewsFeed(
        'CBC News',
        'https://www.cbc.ca/webfeed/rss/rss-technology',
        NewsCategory.technology,
      ),
      NewsFeed(
        'CBC News',
        'https://www.cbc.ca/webfeed/rss/rss-health',
        NewsCategory.health,
      ),
      NewsFeed(
        'Sportsnet',
        'https://www.sportsnet.ca/feed/',
        NewsCategory.sports,
      ),
      NewsFeed(
        'CBC Sports',
        'https://www.cbc.ca/webfeed/rss/rss-sports',
        NewsCategory.sports,
      ),
      NewsFeed(
        'CBC News',
        'https://www.cbc.ca/webfeed/rss/rss-arts',
        NewsCategory.entertainment,
      ),
    ],
    'ca-fr': [
      NewsFeed(
        'Radio-Canada',
        'https://ici.radio-canada.ca/rss/4159',
        NewsCategory.national,
      ),
      NewsFeed(
        'La Presse',
        'https://www.lapresse.ca/actualites/rss',
        NewsCategory.national,
      ),
      NewsFeed(
        'Le Devoir',
        'https://www.ledevoir.com/rss/manchettes.xml',
        NewsCategory.national,
      ),
    ],
    'us-en': [
      NewsFeed(
        'NPR',
        'https://feeds.npr.org/1001/rss.xml',
        NewsCategory.national,
      ),
      NewsFeed(
        'CBS News',
        'https://www.cbsnews.com/latest/rss/main',
        NewsCategory.national,
      ),
      NewsFeed(
        'ABC News',
        'https://abcnews.go.com/abcnews/topstories',
        NewsCategory.national,
      ),
      NewsFeed(
        'NBC News',
        'https://feeds.nbcnews.com/nbcnews/public/news',
        NewsCategory.national,
      ),
      NewsFeed(
        'PBS NewsHour',
        'https://www.pbs.org/newshour/feeds/rss/headlines',
        NewsCategory.national,
      ),
      NewsFeed(
        'ESPN',
        'https://www.espn.com/espn/rss/news',
        NewsCategory.sports,
      ),
    ],
    'uk-en': [
      NewsFeed(
        'BBC News',
        'https://feeds.bbci.co.uk/news/uk/rss.xml',
        NewsCategory.national,
      ),
      NewsFeed(
        'The Guardian',
        'https://www.theguardian.com/uk-news/rss',
        NewsCategory.national,
      ),
      NewsFeed(
        'Sky News',
        'https://feeds.skynews.com/feeds/rss/home.xml',
        NewsCategory.national,
      ),
      NewsFeed(
        'BBC Sport',
        'https://feeds.bbci.co.uk/sport/rss.xml',
        NewsCategory.sports,
      ),
    ],
    'au-en': [
      NewsFeed(
        'ABC News (Australia)',
        'https://www.abc.net.au/news/feed/51120/rss.xml',
        NewsCategory.national,
      ),
    ],
    'in-en': [
      NewsFeed(
        'The Hindu',
        'https://www.thehindu.com/news/national/feeder/default.rss',
        NewsCategory.national,
      ),
    ],
    'fr': [
      NewsFeed(
        'franceinfo',
        'https://www.francetvinfo.fr/titres.rss',
        NewsCategory.national,
      ),
      NewsFeed(
        'Le Monde',
        'https://www.lemonde.fr/rss/une.xml',
        NewsCategory.national,
      ),
    ],
    'de': [
      NewsFeed(
        'tagesschau',
        'https://www.tagesschau.de/xml/rss2',
        NewsCategory.national,
      ),
      NewsFeed(
        'Der Spiegel',
        'https://www.spiegel.de/schlagzeilen/index.rss',
        NewsCategory.national,
      ),
    ],
    'it': [
      NewsFeed(
        'ANSA',
        'https://www.ansa.it/sito/ansait_rss.xml',
        NewsCategory.national,
      ),
    ],
    'es': [
      NewsFeed(
        'El País',
        'https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada',
        NewsCategory.national,
      ),
    ],
  };

  /// Section feeds in English, used for any region.
  static const _sections = <NewsCategory, List<NewsFeed>>{
    NewsCategory.business: [
      NewsFeed(
        'BBC News',
        'https://feeds.bbci.co.uk/news/business/rss.xml',
        NewsCategory.business,
      ),
      NewsFeed(
        'The Guardian',
        'https://www.theguardian.com/business/rss',
        NewsCategory.business,
      ),
    ],
    NewsCategory.technology: [
      NewsFeed(
        'The Verge',
        'https://www.theverge.com/rss/index.xml',
        NewsCategory.technology,
      ),
      NewsFeed(
        'Ars Technica',
        'https://feeds.arstechnica.com/arstechnica/index',
        NewsCategory.technology,
      ),
      NewsFeed(
        'BBC News',
        'https://feeds.bbci.co.uk/news/technology/rss.xml',
        NewsCategory.technology,
      ),
    ],
    NewsCategory.science: [
      NewsFeed(
        'BBC News',
        'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml',
        NewsCategory.science,
      ),
      NewsFeed(
        'The Guardian',
        'https://www.theguardian.com/science/rss',
        NewsCategory.science,
      ),
    ],
    NewsCategory.health: [
      NewsFeed(
        'BBC News',
        'https://feeds.bbci.co.uk/news/health/rss.xml',
        NewsCategory.health,
      ),
    ],
    NewsCategory.sports: [
      NewsFeed(
        'BBC Sport',
        'https://feeds.bbci.co.uk/sport/rss.xml',
        NewsCategory.sports,
      ),
      NewsFeed(
        'ESPN',
        'https://www.espn.com/espn/rss/news',
        NewsCategory.sports,
      ),
    ],
    NewsCategory.entertainment: [
      NewsFeed(
        'BBC News',
        'https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml',
        NewsCategory.entertainment,
      ),
    ],
    NewsCategory.politics: [
      NewsFeed(
        'BBC News',
        'https://feeds.bbci.co.uk/news/world/us_and_canada/rss.xml',
        NewsCategory.politics,
      ),
    ],
  };
}

class _Story {
  SearchResult best;
  final Set<String> terms;
  final Set<String> outlets = {};
  DateTime? newest;
  double score = 0;

  _Story(this.best, this.terms) {
    _count(best);
  }

  void _count(SearchResult r) {
    outlets.add((r.outlet ?? r.source ?? r.url).toLowerCase());
    final d = r.publishedAt;
    if (d != null && (newest == null || d.isAfter(newest!))) newest = d;
  }

  void add(SearchResult r) {
    _count(r);
    // Keep the better-known publisher's version; a readable link and a
    // longer lede break ties.
    if (best.snippet.length < 40 && r.snippet.length > best.snippet.length) {
      best = r;
    }
  }

  SearchResult render(int rank) {
    final others = outlets.length - 1;
    return SearchResult(
      title: best.title,
      url: best.url,
      snippet: best.snippet,
      source: best.source,
      rank: rank,
      pageText: best.pageText,
      publishedAt: best.publishedAt ?? newest,
      outlet: others > 0
          ? '${best.outlet ?? best.source} (+$others other outlet${others == 1 ? '' : 's'})'
          : best.outlet,
      newsItem: true,
    );
  }
}
