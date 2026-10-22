import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';

/// Serves canned responses so the transport paths run without the network.
class _CannedAdapter implements HttpClientAdapter {
  // Factories: a ResponseBody stream can only be read once.
  final List<ResponseBody Function()> queue;
  final requests = <RequestOptions>[];
  int calls = 0;
  _CannedAdapter(this.queue);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    requests.add(options);
    return (queue.length == 1 ? queue.first : queue.removeAt(0))();
  }

  @override
  void close({bool force = false}) {}
}

DuckDuckGoScraper _scraper(List<ResponseBody Function()> queue) {
  final dio = Dio();
  final adapter = _CannedAdapter(queue);
  dio.httpClientAdapter = adapter;
  return DuckDuckGoScraper(dio: dio, requestSpacing: Duration.zero);
}

ResponseBody Function() _body(
  String text,
  int status, {
  Map<String, List<String>>? h,
}) =>
    () => ResponseBody.fromString(text, status, headers: h ?? {});

void main() {
  final challenge = File('test/fixtures/ddg_challenge.html').readAsStringSync();
  final results = File('test/fixtures/ddg_results.html').readAsStringSync();

  test(
    'extracts snippets, decodes redirects once and excludes unsafe URLs',
    () {
      final scraper = DuckDuckGoScraper();
      addTearDown(scraper.dispose);
      final parsed = scraper.parseHtml('''
    <div class="result"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa%253Fb">Example</a><div class="result__snippet">Hello &amp; world</div></div>
    <div class="result"><a class="result__a" href="javascript:alert(1)">Bad</a><div class="result__snippet">Bad</div></div>
    <div class="result"><a class="result__a" href="https://example.org">Empty</a></div>
    ''');
      expect(parsed.length, 2, reason: 'a missing snippet keeps the link');
      expect(parsed.first.url, 'https://example.com/a%3Fb');
      expect(parsed.first.snippet, 'Hello & world');
      expect(parsed.last.url, 'https://example.org');
      expect(parsed.last.snippet, '');
      expect(
        () => scraper.parseHtml('<div>unrecognized response</div>'),
        throwsA(isA<SearchMarkupException>()),
      );
    },
  );

  test('parses the captured live results page', () {
    final scraper = DuckDuckGoScraper();
    addTearDown(scraper.dispose);
    final parsed = scraper.parseHtml(results);
    expect(parsed.length, 2);
    expect(parsed.first.url, startsWith('https://docs.flutter.dev/'));
    expect(parsed.first.snippet, contains('release'));
    expect(parsed.first.title, isNotEmpty);
  });

  test('search region uses only supported country and app-language pairs', () {
    expect(DuckDuckGoScraper.regionFor('', localeName: 'en_CA'), 'ca-en');
    expect(DuckDuckGoScraper.regionFor('fr', localeName: 'en_CA'), 'ca-fr');
    expect(DuckDuckGoScraper.regionFor('', localeName: 'en_US'), 'us-en');
    expect(DuckDuckGoScraper.regionFor('', localeName: 'en-GB'), 'uk-en');
    expect(DuckDuckGoScraper.regionFor('fr', localeName: 'en_US'), 'fr-fr');
    expect(DuckDuckGoScraper.regionFor('', localeName: 'es_US'), 'us-en');
    expect(DuckDuckGoScraper.regionFor('en', localeName: 'ja_JP'), 'jp-jp');
    expect(DuckDuckGoScraper.regionFor('en', localeName: 'zh_TW'), 'tw-tzh');
    expect(DuckDuckGoScraper.regionFor('', localeName: 'en'), 'wt-wt');
    expect(DuckDuckGoScraper.regionFor('fr', localeName: 'C'), 'fr-fr');
    expect(
      DuckDuckGoScraper.acceptLanguageFor('ca-fr'),
      'fr-CA,fr;q=0.9,en;q=0.7',
    );
    expect(DuckDuckGoScraper.acceptLanguageFor('uk-en'), 'en-GB,en;q=0.9');
    expect(
      DuckDuckGoScraper.acceptLanguageFor('jp-jp'),
      'ja-JP,ja;q=0.9,en;q=0.7',
    );
    expect(
      DuckDuckGoScraper.acceptLanguageFor('tw-tzh'),
      'zh-TW,zh;q=0.9,en;q=0.7',
    );
    expect(DuckDuckGoScraper.acceptLanguageFor('wt-wt'), 'en;q=0.9');
  });

  test('ad rows are labeled and their provider redirect is unwrapped', () {
    const page = '''
      <div class="results">
        <div class="result results_links result--ad">
          <a class="result__a" href="https://shop.example">Buy now</a>
          <a class="result__snippet">Sponsored</a>
        </div>
        <div class="result results_links">
          <a class="result__a" href="https://duckduckgo.com/y.js?ad_provider=x&u3=https%3A%2F%2Fpartner.example%2Fdeal">Partner offer</a>
          <a class="result__snippet">Provider ad redirect</a>
        </div>
        <div class="result results_links">
          <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.org%2Fdoc&amp;rut=abc">Real doc</a>
          <a class="result__snippet">A real page.</a>
        </div>
      </div>''';
    final found = _scraper([_body(page, 200)]).parseHtml(page, limit: 5);
    expect(found, hasLength(3));
    expect(found.first.title, 'Buy now');
    expect(found.first.url, 'https://shop.example');
    expect(found.first.sponsored, isTrue);
    expect(found[1].url, 'https://partner.example/deal');
    expect(found[1].sponsored, isTrue);
    expect(found.last.url, 'https://example.org/doc');
    expect(found.last.sponsored, isFalse);
  });

  test('the same query within an hour is answered without a request', () async {
    final dio = Dio();
    final adapter = _CannedAdapter([_body(results, 200)]);
    dio.httpClientAdapter = adapter;
    final scraper = DuckDuckGoScraper(dio: dio, requestSpacing: Duration.zero);
    addTearDown(scraper.dispose);
    final first = await scraper.search('flutter', limit: 3);
    expect(first, hasLength(2));
    expect(adapter.calls, 1);
    final again = await scraper.search('  Flutter ', limit: 3);
    expect(again.map((r) => r.url), first.map((r) => r.url));
    expect(adapter.calls, 1, reason: 'served from the hour cache');
    // A bigger ask than what was remembered goes back to the provider.
    await scraper.search('flutter', limit: 5);
    expect(adapter.calls, 2);
    // Another region is another query.
    await scraper.search('flutter', limit: 3, localeCode: 'fr');
    expect(adapter.calls, 3);
  });

  test(
    'date filters are timely-only, cached separately, and retry empty',
    () async {
      const empty = '<html><div class="no-results">No results.</div></html>';
      final dio = Dio();
      final adapter = _CannedAdapter([
        _body(empty, 200),
        _body(results, 200),
        _body(results, 200),
        _body(results, 200),
      ]);
      dio.httpClientAdapter = adapter;
      final scraper = DuckDuckGoScraper(
        dio: dio,
        requestSpacing: Duration.zero,
      );
      addTearDown(scraper.dispose);

      final latest = RetrievalPlan.searchDateFilter('latest Flutter release');
      expect(latest, 'y');
      expect(
        await scraper.search('latest Flutter release', dateFilter: latest),
        isNotEmpty,
      );
      expect((adapter.requests[0].data as Map)['df'], 'y');
      expect((adapter.requests[1].data as Map).containsKey('df'), isFalse);

      final news = RetrievalPlan.searchDateFilter('Flutter news today');
      expect(news, 'm');
      await scraper.search('Flutter news today', dateFilter: news);
      expect((adapter.requests[2].data as Map)['df'], 'm');

      expect(
        RetrievalPlan.searchDateFilter('Flutter widget lifecycle'),
        isNull,
      );
      await scraper.search('Flutter widget lifecycle');
      expect((adapter.requests[3].data as Map).containsKey('df'), isFalse);

      await scraper.search('Flutter widget lifecycle', dateFilter: 'y');
      expect(adapter.calls, 5, reason: 'df is part of the result-cache key');
    },
  );

  test('falls back once to DuckDuckGo Lite markup', () async {
    final drift =
        '<html>${'<div class="result"><a class="renamed-result-anchor" href="https://example.net">redesigned result</a></div>' * 10}</html>';
    const lite = '''
      <table>
        <tr><td><a class="result-link" href="https://example.com/article">Useful result</a></td></tr>
        <tr><td class="result-snippet">A concise result snippet.</td></tr>
      </table>
    ''';
    final scraper = _scraper([_body(drift, 200), _body(lite, 200)]);
    addTearDown(scraper.dispose);
    final found = await scraper.search('useful', localeCode: 'fr');
    expect(found.single.title, 'Useful result');
    expect(found.single.snippet, 'A concise result snippet.');
    expect(found.single.rank, 1);
  });

  group('a "no results" page gets one Lite try', () {
    const empty = '<html><div class="no-results">No results.</div></html>';
    const lite = '''
      <table>
        <tr><td><a class="result-link" href="https://example.com/z30">Nikon Z30 specs</a></td></tr>
        <tr><td class="result-snippet">Weight: 405 g.</td></tr>
      </table>
    ''';
    (DuckDuckGoScraper, _CannedAdapter) make(ResponseBody Function() second) {
      final dio = Dio();
      final adapter = _CannedAdapter([_body(empty, 200), second]);
      dio.httpClientAdapter = adapter;
      final scraper = DuckDuckGoScraper(
        dio: dio,
        requestSpacing: Duration.zero,
      );
      addTearDown(scraper.dispose);
      return (scraper, adapter);
    }

    test('and its results are used', () async {
      final (scraper, adapter) = make(_body(lite, 200));
      final found = await scraper.search('Nikon Z30 weight');
      expect(found.single.title, 'Nikon Z30 specs');
      expect(adapter.requests.map((r) => r.uri.host), [
        'html.duckduckgo.com',
        'lite.duckduckgo.com',
      ]);
      expect(adapter.requests.last.data, containsPair('q', 'Nikon Z30 weight'));
      expect(scraper.health.status, 'ready');
    });

    test(
      'the empty answer stands when Lite is empty, unreadable or down',
      () async {
        for (final second in [
          _body(empty, 200),
          _body('<html>${'<p>unrelated redesign</p>' * 40}</html>', 200),
          _body('', 500),
        ]) {
          final (scraper, adapter) = make(second);
          expect(await scraper.search('Nikon Z30 weight'), isEmpty);
          expect(adapter.calls, 2, reason: 'one Lite try, no more');
          expect(scraper.health.status, 'empty');
        }
      },
    );

    test('a bot check or rate limit there still pauses search', () async {
      for (final (second, type) in [
        (_body(challenge, 202), isA<SearchChallengeException>()),
        (_body('', 429), isA<SearchRateLimitException>()),
      ]) {
        final (scraper, adapter) = make(second);
        await expectLater(scraper.search('Nikon Z30 weight'), throwsA(type));
        await expectLater(
          scraper.search('another question'),
          throwsA(isA<SearchCooldownException>()),
        );
        expect(adapter.calls, 2);
      }
    });

    test('a dated search goes to its undated retry first', () async {
      final dio = Dio();
      final adapter = _CannedAdapter([
        _body(empty, 200),
        _body(empty, 200),
        _body(lite, 200),
      ]);
      dio.httpClientAdapter = adapter;
      final scraper = DuckDuckGoScraper(
        dio: dio,
        requestSpacing: Duration.zero,
      );
      addTearDown(scraper.dispose);
      final found = await scraper.search('latest Nikon Z30', dateFilter: 'y');
      expect(found.single.title, 'Nikon Z30 specs');
      expect(
        [
          for (final r in adapter.requests)
            '${r.uri.host} ${(r.data as Map)['df'] ?? '-'}',
        ],
        [
          'html.duckduckgo.com y',
          'html.duckduckgo.com -',
          'lite.duckduckgo.com -',
        ],
      );
    });
  });

  test('a 2xx page with neither results nor the empty marker is drift', () {
    final scraper = DuckDuckGoScraper();
    addTearDown(scraper.dispose);
    expect(
      () =>
          scraper.parseHtml('<html>${'<p>unrelated redesign</p>' * 40}</html>'),
      throwsA(isA<SearchMarkupException>()),
    );
    expect(
      scraper.parseHtml(
        '<html><div class="no-results">No results.</div>${' ' * 600}</html>',
      ),
      isEmpty,
    );
  });

  test(
    'bot check (202 anomaly page) is a challenge, then a cooldown',
    () async {
      final scraper = _scraper([_body(challenge, 202)]);
      addTearDown(scraper.dispose);
      await expectLater(
        scraper.search('flutter'),
        throwsA(isA<SearchChallengeException>()),
      );
      await expectLater(
        scraper.search('flutter'),
        throwsA(isA<SearchCooldownException>()),
        reason: 'no second request while paused',
      );
    },
  );

  test('challenge markup with HTTP 200 is still a challenge', () async {
    final scraper = _scraper([_body(challenge, 200)]);
    addTearDown(scraper.dispose);
    await expectLater(
      scraper.search('flutter'),
      throwsA(isA<SearchChallengeException>()),
    );
  });

  test(
    'searches are form POSTs, the way DuckDuckGo\'s own page sends them',
    () async {
      final dio = Dio();
      final adapter = _CannedAdapter([_body(results, 200)]);
      dio.httpClientAdapter = adapter;
      final scraper = DuckDuckGoScraper(
        dio: dio,
        requestSpacing: Duration.zero,
      );
      addTearDown(scraper.dispose);
      await scraper.search('flutter release', localeCode: 'fr');
      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(
        sent.uri.toString(),
        startsWith('https://html.duckduckgo.com/html'),
      );
      expect(sent.contentType, contains('application/x-www-form-urlencoded'));
      expect(sent.data, containsPair('q', 'flutter release'));
      expect(sent.data, containsPair('kl', 'fr-fr'));
      expect(sent.uri.queryParameters, isEmpty, reason: 'nothing in the URL');
    },
  );

  test('an explicit region wins over the app locale', () async {
    final dio = Dio();
    final adapter = _CannedAdapter([_body(results, 200)]);
    dio.httpClientAdapter = adapter;
    final scraper = DuckDuckGoScraper(dio: dio, requestSpacing: Duration.zero);
    addTearDown(scraper.dispose);
    await scraper.search('news', localeCode: 'fr', region: 'uk-en');
    expect(adapter.requests.single.data, containsPair('kl', 'uk-en'));
  });

  test('requests are spaced so a burst does not earn a bot check', () async {
    final dio = Dio();
    final adapter = _CannedAdapter([_body(results, 200)]);
    dio.httpClientAdapter = adapter;
    final scraper = DuckDuckGoScraper(
      dio: dio,
      requestSpacing: const Duration(milliseconds: 250),
    );
    addTearDown(scraper.dispose);
    final clock = Stopwatch()..start();
    await Future.wait([
      scraper.search('one'),
      scraper.search('two'),
      scraper.search('three'),
    ]);
    expect(adapter.calls, 3);
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(480));
  });

  group('news vertical', () {
    const token =
        '<html><script>DDG.deep.initialize("/d.js?q=news&vqd=4-1234567890123-98765", false);</script></html>';
    final listing = jsonEncode({
      'results': [
        {
          'date': 1790127420,
          'excerpt':
              'VICTORIA &mdash; B.C.&#x27;s premier called a snap election.',
          'source': 'The Canadian Press',
          'title': 'Eby calls Oct. 24 snap election',
          'url': 'https://www.msn.com/en-ca/news/canada/eby/ar-AA1',
        },
        {'title': '', 'url': 'https://example.com/no-title'},
        {'title': 'Bad link', 'url': 'javascript:alert(1)'},
        {
          'date': 1790120000,
          'excerpt': 'The US president spoke at the UN.',
          'source': 'Reuters',
          'title': 'Trump addresses the UN',
          'url': 'https://www.reuters.com/world/un-speech',
        },
      ],
    });

    test('takes the query token, then the JSON listing', () async {
      final dio = Dio();
      final adapter = _CannedAdapter([_body(token, 200), _body(listing, 200)]);
      dio.httpClientAdapter = adapter;
      final scraper = DuckDuckGoScraper(
        dio: dio,
        requestSpacing: Duration.zero,
      );
      addTearDown(scraper.dispose);
      final news = await scraper.news('news', region: 'ca-en', window: 'd');
      expect(adapter.requests.first.method, 'POST');
      final listingRequest = adapter.requests.last;
      expect(listingRequest.uri.path, '/news.js');
      expect(
        listingRequest.uri.queryParameters['vqd'],
        '4-1234567890123-98765',
      );
      expect(listingRequest.uri.queryParameters['l'], 'ca-en');
      expect(listingRequest.uri.queryParameters['df'], 'd');
      expect(news, hasLength(2), reason: 'no title or no http link: dropped');
      expect(news.first.title, 'Eby calls Oct. 24 snap election');
      expect(
        news.first.snippet,
        "VICTORIA — B.C.'s premier called a snap election.",
      );
      expect(news.first.outlet, 'The Canadian Press');
      expect(news.first.newsItem, isTrue);
      expect(news.first.pageText, news.first.snippet);
      expect(
        news.first.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(1790127420000, isUtc: true),
      );
      // Ten minutes of reuse: no new request.
      await scraper.news('news', region: 'ca-en', window: 'd');
      expect(adapter.calls, 2);
    });

    test('a bot check on the token page pauses search', () async {
      final scraper = _scraper([_body(challenge, 202)]);
      addTearDown(scraper.dispose);
      await expectLater(
        scraper.news('news'),
        throwsA(isA<SearchChallengeException>()),
      );
      await expectLater(
        scraper.search('flutter'),
        throwsA(isA<SearchCooldownException>()),
      );
    });

    test('token and listing parsing are strict', () {
      expect(DuckDuckGoScraper.vqdOf("vqd='4-111-222'"), '4-111-222');
      expect(DuckDuckGoScraper.vqdOf('vqd=4-333&'), '4-333');
      expect(DuckDuckGoScraper.vqdOf('no token here'), isNull);
      expect(
        () => DuckDuckGoScraper.parseNews('<html>blocked</html>'),
        throwsA(isA<SearchMarkupException>()),
      );
      expect(DuckDuckGoScraper.parseNews('{"results": []}'), isEmpty);
    });
  });

  test('429 with a short Retry-After is retried once, then surfaces', () async {
    final dio = Dio();
    final adapter = _CannedAdapter([
      _body(
        '',
        429,
        h: {
          'retry-after': ['0'],
        },
      ),
      _body(results, 200),
    ]);
    dio.httpClientAdapter = adapter;
    final scraper = DuckDuckGoScraper(dio: dio, requestSpacing: Duration.zero);
    addTearDown(scraper.dispose);
    expect((await scraper.search('flutter')).length, 2);
    expect(adapter.calls, 2);

    final stuck = _scraper([
      _body(
        '',
        429,
        h: {
          'retry-after': ['0'],
        },
      ),
    ]);
    addTearDown(stuck.dispose);
    await expectLater(
      stuck.search('flutter'),
      throwsA(isA<SearchRateLimitException>()),
    );
    await expectLater(
      stuck.search('flutter'),
      throwsA(isA<SearchCooldownException>()),
    );
  });
}
