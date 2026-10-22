import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/wikipedia_client.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence.dart';
import 'package:ondevice_llm/features/chat/domain/search_steps.dart';

class _Adapter implements HttpClientAdapter {
  final List<String> bodies;
  final requests = <RequestOptions>[];
  _Adapter(this.bodies);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(bodies.removeAt(0), 200, headers: {});
  }

  @override
  void close({bool force = false}) {}
}

/// The Nikon Z30 article as the extracts API returned it on 2026-10-04,
/// shortened.
const _z30 = {
  'query': {
    'pages': [
      {
        'pageid': 71185514,
        'title': 'Nikon Z30',
        'fullurl': 'https://en.wikipedia.org/wiki/Nikon_Z30',
        'extract':
            'The Z30 is an APS-C mirrorless camera (1.5x APS Crop) announced by Nikon on June 29, 2022. It is the ninth Z-mount camera body and the third APS-C Z-mount body. The camera yields an effective 20.9-megapixel still image and 4K video (up to 30 fps).\n\n\n== Lenses ==\nThe Z30 uses the Nikon Z-mount.\n\n\n== References ==\n\n\n== External links ==\n\nOfficial website',
      },
    ],
  },
};

SearchResult _r(String url, {String? text, int rank = 1}) =>
    SearchResult(title: url, url: url, snippet: '', rank: rank, pageText: text);

void main() {
  group('Wikipedia', () {
    test('the article is the one about the subject, not a neighbour', () {
      expect(
        WikipediaClient.bestTitle('nikon z30 sensor size', [
          'Nikon DX format',
          'Nikon Z30',
        ]),
        'Nikon Z30',
      );
      expect(
        WikipediaClient.bestTitle('nikon z30 sensor size', [
          'Nikon Z50II',
          'Nikon DX format',
        ]),
        isNull,
        reason: 'another model number is a near miss, not an answer',
      );
      expect(
        WikipediaClient.bestTitle('Nikon Z30 weight and battery life', [
          'Nikon Z-mount',
          'Nikon Z30',
        ]),
        'Nikon Z30',
        reason: 'the family article (phone, 2026-10-04) is not the camera',
      );
      expect(
        WikipediaClient.bestTitle('Nikon Z30 weight', ['Nikon Z-mount']),
        isNull,
      );
      expect(
        WikipediaClient.productName('What is the weight of the Nikon Z30?'),
        'Nikon Z30',
      );
      expect(WikipediaClient.productName('Who is Denis Villeneuve'), isNull);
      expect(
        WikipediaClient.bestTitle('Who won the 2022 World Cup', [
          '2022 FIFA World Cup',
        ]),
        '2022 FIFA World Cup',
        reason: 'a year is not a model code',
      );
      expect(
        WikipediaClient.bestTitle('who painted the Mona Lisa', ['Mona Lisa']),
        'Mona Lisa',
      );
      // Wikipedia's search for these, 2026-10-18.
      expect(
        WikipediaClient.bestTitle('What is the capital of Canada?', [
          'Capital punishment in Canada',
          'Ottawa',
          'National Capital Region (Canada)',
        ]),
        isNull,
        reason: 'phone probe round 7: a near-miss article is worse than none',
      );
      expect(
        WikipediaClient.bestTitle('When did the Titanic sink?', [
          'Sinking of the Titanic',
          'Lifeboats of the Titanic',
        ]),
        'Sinking of the Titanic',
      );
      expect(
        WikipediaClient.bestTitle('Where was Marie Curie born?', [
          'Marie Curie',
          'Ève Curie',
        ]),
        'Marie Curie',
      );
      expect(
        WikipediaClient.subjectName('What is the capital of Australia?'),
        'Australia',
      );
      expect(
        WikipediaClient.subjectName('Where was Marie Curie born?'),
        'Marie Curie',
      );
      expect(
        WikipediaClient.subjectName("What is Canada's population?"),
        'Canada',
      );
      expect(WikipediaClient.subjectName('How tall is it?'), isNull);
      expect(
        WikipediaClient.bestTitle('What is the capital of Australia?', [
          'Australia',
          'Australia (continent)',
        ]),
        'Australia',
      );
      expect(
        WikipediaClient.bestTitle('capital Australia', [
          'Australian Capital Territory',
          'Capital punishment in Australia',
        ]),
        isNull,
      );
      expect(
        WikipediaClient.bestTitle('Paris weather', ['Paris (disambiguation)']),
        'Paris (disambiguation)',
        reason: 'disambiguation pages are dropped when the page is read',
      );
    });

    test('references and links are cut, headings kept as lines', () {
      final article = WikipediaClient.parseArticle(_z30, 'en')!;
      expect(article.url, 'https://en.wikipedia.org/wiki/Nikon_Z30');
      expect(article.title, 'Nikon Z30 — Wikipedia');
      expect(article.outlet, 'Wikipedia');
      expect(article.pageText, contains('20.9-megapixel'));
      expect(article.pageText, contains('\nLenses\n'));
      expect(article.pageText, isNot(contains('Official website')));
      expect(article.pageText, isNot(contains('==')));
      expect(article.snippet, startsWith('The Z30 is an APS-C'));
    });

    test('disambiguation and missing pages are not sources', () {
      expect(
        WikipediaClient.parseArticle({
          'query': {
            'pages': [
              {
                'title': 'Mercury',
                'pageprops': {'disambiguation': ''},
                'extract': 'Mercury may refer to: ' * 10,
              },
            ],
          },
        }, 'en'),
        isNull,
      );
      expect(
        WikipediaClient.parseArticle({
          'query': {
            'pages': [
              {'title': 'Nope', 'missing': true},
            ],
          },
        }, 'en'),
        isNull,
      );
    });

    test('the question\'s own language picks the Wikipedia', () {
      expect(
        WikipediaClient.languageFor('quelle est la taille du capteur', 'en'),
        'fr',
      );
      expect(
        WikipediaClient.languageFor('¿cuál es el tamaño del sensor?', 'en'),
        'es',
      );
      expect(
        WikipediaClient.languageFor('what is the sensor size', 'fr'),
        'en',
      );
      expect(WikipediaClient.languageFor('Nikon Z30', 'fr'), 'fr');
      expect(WikipediaClient.languageFor('Nikon Z30', 'de'), 'en');
    });

    test('lookup searches, then reads the chosen article once', () async {
      final adapter = _Adapter([
        jsonEncode({
          'query': {
            'search': [
              {'title': 'Nikon DX format'},
              {'title': 'Nikon Z30'},
            ],
          },
        }),
        jsonEncode(_z30),
      ]);
      final client = WikipediaClient(dio: Dio()..httpClientAdapter = adapter);
      final article = await client.lookup('nikon z30 sensor size');
      expect(article?.url, 'https://en.wikipedia.org/wiki/Nikon_Z30');
      expect(adapter.requests[1].uri.queryParameters['titles'], 'Nikon Z30');
      expect(adapter.requests.first.uri.host, 'en.wikipedia.org');
      // Within the hour the same question costs no request.
      await client.lookup('Nikon Z30 sensor size');
      expect(adapter.requests, hasLength(2));
    });

    test('the article joins after the read pages, once', () {
      final article = WikipediaClient.parseArticle(_z30, 'en')!;
      final sources = [
        _r('https://nikon.com/z30', text: 'specs', rank: 1),
        _r('https://en.m.wikipedia.org/wiki/Nikon_Z30', rank: 2),
        _r('https://dpreview.com/z30', rank: 3),
      ];
      final merged = SearchSteps.withArticle(sources, article);
      expect(merged.map((s) => s.url), [
        'https://nikon.com/z30',
        'https://en.wikipedia.org/wiki/Nikon_Z30',
        'https://dpreview.com/z30',
      ]);
      expect(merged.map((s) => s.rank), [1, 2, 3]);
      final alreadyRead = [
        _r('https://en.wikipedia.org/wiki/Nikon_Z30', text: 'read'),
      ];
      expect(SearchSteps.withArticle(alreadyRead, article), alreadyRead);
    });
  });

  group('search again', () {
    test('missing words are the question words no page mentions', () {
      expect(
        EvidenceRanker.missingWords('Nikon Z30 weight and battery life', [
          'The Nikon Z30 weight is 405 g.',
        ]),
        ['battery', 'life'],
      );
      expect(
        EvidenceRanker.missingWords('Nikon Z30 weight', [
          'Nikon Z30 weight: 405 g',
        ]),
        isEmpty,
      );
    });

    test('the second query is the subject plus what is missing', () {
      expect(
        SearchSteps.searchAgainQuery(
          'Nikon Z30 weight and battery life',
          ['battery', 'life'],
          subject: ['Nikon Z30'],
        ),
        'Nikon Z30 battery life',
      );
      expect(
        SearchSteps.searchAgainQuery(
          'Nikon Z30 battery',
          ['nikon', 'z30', 'battery'],
          subject: ['Nikon Z30'],
        ),
        isNull,
        reason: 'nothing answered: the pages were off-topic',
      );
      expect(
        SearchSteps.searchAgainQuery('why is the sky blue', ['blue']),
        isNull,
        reason: 'no subject names to anchor a narrower query',
      );
    });

    test('extra pages go after the read ones and before the unread', () {
      final merged = SearchSteps.withExtraPages(
        [_r('https://a.com', text: 'a'), _r('https://b.com')],
        [_r('https://c.com', text: 'c')],
      );
      expect(merged.map((s) => s.url), [
        'https://a.com',
        'https://c.com',
        'https://b.com',
      ]);
      expect(merged.map((s) => s.rank), [1, 2, 3]);
    });
  });
}
