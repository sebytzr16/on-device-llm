import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/chat/domain/research_recipes.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

class _Search extends DuckDuckGoScraper {
  final queries = <String>[];
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async {
    queries.add(query);
    return const [
      SearchResult(
        title: 'PostgreSQL docs',
        url: 'https://example.org/pg',
        snippet: 'Connection settings',
        rank: 1,
      ),
    ];
  }
}

class _RecipeSearch extends DuckDuckGoScraper {
  final queries = <String>[];
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async {
    queries.add(query);
    return const [
      SearchResult(
        title: 'Official biography',
        url: 'https://studio.example/biography',
        snippet: 'Verified biographical details',
        rank: 1,
      ),
      SearchResult(
        title: 'Wikipedia entry',
        url: 'https://en.wikipedia.org/wiki/Example',
        snippet: 'Verified biographical details',
        rank: 2,
      ),
    ];
  }
}

class _Reader extends WebPageReader {
  final String text;
  int calls = 0;
  _Reader(this.text);
  @override
  Future<WebPage> read(
    Uri uri, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 12),
    String language = 'en-US,en;q=0.9',
  }) async {
    calls++;
    return WebPage(
      title: 'PostgreSQL docs',
      text: text,
      finalUri: uri,
      fetchedAt: DateTime.utc(2026, 9, 19),
      publishedAt: DateTime.utc(2025, 1, 2),
    );
  }
}

class _SponsoredSearch extends DuckDuckGoScraper {
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async => const [
    SearchResult(
      title: 'Buy database hosting',
      url: 'https://shop.example/offer',
      snippet: 'Advertisement',
      rank: 1,
      sponsored: true,
    ),
    SearchResult(
      title: 'PostgreSQL docs',
      url: 'https://example.org/pg',
      snippet: 'Connection settings',
      rank: 2,
    ),
  ];
}

ToolRunner _runner(String pageText) => ToolRunner(
  scraper: _Search(),
  reader: _Reader(pageText),
  settings: const InferenceSettings(webMode: WebMode.auto, toolsEnabled: true),
);

ToolCall _call(String name, Map<String, Object> args) => ToolCall(
  id: name,
  name: name,
  arguments:
      '{${args.entries.map((e) => '"${e.key}": "${e.value}"').join(', ')}}',
);

void main() {
  test(
    'biography recipe searches Wikipedia before independent sources',
    () async {
      final search = _RecipeSearch();
      final runner = ToolRunner(
        scraper: search,
        reader: _Reader('Biography'),
        settings: const InferenceSettings(
          webMode: WebMode.auto,
          toolsEnabled: true,
        ),
        researchRecipe: ResearchRecipe.forQuestion('Who is actor Example?'),
      );
      final result = await runner.run(
        _call('search_web', {'query': 'actor Example biography'}),
      );
      // One request: the preferred source leads when the engine returned
      // it; no separate site: search is spent looking for it.
      expect(search.queries, ['actor Example biography']);
      expect(
        result.output.indexOf('wikipedia.org'),
        lessThan(result.output.indexOf('studio.example')),
      );
    },
  );

  test('read_url returns a short page whole, with its dates', () async {
    final page = '${'The default port is 5432. ' * 250}END';
    final r = _runner(page);
    final out = await r.run(
      _call('read_url', {'url': 'https://example.org/pg'}),
    );
    expect(out.ok, isTrue);
    expect(
      out.output,
      startsWith('[1] PostgreSQL docs — https://example.org/pg'),
    );
    expect(out.output, contains('published 2025-01-02'));
    expect(out.output, contains('The default port is 5432.'));
    expect(out.output, endsWith('END'));
    expect(out.output, isNot(contains('long page')));
    expect(out.output.length, lessThanOrEqualTo(ToolRunner.maxReadChars));
  });

  test('SearchResult.withPage preserves metadata omitted by the caller', () {
    final fetched = DateTime.utc(2026, 1, 2);
    final original = SearchResult(
      title: 'Title',
      url: 'https://example.org',
      snippet: 'Snippet',
      source: 'example.org',
      rank: 3,
      pageText: 'old',
      finalUrl: 'https://example.org/final',
      fetchedAt: fetched,
      publishedAt: DateTime.utc(2025, 12, 1),
      readError: 'old error',
      stale: true,
      sponsored: true,
    );
    final changed = original.withPage(text: 'new');
    expect(changed.pageText, 'new');
    expect(changed.finalUrl, original.finalUrl);
    expect(changed.fetchedAt, fetched);
    expect(changed.publishedAt, original.publishedAt);
    expect(changed.readError, original.readError);
    expect(changed.stale, isTrue);
    expect(changed.sponsored, isTrue);
  });

  test('read_url returns the best passages of a long page, in order', () async {
    final filler = List.generate(
      60,
      (i) =>
          'Paragraph $i about backups, replication and vacuum settings. ' * 4,
    );
    filler[40] =
        'Connections: the default TCP port for PostgreSQL is 5432; change it with the port setting.';
    final r = _runner(filler.join('\n'));
    // A search first: read_url without a query ranks by what was searched.
    await r.run(_call('search_web', {'query': 'default TCP port PostgreSQL'}));
    final out = await r.run(
      _call('read_url', {'url': 'https://example.org/pg'}),
    );
    expect(out.ok, isTrue);
    expect(out.output, contains('long page:'));
    expect(out.output, contains('best matching "default TCP port PostgreSQL"'));
    expect(out.output, contains('5432'));
    expect(out.output.length, lessThanOrEqualTo(ToolRunner.maxReadChars));
    expect(out.output, isNot(contains('…[cut at')));
    // An explicit query wins over the last search.
    final again = await r.run(
      _call('read_url', {
        'url': 'https://example.org/pg',
        'query': 'vacuum settings',
      }),
    );
    expect(again.output, contains('best matching "vacuum settings"'));
    // Without any query the opening passages come back.
    final fresh = _runner(filler.join('\n'));
    final opening = await fresh.run(
      _call('read_url', {'url': 'https://example.org/pg'}),
    );
    expect(opening.output, contains('Paragraph 0 about'));
    expect(opening.output, isNot(contains('best matching')));
  });

  test(
    'read_url keeps a decisive late passage and never exceeds its budget',
    () async {
      final paragraphs = List.generate(
        12,
        (i) => 'PASSAGE_$i ${'ordinary archive material. ' * 55}',
      );
      paragraphs[11] =
          'PASSAGE_11 decisive quasar launch authorization code ORCHID-739. '
          '${'supporting context. ' * 45}';
      final r = _runner(paragraphs.join('\n\n'));
      final out = await r.run(
        _call('read_url', {
          'url': 'https://example.org/pg',
          'query': 'quasar launch authorization ORCHID-739',
        }),
      );
      expect(out.ok, isTrue);
      expect(out.output, contains('ORCHID-739'));
      expect(out.output.length, lessThanOrEqualTo(ToolRunner.maxReadChars));
      expect(
        RegExp(r'PASSAGE_\d+').allMatches(out.output).length,
        lessThanOrEqualTo(5),
      );
    },
  );

  test(
    'sponsored search rows are labeled, unnumbered and never readable',
    () async {
      final reader = _Reader('Evidence. ' * 100);
      final runner = ToolRunner(
        scraper: _SponsoredSearch(),
        reader: reader,
        settings: const InferenceSettings(
          webMode: WebMode.auto,
          toolsEnabled: true,
        ),
      );
      final search = await runner.run(
        _call('search_web', {'query': 'database hosting'}),
      );
      expect(
        search.output,
        contains('[sponsored] Buy database hosting — shop.example'),
      );
      expect(search.output, isNot(contains('[1] Buy database hosting')));
      expect(runner.sources, hasLength(1));
      expect(runner.sponsored, hasLength(1));

      final read = await runner.run(
        _call('read_url', {'url': 'https://shop.example/offer'}),
      );
      expect(read.ok, isFalse);
      expect(
        read.output.toLowerCase(),
        contains('sponsored result, not evidence'),
      );
      expect(reader.calls, 0);
    },
  );

  test(
    'phone actions are offered alone when the other tools are off',
    () async {
      final runner = ToolRunner(
        scraper: _Search(),
        reader: _Reader('Page'),
        settings: const InferenceSettings(webMode: WebMode.auto),
        phoneActions: true,
        actionsOnly: true,
      );
      expect(runner.specs().map((s) => s.name).toSet(), PhoneActions.kinds);
      final web = await runner.run(_call('search_web', {'query': 'x'}));
      expect(web.ok, isFalse);
      final alarm = await runner.run(_call('set_alarm', {'time': '07:30'}));
      expect(alarm.ok, isTrue);
      expect(alarm.output, contains('Prepared'));
      // Nothing asked for: nothing offered.
      expect(
        ToolRunner(
          scraper: _Search(),
          reader: _Reader('Page'),
          settings: const InferenceSettings(),
          actionsOnly: true,
        ).specs(),
        isEmpty,
      );
    },
  );

  test('with tools on, action tools join the others only when asked', () {
    final names = _runner('x').specs().map((s) => s.name).toSet();
    expect(names.intersection(PhoneActions.kinds), isEmpty);
    final withActions = ToolRunner(
      scraper: _Search(),
      reader: _Reader('Page'),
      settings: const InferenceSettings(
        webMode: WebMode.auto,
        toolsEnabled: true,
      ),
      phoneActions: true,
    ).specs().map((s) => s.name).toSet();
    expect(withActions, containsAll(PhoneActions.kinds));
    expect(withActions, contains('search_web'));
  });
  test('a remote search_web brings the top pages\' best passages', () async {
    final reader = _Reader(
      '${'Unrelated introduction text about databases. ' * 20}\n\n'
      'The default port for PostgreSQL connections is 5432.\n\n'
      '${'More filler about history and licences. ' * 20}',
    );
    final runner = ToolRunner(
      scraper: _Search(),
      reader: reader,
      remote: true,
      settings: const InferenceSettings(
        webMode: WebMode.auto,
        toolsEnabled: true,
      ),
    );
    final out = await runner.run(
      _call('search_web', {'query': 'postgresql default port'}),
    );
    expect(reader.calls, 1);
    expect(out.output, contains('From the top pages:'));
    expect(out.output, contains('5432'));
    expect(out.output, isNot(contains('Use read_url on a result')));
    // The source is upgraded with the page it read.
    expect(runner.sources.single.pageText, contains('5432'));
    // On the phone the results stay snippets.
    final local = _Reader('The default port is 5432.');
    final phone = await ToolRunner(
      scraper: _Search(),
      reader: local,
      settings: const InferenceSettings(
        webMode: WebMode.auto,
        toolsEnabled: true,
      ),
    ).run(_call('search_web', {'query': 'postgresql default port'}));
    expect(local.calls, 0);
    expect(phone.output, contains('Use read_url on a result'));
  });
}
