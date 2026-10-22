// Frozen web for benchmarks (D1 plan, answer 11: "every configuration
// uses the same frozen search results"). One live pass records what each
// search, Wikipedia lookup, weather answer and page read returned, with how
// long it took; later passes replay that record, so two configurations differ
// only in what they decide, never in what the web happened to say that day.
//
// record: live, every call saved. fill: replay, and a call the record lacks
// goes live and is added (a new configuration growing the shared pool).
// replay: the record only; a missing call fails like an offline one and is
// counted in [FrozenWeb.misses].
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/instant_answers.dart';
import 'package:ondevice_llm/data/network/web_search/news_feed_parser.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/data/network/web_search/wikipedia_client.dart';

/// record: everything live, a new record. fill: saved calls replay, the
/// rest go live and are added. heal: fill, and saved failures (a bot check,
/// a timeout) are tried live again once the engine has cooled down.
/// replay: saved calls only; anything else is a miss.
enum FrozenMode { record, fill, heal, replay }

/// A failure as the app saw it: the pipeline keeps `'$e'` as the read error,
/// so a replayed failure prints the same text.
class ReplayedFailure implements Exception {
  final String text;
  const ReplayedFailure(this.text);
  @override
  String toString() => text;
}

class FrozenWeb {
  final FrozenMode mode;

  /// Replays wait as long as the recorded call took, so timings stay
  /// comparable with a live run; false answers at once.
  final bool latency;
  final Map<String, Map<String, Object?>> entries;

  /// Calls per kind in this run ('search', 'read', ...), and replay misses.
  final calls = <String, int>{};
  final misses = <String>[];

  FrozenWeb(this.mode, {this.latency = true, Map<String, Object?>? saved})
    : entries = {
        for (final e in (saved?['entries'] as Map? ?? const {}).entries)
          e.key as String: (e.value as Map).cast<String, Object?>(),
      };

  static Future<FrozenWeb> open(
    String path,
    FrozenMode mode, {
    bool latency = true,
  }) async {
    final file = File(path);
    final saved = mode != FrozenMode.record && await file.exists()
        ? jsonDecode(await file.readAsString()) as Map<String, Object?>
        : null;
    if (mode == FrozenMode.replay && saved == null) {
      throw StateError('No frozen web record at $path');
    }
    return FrozenWeb(mode, latency: latency, saved: saved);
  }

  /// Writes the record to [path]; a replay never changes it.
  Future<void> save(String path) async {
    if (mode == FrozenMode.replay) return;
    await File(path).writeAsString(
      jsonEncode({
        'version': 1,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'entries': entries,
      }),
    );
  }

  /// The overrides that route the app's keyless providers through here.
  List<Override> get overrides => [
    duckDuckGoScraperProvider.overrideWith((ref) {
      final scraper = _DuckDuckGo(this);
      ref.onDispose(scraper.dispose);
      return scraper;
    }),
    wikipediaClientProvider.overrideWith((ref) {
      final client = _Wikipedia(this);
      ref.onDispose(client.dispose);
      return client;
    }),
    instantAnswersProvider.overrideWith((ref) {
      final answers = _Instant(this);
      ref.onDispose(answers.dispose);
      return answers;
    }),
    webPageReaderProvider.overrideWith((ref) => _Reader(this)),
  ];

  /// What [live] returned for [key], recorded or replayed. [encode] turns a
  /// value into JSON and [decode] back. A replay slower than this run's
  /// [timeout] times out as the live call would have.
  Future<T> call<T>(
    String kind,
    String key,
    Future<T> Function() live,
    Object? Function(T) encode,
    T Function(Object?) decode, {
    CancelToken? cancel,
    Duration? timeout,
  }) async {
    calls[kind] = (calls[kind] ?? 0) + 1;
    final id = '$kind|$key';
    final saved = entries[id];
    final failed =
        saved != null && (saved['error'] != null || saved['cancelled'] == true);
    if (saved != null &&
        mode != FrozenMode.record &&
        !(mode == FrozenMode.heal && failed)) {
      final took = Duration(milliseconds: saved['ms'] as int? ?? 0);
      if (saved['cancelled'] == true) {
        // Stopped by the pipeline while recording: what it would have
        // returned is unknown, so it never returns.
        if (latency) {
          await Future.any([
            Future<void>.delayed(took),
            if (cancel != null) cancel.whenCancel,
          ]);
        }
        throw const ReplayedFailure('Cancelled while recording');
      }
      if (latency) {
        if (timeout != null && took > timeout) {
          await Future<void>.delayed(timeout);
          throw ReplayedFailure('TimeoutException after $timeout');
        }
        await Future<void>.delayed(took);
      }
      final error = saved['error'];
      if (error is String) throw ReplayedFailure(error);
      return decode(saved['value']);
    }
    if (mode == FrozenMode.replay) {
      misses.add(id);
      throw ReplayedFailure('Not in the frozen web record: $id');
    }
    final clock = Stopwatch()..start();
    try {
      final value = await live();
      entries[id] = {'ms': clock.elapsedMilliseconds, 'value': encode(value)};
      return value;
    } catch (e) {
      final cancelled =
          cancel?.isCancelled == true ||
          (e is DioException && e.type == DioExceptionType.cancel);
      // A failure saved before must not be replaced by a cancellation.
      if (!cancelled || !entries.containsKey(id)) {
        entries[id] = {
          'ms': clock.elapsedMilliseconds,
          if (cancelled) 'cancelled': true else 'error': '$e',
        };
      }
      rethrow;
    }
  }

  static Object? results(List<SearchResult> r) => [
    for (final x in r) result(x),
  ];
  static List<SearchResult> resultsFrom(Object? j) => [
    for (final x in j as List) resultFrom(x)!,
  ];

  static Map<String, Object?>? result(SearchResult? r) => r == null
      ? null
      : {
          'title': r.title,
          'url': r.url,
          'snippet': r.snippet,
          'source': r.source,
          'rank': r.rank,
          'pageText': r.pageText,
          'finalUrl': r.finalUrl,
          'fetchedAt': r.fetchedAt?.toIso8601String(),
          'publishedAt': r.publishedAt?.toIso8601String(),
          'readError': r.readError,
          'stale': r.stale,
          'sponsored': r.sponsored,
          'outlet': r.outlet,
          'newsItem': r.newsItem,
          'remembered': r.remembered,
          'archiveDate': r.archiveDate,
          'archiveLanguage': r.archiveLanguage,
          'archiveId': r.archiveId,
        };

  static SearchResult? resultFrom(Object? j) {
    if (j == null) return null;
    final m = j as Map;
    return SearchResult(
      title: m['title'] as String,
      url: m['url'] as String,
      snippet: m['snippet'] as String,
      source: m['source'] as String?,
      rank: m['rank'] as int,
      pageText: m['pageText'] as String?,
      finalUrl: m['finalUrl'] as String?,
      fetchedAt: _date(m['fetchedAt']),
      publishedAt: _date(m['publishedAt']),
      readError: m['readError'] as String?,
      stale: m['stale'] == true,
      sponsored: m['sponsored'] == true,
      outlet: m['outlet'] as String?,
      newsItem: m['newsItem'] == true,
      remembered: m['remembered'] == true,
      archiveDate: m['archiveDate'] as String?,
      archiveLanguage: m['archiveLanguage'] as String?,
      archiveId: m['archiveId'] as String?,
    );
  }

  static Map<String, Object?> page(WebPage p) => {
    'title': p.title,
    'text': p.text,
    'finalUri': p.finalUri.toString(),
    'fetchedAt': p.fetchedAt.toIso8601String(),
    'publishedAt': p.publishedAt?.toIso8601String(),
    'feedItems': p.feedItems == null
        ? null
        : [
            for (final f in p.feedItems!)
              {
                'title': f.title,
                'link': f.link,
                'summary': f.summary,
                'published': f.published?.toIso8601String(),
              },
          ],
  };

  static WebPage pageFrom(Object? j) {
    final m = j as Map;
    final feed = m['feedItems'] as List?;
    return WebPage(
      title: m['title'] as String,
      text: m['text'] as String,
      finalUri: Uri.parse(m['finalUri'] as String),
      fetchedAt: _date(m['fetchedAt'])!,
      publishedAt: _date(m['publishedAt']),
      feedItems: feed == null
          ? null
          : [
              for (final f in feed.cast<Map>())
                FeedItem(
                  title: f['title'] as String,
                  link: f['link'] as String,
                  summary: f['summary'] as String,
                  published: _date(f['published']),
                ),
            ],
    );
  }

  static DateTime? _date(Object? s) => s is String ? DateTime.parse(s) : null;
}

class _DuckDuckGo extends DuckDuckGoScraper {
  final FrozenWeb web;
  _DuckDuckGo(this.web);

  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async {
    region ??= DuckDuckGoScraper.regionFor(localeCode);
    final key =
        '$region|${dateFilter ?? '-'}|$limit|${query.trim().toLowerCase()}';
    final found = await web.call(
      'search',
      key,
      () async {
        final r = await super.search(
          query,
          limit: limit,
          cancelToken: cancelToken,
          localeCode: localeCode,
          dateFilter: dateFilter,
          region: region,
        );
        return (r, health);
      },
      (v) => {'results': FrozenWeb.results(v.$1), 'health': v.$2.toJson()},
      (j) {
        final m = j as Map;
        final h = m['health'] as Map;
        return (
          FrozenWeb.resultsFrom(m['results']),
          SearchProviderHealth(
            h['provider'] as String,
            h['status'] as String,
            parsed: h['parsed'] as int? ?? 0,
            relevant: h['relevant'] as int? ?? 0,
            elapsedMs: h['elapsedMs'] as int? ?? 0,
          ),
        );
      },
      cancel: cancelToken,
    );
    health = found.$2;
    return found.$1;
  }

  @override
  Future<List<SearchResult>> news(
    String query, {
    int limit = 20,
    String window = 'd',
    CancelToken? cancelToken,
    String localeCode = '',
    String? region,
  }) {
    region ??= DuckDuckGoScraper.regionFor(localeCode);
    return web.call(
      'news',
      '$region|$window|$limit|${query.trim().toLowerCase()}',
      () => super.news(
        query,
        limit: limit,
        window: window,
        cancelToken: cancelToken,
        localeCode: localeCode,
        region: region,
      ),
      FrozenWeb.results,
      FrozenWeb.resultsFrom,
      cancel: cancelToken,
    );
  }
}

class _Wikipedia extends WikipediaClient {
  final FrozenWeb web;
  _Wikipedia(this.web);

  @override
  Future<SearchResult?> lookup(
    String query, {
    String language = 'en',
    CancelToken? cancelToken,
  }) => web.call(
    'wikipedia',
    '$language|${query.trim().toLowerCase()}',
    () => super.lookup(query, language: language, cancelToken: cancelToken),
    FrozenWeb.result,
    FrozenWeb.resultFrom,
    cancel: cancelToken,
  );
}

class _Instant extends InstantAnswers {
  final FrozenWeb web;
  _Instant(this.web);

  @override
  Future<SearchResult?> weather(
    String place, {
    String language = 'en',
    CancelToken? cancelToken,
  }) => web.call(
    'weather',
    '$language|${place.trim().toLowerCase()}',
    () => super.weather(place, language: language, cancelToken: cancelToken),
    FrozenWeb.result,
    FrozenWeb.resultFrom,
    cancel: cancelToken,
  );
}

class _Reader extends WebPageReader {
  final FrozenWeb web;

  /// Pages handed out in this run, for [remembered] (follow-ups).
  final _seen = <Uri, WebPage>{};
  _Reader(this.web);

  @override
  WebPage? remembered(Uri uri) =>
      _seen[uri.removeFragment()] ?? super.remembered(uri);

  @override
  Future<WebPage> read(
    Uri uri, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 12),
    String language = 'en-US,en;q=0.9',
  }) async {
    // Same policy as a live read: a blocked address fails before any record.
    PublicWebPolicy.validate(uri);
    final key = uri.removeFragment();
    final page = await web.call(
      'read',
      key.toString(),
      () => super.read(
        uri,
        cancelToken: cancelToken,
        timeout: timeout,
        language: language,
      ),
      FrozenWeb.page,
      FrozenWeb.pageFrom,
      cancel: cancelToken,
      timeout: timeout,
    );
    _seen[key] = page;
    return page;
  }
}
