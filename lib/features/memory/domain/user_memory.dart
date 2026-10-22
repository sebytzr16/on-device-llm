import 'memory_statements.dart';

/// Pure logic for local declarations, grounded model extraction, deduplication
/// and the notes injected into a chat's system prompt.
class UserMemory {
  /// Relevance indices retain the original rows/dates for provenance.
  /// With [byWords] off, only pinned notes and notes on how to answer
  /// (language, length) are kept: a research turn is not steered by a note
  /// that merely shares a word with the question.
  static List<int> relevant(
    String query,
    List<String> facts, {
    Set<int> pinned = const {},
    bool byWords = true,
    bool personalOnly = true,
  }) {
    Set<String> words(String s) => RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(s.toLowerCase())
        .map((m) => m[0]!)
        .where((w) => w.length > 2 && !_stop.contains(w))
        .toSet();
    final personal = personalQuery(query);
    final terms = words(query);
    final scored = <(int, int)>[];
    for (var i = 0; i < facts.length; i++) {
      if (transient(facts[i])) continue;
      final score = byWords && (!personalOnly || personal)
          ? words(facts[i]).intersection(terms).length
          : 0;
      final preference = RegExp(
        r'\b(language|speak|speaks|concise|français|english|french|español)\b|\b(prefer|prefers)\b.{0,30}\b(answer|answers|response|responses|reply|replies|brief|detailed|short|long)\b',
        caseSensitive: false,
      ).hasMatch(facts[i]);
      if (pinned.contains(i) || score > 0 || preference) {
        scored.add((
          i,
          (pinned.contains(i) ? 1000 : 0) + score * 10 + (preference ? 1 : 0),
        ));
      }
    }
    scored.sort((a, b) {
      final rank = b.$2.compareTo(a.$2);
      return rank != 0 ? rank : a.$1.compareTo(b.$1);
    });
    final always = scored.where((item) => pinned.contains(item.$1)).toList();
    final matched = scored.where((item) => !pinned.contains(item.$1)).take(3);
    return [
      for (final item in [...always, ...matched]) item.$1,
    ];
  }

  static bool personalQuery(String query) => RegExp(
    r"\b(i|me|my|mine|myself|je|moi|mon|ma|mes|j'ai|yo|mi|mis|mío|mia)\b",
    caseSensitive: false,
  ).hasMatch(query);

  /// Facts kept; the oldest go when the list is full.
  static const maxFacts = 200;

  /// Facts placed in the system prompt (most recent first).
  static const promptFacts = 40;
  static const minFactLength = 8, maxFactLength = 220;

  /// Even short first-person statements can teach something: "I'm a chef".
  static const minMessageLength = 4;

  /// Clear personal declarations need no extra inference request. The local
  /// predicates retain their literal values and reject unsafe contexts.
  static List<String> explicitFacts(
    String message, {
    required List<String> existing,
  }) {
    return parseFacts(
      MemoryStatements.extract(message).join('\n'),
      existing: existing,
    );
  }

  /// A message may contain a profession and another durable fact. Only
  /// skip model extraction when the local shortcut covered the whole message.
  static bool needsModelExtraction(String message) {
    return MemoryStatements.needsModel(message);
  }

  /// At most this many new facts per message; a person rarely states more.
  static const maxFactsPerTurn = 8;

  /// The message talks about the user themself: a first-person pronoun or
  /// possessive. A request or a question about the world ("summarise the
  /// trade situation") never carries a durable fact, so extraction — where
  /// small models happily invent a persona — is not even attempted.
  static bool worthExtracting(String message) {
    if (message.trim().length < minMessageLength) return false;
    if (MemoryStatements.extract(message).isNotEmpty) return true;
    if (MemoryStatements.groundingSource(message).isEmpty) return false;
    return true;
  }

  static List<Map<String, Object>> extractionMessages({
    required List<String> existing,
    required String userMessage,
    required String assistantAnswer,
  }) {
    // The answer is deliberately not shown: everything worth remembering is
    // in the user's own words, and an answer full of names, places and
    // numbers is what a small model turns into invented facts.
    final known = existing.isEmpty
        ? '(none yet)'
        : existing.take(promptFacts).map((f) => '- $f').join('\n');
    return [
      {
        'role': 'system',
        'content':
            'You keep short long-term notes about the user for their personal assistant. You output facts only, never commentary, and you never invent or infer.',
      },
      {
        'role': 'user',
        'content':
            'Notes so far:\n$known\n\n'
            'The user just wrote:\n"""$userMessage"""\n\n'
            '$extractionRules',
      },
    ];
  }

  /// What counts as a note, for [extractionMessages] and for the remote
  /// request that also names the chat.
  static const extractionRules =
      'Does this message EXPLICITLY state something durable about the user themself (their name, job, home, family, language, a preference, a tool or project they own, a health or diet constraint)? '
      'Questions, requests, tasks and the topics the user asks about are NOT facts about the user. '
      'Ignore quoted text, examples, roleplay, hypotheticals, negated or retracted claims, and statements about other people. '
      'Keep the stated relationship: using a tool does not mean owning it, and living with someone does not imply marriage. '
      'Remember explicitly stated active software, app and other ongoing projects, including their counts and names. Preserve qualifications such as self-taught in job descriptions. '
      'Passing state is NOT a fact either: where the user is right now, an errand, a mood or a one-day task. '
      'If the message states nothing about the user, reply with exactly: NONE\n'
      'Otherwise list only what the message itself says, one fact per line starting with "- ", third person ("The user…"), at most 20 words, at most $maxFactsPerTurn lines. '
      'Do not repeat existing notes. Never add anything the message does not say.';

  /// Words that carry no memory on their own; the rest of a fact must be
  /// visible in the user's message for the fact to count as stated.
  static const _stop = {
    'the',
    'user',
    'users',
    'a',
    'an',
    'is',
    'are',
    'was',
    'were',
    'be',
    'has',
    'have',
    'had',
    'their',
    'they',
    'them',
    'and',
    'or',
    'of',
    'to',
    'in',
    'on',
    'at',
    'for',
    'with',
    'as',
    'by',
    'from',
    'that',
    'this',
    'who',
    'which',
    'it',
    'its',
    'not',
    'no',
    'do',
    'does',
    'did',
    'his',
    'her',
    'he',
    'she',
    'about',
    'into',
    'like',
    'likes',
    'named',
    'called',
    'works',
    'work',
    'lives',
    'live',
    'uses',
    'use',
    'prefers',
    'prefer',
    'enjoys',
    'enjoy',
    'speaks',
    'speak',
    'own',
    'owns',
    'currently',
    'very',
    'also',
    'one',
    'two',
    'name',
  };

  /// Whether every substantive word of [fact] appears in [source]: names,
  /// places, tools and numbers the model could only have invented are
  /// rejected. Only listed inflections and synonyms are equivalent; sharing
  /// a prefix does not make two names, places or professions the same.
  static bool grounded(String fact, String source) {
    if (!MemoryStatements.relationMatches(fact, source)) return false;
    final personal = MemoryStatements.groundingSource(source, fact: fact);
    final src = _words(personal).map(_stem).toSet();
    final words = _words(
      fact,
    ).where((w) => w.length > 1 && !_stop.contains(w)).toList();
    if (words.isEmpty) return false;
    final hits = words.where((w) => src.contains(_stem(w))).length;
    return hits == words.length;
  }

  /// Lower-case words with the possessive dropped: "The user's name is
  /// Sam" is grounded by "My name is Sam". Every "The user's …" fact used
  /// to fail here on the word "user's", so names, pets and favourites —
  /// the commonest things people say about themselves — were never kept.
  static Iterable<String> _words(String text) => text
      .toLowerCase()
      .split(RegExp(r"[^\p{L}\p{N}'’]+", unicode: true))
      .map((w) => w.replaceFirst(RegExp(r"['’]s?$"), ''))
      .where((w) => w.isNotEmpty);

  /// The same word said two ways ("kids" in the message, "children" in the
  /// fact). Deliberately short: anything wider starts to ground inferences.
  static const _same = {
    'kid': 'child',
    'kids': 'child',
    'children': 'child',
    'mom': 'mother',
    'mum': 'mother',
    'dad': 'father',
    'engineering': 'engineer',
    'engineers': 'engineer',
    'nurses': 'nurse',
    'teachers': 'teacher',
    'chefs': 'chef',
    'dogs': 'dog',
    'cats': 'cat',
    'lived': 'live',
  };

  static String _stem(String w) => _same[w] ?? w;

  /// A fact about a moment rather than the person: where the user is right
  /// now ("is in front of Senso-ji temple", "is at the airport", "is in
  /// Tokyo" — "lives in Tokyo" is kept), what they are doing today, a trip
  /// or a plan. It is true for a day and wrong for the rest of the memory's
  /// life, so it is neither stored nor, if stored earlier, put in the prompt.
  static bool transient(String fact) =>
      _moment.hasMatch(fact) || _somewhere.hasMatch(fact);

  static final _moment = RegExp(
    // "currently" alone is not a moment ("currently works as a nurse" is
    // who the user is); "currently in/at/visiting…" is.
    r"\b(currently (in|at|on|near|visiting|travell?ing|staying|abroad)|right now|at the moment|today|tonight|tomorrow|yesterday|this (morning|afternoon|evening|week|weekend|month)|next (week|weekend|month)|last (week|weekend|night)|in front of|on (his|her|their) way|is (visiting|travell?ing|staying|going|heading|planning|about to|asking|looking for|wondering|trying to|waiting|standing|sitting)|(is|are) on (a|the) (trip|way|flight|train|bus)|asked (about|for)|wants to know|needs help)\b",
    caseSensitive: false,
  );
  // "is at <anywhere>", "is in/near <Proper noun>": a place the user is,
  // not one they live in ("is in the software industry" stays).
  static final _somewhere = RegExp(
    r"\b(is|are) (at (the |a |an )?\w|(in|near|inside|outside|by) (the |a |an )?[A-Z])",
  );

  /// Lines of the model's reply that look like facts, cleaned and deduped
  /// against [existing] (case-insensitive; a fact contained in another
  /// counts as known).
  static List<String> parseFacts(
    String raw, {
    required List<String> existing,
    String? source,
  }) {
    final text = raw.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true),
      '',
    );
    if (RegExp(r'^\W*NONE\b', caseSensitive: false).hasMatch(text.trim())) {
      return const [];
    }
    final known = existing.map(_norm).toList();
    final out = <String>[];
    for (final line in text.split('\n')) {
      var f = line.trim().replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s*'), '');
      f = f.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (f.endsWith('.')) f = f.substring(0, f.length - 1);
      if (f.length < minFactLength || f.length > maxFactLength) continue;
      final lower = f.toLowerCase();
      if (lower == 'none' || lower.startsWith('nothing new')) continue;
      if (RegExp(r'^(the )?assistant\b', caseSensitive: false).hasMatch(f)) {
        continue;
      }
      if (transient(f)) continue;
      final n = _norm(f);
      if (known.any((k) => k == n || k.contains(n) || n.contains(k))) continue;
      if (out.any((o) => _norm(o) == n)) continue;
      if (source != null && !grounded(f, source)) continue;
      out.add(f);
      if (out.length == maxFactsPerTurn) break;
    }
    return out;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceFirst(RegExp("^the user(?:['’]s)?\\s+"), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Block appended to the system prompt; empty when nothing is stored.
  /// Each note says when it was written ([notedAt], parallel to [facts];
  /// missing dates are left out) so the model can tell a week-old remark
  /// from something said today, and the notes are background only: never
  /// brought up, asked about or followed up on by the model itself.
  static String promptBlock(
    List<String> facts, {
    List<DateTime?> notedAt = const [],
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    // Notes stored before the transient filter existed are skipped here.
    final lines = <String>[];
    for (var i = 0; i < facts.length && lines.length < promptFacts; i++) {
      final f = facts[i];
      if (transient(f)) continue;
      final at = i < notedAt.length ? notedAt[i] : null;
      lines.add(at == null ? '\n- $f' : '\n- $f (noted ${age(at, today)})');
    }
    if (lines.isEmpty) return '';
    final b = StringBuffer(
      "\nBackground notes about the user from earlier conversations, with when each was written. They may be out of date. Use one only when the user's current message makes it relevant; do not recite them, do not ask about them and do not follow up on them unprompted.",
    );
    lines.forEach(b.write);
    return b.toString();
  }

  /// "today", "3 days ago", "2 weeks ago", "4 months ago": coarse on purpose,
  /// the model only needs to know how stale a note is.
  static String age(DateTime at, DateTime now) {
    final days = now.difference(at).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 14) return '$days days ago';
    if (days < 60) return '${days ~/ 7} weeks ago';
    if (days < 365) return '${days ~/ 30} months ago';
    return '${days ~/ 365} year${days >= 730 ? 's' : ''} ago';
  }
}
