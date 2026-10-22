// The rules the 2026-10-20 audit found too broad: each made everyday
// answers worse on the phone and on remote models.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/wikipedia_client.dart';
import 'package:ondevice_llm/features/chat/domain/about_user.dart';
import 'package:ondevice_llm/features/chat/domain/answer_cleanup.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/features/chat/domain/answer_checks.dart';

void main() {
  test('one foreign word does not switch the answer language', () {
    String lang(String q) => WikipediaClient.languageFor(q, 'en');
    expect(lang('Explain le Chatelier principle'), 'en');
    expect(lang('Tell me about Elle magazine'), 'en');
    expect(lang('Who wrote Les Misérables?'), 'en');
    expect(lang('Fix this: `el.style.color = red; ce = 3`'), 'en');
    expect(lang('Quelle est la capitale du Canada ?'), 'fr');
    expect(lang("Qu'est-ce que la photosynthèse"), 'fr');
    expect(lang('¿Cuál es la capital de España?'), 'es');
    // The app's own language needs one word.
    expect(WikipediaClient.languageFor('Les chats', 'fr'), 'fr');
  });

  test('the Wikipedia pre-check is for facts about a named subject', () {
    bool check(String q) =>
        AnswerChecks.wikipediaFactCheck(q, webOn: true, remote: false);
    for (final q in [
      'What is the capital of Australia?',
      'How tall is the Eiffel Tower?',
      'Who wrote Les Misérables?',
    ]) {
      expect(check(q), isTrue, reason: q);
    }
    for (final q in [
      'What are some good books to read?',
      'What is the best way to learn guitar?',
      'What is the best way to learn Python?',
      'What is the difference between a list and a tuple in Python?',
      'What is a closure in JavaScript?',
      'What is your favorite movie?',
      'What is photosynthesis?',
      'What are the benefits of meditation?',
      'Who are you?',
      'What is love?',
    ]) {
      expect(check(q), isFalse, reason: q);
    }
  });

  test('a request that states a fact is not a question about the user', () {
    for (final q in [
      'My name is Robin, can you help me write a cover letter?',
      'I have two cats. What food is best for them?',
      'Write a short bio: my name is Ana and my job is nursing.',
    ]) {
      expect(AboutUser.asks(q), isFalse, reason: q);
    }
    for (final q in [
      "What's my name?",
      'Can you tell me my name?',
      'Do you remember where I live?',
      'I told you before. What are my cats called?',
    ]) {
      expect(AboutUser.asks(q), isTrue, reason: q);
    }
  });

  test('a typed answer keeps sentences that only sound like narration', () {
    for (final a in [
      'The provided sources do not give the 2027 price. The current price '
          'is \$499 [1].',
      'When the user asks for a refund, the handler checks the order. Then '
          'it returns 200.',
      "I'll use a dictionary to count the words:\n\n```python\ncounts = {}\n```",
      'To solve it, I will use the quadratic formula.',
    ]) {
      expect(AnswerCleanup.dropNarration(a, sentences: false), a, reason: a);
    }
    // Over sources the honest gap is kept too.
    const gap =
        'The provided sources do not give the 2027 price. The current '
        'price is \$499 [1].';
    expect(AnswerCleanup.dropNarration(gap), gap);
    // A narrating line is still dropped, outside code.
    expect(
      AnswerCleanup.dropNarration(
        'He is 32.\nThe user asked for his age, so I should answer briefly.',
        sentences: false,
      ),
      'He is 32.',
    );
    const code =
        'Here it is:\n```\n# The user asks for a name\nname = input()\n```';
    expect(AnswerCleanup.dropNarration(code), code);
  });

  test('"keep it" is narration only about the answer', () {
    expect(
      AnswerCleanup.isNarrating(
        'We need to keep it under 5 V.\nWe need to keep it cool too.',
      ),
      isFalse,
    );
    expect(
      AnswerCleanup.isNarrating('Sunny, 20 °C [1].\nI should keep it short'),
      isTrue,
    );
  });

  test('a remark about the user\'s day or an opinion ask does not search', () {
    expect(RetrievalPlan.timeSensitive("I'm tired today"), isFalse);
    expect(RetrievalPlan.timeSensitive('I feel great today'), isFalse);
    expect(RetrievalPlan.timeSensitive("What's the weather today?"), isTrue);
    expect(
      RetrievalPlan.timeSensitive("I'm in Paris today, what's the weather?"),
      isTrue,
    );
    expect(RetrievalPlan.howTo('How would you rate this essay?'), isFalse);
    expect(
      RetrievalPlan.howTo('How should I tell my boss I am quitting?'),
      isFalse,
    );
    expect(RetrievalPlan.howTo('How do I reverse a list in Python?'), isTrue);
  });

  test('a busy provider is asked again, at most twice', () {
    Headers h(String? after) => Headers.fromMap({
      if (after != null) 'retry-after': [after],
    });
    expect(
      RemoteEngine.retryDelay(429, h(null), 0),
      const Duration(seconds: 5),
    );
    expect(
      RemoteEngine.retryDelay(429, h(null), 1),
      const Duration(seconds: 12),
    );
    expect(RemoteEngine.retryDelay(429, h(null), 2), isNull);
    expect(
      RemoteEngine.retryDelay(503, h(null), 0),
      const Duration(seconds: 2),
    );
    expect(RemoteEngine.retryDelay(429, h('7'), 0), const Duration(seconds: 7));
    expect(RemoteEngine.retryDelay(429, h('90'), 0), isNull);
    expect(RemoteEngine.retryDelay(400, h(null), 0), isNull);
    expect(RemoteEngine.retryDelay(401, h(null), 0), isNull);
    expect(RemoteEngine.retryDelay(null, null, 0), isNull);
  });
}
