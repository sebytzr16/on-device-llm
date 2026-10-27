// German beyond the UI strings: the wording the app reads itself (search
// gate, news, dates, sums, phone actions, memory, voice), 2026-10-27.
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/instant_answers.dart';
import 'package:ondevice_llm/data/network/web_search/wikipedia_client.dart';
import 'package:ondevice_llm/features/chat/domain/about_user.dart';
import 'package:ondevice_llm/features/chat/domain/math_question.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/memory/domain/memory_statements.dart';
import 'package:ondevice_llm/features/retrieval/domain/date_check.dart';
import 'package:ondevice_llm/features/retrieval/domain/life_dates.dart';
import 'package:ondevice_llm/features/retrieval/domain/news_intent.dart';
import 'package:ondevice_llm/features/retrieval/domain/subject_terms.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_pipeline.dart';

void main() {
  test('a German question is answered in German', () {
    expect(
      WikipediaClient.languageFor('Wie hoch ist der Eiffelturm?', 'en'),
      'de',
    );
    expect(WikipediaClient.languageNames['de'], 'German');
    expect(WikipediaClient.languageFor('Die Hard', 'en'), 'en');
  });

  test('the search gate reads German', () {
    bool web(String q) => RetrievalPlan.of(q, webEnabled: true).wantsWeb;
    expect(web('Wie wird das Wetter morgen in Berlin?'), isTrue);
    expect(web('Hat der Rewe am Sonntag offen?'), isTrue);
    expect(web('Wie mache ich eine Hühnerbrühe?'), isTrue);
    expect(web('Hallo, wie geht es dir?'), isFalse);
    expect(web('Schreib ein Gedicht über den Herbst'), isFalse);
    expect(web('Erkläre die Photosynthese'), isFalse);
    expect(RetrievalPlan.smallTalk('Danke schön'), isTrue);
    expect(RetrievalPlan.encyclopedic('Wer war Marie Curie?'), isTrue);
    // German words that are English words too change nothing in English.
    expect(web('Name some fruits such as apples'), isFalse);
    expect(RetrievalPlan.keywords('When did the war end'), contains('war'));
  });

  test('weather questions name their place', () {
    expect(
      InstantAnswers.weatherPlace('Wie wird das Wetter morgen in Berlin?'),
      'Berlin',
    );
    expect(InstantAnswers.weatherPlace('Wetter Hamburg'), 'Hamburg');
  });

  test('German news requests, places and regions', () {
    final intent = NewsIntent.of('Nachrichten aus Deutschland heute')!;
    expect(intent.place, 'de-de');
    expect(
      NewsIntent.of('Schreib einen Nachrichtenartikel über eine Katze'),
      isNull,
    );
    expect(NewsIntent.of('Was gibt es Neues zur Bundesliga?'), isNotNull);
    expect(DuckDuckGoScraper.regionFor('de', localeName: 'en_US'), 'de-de');
    expect(DuckDuckGoScraper.regionFor('de', localeName: 'de_AT'), 'at-de');
    expect(DuckDuckGoScraper.regionFor('', localeName: 'de_CH'), 'ch-de');
  });

  test('German dates are read', () {
    expect(DateCheck.fullDates('Die Wahl ist am 3. März 2043.'), [
      DateTime(2043, 3, 3),
    ]);
    expect(DateCheck.fullDates('Termin: 01.10.2031'), [DateTime(2031, 10, 1)]);
    expect(
      LifeDates.birthDates('Helene Fischer (* 5. August 1984 in Krasnojarsk)'),
      [DateTime(1984, 8, 5)],
    );
    expect(LifeDates.birthDates('geboren am 01.03.1994 in Köln'), [
      DateTime(1994, 3, 1),
    ]);
    expect(LifeDates.asksAge('Wie alt ist Helene Fischer?'), isTrue);
  });

  test('a lone German noun is not a name to stay on', () {
    final terms = SubjectTerms.of(
      'Vergleiche die drei beliebtesten Elektroautos für eine Familie',
    ).terms;
    expect(terms, isNot(contains('Elektroautos')));
    expect(
      SubjectTerms.of('Wie schwer ist die Sony ZV-E10?').terms,
      contains('Sony ZV-E10'),
    );
  });

  test('German sums are worked out and spoken with a decimal comma', () {
    expect(
      MathQuestion.note('Was ist siebenundzwanzig mal drei?'),
      contains('= 81'),
    );
    expect(MathQuestion.note('Wie viel ist 2,5 mal 4?'), contains('= 10'));
    expect(
      MathQuestion.note('Was ist 1.000 geteilt durch 8?'),
      contains('= 125'),
    );
    expect(
      MathQuestion.spoken('Was ist 7 geteilt durch 2?'),
      '7 geteilt durch 2 ist 3,5.',
    );
    expect(MathQuestion.note('Wie hoch ist der Eiffelturm?'), isNull);
  });

  test('German phone actions', () {
    expect(PhoneActions.plainTimer('Stell einen Timer auf 5 Minuten'), {
      'minutes': 5,
    });
    expect(PhoneActions.plainTimer('Timer für zwei Stunden'), {'minutes': 120});
    expect(PhoneActions.plainTimer('Timer für 30 Sekunden'), {'seconds': 30});
    expect(PhoneActions.command('Weck mich morgen um 7 Uhr'), isTrue);
    expect(
      PhoneActions.command('Erinnere mich morgen an den Zahnarzt'),
      isTrue,
    );
    expect(PhoneActions.wanted('Erinnere mich, wie ich heiße'), isFalse);
    expect(PhoneActions.command('Wie stelle ich einen Wecker?'), isFalse);
    expect(PhoneActions.wanted('Was ist der beste Wecker?'), isFalse);
  });

  test('German introductions and questions about the user', () {
    expect(
      AboutUser.spokenName('Wie heiße ich?', ['Ich heiße Robin.']),
      'Du heißt Robin.',
    );
    expect(
      AboutUser.spokenIntro('Hallo, ich heiße Lea.'),
      'Hallo Lea! Wie kann ich dir helfen?',
    );
    expect(
      AboutUser.spokenGreeting('Hallo, wie geht’s?'),
      startsWith('Mir geht'),
    );
    expect(AboutUser.spokenGreeting('Danke schön!'), 'Gern geschehen!');
    expect(
      AboutUser.spokenAbilities('Was kannst du?', web: true),
      startsWith('Ich kann'),
    );
    expect(AboutUser.asks('Wie heiße ich?'), isTrue);
  });

  test('German statements are remembered', () {
    expect(MemoryStatements.extract('Ich wohne in Berlin.'), [
      'The user lives in Berlin',
    ]);
    expect(MemoryStatements.extract('Ich heiße Anna.'), [
      "The user's name is Anna",
    ]);
    expect(MemoryStatements.extract('Meine Lieblingsfarbe ist Grün.'), [
      "The user's favourite colour is Grün",
    ]);
    expect(MemoryStatements.extract('Ich bin heute müde.'), isEmpty);
    expect(
      MemoryStatements.extract('Ich wohne nicht mehr in Berlin.'),
      isEmpty,
    );
  });

  test('German speech: its own voice, no pause inside dates', () {
    expect(voiceLanguage('de'), 'de');
    expect(VoiceModels.packsFor('de'), contains(VoiceModels.german));
    expect(VoiceModels.packsFor('fr'), contains(VoiceModels.speaking));
    expect(KokoroVoice.forLanguage('de').piper, isTrue);
    expect(
      KokoroSpeaker.sentences(
        'Am 3. Oktober ist Feiertag. Dann geht es weiter.',
      ),
      ['Am 3. Oktober ist Feiertag.', 'Dann geht es weiter.'],
    );
    expect(
      KokoroSpeaker.sentences('Zum Beispiel z. B. Berlin. Ende.'),
      hasLength(2),
    );
  });
}
