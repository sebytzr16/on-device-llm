import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/about_user.dart';
import 'package:ondevice_llm/features/chat/domain/answer_cleanup.dart';
import 'package:ondevice_llm/features/memory/domain/memory_statements.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:ondevice_llm/data/network/web_search/instant_answers.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';

/// Odd answers read from the October 20 phone sweep and the audit of the
/// handoff work.
void main() {
  test('an aside is not part of a remembered value', () {
    for (final input in [
      'My favourite colour is green, by the way.',
      'By the way, my favourite colour is green.',
      'My favourite colour is green, btw.',
    ]) {
      expect(MemoryStatements.extract(input), [
        "The user's favourite colour is green",
      ], reason: input);
    }
    expect(MemoryStatements.extract('Btw I live in Denver.'), [
      'The user lives in Denver',
    ]);
    expect(
      AboutUser.spokenNoted(
        'My favourite colour is green, by the way.',
        remembered: false,
      ),
      'Got it: your favourite colour is green.',
    );
  });

  test('a French or Spanish aside keeps the reply in that language', () {
    expect(
      AboutUser.spokenNoted(
        'Au fait, ma couleur préférée est le vert.',
        remembered: true,
      ),
      'C’est noté, je m’en souviendrai.',
    );
    expect(
      AboutUser.spokenNoted(
        'Por cierto, mi color favorito es el verde.',
        remembered: false,
      ),
      'Anotado.',
    );
  });

  test('named pets after a comma are a fact; anything else is not', () {
    expect(
      AboutUser.spokenNoted(
        'I have two cats, Milo and Luna.',
        remembered: true,
      ),
      'Got it: you have two cats, Milo and Luna. I’ll remember that.',
    );
    for (final input in [
      'I have two cats, and they fight.',
      'I have two cats, both very old.',
    ]) {
      expect(
        MemoryStatements.extract(input).where((f) => f.contains(',')),
        isEmpty,
        reason: input,
      );
    }
  });

  test('what the user does is not a request, a plant is not a crash', () {
    expect(
      AboutUser.spokenIntro('Hi, my name is Sam and I fix cars.'),
      'Nice to meet you, Sam. How can I help?',
    );
    expect(
      AboutUser.spokenIntro('Je m’appelle Léa et ma plante est verte.'),
      'Bonjour Léa ! Que puis-je faire pour toi ?',
    );
    // Still a crash report and still a request.
    expect(
      AboutUser.spokenIntro('Je m’appelle Ana et mon application plante.'),
      isNull,
    );
    expect(AboutUser.spokenIntro('My name is Sam, fix my code.'), isNull);
    expect(AboutUser.spokenIntro('My name is Sam. Can you fix it'), isNull);
  });

  test('retrieval narration and "the source for this" are dropped', () {
    expect(
      AnswerCleanup.dropNarration(
        'The capital of Canada is Ottawa. [1]\nThis is stated directly in '
        'the Wikipedia article for Canada which was retrieved today at 22:32 '
        'UTC-04:00 (Tuesday).',
      ),
      'The capital of Canada is Ottawa. [1]',
    );
    expect(
      AnswerCleanup.dropNarration(
        'Justin Bieber was born on March 1, 1994 [1]. He is 32. The source '
        'for this age calculation is https://en.wikipedia.org/wiki/'
        'Justin_Bieber [2].',
      ),
      'Justin Bieber was born on March 1, 1994 [1]. He is 32.',
    );
    // A page's own time stays when it is the answer.
    expect(
      AnswerCleanup.dropNarration('The store opens at 9:30 [1].'),
      'The store opens at 9:30 [1].',
    );
  });
  test('a call cut off inside its arguments is repaired, not fatal', () {
    // "Set a timer for five minutes." on the phone (second sweep): the
    // arguments ended inside a string and the next round failed to render.
    const cut = ToolCall(
      id: '1',
      name: 'set_timer',
      arguments: '{"minutes": 5, "label": "five min',
    );
    expect(cut.args, {'minutes': 5, 'label': 'five min'});
    expect(jsonDecode(cut.jsonArguments), {'minutes': 5, 'label': 'five min'});
    const open = ToolCall(
      id: '2',
      name: 'set_timer',
      arguments: '{"minutes": 5, "label": "',
    );
    expect(open.args, {'minutes': 5, 'label': ''});
    const junk = ToolCall(
      id: '3',
      name: 'set_timer',
      arguments: 'five minutes',
    );
    expect(junk.jsonArguments, '{}');
    const fine = ToolCall(
      id: '4',
      name: 'set_timer',
      arguments: '{"minutes":5}',
    );
    expect(fine.jsonArguments, '{"minutes":5}');
  });

  test('more retrieval narration from the second phone sweep', () {
    for (final narration in [
      "This is found in Wikipedia as the country's capital [1].",
      'The source is Wikipedia [1].',
      'You can find this specific data point in the extracted section.',
      'I found a recipe in the extracted section of the page.',
      'You can find this information in [1].',
    ]) {
      expect(
        AnswerCleanup.dropNarration(
          'The capital of Australia is Canberra [1]. $narration',
        ),
        'The capital of Australia is Canberra [1].',
        reason: narration,
      );
    }
    // The answer behind "the text states that" stays.
    expect(
      AnswerCleanup.dropNarration(
        "The text states that Canberra is the nation's capital [1].",
      ),
      "Canberra is the nation's capital [1].",
    );
    // Ordinary answers keep their words.
    for (final kept in [
      'The source of the Nile is Lake Victoria.',
      'You can find the Louvre in Paris.',
      'The text of the treaty was signed in 1648.',
      'It is found in tropical forests across South America.',
    ]) {
      expect(AnswerCleanup.dropNarration(kept), kept);
    }
  });

  test("the phone's own time is not another city's", () {
    expect(
      AnswerCleanup.dropNarration(
        'The local time in Rome today is 23:44 (UTC-04:00). The weather in '
        'Rome is rainy with a high of 21 °C [1].',
      ),
      'The weather in Rome is rainy with a high of 21 °C [1].',
    );
  });

  // The LM Studio run of the remote probes (2026-10-21).
  test('a timer the model labelled "None" has no label', () {
    const timer = PhoneAction('set_timer', {'label': 'None', 'minutes': 5});
    expect(timer.title, '');
    expect(timer.toPlatform()['label'], '');
    for (final empty in ['null', 'N/A', ' none ']) {
      expect(PhoneAction('set_timer', {'label': empty}).title, '');
    }
    expect(const PhoneAction('set_timer', {'label': 'Pasta'}).title, 'Pasta');
  });

  test('a weather follow-up is still about the weather', () {
    const asked = 'What is the weather like in Rome today?';
    expect(InstantAnswers.isWeather(asked), isTrue);
    expect(
      InstantAnswers.isWeather(
        RetrievalPlan.withContext('And what about tomorrow?', asked),
      ),
      isTrue,
    );
    expect(
      InstantAnswers.isWeather('How much is a Nintendo Switch 2?'),
      isFalse,
    );
  });

  test('"based on the search results" is not part of the answer', () {
    for (final (input, want) in [
      (
        'Based on the search results, Justin Bieber is thirty-two years old [1].',
        'Justin Bieber is thirty-two years old [1].',
      ),
      (
        'He was born in 1994. According to the sources, he lives in Los Angeles.',
        'He was born in 1994. He lives in Los Angeles.',
      ),
    ]) {
      expect(AnswerCleanup.dropNarration(input), want, reason: input);
    }
    for (final kept in [
      'Based on the results of the 2021 census, Ottawa grew.',
      'According to the sources [1], the price rose.',
      'According to Reuters, the talks ended.',
    ]) {
      expect(AnswerCleanup.dropNarration(kept), kept);
    }
  });
}
