import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import 'search_models.dart';

class DuckDuckGoScraper {
  SearchProviderHealth health = const SearchProviderHealth(
    'DuckDuckGo',
    'idle',
  );
  final Dio _dio;
  final Duration _timeout;

  /// Minimum gap between two requests to DuckDuckGo. A burst of queries (a
  /// planner query, a retry, the tool loop, a Goal) is what earns a bot
  /// check; spacing them costs well under a second a turn.
  final Duration requestSpacing;

  /// After a bot check or rate limit, searches fail fast until this time
  /// instead of repeating the request (roadmap §7.3: bounded retries, no
  /// anti-bot bypass loops).
  DateTime? _pausedUntil;
  String? _pauseReason;
  static const cooldown = Duration(seconds: 60);

  /// Text markers of DuckDuckGo's challenge page (captured 2026-09-15).
  static bool looksLikeChallenge(String body) =>
      body.contains('anomaly-modal') ||
      body.contains('bots use DuckDuckGo') ||
      body.contains('challenge-form');

  /// DuckDuckGo's own empty-result marker.
  static bool looksLikeNoResults(String body) =>
      body.contains('no-results') || body.contains('No results.');

  DuckDuckGoScraper({
    Dio? dio,
    Duration timeout = const Duration(seconds: 8),
    this.requestSpacing = const Duration(milliseconds: 600),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: timeout,
               receiveTimeout: timeout,
               headers: {
                 'User-Agent': 'Mozilla/5.0 (compatible; OnDeviceLLM/1.0)',
                 'Accept': 'text/html',
                 'Accept-Language': 'en-US,en;q=0.9',
               },
             ),
           ),
       _timeout = timeout;

  /// The user's chosen search region (Settings > Reasoning & search), kept
  /// in step with the settings by SettingsNotifier; '' derives it below.
  static String preferredRegion = '';

  /// DuckDuckGo region (`kl`) from the app language and phone country.
  ///
  /// Values are selected exclusively from DuckDuckGo's documented allowlist;
  /// arbitrary locale pairs must never be synthesized here. [localeName] is
  /// injectable for tests; the app passes the platform locale.
  static String regionFor(String appLanguage, {String? localeName}) {
    if (localeName == null && preferredRegion.isNotEmpty) {
      return preferredRegion;
    }
    final parts = (localeName ?? _platformLocale())
        .replaceAll('-', '_')
        .split('_');
    final requested = appLanguage.trim().toLowerCase();
    final language =
        requested == 'fr' ||
            (requested.isEmpty && parts.first.toLowerCase() == 'fr')
        ? 'fr'
        : 'en';
    final country = parts.length > 1 ? parts[1].toUpperCase() : '';
    final localized = _localizedRegions['$country|$language'];
    if (localized != null) return localized;
    if (language == 'fr') return 'fr-fr';
    return _countryRegions[country] ?? 'wt-wt';
  }

  static const _localizedRegions = <String, String>{
    'CA|en': 'ca-en',
    'CA|fr': 'ca-fr',
    'BE|fr': 'be-fr',
    'CH|fr': 'ch-fr',
  };

  static const _countryRegions = <String, String>{
    'US': 'us-en',
    'GB': 'uk-en',
    'CA': 'ca-en',
    'AU': 'au-en',
    'NZ': 'nz-en',
    'IE': 'ie-en',
    'IN': 'in-en',
    'ZA': 'za-en',
    'SG': 'sg-en',
    'FR': 'fr-fr',
    'BE': 'be-nl',
    'CH': 'ch-de',
    'DE': 'de-de',
    'AT': 'at-de',
    'ES': 'es-es',
    'MX': 'mx-es',
    'AR': 'ar-es',
    'CL': 'cl-es',
    'CO': 'co-es',
    'IT': 'it-it',
    'NL': 'nl-nl',
    'BR': 'br-pt',
    'PT': 'pt-pt',
    'SE': 'se-sv',
    'NO': 'no-no',
    'DK': 'dk-da',
    'FI': 'fi-fi',
    'PL': 'pl-pl',
    'CZ': 'cz-cs',
    'HU': 'hu-hu',
    'RU': 'ru-ru',
    'TR': 'tr-tr',
    'JP': 'jp-jp',
    'KR': 'kr-kr',
    'CN': 'cn-zh',
    'TW': 'tw-tzh',
    'HK': 'hk-tzh',
    'SA': 'xa-ar',
    'AE': 'xa-ar',
  };

  static String _platformLocale() {
    try {
      return Platform.localeName;
    } catch (_) {
      return 'en_US';
    }
  }

  /// Accept-Language matching the region, so the provider and the pages
  /// agree on the language.
  static String acceptLanguageFor(String region) {
    final locale = localeFor(region);
    if (locale == null) return 'en;q=0.9';
    final language = locale.split('-').first;
    if (language == 'en') return '$locale,en;q=0.9';
    return '$locale,$language;q=0.9,en;q=0.7';
  }

  /// The BCP 47 locale of a DuckDuckGo region ('ca-fr' → 'fr-CA'), or null
  /// for "all regions".
  static String? localeFor(String region) {
    const locales = <String, String>{
      'us-en': 'en-US',
      'uk-en': 'en-GB',
      'ca-en': 'en-CA',
      'ca-fr': 'fr-CA',
      'au-en': 'en-AU',
      'nz-en': 'en-NZ',
      'ie-en': 'en-IE',
      'in-en': 'en-IN',
      'za-en': 'en-ZA',
      'sg-en': 'en-SG',
      'fr-fr': 'fr-FR',
      'be-fr': 'fr-BE',
      'ch-fr': 'fr-CH',
      'de-de': 'de-DE',
      'at-de': 'de-AT',
      'ch-de': 'de-CH',
      'es-es': 'es-ES',
      'mx-es': 'es-MX',
      'ar-es': 'es-AR',
      'cl-es': 'es-CL',
      'co-es': 'es-CO',
      'it-it': 'it-IT',
      'nl-nl': 'nl-NL',
      'be-nl': 'nl-BE',
      'br-pt': 'pt-BR',
      'pt-pt': 'pt-PT',
      'se-sv': 'sv-SE',
      'no-no': 'no-NO',
      'dk-da': 'da-DK',
      'fi-fi': 'fi-FI',
      'pl-pl': 'pl-PL',
      'cz-cs': 'cs-CZ',
      'hu-hu': 'hu-HU',
      'ru-ru': 'ru-RU',
      'tr-tr': 'tr-TR',
      'jp-jp': 'ja-JP',
      'kr-kr': 'ko-KR',
      'cn-zh': 'zh-CN',
      'tw-tzh': 'zh-TW',
      'hk-tzh': 'zh-HK',
      'xa-ar': 'ar',
    };
    return locales[region];
  }

  /// Results of the last hour by query: a retry, a comparison or the tool
  /// loop asking the same thing again does not cost another provider hit
  /// (web-research overhaul phase 3). Answered even during a cooldown.
  static const resultsTtl = Duration(hours: 1);

  /// News moves faster than pages: a news listing is reused for ten minutes.
  static const newsTtl = Duration(minutes: 10);
  static const _maxRemembered = 64;
  final _recent = <String, (DateTime, int, List<SearchResult>)>{};

  List<SearchResult>? _remembered(String key, int limit, Duration ttl) {
    final hit = _recent[key];
    if (hit == null ||
        DateTime.now().difference(hit.$1) >= ttl ||
        hit.$2 < limit) {
      return null;
    }
    return hit.$3.take(limit).toList();
  }

  void _remember(String key, int limit, List<SearchResult> results) {
    if (results.isEmpty) return;
    _recent.remove(key);
    if (_recent.length >= _maxRemembered) _recent.remove(_recent.keys.first);
    _recent[key] = (DateTime.now(), limit, results);
  }

  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async {
    region ??= regionFor(localeCode);
    final key = '$region|${dateFilter ?? '-'}|${query.trim().toLowerCase()}';
    final remembered = _remembered(key, limit, resultsTtl);
    if (remembered != null) {
      health = SearchProviderHealth(
        'DuckDuckGo',
        'cached',
        relevant: remembered.length,
      );
      return remembered;
    }
    final healthClock = Stopwatch()..start();
    List<SearchResult> results;
    try {
      results = await _fetchResults(
        query,
        region: region,
        limit: limit,
        cancelToken: cancelToken,
        dateFilter: dateFilter,
      );
      if (results.isEmpty && dateFilter != null) {
        results = await _fetchResults(
          query,
          region: region,
          limit: limit,
          cancelToken: cancelToken,
        );
      }
      health = SearchProviderHealth(
        'DuckDuckGo',
        results.isEmpty ? 'empty' : 'ready',
        parsed: results.length,
        relevant: results.length,
        elapsedMs: healthClock.elapsedMilliseconds,
      );
    } catch (e) {
      health = SearchProviderHealth(
        'DuckDuckGo',
        e is SearchChallengeException || e is SearchCooldownException
            ? 'blocked'
            : e is SearchRateLimitException
            ? 'rate_limited'
            : e is SearchMarkupException
            ? 'parser_error'
            : 'network_error',
        elapsedMs: healthClock.elapsedMilliseconds,
      );
      rethrow;
    }
    _remember(key, limit, results);
    return results;
  }

  /// Serialises request starts at least [requestSpacing] apart.
  Future<void> _gate = Future.value();
  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _space(CancelToken? cancelToken) {
    final previous = _gate;
    final turn = Completer<void>();
    _gate = turn.future;
    return previous.then((_) async {
      try {
        final wait = _lastStart.add(requestSpacing).difference(DateTime.now());
        if (wait > Duration.zero) {
          await Future.any<void>([
            Future<void>.delayed(wait),
            if (cancelToken != null) cancelToken.whenCancel.then((_) {}),
          ]);
        }
        _lastStart = DateTime.now();
      } finally {
        turn.complete();
      }
      if (cancelToken?.isCancelled == true) {
        throw const SearchHttpException('Cancelled');
      }
    });
  }

  void _checkPause() {
    final paused = _pausedUntil;
    if (paused == null) return;
    if (DateTime.now().isBefore(paused)) {
      throw SearchCooldownException(
        _pauseReason ?? 'Search is paused after a provider block.',
        paused,
      );
    }
    _pausedUntil = null;
  }

  /// One form submission, the way DuckDuckGo's own no-JavaScript page
  /// sends it. Measured 2026-09-23 from a Canadian connection: the same
  /// query as a GET got the bot check three times out of three, as a POST it
  /// got results three times out of three.
  Future<Response<String>> _post(
    String endpoint,
    Map<String, String> form,
    String region,
    CancelToken? cancelToken,
  ) async {
    await _space(cancelToken);
    return _dio
        .post<String>(
          endpoint,
          data: form,
          cancelToken: cancelToken,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'Accept-Language': acceptLanguageFor(region),
              'Origin': Uri.parse(endpoint).origin,
              'Referer': '${Uri.parse(endpoint).origin}/',
            },
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        )
        .timeout(_timeout);
  }

  Future<List<SearchResult>> _fetchResults(
    String query, {
    required String region,
    required int limit,
    CancelToken? cancelToken,
    String? dateFilter,
  }) async {
    _checkPause();
    final form = {'q': query, 'kl': region, 'kp': '-1', 'df': ?dateFilter};
    var res = await _post(
      AppConstants.ddgHtmlEndpoint,
      form,
      region,
      cancelToken,
    );
    var status = res.statusCode ?? 0;
    if (status == 429) {
      // One bounded retry when the provider says how long to wait.
      final wait = _retryAfter(res);
      if (wait != null && wait <= const Duration(seconds: 5)) {
        await Future.any<void>([
          Future<void>.delayed(wait),
          if (cancelToken != null) cancelToken.whenCancel.then((_) {}),
        ]);
        if (cancelToken?.isCancelled == true) {
          throw const SearchHttpException('Cancelled');
        }
        res = await _post(
          AppConstants.ddgHtmlEndpoint,
          form,
          region,
          cancelToken,
        );
        status = res.statusCode ?? 0;
      }
      if (status == 429) {
        _pause('DuckDuckGo rate limit');
        throw SearchRateLimitException(
          'DuckDuckGo rate limit',
          retryAfter: _retryAfter(res),
        );
      }
    }
    final body = res.data ?? '';
    // The bot check arrives as 202 (sometimes 403) with an "anomaly" page.
    if (status == 202 || status == 403 || looksLikeChallenge(body)) {
      _pause('DuckDuckGo asked for a bot check');
      throw const SearchChallengeException('DuckDuckGo asked for a bot check');
    }
    if (status < 200 || status >= 300) {
      throw SearchHttpException('DDG HTTP $status');
    }
    final List<SearchResult> found;
    try {
      found = parseHtml(body, limit: limit);
    } on SearchMarkupException {
      // Lite is DuckDuckGo's other documented no-JavaScript surface. One
      // bounded fallback makes markup drift less likely to disable search.
      return _fetchLite(form, region, limit, cancelToken);
    }
    // A dated search that comes back empty is retried undated by [search],
    // and that retry gets the Lite try below.
    if (found.isNotEmpty || dateFilter != null) return found;
    // "No results found" can also be how the HTML page sheds load: on
    // 2026-10-11 it said so for "Nikon Z30 weight" seconds after answering
    // it with eight results, while Lite answered the same query. With no
    // second engine, Lite gets one try before the search counts as empty;
    // a bot check there still pauses search.
    try {
      return await _fetchLite(form, region, limit, cancelToken);
    } on SearchChallengeException {
      rethrow;
    } on SearchRateLimitException {
      rethrow;
    } catch (_) {
      // Lite unreachable or unreadable: the HTML page's answer stands.
      if (cancelToken?.isCancelled == true) rethrow;
      return found;
    }
  }

  Future<List<SearchResult>> _fetchLite(
    Map<String, String> form,
    String region,
    int limit,
    CancelToken? cancelToken,
  ) async {
    final res = await _post(
      AppConstants.ddgLiteEndpoint,
      form,
      region,
      cancelToken,
    );
    final body = res.data ?? '';
    final status = res.statusCode ?? 0;
    if (status == 429) {
      _pause('DuckDuckGo rate limit');
      throw SearchRateLimitException(
        'DuckDuckGo rate limit',
        retryAfter: _retryAfter(res),
      );
    }
    if (status == 202 || status == 403 || looksLikeChallenge(body)) {
      _pause('DuckDuckGo asked for a bot check');
      throw const SearchChallengeException('DuckDuckGo asked for a bot check');
    }
    if (status < 200 || status >= 300) {
      throw SearchHttpException('DDG Lite HTTP $status');
    }
    return parseHtml(body, limit: limit);
  }

  /// DuckDuckGo's news vertical: dated stories with their publisher and
  /// lede, newest reporting first — what a "latest news" question needs,
  /// where the web index returns front pages and aggregators (measured
  /// 2026-09-23: "latest news" gave Al Jazeera's section page, Reuters'
  /// front page, news24online and canadanewsmedia.ca). Two requests: the
  /// page that carries the query token (`vqd`), then the JSON listing.
  /// [window] is DuckDuckGo's `df`: d, w or m.
  Future<List<SearchResult>> news(
    String query, {
    int limit = 20,
    String window = 'd',
    CancelToken? cancelToken,
    String localeCode = '',
    String? region,
  }) async {
    region ??= regionFor(localeCode);
    final key = 'news|$region|$window|${query.trim().toLowerCase()}';
    final remembered = _remembered(key, limit, newsTtl);
    if (remembered != null) return remembered;
    _checkPause();
    final token = await _post(
      AppConstants.ddgHomeEndpoint,
      {'q': query},
      region,
      cancelToken,
    );
    final page = token.data ?? '';
    if ((token.statusCode ?? 0) == 202 ||
        (token.statusCode ?? 0) == 403 ||
        looksLikeChallenge(page)) {
      _pause('DuckDuckGo asked for a bot check');
      throw const SearchChallengeException('DuckDuckGo asked for a bot check');
    }
    final vqd = vqdOf(page);
    if (vqd == null) {
      throw const SearchMarkupException('DuckDuckGo news token not found');
    }
    await _space(cancelToken);
    final res = await _dio
        .get<String>(
          AppConstants.ddgNewsEndpoint,
          queryParameters: {
            'l': region,
            'o': 'json',
            'noamp': '1',
            'q': query,
            'vqd': vqd,
            'p': '-1',
            'df': window,
          },
          cancelToken: cancelToken,
          options: Options(
            headers: {
              'Accept': 'application/json, text/javascript, */*; q=0.01',
              'Accept-Language': acceptLanguageFor(region),
              'Referer': 'https://duckduckgo.com/',
            },
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        )
        .timeout(_timeout);
    final status = res.statusCode ?? 0;
    final body = res.data ?? '';
    if (status == 429) {
      _pause('DuckDuckGo rate limit');
      throw const SearchRateLimitException('DuckDuckGo rate limit');
    }
    if (status == 202 || status == 403 || looksLikeChallenge(body)) {
      _pause('DuckDuckGo asked for a bot check');
      throw const SearchChallengeException('DuckDuckGo asked for a bot check');
    }
    if (status < 200 || status >= 300) {
      throw SearchHttpException('DDG news HTTP $status');
    }
    final results = parseNews(body, limit: limit);
    _remember(key, limit, results);
    return results;
  }

  /// The query token DuckDuckGo embeds in its result page.
  static String? vqdOf(String page) =>
      RegExp(r'''vqd=["']?(\d[\d-]+)''').firstMatch(page)?.group(1);

  /// The news vertical's JSON (`{"results": [{title, url, excerpt, source,
  /// date}]}`) as dated, attributed listings. Items without a title or an
  /// http(s) link are dropped; the lede stands in for page text.
  static List<SearchResult> parseNews(String body, {int limit = 20}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      throw const SearchMarkupException('DuckDuckGo news could not be parsed');
    }
    final rows = json is Map ? json['results'] : null;
    if (rows is! List) {
      throw const SearchMarkupException('DuckDuckGo news could not be parsed');
    }
    final out = <SearchResult>[];
    for (final row in rows) {
      if (out.length >= limit) break;
      if (row is! Map) continue;
      final title = plainText('${row['title'] ?? ''}');
      final url = '${row['url'] ?? ''}';
      final uri = Uri.tryParse(url);
      if (title.isEmpty ||
          uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        continue;
      }
      if (out.any((r) => r.url == url)) continue;
      final excerpt = plainText('${row['excerpt'] ?? ''}');
      final seconds = row['date'];
      final published = seconds is num && seconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              (seconds * 1000).round(),
              isUtc: true,
            )
          : null;
      final outlet = plainText('${row['source'] ?? ''}');
      out.add(
        SearchResult(
          title: title,
          url: url,
          snippet: excerpt,
          source: uri.host,
          rank: out.length + 1,
          pageText: excerpt.isEmpty ? title : excerpt,
          publishedAt: published,
          outlet: outlet.isEmpty ? null : outlet,
          newsItem: true,
        ),
      );
    }
    return out;
  }

  /// Markup and entities out of a provider string ("Trump&#x27;s" → "Trump's").
  static String plainText(String s) {
    if (!s.contains('<') && !s.contains('&')) {
      return s.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return html_parser
        .parseFragment(s)
        .text!
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _pause(String reason) {
    _pausedUntil = DateTime.now().add(cooldown);
    _pauseReason = reason;
  }

  static Duration? _retryAfter(Response<String> res) {
    final v = res.headers.value('retry-after');
    if (v == null) return null;
    final seconds = int.tryParse(v.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }

  /// Parses a 2xx page. Distinguishes "no results" from markup drift:
  /// a page with neither results nor the provider's empty marker means the
  /// parser is out of date, which must not masquerade as an empty search.
  List<SearchResult> parseHtml(String html, {int limit = 5}) {
    final results = _parse(html_parser.parse(html), limit);
    if (results.isEmpty && !looksLikeNoResults(html)) {
      throw const SearchMarkupException(
        'DuckDuckGo results could not be parsed',
      );
    }
    return results;
  }

  List<SearchResult> _parse(dom.Document doc, int limit) {
    final out = <SearchResult>[];
    final anchors = <dom.Element>[
      ...doc.querySelectorAll('div.result a.result__a'),
      ...doc.querySelectorAll('a.result-link'),
    ];
    for (final anchor in anchors) {
      if (out.length >= limit) break;
      final href = anchor.attributes['href'];
      if (href == null) continue;

      dom.Element? row = anchor;
      while (row?.parent != null &&
          row!.localName != 'tr' &&
          !row.classes.contains('result')) {
        row = row.parent;
      }
      final rawUri = Uri.parse('https://duckduckgo.com').resolve(href);
      final providerAd = _isProvider(rawUri) && rawUri.path == '/y.js';
      final sponsored =
          providerAd ||
          (row != null &&
              (row.classes.contains('result--ad') ||
                  row.classes.any((c) => c.startsWith('result--ad'))));
      final url = _resolve(href);
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          (_isProvider(uri) && !sponsored)) {
        continue;
      }
      final snippet =
          row?.querySelector('a.result__snippet')?.text ??
          row?.querySelector('.result__snippet')?.text ??
          row?.querySelector('td.result-snippet')?.text ??
          row?.nextElementSibling?.querySelector('.result-snippet')?.text ??
          '';

      // A missing snippet is not a reason to drop a usable destination
      // (roadmap §7.3); the page itself is what gets read.
      if (out.any((r) => r.url == url)) continue;
      final clean = _clean(snippet);
      out.add(
        SearchResult(
          title: anchor.text.trim(),
          url: url,
          snippet: clean.substring(0, clean.length.clamp(0, 1200)),
          source: Uri.tryParse(url)?.host,
          rank: out.length + 1,
          sponsored: sponsored,
        ),
      );
    }
    return out;
  }

  String _resolve(String href) {
    final uri = Uri.parse('https://duckduckgo.com').resolve(href);
    if (_isProvider(uri) && uri.path == '/l/') {
      return uri.queryParameters['uddg'] ?? uri.toString();
    }
    if (_isProvider(uri) && uri.path == '/y.js') {
      return uri.queryParameters['u3'] ?? uri.toString();
    }
    return uri.toString();
  }

  static bool _isProvider(Uri uri) =>
      uri.host == 'duckduckgo.com' || uri.host.endsWith('.duckduckgo.com');

  String _clean(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void dispose() => _dio.close();
}
