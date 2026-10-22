import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';

void main() {
  group('tools are offered only when a message may need them', () {
    test('nothing to look up or work out', () {
      for (final s in [
        'hi',
        'thanks a lot',
        'Give me three tips for better sleep.',
        'Give me three tips. Keep them short.',
        'what is a good way to fall asleep faster?',
        "Explain recursion like I'm five.",
        'Rewrite this more politely: send me the file.',
        'Traduis en anglais : je suis fatigué.',
        '¿Cómo puedo dormir mejor?',
      ]) {
        expect(RetrievalPlan.mayNeedTools(s), isFalse, reason: s);
      }
    });

    test('a link, timely wording, a name, a model number or a sum', () {
      for (final s in [
        'Summarize https://example.com/article',
        'Is it going to rain today?',
        'search the web for sourdough tips',
        'Compare the Nikon and the Sony for vlogging.',
        'compare the z30 and the zv-e10',
        'What happened in 1969?',
        'Tell me about Rome.',
        'What is six times seven?',
        'What is 15% of 240?',
        'Combien font cinq fois sept ?',
        '¿Cuánto es seis por siete?',
      ]) {
        expect(RetrievalPlan.mayNeedTools(s), isTrue, reason: s);
      }
    });

    test('with a document collection, any real request may be about it', () {
      const q = 'What does my contract say about notice?';
      expect(RetrievalPlan.mayNeedTools(q), isFalse);
      expect(RetrievalPlan.mayNeedTools(q, documents: true), isTrue);
      expect(RetrievalPlan.mayNeedTools('thanks', documents: true), isFalse);
    });
  });

  test('small talk never reaches the web judge', () {
    for (final s in [
      'hi',
      'Hello!',
      'thanks a lot',
      'ok',
      'bonjour',
      'good night',
      // As a speech recognizer writes them (voice conversation mode).
      'Hi?',
      'Hi there!',
      'Hey, how are you doing?',
      "Hello, how's it going?",
      'hi how are you today',
      'Hi! How are you today?',
      'Hi there. How are you doing tonight?',
      'Hey, how was your day?',
      'Good evening, how have you been?',
      'Bonsoir, ça va ce soir ?',
      'Hola, ¿cómo estás hoy?',
      'Good morning everyone.',
      'Bonjour, comment ça va ?',
      'Salut, ça va ?',
      'Hola, ¿cómo estás?',
      '¿Qué tal?',
    ]) {
      expect(RetrievalPlan.smallTalk(s), isTrue, reason: s);
      expect(RetrievalPlan.greetingOnly(s), isTrue, reason: s);
      // "today" in a greeting is not news to look up (phone probe).
      expect(
        RetrievalPlan.of(s, webEnabled: true).wantsWeb,
        isFalse,
        reason: s,
      );
    }
    for (final s in [
      'hi, what is the weather?',
      'hello, who won in 2024',
      'hi, is it going to rain today?',
      'Hey, how are the Leafs doing?',
      'Bonjour, quel temps fait-il ?',
      'Hola, ¿qué tiempo hace hoy?',
      'summarise https://example.com',
      'tell me about the Rust borrow checker',
      'python version',
      'recommend restaurants',
    ]) {
      expect(RetrievalPlan.smallTalk(s), isFalse, reason: s);
    }
    expect(RetrievalPlan.smallTalk('bitcoin'), isTrue);
  });

  test('Always mode skips greetings but searches a lone topic', () {
    RetrievalPlan alwaysPlan(String input) => RetrievalPlan.of(
      input,
      webEnabled: true,
      always: !RetrievalPlan.greetingOnly(input),
    );

    expect(alwaysPlan('bitcoin').mode, RetrievalMode.search);
    expect(alwaysPlan('thanks').mode, RetrievalMode.none);
    expect(
      RetrievalPlan.smallTalk('bitcoin'),
      isTrue,
      reason: 'Auto unchanged',
    );
  });

  test(
    'local tasks skip the web judge; anything timely or linked does not',
    () {
      for (final s in [
        'Write a haiku about rain',
        'please translate this to French: bonjour tout le monde',
        'Refactor this function to be async',
        'Fix this:\n```dart\nvoid main() {}\n```',
        'x ' * 400,
      ]) {
        expect(RetrievalPlan.localTask(s), isTrue, reason: s);
      }
      for (final s in [
        'Write about the latest Flutter release',
        'explain https://example.com/post',
        'summarize the news today',
        'search for a good pasta recipe',
        'What is the capital of Peru?',
      ]) {
        expect(RetrievalPlan.localTask(s), isFalse, reason: s);
      }
    },
  );

  test('keywords: the bare content words of a question', () {
    expect(
      RetrievalPlan.keywords('What is the default TCP port for PostgreSQL?'),
      'default TCP port PostgreSQL',
    );
    expect(
      RetrievalPlan.keywords(
        'please search for the latest stable version of the Flutter SDK',
      ),
      'latest stable version Flutter SDK',
    );
    expect(RetrievalPlan.keywords('hi'), 'hi');
    expect(
      RetrievalPlan.keywords('summarise https://example.com/post for me'),
      'summarise',
    );
  });

  test('timely search windows distinguish news-like wording', () {
    expect(RetrievalPlan.searchDateFilter('latest Flutter release'), 'y');
    expect(RetrievalPlan.searchDateFilter('Flutter news today'), 'm');
    expect(RetrievalPlan.searchDateFilter('changes this week'), 'm');
    expect(RetrievalPlan.searchDateFilter('explain Flutter widgets'), isNull);
  });

  test('pasted URLs are read directly, without a timeliness keyword', () {
    final p = RetrievalPlan.of(
      'Summarize https://example.com/a-story. And https://example.com/b?x=1, thanks',
      webEnabled: true,
    );
    expect(p.mode, RetrievalMode.readUrls);
    expect(p.urls.map((u) => u.toString()), [
      'https://example.com/a-story',
      'https://example.com/b?x=1',
    ]);
    expect(p.query, 'Summarize And thanks');
  });

  test('explicit search request works without a timeliness keyword', () {
    expect(
      RetrievalPlan.of(
        'search the web for Vulkan on Android',
        webEnabled: true,
      ).mode,
      RetrievalMode.search,
    );
    expect(
      RetrievalPlan.of(
        'look up how tall the Eiffel tower is',
        webEnabled: true,
      ).mode,
      RetrievalMode.search,
    );
  });

  test('timeliness keywords still trigger discovery', () {
    final p = RetrievalPlan.of(
      "what's the weather in Toronto",
      webEnabled: true,
    );
    expect(p.mode, RetrievalMode.search);
    expect(p.query, "what's the weather in Toronto");
  });

  test('ordinary questions stay local', () {
    final p = RetrievalPlan.of('explain recursion', webEnabled: true);
    expect(p.mode, RetrievalMode.none);
    expect(p.wantsWeb, false);
  });

  test('web off never retrieves but still reports the wish', () {
    final p = RetrievalPlan.of('latest news on llama.cpp', webEnabled: false);
    expect(p.mode, RetrievalMode.none);
    expect(p.wantsWeb, true);
  });

  test('duplicates, junk and more than three URLs are bounded', () {
    final p = RetrievalPlan.of(
      'http://a.com http://a.com http://b.com http://c.com http://d.com https://',
      webEnabled: true,
    );
    expect(p.urls.length, 3);
    expect(p.urls.map((u) => u.host), ['a.com', 'b.com', 'c.com']);
  });

  test('always mode researches ordinary questions too', () {
    final p = RetrievalPlan.of(
      'explain recursion',
      webEnabled: true,
      always: true,
    );
    expect(p.mode, RetrievalMode.search);
    expect(p.query, 'explain recursion');
    expect(
      RetrievalPlan.of(
        'explain recursion',
        webEnabled: false,
        always: true,
      ).mode,
      RetrievalMode.none,
    );
  });

  test('everyday phrasings for going online trigger discovery in auto', () {
    for (final q in [
      'can you look for the new Pixel phone online?',
      'find out who won the match',
      'check on the internet what the Adreno 830 supports',
      'what happened in 2026 with llama.cpp',
      'research the best budget phone',
    ]) {
      expect(
        RetrievalPlan.of(q, webEnabled: true).mode,
        RetrievalMode.search,
        reason: q,
      );
    }
    expect(
      RetrievalPlan.of('write a haiku about rain', webEnabled: true).mode,
      RetrievalMode.none,
    );
  });

  group('follow-ups keep the subject (phone report 2026-10-04)', () {
    test('back references and short comparisons are follow-ups', () {
      for (final q in [
        'What is its price in Canada?',
        'which one is cheaper?',
        'and the battery life?',
        'how heavy are they?',
      ]) {
        expect(RetrievalPlan.looksLikeFollowUp(q), isTrue, reason: q);
      }
      for (final q in [
        'Is Python better than Java?',
        'What is the tallest building in Toronto?',
      ]) {
        expect(RetrievalPlan.looksLikeFollowUp(q), isFalse, reason: q);
      }
    });

    test('a chain of follow-ups still names the first subject', () {
      final topic = RetrievalPlan.conversationTopic([
        'Compare the Nikon Z30 to the Sony ZV-E10',
        'what about their price?',
      ]);
      final query = RetrievalPlan.withContext('and the battery life?', topic);
      expect(query, contains('Z30'));
      expect(query, contains('battery'));
    });

    test('a fresh question ends the chain', () {
      expect(
        RetrievalPlan.conversationTopic([
          'Compare the Nikon Z30 to the Sony ZV-E10',
          'What is the tallest building in Toronto?',
        ]),
        'What is the tallest building in Toronto?',
      );
    });
  });

  test('a named product with a specification is searched in Auto', () {
    for (final q in [
      'Nikon Z30 weight and battery life',
      'iPhone 17 screen size',
      'Galaxy S25 price in Canada',
      'qwen3.5 parameters',
      'poids du Nikon Z30',
      'autonomie de la batterie du Pixel 9',
      'precio del Galaxy S25',
    ]) {
      expect(RetrievalPlan.of(q, webEnabled: true).wantsWeb, isTrue, reason: q);
    }
    for (final q in [
      'what is the weight of 2 liters of water',
      'write a product description for the Nikon Z30 with its weight',
      'explain how battery capacity works',
      'my Z30 is heavy',
    ]) {
      expect(
        RetrievalPlan.of(q, webEnabled: true).wantsWeb,
        isFalse,
        reason: q,
      );
    }
  });

  test('factual questions an offline encyclopedia answers', () {
    for (final q in [
      'Who was Marie Curie?',
      'How tall is the Eiffel Tower?',
      'What is the capital of Australia?',
      'When was the Berlin Wall built?',
      'Qui était Victor Hugo ?',
      "Qu'est-ce que la photosynthèse ?",
      '¿Cuándo nació Frida Kahlo?',
      '¿Dónde está Machu Picchu?',
    ]) {
      expect(RetrievalPlan.encyclopedic(q), isTrue, reason: q);
    }
    for (final q in [
      'Hi! How are you today?',
      'Write a poem about Paris',
      'Remind me tomorrow at 9 to call the dentist',
      'Remind me what my name is',
      'Can you fix this code?',
      'thanks',
    ]) {
      expect(RetrievalPlan.encyclopedic(q), isFalse, reason: q);
    }
  });

  group('questions about the assistant itself are not searched', () {
    const self = [
      'Are you able to do online searches?',
      'Uh, are you able to do online searches?',
      'Can you search the web?',
      'Can you browse the internet?',
      'Do you have internet access?',
      'Are you connected to the internet?',
      'Can you look things up online?',
      'Do you know how to google?',
      'Peux-tu faire des recherches sur internet ?',
      'Est-ce que tu as accès à internet ?',
      '¿Puedes buscar en internet?',
      '¿Tienes acceso a internet?',
    ];
    test('recognised, with no search and no tools', () {
      for (final q in self) {
        expect(RetrievalPlan.aboutAssistant(q), isTrue, reason: q);
        expect(RetrievalPlan.mayNeedTools(q), isFalse, reason: q);
      }
    });
    test('a request with a subject still searches', () {
      for (final q in [
        'Can you search the web for the weather in Rome?',
        'Can you look up the latest Pixel price online?',
        'Search online for flights to Paris',
        'Can you search it online?',
        'Busca en internet el precio del oro',
        'What is web search?',
      ]) {
        expect(RetrievalPlan.aboutAssistant(q), isFalse, reason: q);
      }
    });
    test(
      'after a question, a polite "can you search online?" asks for one',
      () {
        expect(
          RetrievalPlan.aboutAssistant(
            'Can you search online?',
            afterQuestion: true,
          ),
          isFalse,
        );
        expect(
          RetrievalPlan.aboutAssistant(
            'Do you have internet access?',
            afterQuestion: true,
          ),
          isTrue,
        );
      },
    );
  });
}
