import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';
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

class _FailedSearch extends _Search {
  final Exception error;
  _FailedSearch(this.error);

  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async => throw error;
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

class _RedirectReader extends WebPageReader {
  final Uri to;
  _RedirectReader(this.to);
  @override
  Future<WebPage> read(
    Uri uri, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 12),
    String language = 'en-US,en;q=0.9',
  }) async => WebPage(
    title: 'Moved',
    text: 'Page',
    finalUri: to,
    fetchedAt: DateTime.utc(2026, 9, 19),
  );
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

ToolRunner _runner(
  String pageText, {
  String userText = 'Read https://example.org/pg',
}) => ToolRunner(
  scraper: _Search(),
  reader: _Reader(pageText),
  settings: const InferenceSettings(webMode: WebMode.auto, toolsEnabled: true),
  userText: userText,
);

ToolCall _call(String name, Map<String, Object> args) => ToolCall(
  id: name,
  name: name,
  arguments:
      '{${args.entries.map((e) => '"${e.key}": "${e.value}"').join(', ')}}',
);

void main() {
  test(
    'search failures direct helpers to existing evidence without claiming a block',
    () async {
      for (final error in [
        const SearchChallengeException('provider bot check'),
        SearchCooldownException('provider block', DateTime.now()),
        const SearchHttpException('DDG HTTP 503'),
      ]) {
        final runner = ToolRunner(
          scraper: _FailedSearch(error),
          reader: _Reader(''),
          settings: const InferenceSettings(
            webMode: WebMode.auto,
            toolsEnabled: true,
          ),
        );
        final result = await runner.run(
          _call('search_web', {'query': 'current facts'}),
        );
        expect(result.ok, isFalse);
        expect(result.output, contains('Search failed temporarily'));
        expect(result.output, contains('already found this turn'));
        expect(result.output, isNot(contains('provider block')));
        expect(result.output, isNot(contains('provider bot check')));
      }
    },
  );

  test('source keys keep path and query case (P2-49)', () {
    expect(
      ToolRunner.sourceKey('https://example.com/Foo'),
      isNot(ToolRunner.sourceKey('https://example.com/foo')),
    );
    expect(
      ToolRunner.sourceKey('https://WWW.Example.com/a/'),
      ToolRunner.sourceKey('http://example.com/a'),
    );
  });

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

  test(
    'read_url refuses a page nobody linked or found (audit P2-01)',
    () async {
      final r = _runner('Secret page', userText: 'What is the default port?');
      final out = await r.run(
        _call('read_url', {'url': 'https://attacker.example/c?d=private'}),
      );
      expect(out.ok, isFalse);
      expect(out.output, contains('Search for it first'));
      // A search result may be read; another page on its site may not,
      // since a found page could carry a secret out in its own path.
      await r.run(_call('search_web', {'query': 'default port'}));
      final found = await r.run(
        _call('read_url', {'url': 'https://example.org/pg'}),
      );
      expect(found.ok, isTrue);
      final pathLeak = await r.run(
        _call('read_url', {'url': 'https://example.org/private-name-here'}),
      );
      expect(pathLeak.ok, isFalse);
      final leak = await r.run(
        _call('read_url', {'url': 'https://example.org/x?q=private'}),
      );
      expect(leak.ok, isFalse);
      // Letter case in a path can carry data too.
      final cased = await r.run(
        _call('read_url', {'url': 'https://example.org/PG'}),
      );
      expect(cased.ok, isFalse);
      // A site the user named is matched by its whole name only.
      final named = _runner('Page', userText: 'Look at github.com for it');
      final ok = await named.run(
        _call('read_url', {'url': 'https://www.github.com/'}),
      );
      expect(ok.ok, isTrue);
      // Naming a site opens its home page, not any path on it.
      final deep = await named.run(
        _call('read_url', {'url': 'https://github.com/a?b=1'}),
      );
      expect(deep.ok, isFalse);
      final part = await named.run(
        _call('read_url', {'url': 'https://hub.com/x'}),
      );
      expect(part.ok, isFalse);
    },
  );

  test(
    'a user URL names its host, not names in its path or user info',
    () async {
      Future<bool> may(String user, String url) async => (await _runner(
        'Page',
        userText: user,
      ).run(_call('read_url', {'url': url}))).ok;
      const link = 'Read https://docs.example/a/evil.example/b?x=leak.example';
      expect(await may(link, 'https://docs.example/'), isTrue);
      expect(
        await may(link, 'https://docs.example/a/evil.example/b?x=leak.example'),
        isTrue,
      );
      expect(await may(link, 'https://docs.example/other'), isFalse);
      expect(await may(link, 'https://evil.example/c'), isFalse);
      expect(await may(link, 'https://leak.example/c'), isFalse);
      const info = 'See https://evil.example@good.example/page';
      expect(await may(info, 'https://good.example/page'), isTrue);
      expect(await may(info, 'https://evil.example/x'), isFalse);
      expect(
        await may('mail me at bob@evil.example', 'https://evil.example/x'),
        isFalse,
      );
      expect(
        await may('try example.net/path', 'https://example.net/path'),
        isTrue,
      );
      expect(
        await may('try example.net/path', 'https://example.net/q'),
        isFalse,
      );
      // Brackets and sentence punctuation are not part of a link.
      expect(
        await may('Read [site](https://example.org).', 'https://example.org/'),
        isTrue,
      );
      expect(
        await may('See <https://example.org/a>.', 'https://example.org/a'),
        isTrue,
      );
      expect(
        await may('Is it https://example.org/a?', 'https://example.org/a'),
        isTrue,
      );
    },
  );

  test('a page a read was redirected to may be read again', () async {
    final r = ToolRunner(
      scraper: _Search(),
      reader: _RedirectReader(Uri.parse('https://example.org/moved')),
      settings: const InferenceSettings(
        webMode: WebMode.auto,
        toolsEnabled: true,
      ),
      userText: 'Read https://short.example/x',
    );
    expect(
      (await r.run(_call('read_url', {'url': 'https://short.example/x'}))).ok,
      isTrue,
    );
    expect(
      (await r.run(_call('read_url', {'url': 'https://example.org/moved'}))).ok,
      isTrue,
    );
    expect(
      (await r.run(_call('read_url', {'url': 'https://example.org/else'}))).ok,
      isFalse,
    );
  });

  test('web-only and actions-only turns never run an external tool', () async {
    for (final mode in ['web', 'actions']) {
      var ran = 0;
      final r = ToolRunner(
        scraper: _Search(),
        reader: _Reader('Page'),
        settings: const InferenceSettings(
          webMode: WebMode.auto,
          toolsEnabled: true,
        ),
        webOnly: mode == 'web',
        actionsOnly: mode == 'actions',
        externalTools: const [
          ToolSpec(name: 'mcp_files', description: 'Files', parameters: {}),
        ],
        externalRun: (call) async {
          ran++;
          return ToolResult(
            call: call,
            output: 'secret',
            ok: true,
            elapsedMs: 0,
          );
        },
      );
      final out = await r.run(_call('mcp_files', {'path': '/'}));
      expect(ran, 0, reason: mode);
      expect(out.ok, isFalse, reason: mode);
    }
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

  test('remote research with Tools off offers only the web tools (P1-04)', () {
    final runner = ToolRunner(
      scraper: _Search(),
      reader: _Reader('Page'),
      settings: const InferenceSettings(
        webMode: WebMode.auto,
        toolsEnabled: true,
      ),
      remote: true,
      webOnly: true,
      recall: (_) async => 'note',
      externalTools: const [
        ToolSpec(name: 'mcp_files', description: 'x', parameters: {}),
      ],
    );
    final names = runner.specs().map((s) => s.name).toSet();
    expect(names, contains('search_web'));
    expect(names.difference(ToolRunner.webTools), isEmpty);
  });

  test('a remote model gets Knowledge only with document sharing (P1-03)', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    ToolRunner runner(bool share) => ToolRunner(
      scraper: _Search(),
      reader: _Reader('Page'),
      knowledge: KnowledgeStore(db),
      remote: true,
      settings: InferenceSettings(
        toolsEnabled: true,
        knowledgeCollection: 'Manuals',
        remoteDocuments: share,
      ),
    );
    expect(runner(true).documentsAllowed, isTrue);
    expect(runner(false).documentsAllowed, isFalse);
  });

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
