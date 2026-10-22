import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/memory/domain/user_memory.dart';

void main() {
  test('parses fact lines, drops NONE, assistant claims and known facts', () {
    expect(UserMemory.parseFacts('NONE', existing: const []), isEmpty);
    expect(
      UserMemory.parseFacts('<think>hm</think>\nnone.', existing: const []),
      isEmpty,
    );
    final facts = UserMemory.parseFacts(
      '- The user is called Robin.\n'
      '- The user works as a nurse in Lisbon\n'
      '* The assistant recommended Flutter.\n'
      '- The user is called Robin\n'
      '- ok\n',
      existing: const ['The user prefers metric units'],
    );
    expect(facts, [
      'The user is called Robin',
      'The user works as a nurse in Lisbon',
    ]);
    // Already known (even phrased slightly differently) is not repeated.
    expect(
      UserMemory.parseFacts(
        '- The user prefers metric units.',
        existing: const ['The user prefers metric units'],
      ),
      isEmpty,
    );
  });

  test('prompt block and extraction prompt carry the notes', () {
    expect(UserMemory.promptBlock(const []), '');
    final block = UserMemory.promptBlock(const ['The user is a nurse']);
    expect(block, contains('- The user is a nurse'));
    expect(block, contains('do not recite'));
    expect(block, contains('do not follow up'));
    // Notes carry their age so a week-old remark is not treated as today's.
    final now = DateTime(2026, 9, 19);
    final dated = UserMemory.promptBlock(
      const ['The user is a nurse', 'The user lives in Porto'],
      notedAt: [now.subtract(const Duration(days: 8)), null],
      now: now,
    );
    expect(dated, contains('- The user is a nurse (noted 8 days ago)'));
    expect(dated, endsWith('- The user lives in Porto'));
    expect(UserMemory.age(now, now), 'today');
    expect(
      UserMemory.age(now.subtract(const Duration(days: 1)), now),
      'yesterday',
    );
    expect(
      UserMemory.age(now.subtract(const Duration(days: 21)), now),
      '3 weeks ago',
    );
    expect(
      UserMemory.age(now.subtract(const Duration(days: 100)), now),
      '3 months ago',
    );
    expect(
      UserMemory.age(now.subtract(const Duration(days: 800)), now),
      '2 years ago',
    );
    final messages = UserMemory.extractionMessages(
      existing: const ['The user is a nurse'],
      userMessage: 'I moved to Porto last month',
      assistantAnswer: 'Congratulations',
    );
    expect(messages.last['content'], contains('- The user is a nurse'));
    expect(messages.last['content'], contains('I moved to Porto'));
    // The answer is never shown: it is where invented facts come from.
    expect(messages.last['content'], isNot(contains('Congratulations')));
    expect(messages.last['content'], contains('NONE'));
  });

  test('passing state is not kept as a fact', () {
    expect(UserMemory.transient('The user is currently in Rome'), true);
    expect(UserMemory.transient('The user is visiting Rome this week'), true);
    expect(UserMemory.transient('The user asked about train times'), true);
    expect(UserMemory.transient('The user is looking for a hotel'), true);
    expect(UserMemory.transient('The user lives in Rome'), false);
    expect(UserMemory.transient('The user is a nurse'), false);
    // The note that made Gemma open with "your visit to Senso-ji today".
    expect(
      UserMemory.transient('The user is in front of Senso-ji temple'),
      true,
    );
    expect(UserMemory.transient('The user is at the airport'), true);
    expect(UserMemory.transient('The user is in Tokyo'), true);
    expect(UserMemory.transient('The user is in the software industry'), false);
    expect(UserMemory.transient('The user is a teacher in Lyon'), false);
    // Stored earlier, still kept out of the prompt.
    expect(
      UserMemory.promptBlock(const ['The user is in front of Senso-ji temple']),
      '',
    );
    expect(
      UserMemory.promptBlock(const [
        'The user is in front of Senso-ji temple',
        'The user is a nurse',
      ]),
      isNot(contains('Senso-ji')),
    );
    expect(
      UserMemory.parseFacts('''
- The user is in Rome today
- The user speaks Italian''', existing: const []),
      ['The user speaks Italian'],
    );
  });

  test('only first-person messages are worth extracting', () {
    expect(UserMemory.worthExtracting('I am a chef'), true);
    expect(UserMemory.worthExtracting("I'm a chef"), true);
    expect(UserMemory.worthExtracting('I am Sam'), true);
    expect(
      UserMemory.worthExtracting(
        'Make me a summary of the United States and Canada trade situation',
      ),
      false,
    );
    expect(UserMemory.worthExtracting('What is the capital of Peru?'), false);
    expect(UserMemory.worthExtracting('I am a nurse in Lisbon'), true);
    expect(UserMemory.worthExtracting("I'm allergic to peanuts, ideas?"), true);
    expect(UserMemory.worthExtracting('My cat is called Luna'), true);
    expect(UserMemory.worthExtracting('Je suis infirmier à Lyon'), true);
    expect(UserMemory.worthExtracting('ok thanks'), false);
  });

  test('explicit professions are captured locally without guessing roles', () {
    expect(UserMemory.needsModelExtraction('I am a chef.'), false);
    expect(
      UserMemory.needsModelExtraction('I am a chef. My cat is Luna.'),
      true,
    );
    for (final text in [
      'I am a chef',
      "I'm a chef.",
      'I am a chef. That is my job.',
      'I work as a chef for a living.',
    ]) {
      expect(UserMemory.explicitFacts(text, existing: const []), [
        'The user is a chef',
      ]);
    }
    expect(
      UserMemory.explicitFacts(
        'I am a chef',
        existing: const ['The user is a chef'],
      ),
      isEmpty,
    );
    for (final text in [
      'Pretend I am a chef.',
      'I am not a chef',
      'Am I a chef?',
      'I am a chef today',
      'I am a chef in a video game',
      'My friend is a chef',
      'Translate: I am a chef.',
      '"I am a chef."',
      'If I am a chef, what should I buy?',
    ]) {
      expect(
        UserMemory.explicitFacts(text, existing: const []),
        isEmpty,
        reason: text,
      );
    }
  });

  test('invented facts are rejected because they are not in the message', () {
    const message =
        'Summarise the United States and Canada trade situation for me';
    // The persona a small model produced for that request.
    final facts = UserMemory.parseFacts(
      '- The user works as a software engineer and runs a website on GitHub\n'
      '- The user lives in Canada and speaks English fluently\n'
      '- The user has a cat named Luna who they take to the vet\n'
      '- The user enjoys reading sci-fi novels by Isaac Asimov\n',
      existing: const [],
      source: message,
    );
    expect(facts, isEmpty);
    // Every stated fact passes, including inflections.
    final stated = UserMemory.parseFacts(
      '- The user is a nurse in Lisbon\n'
      '- The user is allergic to peanuts\n'
      '- The user prefers metric units\n',
      existing: const [],
      source:
          "I'm a nurse in Lisbon, allergic to peanuts, and I prefer metric units",
    );
    expect(stated, [
      'The user is a nurse in Lisbon',
      'The user is allergic to peanuts',
      'The user prefers metric units',
    ]);
    expect(
      UserMemory.grounded('The user lives in Porto', 'I live in Porto'),
      true,
    );
    expect(
      UserMemory.grounded('The user lives in Porto', 'I live in Lisbon'),
      false,
    );
  });

  // Report 2026-09-23: Memory on, nothing ever learned. Every
  // "The user's …" fact failed grounding on the word "user's".
  test('possessive and plainly reworded facts are kept', () {
    List<String> kept(String message, String reply) =>
        UserMemory.parseFacts(reply, existing: const [], source: message);
    expect(kept('My name is Robin', "- The user's name is Robin"), [
      "The user's name is Robin",
    ]);
    expect(kept('My name is Robin', '- The user’s name is Robin'), [
      'The user’s name is Robin',
    ]);
    expect(
      kept(
        'My dog is called Max and I love him',
        "- The user's dog is named Max",
      ),
      hasLength(1),
    );
    expect(
      kept(
        'My favourite colour is blue',
        "- The user's favourite colour is blue",
      ),
      hasLength(1),
    );
    expect(
      kept('I have two kids, any game ideas?', '- The user has two children'),
      hasLength(1),
    );
    expect(
      kept(
        'I am currently working as a nurse',
        '- The user currently works as a nurse',
      ),
      hasLength(1),
    );
    // Still no inference and no invented names.
    expect(
      kept('I live in Denver with my wife', '- The user is married'),
      isEmpty,
    );
    expect(kept('My name is Robin', "- The user's name is Sam"), isEmpty);
  });
}
