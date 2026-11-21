// Live network check of the news desk: real DuckDuckGo news listing and
// real publisher feeds, printed for review. Skipped unless LIVE_WEB=1 so the
// normal suite never touches the network:
//   $env:LIVE_WEB=1; flutter test test/live/news_desk_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/retrieval/domain/news_intent.dart';
import 'package:ondevice_llm/features/retrieval/news_desk.dart';

void main() {
  final live = Platform.environment['LIVE_WEB'] == '1';
  final questions =
      (Platform.environment['LIVE_QUESTIONS'] ??
              "What's the latest news?|Latest news about the Toronto Blue Jays")
          .split('|');
  for (final q in questions) {
    test('news desk: $q', () async {
      final intent = NewsIntent.of(q);
      // ignore: avoid_print
      print('\n=== $q → $intent');
      expect(intent, isNotNull);
      final desk = NewsDesk(
        scraper: DuckDuckGoScraper(),
        reader: WebPageReader(),
      );
      final clock = Stopwatch()..start();
      final b = await desk.gather(
        intent!,
        region: Platform.environment['LIVE_REGION'] ?? 'ca-en',
        language: 'en-CA,en;q=0.9',
        // ignore: avoid_print
        progress: (p) => print('  … $p'),
      );
      // ignore: avoid_print
      print(
        '  ${clock.elapsedMilliseconds} ms · ${b.items.length} stories · '
        '${b.articles.length} articles · feeds ${b.feedsRead} ok / '
        '${b.feedsFailed} failed · provider ${b.providerError ?? 'ok'}',
      );
      for (final s in b.items) {
        final age = s.publishedAt == null
            ? '?'
            : '${DateTime.now().toUtc().difference(s.publishedAt!).inMinutes ~/ 60}h';
        // ignore: avoid_print
        print(
          '  [${s.rank}] ${s.outlet} · $age · ${s.title}\n'
          '      ${s.url}\n      ${s.snippet.length > 160 ? '${s.snippet.substring(0, 160)}…' : s.snippet}',
        );
      }
      for (final a in b.articles) {
        // ignore: avoid_print
        print(
          '  ARTICLE ${a.outlet ?? a.source} · ${a.title} · ${a.pageText?.length} chars\n      ${a.url}',
        );
      }
      expect(b.items, isNotEmpty);
    }, skip: live ? false : 'set LIVE_WEB=1 to run against the network');
  }
}
