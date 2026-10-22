// Decisions of 2026-10-19: claim
// notice without the source-check model, spoken answer length, how-to
// questions search, stated facts are acknowledged and remembered, and the
// date the sources behind a timely answer were updated.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/chat/domain/about_user.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/chat/domain/source_dates.dart';
import 'package:ondevice_llm/features/memory/domain/memory_statements.dart';
import 'package:ondevice_llm/features/retrieval/claim_check_runner.dart';
import 'package:ondevice_llm/features/retrieval/domain/claim_check.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/voice/conversation_screen.dart';
import 'package:ondevice_llm/l10n/app_localizations_en.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:ondevice_llm/features/chat/domain/answer_checks.dart';

SearchResult _read(
  String url, {
  DateTime? published,
  DateTime? updated,
  bool sponsored = false,
  bool newsItem = false,
}) => SearchResult(
  title: url,
  url: url,
  snippet: '',
  rank: 1,
  pageText: 'Page text.',
  publishedAt: published,
  updatedAt: updated,
  sponsored: sponsored,
  newsItem: newsItem,
);

void main() {
  group('claim notice without the source-check model', () {
    final t = AppLocalizationsEn();

    test('an uncertain sentence alone is not flagged', () {
      expect(
        ClaimCheckRunner.notice([
          const ClaimVerdict(
            'The tower opened in 1889.',
            ClaimStatus.uncertain,
          ),
        ], t),
        isNull,
      );
    });

    test('an uncertain sentence the model read and doubted is flagged', () {
      expect(
        ClaimCheckRunner.notice([
          const ClaimVerdict(
            'The tower opened in 1889.',
            ClaimStatus.uncertain,
            support: 0.4,
          ),
        ], t),
        contains('opened in 1889'),
      );
    });

    test('a sentence saying what the sources lack is not a claim', () {
      for (final s in [
        'The provided sources do not contain information about how many '
            'shots the battery lasts [1].',
        "I couldn't find the battery life in these pages.",
        'Les sources ne précisent pas l’autonomie de la batterie.',
        'Las fuentes no mencionan la duración de la batería.',
      ]) {
        expect(ClaimCheck.sentences(s), isEmpty, reason: s);
      }
      expect(
        ClaimCheck.sentences('The battery lasts about 330 shots per charge.'),
        hasLength(1),
      );
    });

    test('advice and result summaries without figures are not claims', () {
      for (final s in [
        'You should check your preferred retailer (like MobileSyrup or '
            'Wireless Nerds) for exact blue model pricing in your area [1, 3].',
        'The search results indicate that pricing is specific to regions '
            'and carriers.',
        'Vous devriez vérifier le prix chez votre opérateur.',
        'Te recomiendo consultar la tienda de tu operador.',
      ]) {
        expect(ClaimCheck.sentences(s), isEmpty, reason: s);
      }
      expect(
        ClaimCheck.sentences('You can buy it at Bell for 3,265 dollars.'),
        hasLength(1),
        reason: 'a figure keeps the sentence checked',
      );
    });

    test('exclamations and questions without figures are not claims', () {
      for (final s in [
        "Blue is such a fantastic color—it's so calming and vibrant! 💙",
        "Would you like me to look up the retailer's page for the blue model?",
        '¿Quieres que busque el precio del modelo azul en la tienda?',
      ]) {
        expect(ClaimCheck.sentences(s), isEmpty, reason: s);
      }
      expect(
        ClaimCheck.sentences('The Fold8 Ultra costs a whopping 3,265 dollars!'),
        hasLength(1),
      );
      expect(
        ClaimCheck.sentences(
          'Hello! The latest model appears to be the Galaxy Z Fold 8 Ultra.',
        ),
        ['The latest model appears to be the Galaxy Z Fold 8 Ultra.'],
      );
    });

    test('a currency code is a unit, not a name', () {
      expect(
        ClaimCheck.novelDetails('The Fold8 Ultra costs \$3,265 CAD on Bell.', [
          'Bell: the Galaxy Z Fold8 Ultra costs \$3,265 outright.',
        ]),
        isEmpty,
      );
    });

    test('contradicted and unmentioned sentences are still flagged', () {
      for (final status in [
        ClaimStatus.conflicting,
        ClaimStatus.offSource,
        ClaimStatus.novelDetails,
      ]) {
        expect(
          ClaimCheckRunner.notice([ClaimVerdict('It is 400 m.', status)], t),
          isNotNull,
          reason: status.name,
        );
      }
    });
  });

  group('spoken answer length', () {
    const style =
        'Be warm. Answer in one to three short spoken sentences, no lists.';

    test('three or fewer keep the usual instruction', () {
      expect(ConversationScreen.styled(style, 3), style);
      expect(ConversationScreen.styled(style, 2), style);
    });

    test('a longer choice raises the limit and the token room', () {
      expect(
        ConversationScreen.styled(style, 6),
        contains('Answer in at most 6 short spoken sentences, no lists.'),
      );
      expect(
        ConversationScreen.turnSettingsFor(6)['maxTokens'],
        greaterThanOrEqualTo(360),
      );
      expect(
        ConversationScreen.turnSettingsFor(3)['maxTokens'],
        ConversationScreen.maxAnswerTokens,
      );
    });

    test('no limit asks for as much as the question needs', () {
      expect(
        ConversationScreen.styled(style, 0),
        contains('as fully as the question needs'),
      );
      expect(
        ConversationScreen.turnSettingsFor(0)['maxTokens'] as int,
        greaterThan(ConversationScreen.maxAnswerTokens),
      );
    });

    test('the setting defaults to three and survives a round trip', () {
      expect(const InferenceSettings().spokenSentences, 3);
      final s = const InferenceSettings().copyWith(spokenSentences: 6);
      expect(InferenceSettings.fromJson(s.toJson()).spokenSentences, 6);
      expect(
        InferenceSettings.fromJson({
          ...s.toJson(),
          'spokenSentences': 99,
        }).spokenSentences,
        lessThanOrEqualTo(20),
      );
    });
  });

  group('how-to questions search', () {
    test('how-to openers in every language', () {
      for (final q in [
        'How do I make chicken stock?',
        'how to change a bike tire',
        'What are the steps to renew a passport?',
        'Comment faire un bouillon de poulet ?',
        '¿Cómo hago caldo de pollo?',
        'Pasos para cambiar una rueda',
      ]) {
        expect(RetrievalPlan.howTo(q), isTrue, reason: q);
        expect(
          RetrievalPlan.of(q, webEnabled: true).wantsWeb,
          isTrue,
          reason: q,
        );
      }
    });

    test('feelings, words and web search off stay quiet', () {
      for (final q in [
        'How do you feel today?',
        'How do you say thank you in Japanese?',
        'How do you spell necessary?',
        'Write a poem about how to love',
      ]) {
        expect(RetrievalPlan.howTo(q), isFalse, reason: q);
      }
      expect(
        RetrievalPlan.of(
          'How do I make chicken stock?',
          webEnabled: false,
        ).mode,
        RetrievalMode.none,
      );
    });
  });

  group('facts the user states', () {
    for (final (language, facts, requests) in [
      (
        'EN',
        [
          'My name is Ana.',
          'I live in Denver.',
          'I work as a help desk technician.',
        ],
        [
          'I am a developer and I get this error.',
          'My name is Ana and my phone is broken.',
          'My name is Ana and my apps crash.',
          'I live in Denver, write a poem about it.',
          'I am a developer. Help with this bug.',
          'I live in Denver. Why is it so cold?',
        ],
      ),
      (
        'FR',
        ["Je m’appelle Ana.", "J'habite à Lyon."],
        [
          'Je suis développeur et je reçois cette erreur.',
          'Je m’appelle Ana et mon application plante.',
          "J'habite à Lyon, écris un poème sur cette ville.",
          'Je suis développeur, aide-moi à corriger ce problème.',
          "J'habite à Lyon. Pourquoi fait-il froid ?",
        ],
      ),
      (
        'ES',
        ['Me llamo Ana.', 'Vivo en Madrid.'],
        [
          'Soy desarrollador y recibo este error.',
          'Me llamo Ana y mi aplicación no funciona.',
          'Vivo en Madrid, escribe un poema sobre la ciudad.',
          'Soy desarrollador, ayúdame con este problema.',
          'Vivo en Madrid. ¿Por qué hace frío?',
        ],
      ),
    ]) {
      test('$language short facts retain acknowledgement', () {
        for (final input in facts) {
          expect(
            AboutUser.statedNote(input, remembered: true),
            contains('Acknowledge it in one short sentence'),
            reason: input,
          );
        }
      });
      test('$language requests and problems bypass acknowledgement', () {
        for (final input in requests) {
          expect(
            AboutUser.statedNote(input, remembered: true),
            isNull,
            reason: input,
          );
          expect(
            AboutUser.spokenNoted(input, remembered: true),
            isNull,
            reason: input,
          );
          expect(AboutUser.spokenIntro(input), isNull, reason: input);
        }
      });
    }
    test('long factual paragraphs do not force a short acknowledgement', () {
      final input = List.filled(10, 'I live in Denver.').join(' ');
      expect(MemoryStatements.extract(input), isNotEmpty);
      expect(AboutUser.statedNote(input, remembered: true), isNull);
    });

    test('a fact alone gets a spoken acknowledgement', () {
      expect(
        AboutUser.spokenNoted('My favourite colour is blue.', remembered: true),
        allOf(contains('your favourite colour is blue'), contains('remember')),
      );
      expect(
        AboutUser.spokenNoted(
          'My favourite colour is blue.',
          remembered: false,
        ),
        isNot(contains('remember')),
      );
    });

    test('a fact followed by a question goes to the model to answer', () {
      const input = 'My favourite colour is blue. What goes well with it?';
      expect(AboutUser.spokenNoted(input, remembered: true), isNull);
      expect(MemoryStatements.extract(input), isNotEmpty);
      expect(AboutUser.statedNote(input, remembered: true), isNull);
    });

    test('a fact joined to a request by a comma is still a fact', () {
      // The tester's phone chat, 2026-10-19: no acknowledgement came.
      const cases = {
        'My favorite color is blue, and so please look at the price of the '
                'latest samsung galaxy fold in blue color.':
            "The user's favorite color is blue",
        'I live in Denver, so please check the weather.':
            'The user lives in Denver',
        'Ma couleur préférée est le bleu, alors cherche le prix du Fold.':
            "The user's favourite colour is bleu",
        'Mi color favorito es el azul, así que busca el precio del Fold.':
            "The user's favourite colour is azul",
        'Vivo en Madrid, así que busca el tiempo.': 'The user lives in Madrid',
      };
      cases.forEach((input, fact) {
        expect(MemoryStatements.extract(input), [fact], reason: input);
        expect(
          AboutUser.statedNote(input, remembered: true),
          isNull,
          reason: input,
        );
      });
    });

    test('a French or Spanish favourite alone is acknowledged', () {
      expect(
        AboutUser.spokenNoted(
          'Ma couleur préférée est le bleu.',
          remembered: true,
        ),
        'C’est noté, je m’en souviendrai.',
      );
      expect(
        AboutUser.spokenNoted(
          'Mi color favorito es el azul.',
          remembered: true,
        ),
        'Anotado, lo recordaré.',
      );
    });

    test('a question alone has no note', () {
      expect(
        AboutUser.statedNote('What is the capital of Peru?', remembered: true),
        isNull,
      );
      expect(
        AboutUser.spokenNoted('What is the capital of Peru?', remembered: true),
        isNull,
      );
    });
  });

  group('when the sources were updated', () {
    test('cited sources are the ones the answer numbers', () {
      final sources = [
        _read('https://a.example/', published: DateTime.utc(2026, 1, 5)),
        _read('https://b.example/', updated: DateTime.utc(2026, 9, 30)),
      ];
      expect(SourceDates.cited('The price is 499 dollars [1].', sources), [
        sources[0],
      ]);
      expect(SourceDates.cited('The price is 499 dollars.', sources), sources);
      expect(
        SourceDates.newest(sources),
        DateTime.utc(2026, 9, 30),
        reason: 'the last update counts over an older publication',
      );
    });

    test('ads, news stories and instant answers are left out', () {
      final sources = [
        _read('https://ad.example/', sponsored: true),
        _read('https://news.example/', newsItem: true),
        _read('https://duckduckgo.com/?q=weather'),
      ];
      expect(SourceDates.cited('It is sunny [1][2][3].', sources), isEmpty);
    });

    test('an answer that already gives a date is left alone', () {
      expect(SourceDates.dated('As of 2026 it costs 499 dollars.'), isTrue);
      expect(SourceDates.dated('En octobre il coûte 499 dollars.'), isTrue);
      expect(SourceDates.dated('It costs 499 dollars.'), isFalse);
      expect(SourceDates.dated('You may pay 499 dollars.'), isFalse);
    });

    test('a year from a page date is not an unfounded figure', () {
      // The tester's phone chat: "unveiled around July 2026 [1]" got
      // "Not found in the sources: 2026".
      final sources = [
        SearchResult(
          title: 'Galaxy Z Fold 8 unveiled',
          url: 'https://mobilesyrup.example/fold',
          snippet: '',
          rank: 1,
          pageText:
              'Samsung unveiled the Galaxy Z Fold 8 in July at 1,999 dollars.',
          publishedAt: DateTime.utc(2025, 7, 9),
        ),
      ];
      expect(
        AnswerChecks.figureNotice(
          'The Fold 8 costs 1,999 dollars and was unveiled in July 2025 [1].',
          sources,
        ),
        isNull,
      );
      expect(
        AnswerChecks.figureNotice(
          'The Fold 8 costs 2,199 dollars [1].',
          sources,
        ),
        contains('2199'),
      );
      expect(
        AnswerChecks.figureNotice(
          'The Fold 8 costs 1,999 dollars and was unveiled in July 2025 [1].',
          [sources.single.withPage(publishedAt: null)],
        ),
        contains('2025'),
        reason: 'without the page date the year is unfounded',
      );
    });

    test('the date is written out, or as ISO without locale data', () {
      expect(
        SourceDates.format(DateTime(2026, 10, 19, 12), 'xx_NOPE'),
        '2026-10-19',
      );
    });

    test('pages give their last update after their publication', () {
      final page = WebPageReader.extractPage(
        '''<html><head>
        <meta property="article:published_time" content="2026-03-01T09:00:00Z">
        <meta property="article:modified_time" content="2026-10-02T15:00:00Z">
        </head><body><article><p>${'The phone costs 799 dollars. ' * 20}</p></article></body></html>''',
      );
      expect(page.publishedAt, DateTime.utc(2026, 3, 1, 9));
      expect(page.updatedAt, DateTime.utc(2026, 10, 2, 15));

      final ld = WebPageReader.extractPage(
        '''<html><head>
        <script type="application/ld+json">{"datePublished":"2026-03-01T09:00:00Z","dateModified":"2026-02-01T09:00:00Z"}</script>
        </head><body><article><p>${'Plain text. ' * 40}</p></article></body></html>''',
      );
      expect(ld.updatedAt, isNull, reason: 'older than the publication');
    });

    test('a v13 database loses the old page cache table', () async {
      final dir = await Directory.systemTemp.createTemp('v14-migration-');
      final file = File(p.join(dir.path, 'old.sqlite'));
      var db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        await db.customSelect('SELECT 1').get();
        await db.close();
        final old = sqlite3.open(file.path);
        try {
          old.execute(
            'CREATE TABLE web_pages (url TEXT PRIMARY KEY, body TEXT)',
          );
          old.execute('PRAGMA user_version = 13');
        } finally {
          old.close();
        }
        db = AppDatabase.forTesting(NativeDatabase(file));
        final tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name='web_pages'",
            )
            .get();
        expect(tables, isEmpty);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    });
  });
}
