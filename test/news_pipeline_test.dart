import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/news_feed_parser.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/chat/domain/answer_cleanup.dart';
import 'package:ondevice_llm/features/chat/domain/answer_shape.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/retrieval/domain/news_intent.dart';
import 'package:ondevice_llm/features/retrieval/domain/source_quality.dart';
import 'package:ondevice_llm/features/retrieval/news_desk.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

import 'chat_test.dart' show TestEngine, TestModels, TestSettings, TestSearch;

class _WebSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(webMode: WebMode.auto);
}

final _now = DateTime.now().toUtc();

SearchResult _story(
  String title,
  String outlet, {
  String? url,
  Duration age = const Duration(hours: 2),
  String lede = '',
}) => SearchResult(
  title: title,
  url: url ?? 'https://news.example/${title.hashCode.abs()}',
  snippet: lede,
  rank: 0,
  pageText: lede.isEmpty ? title : lede,
  publishedAt: _now.subtract(age),
  outlet: outlet,
  newsItem: true,
);

class _FakeDesk extends NewsDesk {
  final List<SearchResult> items;
  final intents = <NewsIntent>[];
  _FakeDesk(this.items)
    : super(scraper: DuckDuckGoScraper(), reader: WebPageReader());

  @override
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
    intents.add(intent);
    return NewsBriefing(
      items: items,
      elapsed: const Duration(milliseconds: 900),
    );
  }
}

class _ArticleReader extends WebPageReader {
  final reads = <Uri>[];
  @override
  Future<WebPage> read(
    Uri uri, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 12),
    String language = 'en-US,en;q=0.9',
  }) async {
    reads.add(uri);
    return WebPage(
      title: 'Full article',
      text:
          'VICTORIA — Premier David Eby called a snap election for October 24, citing the trade threat. '
              'The opposition parties announced a merger the same afternoon. ' *
          4,
      finalUri: uri,
      fetchedAt: DateTime.now().toUtc(),
    );
  }
}

/// Writes an answer and then starts writing it again, word by word.
class _RepeatingEngine extends TestEngine {
  static const paragraph =
      'The Blue Jays lost 4-3 to the Orioles on Monday and are now 3.5 games '
      'behind the last wild-card spot with five games left in the season [1].';
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    receivedMessages = messages;
    for (final w in paragraph.split(' ')) {
      yield '$w ';
    }
    yield '\n\nAnswer: ';
    for (var i = 0; i < 3; i++) {
      for (final w in paragraph.split(' ')) {
        if (stopped) return;
        yield '$w ';
      }
    }
  }
}

void main() {
  group('NewsIntent', () {
    test('general, place, topic and section questions', () {
      final general = NewsIntent.of("What's the latest news?")!;
      expect(general.general, isTrue);
      expect(general.window, 'd');
      final canada = NewsIntent.of('What is the latest news in Canada today?')!;
      expect(canada.place, 'ca-en');
      expect(canada.topic, isNull);
      final jays = NewsIntent.of(
        'What is the latest news about the Toronto Blue Jays?',
      )!;
      expect(jays.topic, 'Toronto Blue Jays');
      expect(jays.window, 'w');
      expect(NewsIntent.of('tech news')!.category, NewsCategory.technology);
      expect(NewsIntent.of('US news today')!.place, 'us-en');
      expect(NewsIntent.of('any news in New York?')!.topic, 'New York');
      expect(NewsIntent.of('What happened today?')!.general, isTrue);
      expect(
        NewsIntent.of('quelles sont les dernières nouvelles')!.general,
        isTrue,
      );
      expect(NewsIntent.of('sports headlines')!.category, NewsCategory.sports);
    });

    test('questions about the news business are not news requests', () {
      expect(NewsIntent.of('How do news agencies verify stories?'), isNull);
      expect(NewsIntent.of('Write a news article about my cat'), isNull);
      expect(NewsIntent.of('Explain the history of news'), isNull);
      expect(NewsIntent.of('What is the capital of France?'), isNull);
      expect(
        NewsIntent.of(
          'Summarise this long news report for me in five bullet points please because I need it for work tomorrow',
        ),
        isNull,
      );
    });
  });

  group('NewsDesk.rank', () {
    test('merges one story told by several outlets and ranks it up', () {
      final items = [
        _story('Local council debates parking fees', 'Small Paper'),
        _story(
          'Eby calls October 24 snap election in British Columbia',
          'The Canadian Press',
          age: const Duration(hours: 3),
        ),
        _story(
          'B.C. Premier Eby calls snap election for October 24',
          'CBC News',
          age: const Duration(hours: 2),
          lede: 'The premier cited the trade threat from the United States.',
        ),
        _story(
          'Eby calls a snap October 24 election in British Columbia',
          'Global News',
        ),
        _story('Old story', 'BBC News', age: const Duration(days: 3)),
      ];
      final ranked = NewsDesk.rank(
        items,
        const NewsIntent(),
        now: _now,
        maxItems: 10,
      );
      expect(ranked.first.title, contains('snap election'));
      expect(ranked.first.outlet, contains('other outlet'));
      expect(ranked.where((s) => s.title.contains('snap')), hasLength(1));
      expect(
        ranked.any((s) => s.title == 'Old story'),
        isFalse,
        reason: 'a general briefing keeps the last 36 hours',
      );
      expect(ranked.map((s) => s.rank), [1, 2]);
    });

    test('a topic keeps only stories about it, over a week', () {
      final items = [
        _story('Blue Jays postponed by rain in Baltimore', 'Sportsnet'),
        _story('Leafs sign a defenceman', 'TSN'),
        _story(
          'Blue Jays near elimination',
          'CP24',
          age: const Duration(days: 4),
        ),
      ];
      final ranked = NewsDesk.rank(
        items,
        const NewsIntent(topic: 'Blue Jays', window: 'w'),
        now: _now,
      );
      expect(ranked.map((s) => s.title), [
        'Blue Jays postponed by rain in Baltimore',
        'Blue Jays near elimination',
      ]);
    });

    test(
      'feeds: national and world for a briefing, sections for a category',
      () {
        final ca = NewsDesk.feedsFor('ca-en', const NewsIntent());
        expect(ca, hasLength(4));
        expect(ca.first.outlet, 'CBC News');
        expect(ca.any((f) => f.outlet == 'BBC News'), isTrue);
        final sports = NewsDesk.feedsFor(
          'ca-en',
          const NewsIntent(category: NewsCategory.sports),
        );
        expect(sports.every((f) => f.section == NewsCategory.sports), isTrue);
        final fr = NewsDesk.feedsFor('fr-fr', const NewsIntent());
        expect(fr.any((f) => f.outlet == 'Le Monde'), isTrue);
      },
    );
  });

  group('NewsFeedParser', () {
    test('RSS with numeric and named zones, CDATA markup and dates', () {
      const rss =
          '''<?xml version="1.0"?><rss version="2.0"><channel><title>CBC</title>
        <item><title>First &amp; foremost</title><link>https://www.cbc.ca/news/a-1.1</link>
          <description><![CDATA[<p>Lede <b>one</b>.</p>]]></description>
          <pubDate>Tue, 22 Sep 2026 18:47:51 -0400</pubDate></item>
        <item><title>Second</title><link>https://www.cbc.ca/news/b-1.2</link>
          <pubDate>Wed, 23 Sep 2026 01:08:40 GMT</pubDate></item>
        <item><title></title><link>https://www.cbc.ca/news/c</link></item>
      </channel></rss>''';
      final items = NewsFeedParser.parse(
        rss,
        now: DateTime.utc(2026, 9, 23, 12),
      );
      expect(items, hasLength(2));
      expect(items.first.title, 'First & foremost');
      expect(items.first.summary, 'Lede one.');
      expect(items.first.published, DateTime.utc(2026, 9, 22, 22, 47, 51));
      expect(items.last.published, DateTime.utc(2026, 9, 23, 1, 8, 40));
    });

    test('Atom entries and a feed stamped hours in the future', () {
      const atom = '''<feed xmlns="http://www.w3.org/2005/Atom">
        <entry><title>Later</title><link rel="alternate" href="https://x.example/later"/>
          <updated>2026-09-23T15:00:00Z</updated><summary>S</summary></entry>
        <entry><title>Earlier</title><link href="https://x.example/earlier"/>
          <updated>2026-09-23T13:00:00Z</updated></entry></feed>''';
      final items = NewsFeedParser.parse(
        atom,
        now: DateTime.utc(2026, 9, 23, 12),
      );
      expect(items.map((i) => i.link), [
        'https://x.example/later',
        'https://x.example/earlier',
      ]);
      // Newest was 3 h ahead: the feed is shifted back, order kept.
      expect(items.first.published, DateTime.utc(2026, 9, 23, 12));
      expect(items.last.published, DateTime.utc(2026, 9, 23, 10));
    });

    test('a feed read like a page becomes readable lines', () async {
      expect(NewsFeedParser.looksLikeFeed('<?xml?><rss><channel>'), isTrue);
      expect(NewsFeedParser.looksLikeFeed('<html><body>'), isFalse);
    });
  });

  group('SourceQuality', () {
    test('outlets, walls, filler and front pages', () {
      expect(
        SourceQuality.outletOf('https://www.cbc.ca/news/x')!.name,
        'CBC News',
      );
      expect(
        SourceQuality.outletOf('https://sports.yahoo.com/a')!.name,
        'Yahoo News',
      );
      expect(
        SourceQuality.unreadable('https://www.reuters.com/world/'),
        isTrue,
      );
      expect(
        SourceQuality.unreadable('https://www.msn.com/en-ca/news/x'),
        isTrue,
      );
      expect(
        SourceQuality.unreadable('https://www.bbc.com/news/articles/c1'),
        isFalse,
      );
      expect(SourceQuality.lowValue('https://canadanewsmedia.ca/'), isTrue);
      expect(SourceQuality.lowValue('https://www.latestcanada.com/'), isTrue);
      expect(
        SourceQuality.lowValue('https://globalnews.ca/news/1/x/'),
        isFalse,
      );
      expect(
        SourceQuality.isFrontPage('https://www.aljazeera.com/news/'),
        isTrue,
      );
      expect(SourceQuality.isFrontPage('https://www.cp24.com/local/'), isTrue);
      expect(
        SourceQuality.isFrontPage(
          'https://www.cbc.ca/news/canada/eby-1.7354572',
        ),
        isFalse,
      );
      expect(SourceQuality.authority('https://en.wikipedia.org/wiki/X'), 1.0);
      expect(
        SourceQuality.authority('https://www.canada.ca/en/services'),
        greaterThan(0.8),
      );
      expect(SourceQuality.tierByName('The Canadian Press'), OutletTier.top);
      expect(SourceQuality.tierByName('CBC'), OutletTier.top);
      expect(SourceQuality.tierByName('Raw Story'), OutletTier.minor);
    });
  });

  group('answers', () {
    test('the shape follows the question', () {
      expect(
        AnswerShapes.of('whatever', news: const NewsIntent()),
        AnswerShape.briefing,
      );
      expect(
        AnswerShapes.of('x', news: const NewsIntent(topic: 'Jays')),
        AnswerShape.topicNews,
      );
      expect(AnswerShapes.of('How do I reset my router?'), AnswerShape.howTo);
      expect(AnswerShapes.of('iPhone 17 vs Pixel 11'), AnswerShape.comparison);
      expect(
        AnswerShapes.of('best budget laptops for students'),
        AnswerShape.list,
      );
      expect(
        AnswerShapes.of('How much is a Tesla Model 3?'),
        AnswerShape.figure,
      );
      expect(AnswerShapes.of('Who is Mark Carney?'), AnswerShape.person);
      expect(
        AnswerShapes.of('Explain quantum tunnelling'),
        AnswerShape.explanation,
      );
      final briefing = AnswerShapes.instructions(AnswerShape.briefing);
      expect(briefing, contains('**bold headline**'));
      expect(briefing, contains('cite its source number'));
      expect(
        briefing,
        isNot(contains('one or two sentences and add detail only')),
      );
    });

    test('a restated answer is detected and trimmed', () {
      const p =
          'The Blue Jays lost 4-3 to the Orioles on Monday and are now 3.5 games behind the last wild-card spot with five games left [1].';
      expect(AnswerCleanup.isRepeating('$p\n\nAnswer: $p'), isTrue);
      expect(AnswerCleanup.dropRepeats('$p\n\n**Answer:** $p'), p);
      const distinct =
          'Carney spoke at the UN about Gaza and pledged new aid for Palestinian institutions [2].';
      expect(AnswerCleanup.isRepeating('$p\n\n$distinct'), isFalse);
      expect(AnswerCleanup.dropRepeats('$p\n\n$distinct'), '$p\n\n$distinct');
    });
  });

  group('follow-ups', () {
    test('detection, pointers and contextual queries', () {
      expect(
        RetrievalPlan.looksLikeFollowUp('tell me more about the second story'),
        isTrue,
      );
      expect(RetrievalPlan.looksLikeFollowUp('why?'), isTrue);
      expect(RetrievalPlan.looksLikeFollowUp('how old is he?'), isTrue);
      expect(
        RetrievalPlan.looksLikeFollowUp('What is the capital of Peru?'),
        isFalse,
      );
      expect(RetrievalPlan.looksLikeFollowUp('why did Rome fall?'), isFalse);
      expect(RetrievalPlan.looksLikeFollowUp('what about sports?'), isTrue);
      expect(
        RetrievalPlan.looksLikeFollowUp(
          'Is it true that Carney called an election?',
        ),
        isFalse,
      );
      expect(RetrievalPlan.referencedItem('more on the second story'), 2);
      expect(RetrievalPlan.referencedItem('what does [4] say'), 4);
      expect(RetrievalPlan.referencedItem('open source 3'), 3);
      expect(RetrievalPlan.referencedItem('the last one please'), -1);
      expect(RetrievalPlan.referencedItem('what is the weather'), isNull);
      expect(
        RetrievalPlan.withContext('how old is he?', 'Who is Mark Carney?'),
        'Mark Carney old',
      );
      expect(
        RetrievalPlan.withContext('What is the capital of Peru?', 'Who is X?'),
        'What is the capital of Peru?',
      );
    });
  });

  group('chat pipeline', () {
    late AppDatabase db;
    late TestEngine engine;
    late ProviderContainer container;
    late TestSearch search;
    late _ArticleReader reader;
    late _FakeDesk desk;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      engine = TestEngine();
      search = TestSearch();
      reader = _ArticleReader();
      desk = _FakeDesk([
        _story(
          'Trump addresses the UN General Assembly',
          'BBC News',
          url: 'https://www.bbc.co.uk/news/articles/c1',
          lede: 'The US president spoke about Iran.',
        ),
        _story(
          'Eby calls October 24 snap election',
          'The Canadian Press',
          url: 'https://www.msn.com/en-ca/news/canada/eby/ar-AA1',
          lede: 'VICTORIA — B.C. goes to the polls.',
        ),
      ]);
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          settingsProvider.overrideWith(_WebSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          duckDuckGoScraperProvider.overrideWithValue(search),
          webPageReaderProvider.overrideWithValue(reader),
          newsDeskProvider.overrideWithValue(desk),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('a news question gets a briefing from the news desk', () async {
      await container
          .read(chatProvider.notifier)
          .send("What's the latest news?");
      expect(desk.intents.single.general, isTrue);
      expect(search.calls, 0, reason: 'no web search for a briefing');
      final prompt = engine.receivedMessages!.last['content'] as String;
      expect(
        prompt,
        contains(
          '[1] BBC News — Trump addresses the UN General Assembly (news story, published',
        ),
      );
      expect(
        prompt,
        anyOf(contains('published today'), contains('published yesterday')),
      );
      expect(prompt, contains('([1] to [2])'));
      expect(
        prompt,
        contains('[2] The Canadian Press — Eby calls October 24 snap election'),
      );
      expect(prompt, contains('**bold headline**'));
      // On the phone the note travels with the stories, not in the system
      // prompt, so the next turn keeps the cached prefix.
      expect(prompt, contains('news stories'));
      expect(prompt, contains('the local time is'));
      final system = engine.receivedMessages!.first['content'] as String;
      expect(system, isNot(contains('news stories')));
      final saved = container.read(chatProvider).messages.last;
      final sources = jsonDecode(saved.sourcesJson) as List;
      expect(sources.first['retrievalStatus'], 'news_story');
      expect(sources.first['outlet'], 'BBC News');
      expect(
        container.read(chatProvider).notice,
        isNot(contains('Web search is off')),
      );
    });

    test(
      '"what about sports?" after a briefing is a sports briefing',
      () async {
        final n = container.read(chatProvider.notifier);
        await n.send("What's the latest news?");
        await n.send('What about sports?');
        expect(desk.intents, hasLength(2));
        expect(desk.intents.last.category, NewsCategory.sports);
        expect(engine.judgeCalls, 0, reason: 'no judge for a news follow-up');
      },
    );

    test('"tell me more about the second story" opens that story', () async {
      final n = container.read(chatProvider.notifier);
      await n.send("What's the latest news?");
      reader.reads.clear();
      await n.send('Tell me more about the second story');
      // Story 2 is a script-only mirror: its headline is searched and the
      // readable result is opened instead.
      expect(search.queries.single, 'Eby calls October 24 snap election');
      expect(reader.reads.single.toString(), 'https://example.com');
      expect(desk.intents, hasLength(1), reason: 'no second briefing');
      final prompt = engine.receivedMessages!.last['content'] as String;
      expect(prompt, contains('Premier David Eby called a snap election'));
      expect(
        prompt,
        contains('Eby calls October 24 snap election (news story'),
      );
    });
  });

  test('a repeated answer is cut short and saved once', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final engine = _RepeatingEngine();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container.read(chatProvider.notifier).send('How did the Jays do?');
    final saved = container.read(chatProvider).messages.last.content;
    // Nothing was searched here, so the "[1]" pointing nowhere goes too.
    expect(saved.trim(), _RepeatingEngine.paragraph.replaceAll(' [1]', ''));
    expect(engine.stopped, isTrue, reason: 'generation stopped at the repeat');
  });
}
