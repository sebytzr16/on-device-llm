import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/about_user.dart';
import 'package:ondevice_llm/features/chat/domain/answer_cleanup.dart';
import 'package:ondevice_llm/features/chat/domain/math_question.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:ondevice_llm/features/chat/domain/answer_checks.dart';

/// Conversation probe, 2026-10-18: simple turns the 0.8B (and a remote
/// Gemma 4 E4B) got wrong.
void main() {
  group('plain arithmetic is worked out by the app', () {
    test('in words or digits', () {
      expect(
        MathQuestion.expression('What is fifteen plus twenty-seven?'),
        '15 + 27',
      );
      expect(MathQuestion.note('What is 17 times 23?'), contains('= 391'));
      expect(
        MathQuestion.note('How much is 20 percent of 50?'),
        contains('= 10'),
      );
      expect(
        MathQuestion.note('What is one hundred and five divided by five?'),
        contains('= 21'),
      );
      expect(
        MathQuestion.note('What is 2 to the power of 10?'),
        contains('= 1024'),
      );
      expect(MathQuestion.note('Combien font 12 fois 12 ?'), contains('= 144'));
      expect(
        MathQuestion.note('What is two thousand minus 1?'),
        contains('= 1999'),
      );
    });

    test('"that" is the sum just before', () {
      const earlier = ['What is fifteen plus twenty-seven?'];
      expect(
        MathQuestion.note('Now double that.', earlier: earlier),
        contains('= 84'),
      );
      expect(
        MathQuestion.note('Add 8 to that', earlier: earlier),
        contains('= 50'),
      );
      expect(
        MathQuestion.note(
          'And half of that?',
          earlier: [...earlier, 'Now double that.'],
        ),
        contains('= 42'),
      );
      // After another question, "that" is something else.
      expect(
        MathQuestion.note(
          'Double that',
          earlier: [...earlier, 'Who wrote Hamlet?'],
        ),
        isNull,
      );
      expect(MathQuestion.note('Now double that.'), isNull);
    });

    test('names, dates and questions about numbers are not sums', () {
      for (final q in [
        'How much is the iPhone 15 Plus?',
        'What happened in 2024-2025?',
        'Tell me about COVID-19',
        'What is 3 plus 4 in Spanish?',
        'Is a 4x4 worth it?',
        'What is the date 10/18?',
        'Hi, how are you?',
        'What is 15?',
      ]) {
        expect(MathQuestion.note(q), isNull, reason: q);
      }
    });
  });

  group('"where I live" is the place the user named', () {
    test('a stated city replaces the phrase', () {
      expect(
        RetrievalPlan.withUserPlace(
          "What's the weather like where I live today?",
          ['Hi, my name is Robin and I live in Denver.'],
        ),
        "What's the weather like in Denver today?",
      );
      expect(
        RetrievalPlan.withUserPlace('Any good restaurants near me?', [
          "I'm from New York and I love pizza.",
        ]),
        'Any good restaurants in New York?',
      );
      expect(
        RetrievalPlan.withUserPlace('Quel temps fait-il chez moi ?', [
          'J’habite à Lyon.',
        ]),
        'Quel temps fait-il in Lyon ?'.replaceAll(' ?', '?'),
      );
      expect(
        RetrievalPlan.withUserPlace('¿Qué tiempo hace donde vivo?', [
          'Vivo en Buenos Aires.',
        ]),
        '¿Qué tiempo hace in Buenos Aires?',
      );
      // The latest place counts.
      expect(
        RetrievalPlan.withUserPlace('weather where I am', [
          'I live in Denver.',
          "This week I'm in Rome on business.",
        ]),
        'weather in Rome',
      );
    });

    test('without a stated place the question is left alone', () {
      expect(
        RetrievalPlan.withUserPlace('weather near me', ['I have two cats.']),
        'weather near me',
      );
      expect(
        RetrievalPlan.withUserPlace('weather in Paris', ['I live in Denver.']),
        'weather in Paris',
      );
      expect(
        RetrievalPlan.withUserPlace('weather near me', [
          'I live in Denver on Sundays',
        ]),
        'weather in Denver',
      );
    });
  });

  test('a population is a number that changes', () {
    for (final q in [
      'And roughly how many people live there?',
      'What is the population of Ottawa?',
      'Quelle est la population de Lyon ? Combien de personnes vivent là ?',
      '¿Cuántas personas viven en Madrid?',
    ]) {
      expect(RetrievalPlan.timeSensitive(q), isTrue, reason: q);
    }
  });

  test('an answer without sources loses its citation numbers', () {
    expect(
      AnswerCleanup.dropCitations('The capital of Australia is Canberra [1].'),
      'The capital of Australia is Canberra.',
    );
    expect(
      AnswerCleanup.dropCitations('Your favourite colour is green [2, 3].'),
      'Your favourite colour is green.',
    );
    expect(
      AnswerCleanup.dropCitations('It is in Australia.[1]'),
      'It is in Australia.',
    );
    // Code and links stay.
    expect(
      AnswerCleanup.dropCitations('Use `a[1]` here [1].'),
      'Use `a[1]` here [1].',
    );
    expect(
      AnswerCleanup.dropCitations('See list[1] and [2](https://x.y).'),
      'See list[1] and [2](https://x.y).',
    );
  });

  test('a chained sum shows the earlier result and ends with the answer', () {
    final note = MathQuestion.note(
      'Now double that.',
      earlier: ['What is fifteen plus twenty-seven?'],
    )!;
    expect(note, contains('42 × 2 = 84'));
    expect(note, endsWith('The answer is 84.'));
  });

  test('a spoken sum is said in words, in the question\'s language', () {
    expect(
      MathQuestion.spoken('What is fifteen plus twenty-seven?'),
      '15 plus 27 is 42.',
    );
    expect(
      MathQuestion.spoken(
        'Now double that.',
        earlier: ['What is fifteen plus twenty-seven?'],
      ),
      '42 times 2 is 84.',
    );
    expect(MathQuestion.spoken('What is 9 squared?'), '9 squared is 81.');
    expect(
      MathQuestion.spoken('What is the square root of 144?'),
      'the square root of 144 is 12.',
    );
    expect(
      MathQuestion.spoken('What is 3 minus 10?'),
      '3 minus 10 is minus 7.',
    );
    expect(
      MathQuestion.spoken('What is 2 to the power of 10?'),
      '2 to the power of 10 is 1024.',
    );
    expect(
      MathQuestion.spoken('Combien font 12 fois 12 ?'),
      '12 fois 12 égale 144.',
    );
    expect(MathQuestion.spoken('¿Cuánto es 7 por 8?'), '7 por 8 es 56.');
    expect(MathQuestion.spoken('What is the capital of Canada?'), isNull);
  });

  test('"what can you do?" is answered by the app', () {
    expect(
      AboutUser.spokenAbilities('What can you do?', web: true),
      startsWith('I can answer questions, look up news'),
    );
    expect(
      AboutUser.spokenAbilities('So, what can you help me with?', web: false),
      contains('Web search is off'),
    );
    expect(
      AboutUser.spokenAbilities('Que peux-tu faire ?', web: true),
      startsWith('Je peux'),
    );
    expect(
      AboutUser.spokenAbilities('¿Qué puedes hacer?', web: true),
      startsWith('Puedo'),
    );
    expect(
      AboutUser.spokenAbilities('What can you do about my printer?', web: true),
      isNull,
    );
  });

  test('"can you search online?" follows the web setting', () {
    expect(
      AboutUser.spokenAbilities(
        'Are you able to do online searches?',
        web: true,
      ),
      startsWith('Yes.'),
    );
    expect(
      AboutUser.spokenAbilities('Can you search the web?', web: false),
      contains('web search is off'),
    );
    expect(
      AboutUser.spokenAbilities('Do you have internet access?', web: true),
      startsWith('Yes.'),
    );
    expect(
      AboutUser.spokenAbilities('Peux-tu chercher sur internet ?', web: true),
      startsWith('Oui.'),
    );
    expect(
      AboutUser.spokenAbilities('¿Puedes buscar en internet?', web: false),
      startsWith('Ahora no'),
    );
    // A search request is not a question about searching.
    expect(
      AboutUser.spokenAbilities(
        'Can you search online for the weather in Paris?',
        web: true,
      ),
      isNull,
    );
  });

  test('"what are my cats called?" is answered from what was said', () {
    const said = ['Hi, I am Robin.', 'I have two cats, Milo and Luna.'];
    expect(
      AboutUser.spokenNames('What are my cats called?', said),
      'Your cats are Milo and Luna.',
    );
    expect(
      AboutUser.spokenNames("What are my cats' names?", said),
      'Your cats are Milo and Luna.',
    );
    expect(
      AboutUser.spokenNames('What are the names of my cats?', said),
      'Your cats are Milo and Luna.',
    );
    expect(AboutUser.spokenNames('What are my dogs called?', said), isNull);
    expect(
      AboutUser.spokenNames('What are cats called in French?', said),
      isNull,
    );
  });

  test('narration that opens the only line is dropped', () {
    expect(
      AnswerCleanup.dropNarration(
        'The user asked for the population of Ottawa. The source [1] '
        'states that there were 1,188,114 residents.',
      ),
      'The source [1] states that there were 1,188,114 residents.',
    );
    expect(
      AnswerCleanup.dropNarration('The user has to sign in first.'),
      'The user has to sign in first.',
    );
    expect(
      AnswerCleanup.dropNarration(
        'Canberra is in Australia. The question asks which country is it '
        'in based on the provided text about Australia. I could not find '
        'another country, so I will state this directly. [1]',
      ),
      'Canberra is in Australia. [1]',
    );
    expect(
      AnswerCleanup.dropNarration(
        'The capital of Canada is Ottawa [1]. I found this in [1].',
      ),
      'The capital of Canada is Ottawa [1].',
    );
    expect(
      AnswerCleanup.spokenLength(
        'Stay dry! Bring an umbrella. Avoid puddles [1]. Eat at a café. '
        'Wear a coat. Use water bottles instead.',
      ),
      'Stay dry! Bring an umbrella. Avoid puddles [1]. Eat at a café. '
      'Wear a coat.',
    );
    expect(AnswerCleanup.spokenLength('One. Two. Three.'), 'One. Two. Three.');
    expect(
      AnswerCleanup.spokenLength('- a.\n- b.\n- c.\n- d.\n- e.\n- f.'),
      '- a.\n- b.\n- c.\n- d.\n- e.\n- f.',
    );
    expect(
      AnswerCleanup.dropNarration(
        "Australia's capital is Canberra [1]. This fact comes from the "
        'Wikipedia page about Australia which states that Canberra is the '
        "nation's capital [1].",
      ),
      "Australia's capital is Canberra [1].",
    );
    expect(
      AnswerCleanup.dropNarration(
        'The capital of Canada is Ottawa [1]. The information about Ottawa '
        'comes from the Wikipedia article covering Canada [1].',
      ),
      'The capital of Canada is Ottawa [1].',
    );
    expect(
      AnswerCleanup.dropNarration(
        'Japan is launching a spacecraft to Phobos [5]. The specific source '
        'providing this information is [5].',
      ),
      'Japan is launching a spacecraft to Phobos [5].',
    );
    expect(
      AnswerCleanup.dropNarration(
        'The population grew to 1,188,114 people on July 1, 2025, and '
        'cite [1].',
      ),
      'The population grew to 1,188,114 people on July 1, 2025 [1].',
    );
  });

  test('a greeting alone is answered by the app', () {
    expect(AboutUser.spokenGreeting('Hi!'), 'Hi! How can I help?');
    expect(
      AboutUser.spokenGreeting('Hey there, how are you?'),
      "I'm well, thanks. How can I help?",
    );
    expect(AboutUser.spokenGreeting('Good morning.'), 'Hi! How can I help?');
    expect(AboutUser.spokenGreeting('Bonjour !'), startsWith('Bonjour'));
    expect(
      AboutUser.spokenGreeting('Salut, ça va ?'),
      startsWith('Ça va bien'),
    );
    expect(AboutUser.spokenGreeting('Hola, buenos días'), startsWith('¡Hola!'));
    expect(
      AboutUser.spokenGreeting('Hola, ¿qué tal?'),
      startsWith('¡Muy bien'),
    );
    expect(AboutUser.spokenGreeting('Thank you.'), "You're welcome!");
    expect(AboutUser.spokenGreeting('Merci beaucoup !'), 'De rien !');
    expect(AboutUser.spokenGreeting('Muchas gracias'), '¡De nada!');
    expect(AboutUser.spokenGreeting('Thanks. What is two plus two?'), isNull);
    expect(AboutUser.spokenGreeting('Hi, what is the weather?'), isNull);
    expect(AboutUser.spokenGreeting('Hello world program in Python'), isNull);
  });

  test('an introduction is answered by the app', () {
    expect(
      AboutUser.spokenIntro('Hi, my name is Robin and I live in Denver.'),
      'Nice to meet you, Robin. How can I help?',
    );
    expect(
      AboutUser.spokenIntro("Salut, je m'appelle léa."),
      'Bonjour Léa ! Que puis-je faire pour toi ?',
    );
    expect(
      AboutUser.spokenIntro('Hola, me llamo Ana.'),
      '¡Hola, Ana! ¿En qué puedo ayudarte?',
    );
    // A request or a question is the model's to answer.
    expect(
      AboutUser.spokenIntro('My name is Sam, can you set a timer?'),
      isNull,
    );
    expect(
      AboutUser.spokenIntro('My name is Sam and I want a pasta recipe.'),
      isNull,
    );
    expect(AboutUser.spokenIntro('Call me tomorrow.'), isNull);
    expect(AboutUser.spokenIntro('I have two cats.'), isNull);
  });

  test('"what\'s my name?" is answered from what the user said', () {
    const said = ['Hi, my name is Robin and I live in Denver.'];
    expect(
      AboutUser.spokenName("What's my name?", said),
      'Your name is Robin.',
    );
    expect(
      AboutUser.spokenName('And do you remember my name?', said),
      'Your name is Robin.',
    );
    expect(
      AboutUser.spokenName('Comment je m’appelle ?', [
        "Salut, je m'appelle léa.",
      ]),
      'Tu t’appelles Léa.',
    );
    expect(
      AboutUser.spokenName('¿Cómo me llamo?', ['Hola, me llamo Ana.']),
      'Te llamas Ana.',
    );
    // The latest name wins; a name never given leaves the model to answer.
    expect(
      AboutUser.spokenName("What's my name?", [
        'My name is Sam.',
        'Actually, call me Alex.',
      ]),
      'Your name is Alex.',
    );
    expect(
      AboutUser.spokenName("What's my name?", ['I live in Lyon.']),
      isNull,
    );
    expect(AboutUser.spokenName('What should I name my cat?', said), isNull);
    expect(
      AboutUser.spokenName("What's my name and where do I live?", said),
      isNull,
    );
  });

  test('the user\'s facts are given back as theirs', () {
    const said = [
      'Hi, my name is Robin and I live in Denver.',
      'I have two cats, Milo and Luna.',
    ];
    expect(
      AboutUser.ownFacts(
        'The two cats I have are Milo and Luna. They are very cute.',
        said,
      ),
      'The two cats you have are Milo and Luna. They are very cute.',
    );
    expect(
      AboutUser.ownFacts('I live in Denver.', said),
      'You live in Denver.',
    );
    expect(
      AboutUser.ownFacts('My cats are Milo and Luna.', said),
      'Your cats are Milo and Luna.',
    );
    // Not about what they said, or a negation: left as written.
    for (final a in [
      'I have no record of your cats.',
      "I don't know where Milo lives.",
      'I have a great idea for dinner.',
    ]) {
      expect(AboutUser.ownFacts(a, said), a);
    }
  });

  test('"what\'s my favourite colour?" is answered from what was said', () {
    const said = [
      'My favourite colour is green, by the way.',
      "My dog's name is Rex and he is three.",
    ];
    expect(
      AboutUser.spokenFact('What is my favourite colour?', said),
      'Your favourite colour is green.',
    );
    expect(
      AboutUser.spokenFact("What's my favorite color?", said),
      'Your favorite color is green.',
    );
    expect(
      AboutUser.spokenFact("What is my dog's name?", said),
      "Your dog's name is Rex.",
    );
    expect(AboutUser.spokenFact('What is my favourite food?', said), isNull);
    expect(
      AboutUser.spokenFact('What is the capital of France?', said),
      isNull,
    );
  });

  test('a sum after thanks is still a sum', () {
    expect(
      MathQuestion.spoken('Thanks. What is two plus two?'),
      '2 plus 2 is 4.',
    );
  });

  test('an answer that denies the figure asked for is caught', () {
    const q = 'And roughly how many people live there?';
    expect(
      AnswerCleanup.deniesFigure(
        'There is no current record of how many people live in Ottawa as '
        'of today because this data is currently unavailable [1].',
        q,
      ),
      isTrue,
    );
    expect(
      AnswerCleanup.deniesFigure(
        'About 1.1 million people live in Ottawa, though the sources do not '
        'give the region.',
        q,
      ),
      isFalse,
    );
    expect(
      AnswerCleanup.deniesFigure(
        'The sources do not say who painted it.',
        'Who painted the Mona Lisa?',
      ),
      isFalse,
    );
  });

  test('a stable fact on the phone gets the Wikipedia check', () {
    bool check(String q, {bool webOn = true, bool remote = false}) =>
        AnswerChecks.wikipediaFactCheck(q, webOn: webOn, remote: remote);
    for (final q in [
      'What is the capital of Australia?',
      'Where was Marie Curie born?',
      'When was the Dart language created?',
      'Who wrote Les Misérables?',
      '¿Dónde nació Frida Kahlo?',
    ]) {
      expect(check(q), isTrue, reason: q);
    }
    for (final q in [
      'What is my favourite colour?',
      'How many cats do I have?',
      'What is fifteen plus twenty-seven?',
      'Tell me a short joke.',
      'Hi, how are you?',
      'Set a timer for five minutes.',
      'And which country is it in?',
    ]) {
      expect(check(q), isFalse, reason: q);
    }
    // Web search off (the offline archive has its own path) or a remote
    // model (it decides itself).
    expect(check('Where was Marie Curie born?', webOn: false), isFalse);
    expect(check('Where was Marie Curie born?', remote: true), isFalse);
  });

  test('a plain timer request gives the timer\'s arguments', () {
    expect(PhoneActions.plainTimer('Set a timer for five minutes.'), {
      'minutes': 5,
    });
    expect(PhoneActions.plainTimer('Start a 30 second timer'), {'seconds': 30});
    expect(PhoneActions.plainTimer('Set a timer for an hour'), {'minutes': 60});
    expect(PhoneActions.plainTimer('Mets un minuteur de 10 minutes'), {
      'minutes': 10,
    });
    expect(PhoneActions.plainTimer('Pon un temporizador de 2 minutos'), {
      'minutes': 2,
    });
    for (final q in [
      'Set a timer for an hour and a half',
      'Set a timer for 5 minutes and 30 seconds',
      'Remind me in 5 minutes to call Ana',
      'Set a timer',
    ]) {
      expect(PhoneActions.plainTimer(q), isNull, reason: q);
    }
  });

  test('an answer that points at sources instead of answering', () {
    // LM Studio Gemma 4 E4B after one search (round 4).
    expect(
      AnswerCleanup.defersToSources(
        'The current weather in Denver is showing various reports, but '
        'based on the search results, you can check Environment Canada for '
        'detailed hourly forecasts [1, 2]. It looks like temperatures, '
        'conditions, and precipitation likelihood are all available right '
        'now [3, 5].',
      ),
      isTrue,
    );
    // A figure, in digits or in words, is an answer.
    expect(
      AnswerCleanup.defersToSources(
        'It is twenty-five degrees and sunny; you can check Environment '
        'Canada for the hourly forecast.',
      ),
      isFalse,
    );
    expect(
      AnswerCleanup.defersToSources(
        'It is 18 °C. You can check the hourly forecast on weather.gc.ca.',
      ),
      isFalse,
    );
    expect(AnswerCleanup.defersToSources('The capital is Ottawa.'), isFalse);
    // Round 5: the offer came before the citations.
    expect(
      AnswerCleanup.offersToLookFurther(
        'The weather in Denver today is currently showing various forecasts '
        'from Environment Canada and other sources. Would you like the '
        'current temperature or a more detailed outlook? [1, 2]',
      ),
      isTrue,
    );
  });

  test('a changing figure is told apart from a fixed one', () {
    for (final a in [
      'Tomorrow in Rome, the weather will be sunny with a high of '
          'twenty-eight degrees Celsius.',
      'It is 18 °C in Denver.',
      'The Switch 2 costs four hundred ninety-nine dollars.',
      'Demain à Rome, il fera 28 degrés.',
    ]) {
      expect(AnswerCleanup.statesLiveFigure(a), isTrue, reason: a);
    }
    for (final a in [
      'Two plus two equals four.',
      'Let it simmer for about eight to ten minutes.',
      'Tomorrow will probably be sunny; I would check a forecast.',
      'The capital of Australia is Canberra.',
      'A circle has three hundred sixty degrees.',
    ]) {
      expect(AnswerCleanup.statesLiveFigure(a), isFalse, reason: a);
    }
  });

  test('made-up footnotes and tool tags go with the citations', () {
    expect(
      AnswerCleanup.dropCitations(
        'Take an umbrella and visit a museum.\n\n'
        '[1] The forecast for Rome shows a seven percent chance of rain.\n'
        '[2] This refers to general advice.',
      ),
      'Take an umbrella and visit a museum.',
    );
    expect(
      AnswerCleanup.dropCitations(
        'Fifteen plus twenty-seven is forty-two [calculator].',
      ),
      'Fifteen plus twenty-seven is forty-two.',
    );
  });

  test('the role notes give no answer to copy', () {
    // The 0.8B spoke "Your name is Robin. You live in Denver" to
    // every question once the note held those words (round 3).
    expect(AboutUser.note, isNot(contains('Your name is')));
    expect(AboutUser.note, isNot(contains('…')));
    expect(AboutUser.note, contains('never "I" or "my"'));
  });

  test('"there" after a capital is the capital, not the country', () {
    expect(
      RetrievalPlan.withContext(
        'And roughly how many people live there?',
        'What is the capital of Canada?',
        previousAnswer: "It's Ottawa.",
      ),
      startsWith('Ottawa'),
    );
    expect(
      RetrievalPlan.answerNames(
        'Who is the prime minister of Canada?',
        'Mark Carney is the Prime Minister of Canada [1].',
      ),
      ['Mark', 'Carney'],
    );
    expect(
      RetrievalPlan.answerNames(
        'What is the capital of Canada?',
        "Canada's capital city is Ottawa.",
      ),
      ['Ottawa'],
    );
    // "Who is Mark Carney?" names its subject; the answer adds nothing.
    expect(
      RetrievalPlan.answerNames(
        'Who is Mark Carney?',
        'Mark Carney is a Canadian economist.',
      ),
      isEmpty,
    );
    expect(
      RetrievalPlan.withContext('How old is he?', 'Who is Mark Carney?'),
      'Mark Carney old',
    );
  });

  group('questions about the user', () {
    for (final (language, questions) in [
      (
        'EN',
        [
          'How many calories does my cat need?',
          'Why is my dog coughing?',
          'What is wrong with my car?',
          'Do you remember my phone specifications?',
          'What food is best for my pets?',
        ],
      ),
      (
        'FR',
        [
          'Combien de calories faut-il à mon chat ?',
          'Pourquoi mon chien tousse ?',
          'Quel est le problème de ma voiture ?',
          'Comment réparer mon téléphone ?',
        ],
      ),
      (
        'ES',
        [
          '¿Cuántas calorías necesita mi gato?',
          '¿Por qué tose mi perro?',
          '¿Qué problema tiene mi coche?',
          '¿Cómo reparo mi teléfono?',
        ],
      ),
    ]) {
      test('$language pet and object questions are not about the user', () {
        for (final q in questions) {
          expect(AboutUser.asks(q), isFalse, reason: q);
        }
      });
    }
    test('personal and pet-name recall still works', () {
      for (final q in [
        "What's my dog's name?",
        'Tell me my cat’s name.',
        'What are my cats called?',
        'Quel est le nom de mon chat ?',
        'Comment s’appelle mon chien ?',
        '¿Cómo se llama mi gato?',
        '¿Cuál es el nombre de mi perro?',
        'Do you remember my age?',
        'How many cats do I have?',
      ]) {
        expect(AboutUser.asks(q), isTrue, reason: q);
      }
    });

    test('are told apart', () {
      for (final q in [
        "What's my name?",
        'Which city do I live in?',
        'How many cats do I have?',
        'What are my cats called?',
        'Do you remember where I live?',
        'Who am I?',
        'Comment je m’appelle ?',
        '¿Cómo me llamo?',
        'Quel est le nom de mon chat ?',
      ]) {
        expect(AboutUser.asks(q), isTrue, reason: q);
      }
      for (final q in [
        'What should I name my cat?',
        'How do I clean my oven?',
        'What is the capital of Canada?',
        'My name is Robin.',
        'I have two cats.',
        'Can my dog eat grapes?',
      ]) {
        expect(AboutUser.asks(q), isFalse, reason: q);
      }
    });
  });

  test('a spoken answer loses the model working out loud', () {
    const said =
        'Source [1] states he was born March 1, 1994. Age calculation: '
        'October 18, 2026 minus March 1, 1994 is approximately 32 years. '
        "Since the user's request mentions a specific date, I will use it.";
    expect(
      AnswerCleanup.dropNarration(said),
      'Source [1] states he was born March 1, 1994. Age calculation: '
      'October 18, 2026 minus March 1, 1994 is approximately 32 years.',
    );
    expect(
      AnswerCleanup.dropNarration(
        'He is 32.\nThe user asked for his age, so I should answer briefly.',
      ),
      'He is 32.',
    );
    // An answer about users is kept.
    const help = 'The user list is under Settings. Each user has a role.';
    expect(AnswerCleanup.dropNarration(help), help);
  });

  test('an offer to look further is caught only before any figure', () {
    expect(
      AnswerCleanup.offersToLookFurther(
        'The current weather in Denver is being reported by several '
        'sources today. Would you like the specific details from '
        'Environment Canada or one of the other sites?',
      ),
      isTrue,
    );
    expect(
      AnswerCleanup.offersToLookFurther(
        'I found a few sources for the weather in Rome. Would you like me '
        'to check the current conditions from AccuWeather?',
      ),
      isTrue,
    );
    expect(
      AnswerCleanup.offersToLookFurther(
        'It is 18 degrees and sunny. Would you like more details?',
      ),
      isFalse,
    );
    expect(
      AnswerCleanup.offersToLookFurther('Would you like to hear a joke?'),
      isFalse,
    );
  });

  test('an age given as of an earlier year is caught', () {
    final now = DateTime(2026, 10, 18);
    const q = 'How old is Justin Bieber?';
    expect(
      AnswerCleanup.staleAge(
        q,
        'Justin Bieber is thirty years old as of two thousand twenty-four '
        '[2]. He was born on March first, nineteen ninety-four.',
        now,
      ),
      isTrue,
    );
    expect(
      AnswerCleanup.staleAge(q, 'He is 30 years old as of 2024 [1].', now),
      isTrue,
    );
    expect(
      AnswerCleanup.staleAge(
        q,
        'Justin Bieber is 32. He was born on March 1, 1994, and was '
        'famous in 2010.',
        now,
      ),
      isFalse,
    );
    expect(
      AnswerCleanup.staleAge(
        'What is the population of Ottawa?',
        'It was 1,017,449 as of 2021.',
        now,
      ),
      isFalse,
    );
  });

  test('an answer that asks the question back loses that sentence', () {
    const q = 'How much does a Nintendo Switch 2 cost?';
    expect(
      AnswerCleanup.dropAskedBack(
        'How much does a Nintendo Switch 2 cost [1]? It costs \$449.99 [1].',
        q,
      ),
      'It costs \$449.99 [1].',
    );
    expect(
      AnswerCleanup.dropAskedBack('A Nintendo Switch 2 costs \$449.99.', q),
      'A Nintendo Switch 2 costs \$449.99.',
    );
    expect(AnswerCleanup.dropAskedBack(q, q), q);
  });
}
