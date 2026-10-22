// The frozen web the D1 benchmark replays (answer 11: every
// configuration sees the same search results): what one run recorded comes
// back the same in the next, failures included, and nothing else does.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/news_feed_parser.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';

import '../integration_test/support/frozen_web.dart';

void main() {
  final page = WebPage(
    title: 'Measles',
    text: 'Two doses of measles vaccine.',
    finalUri: Uri.parse('https://www.who.int/news-room/measles'),
    fetchedAt: DateTime.utc(2026, 10, 11, 20),
    publishedAt: DateTime.utc(2026, 9, 1),
    feedItems: [
      FeedItem(
        title: 'Story',
        link: 'https://example.org/a',
        summary: 'Lede',
        published: DateTime.utc(2026, 10, 11),
      ),
    ],
  );
  final result = SearchResult(
    title: 'WHO measles',
    url: 'https://www.who.int/news-room/measles',
    snippet: 'Two doses',
    rank: 2,
    pageText: 'Two doses of measles vaccine.',
    publishedAt: DateTime.utc(2026, 9, 1),
    outlet: 'WHO',
    newsItem: true,
  );

  Future<FrozenWeb> reopen(FrozenWeb web, FrozenMode mode) async {
    final dir = await Directory.systemTemp.createTemp('frozen_web');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/web.json';
    await web.save(path);
    return FrozenWeb.open(path, mode, latency: false);
  }

  test('a recorded page and result come back the same', () async {
    final rec = FrozenWeb(FrozenMode.record, latency: false);
    await rec.call(
      'read',
      'a',
      () async => page,
      FrozenWeb.page,
      FrozenWeb.pageFrom,
    );
    await rec.call(
      'search',
      'q',
      () async => [result],
      FrozenWeb.results,
      FrozenWeb.resultsFrom,
    );
    final web = await reopen(rec, FrozenMode.replay);
    final back = await web.call<WebPage>(
      'read',
      'a',
      () => fail('replay must not go live'),
      FrozenWeb.page,
      FrozenWeb.pageFrom,
    );
    expect(jsonEncode(FrozenWeb.page(back)), jsonEncode(FrozenWeb.page(page)));
    expect(back.feedItems!.single.published, DateTime.utc(2026, 10, 11));
    final found = await web.call<List<SearchResult>>(
      'search',
      'q',
      () => fail('replay must not go live'),
      FrozenWeb.results,
      FrozenWeb.resultsFrom,
    );
    expect(
      jsonEncode(FrozenWeb.results(found)),
      jsonEncode(FrozenWeb.results([result])),
    );
    expect(web.calls, {'read': 1, 'search': 1});
    expect(web.misses, isEmpty);
  });

  test('a failure replays as the same failure', () async {
    final rec = FrozenWeb(FrozenMode.record, latency: false);
    await expectLater(
      rec.call<WebPage>(
        'read',
        'down',
        () async => throw const HttpException('Connection reset'),
        FrozenWeb.page,
        FrozenWeb.pageFrom,
      ),
      throwsA(isA<HttpException>()),
    );
    final web = await reopen(rec, FrozenMode.replay);
    await expectLater(
      web.call<WebPage>(
        'read',
        'down',
        () => fail('replay must not go live'),
        FrozenWeb.page,
        FrozenWeb.pageFrom,
      ),
      throwsA(
        predicate((e) => '$e' == '${const HttpException('Connection reset')}'),
      ),
    );
  });

  test(
    'a call the record lacks fails in replay and goes live in fill',
    () async {
      final rec = FrozenWeb(FrozenMode.record, latency: false);
      await rec.call(
        'read',
        'a',
        () async => page,
        FrozenWeb.page,
        FrozenWeb.pageFrom,
      );
      final replay = await reopen(rec, FrozenMode.replay);
      await expectLater(
        replay.call<WebPage>(
          'read',
          'b',
          () => fail('replay must not go live'),
          FrozenWeb.page,
          FrozenWeb.pageFrom,
        ),
        throwsA(isA<ReplayedFailure>()),
      );
      expect(replay.misses, ['read|b']);

      final fill = await reopen(rec, FrozenMode.fill);
      var live = 0;
      Future<WebPage> fetch() async {
        live++;
        return page;
      }

      await fill.call('read', 'a', fetch, FrozenWeb.page, FrozenWeb.pageFrom);
      await fill.call('read', 'b', fetch, FrozenWeb.page, FrozenWeb.pageFrom);
      expect(live, 1, reason: 'only the missing page is fetched');
      expect(fill.entries.keys, containsAll(['read|a', 'read|b']));
    },
  );

  test('heal tries a saved failure again and keeps what answers', () async {
    final rec = FrozenWeb(FrozenMode.record, latency: false);
    await expectLater(
      rec.call<WebPage>(
        'read',
        'a',
        () async => throw const HttpException('bot check'),
        FrozenWeb.page,
        FrozenWeb.pageFrom,
      ),
      throwsA(isA<HttpException>()),
    );
    await rec.call(
      'read',
      'b',
      () async => page,
      FrozenWeb.page,
      FrozenWeb.pageFrom,
    );
    final heal = await reopen(rec, FrozenMode.heal);
    var live = 0;
    Future<WebPage> fetch() async {
      live++;
      return page;
    }

    await heal.call('read', 'a', fetch, FrozenWeb.page, FrozenWeb.pageFrom);
    await heal.call('read', 'b', fetch, FrozenWeb.page, FrozenWeb.pageFrom);
    expect(live, 1, reason: 'only the failure is tried again');
    final web = await reopen(heal, FrozenMode.replay);
    final back = await web.call<WebPage>(
      'read',
      'a',
      () => fail('replay must not go live'),
      FrozenWeb.page,
      FrozenWeb.pageFrom,
    );
    expect(back.title, 'Measles');
  });

  test('a call cancelled while recording never answers in replay', () async {
    final rec = FrozenWeb(FrozenMode.record, latency: false);
    final token = CancelToken()..cancel();
    await expectLater(
      rec.call<WebPage>(
        'read',
        'slow',
        () async => throw StateError('closed'),
        FrozenWeb.page,
        FrozenWeb.pageFrom,
        cancel: token,
      ),
      throwsA(isA<StateError>()),
    );
    expect(rec.entries['read|slow']!['cancelled'], isTrue);
    expect(rec.entries['read|slow']!.containsKey('error'), isFalse);
    final web = await reopen(rec, FrozenMode.replay);
    await expectLater(
      web.call<WebPage>(
        'read',
        'slow',
        () => fail('replay must not go live'),
        FrozenWeb.page,
        FrozenWeb.pageFrom,
      ),
      throwsA(isA<ReplayedFailure>()),
    );
    expect(web.misses, isEmpty);
  });

  test('a replay slower than this run allows times out', () async {
    final web = FrozenWeb(
      FrozenMode.replay,
      saved: {
        'entries': {
          'read|a': {'ms': 400, 'value': FrozenWeb.page(page)},
        },
      },
    );
    final clock = Stopwatch()..start();
    await expectLater(
      web.call<WebPage>(
        'read',
        'a',
        () => fail('replay must not go live'),
        FrozenWeb.page,
        FrozenWeb.pageFrom,
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(predicate((e) => '$e'.startsWith('TimeoutException'))),
    );
    expect(clock.elapsedMilliseconds, lessThan(400));
    // With time to spare it answers, after the recorded time.
    final back = await web.call<WebPage>(
      'read',
      'a',
      () => fail('replay must not go live'),
      FrozenWeb.page,
      FrozenWeb.pageFrom,
      timeout: const Duration(seconds: 2),
    );
    expect(back.title, 'Measles');
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(400));
  });
}
