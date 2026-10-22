// Live check of the two keyless sources (DuckDuckGo, Wikipedia)
// against the real network; skipped unless LIVE_WEB=1.
//   $env:LIVE_WEB=1; flutter test test/live/search_engines_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/wikipedia_client.dart';

void main() {
  final live = Platform.environment['LIVE_WEB'] == '1';
  final skip = live ? false : 'set LIVE_WEB=1 to run against the network';

  void show(String name, List<SearchResult> results) {
    // ignore: avoid_print
    print('\n=== $name: ${results.length} results');
    for (final r in results) {
      // ignore: avoid_print
      print('  ${r.rank}. ${r.title} · ${Uri.tryParse(r.url)?.host}');
    }
  }

  test('DuckDuckGo finds the maker page for a product', () async {
    final results = await DuckDuckGoScraper().search(
      'Nikon Z30 weight',
      limit: 8,
      region: 'ca-en',
    );
    show('DuckDuckGo', results);
    expect(results, isNotEmpty);
    expect(results.every((r) => r.url.startsWith('http')), isTrue);
  }, skip: skip);

  test(
    'live suite yields useful coverage, including a maker manual',
    () async {
      final ddg = DuckDuckGoScraper();
      var useful = 0;
      var primary = false;
      for (final (query, anchor) in [
        ('Nikon Z30 weight', 'z30'),
        ('Dart Map API documentation', 'map'),
        ('site:nikonusa.com Z30 specifications manual', 'z30'),
      ]) {
        List<SearchResult> results;
        try {
          results = await ddg.search(query, limit: 8, region: 'ca-en');
        } catch (_) {
          // A blocked provider is observed, never counted as coverage.
          // ignore: avoid_print
          print(
            'COVERAGE_UNAVAILABLE: $query; ${ddg.health.toJson()}',
          );
          continue;
        }
        final relevant = results
            .where(
              (r) => '${r.title} ${r.snippet} ${r.url}'.toLowerCase().contains(
                anchor,
              ),
            )
            .toList();
        show('coverage $query', relevant);
        if (relevant.isNotEmpty) useful++;
        primary |= relevant.any((r) {
          final host = Uri.tryParse(r.url)?.host ?? '';
          return [
            'nikonusa.com',
            'nikon.com',
            'nikon.ca',
            'nikonimglib.com',
          ].any((domain) => host == domain || host.endsWith('.$domain'));
        });
      }
      expect(
        useful,
        greaterThanOrEqualTo(2),
        reason: 'empty provider lists cannot establish coverage',
      );
      expect(
        primary,
        isTrue,
        reason:
            'a real primary-site result is required, even when the targeted query is blocked',
      );
    },
    skip: skip,
  );

  test('Wikipedia: product, person (FR) and event (ES)', () async {
    final wiki = WikipediaClient();
    final camera = await wiki.lookup('Nikon Z30 weight and battery life');
    final person = await wiki.lookup(
      'Qui est Denis Villeneuve ?',
      language: 'fr',
    );
    final event = await wiki.lookup(
      'Copa Mundial de la FIFA 2022',
      language: 'es',
    );
    for (final (name, r) in [
      ('camera', camera),
      ('person', person),
      ('event', event),
    ]) {
      // ignore: avoid_print
      print(
        '\n=== Wikipedia $name: ${r?.title} · ${r?.url} · '
        '${r?.pageText?.length ?? 0} chars',
      );
    }
    expect(
      camera == null || camera.title.contains('Z30'),
      isTrue,
      reason: 'never the family article',
    );
    expect(person?.url, contains('fr.wikipedia.org'));
    expect(person?.pageText, contains('Villeneuve'));
    expect(event?.url, contains('es.wikipedia.org'));
  }, skip: skip);
}
