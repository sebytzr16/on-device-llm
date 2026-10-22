import '../../retrieval/domain/news_intent.dart';

/// The form a grounded answer should take. One instruction for every
/// question ("lead with the answer in one or two sentences") made news
/// briefings and explanations come out as two lines (report
/// 2026-09-23); the shape follows what was asked instead.
enum AnswerShape {
  /// "What's the latest news?": several stories, most important first.
  briefing,

  /// "Latest news about X": the newest developments about one subject.
  topicNews,

  /// A single figure: price, version, date, score, count.
  figure,

  /// A how-to: steps.
  howTo,

  /// X vs Y.
  comparison,

  /// Best/top/options/ideas: a list of items with reasons.
  list,

  /// Who someone is.
  person,

  /// Explain / overview / how does it work.
  explanation,

  /// Anything else: a direct answer with its support.
  fact,

  /// Heard, not read (Conversation): a few short sentences, no lists. A
  /// weather answer with a "Key points" list took half a minute to say
  /// (conversation probe, 2026-10-07).
  spoken,
}

class AnswerShapes {
  /// Shorter local answers, for the frozen-web A/B (decode is ~75% of a
  /// searched answer's time on the phone; technology scan 2026-10-11). Off
  /// in the app until the eval shows no loss in correctness.
  static const concise = bool.fromEnvironment('EVAL_CONCISE');

  static AnswerShape of(String question, {NewsIntent? news}) {
    if (news != null) {
      return news.topic == null ? AnswerShape.briefing : AnswerShape.topicNews;
    }
    final q = question.trim().toLowerCase();
    if (_howTo.hasMatch(q)) return AnswerShape.howTo;
    if (_comparison.hasMatch(q)) return AnswerShape.comparison;
    if (_list.hasMatch(q)) return AnswerShape.list;
    if (_figure.hasMatch(q)) return AnswerShape.figure;
    if (_person.hasMatch(q)) return AnswerShape.person;
    if (_explain.hasMatch(q)) return AnswerShape.explanation;
    return AnswerShape.fact;
  }

  static final _howTo = RegExp(
    r"^(how (?:do|can|should|to|would) (?:i|you|we|one)?|steps? (?:to|for)|guide to|tutorial)|\b(install|set ?up|configure|enable|disable|fix|troubleshoot|migrate|reset|update|upgrade|connect)\b.*\b(how|steps?)\b",
  );
  static final _comparison = RegExp(
    r"\b(vs\.?|versus|compared? (?:to|with)|comparison|difference between|differences between|better than|or .+ which is better|which is better)\b",
  );
  static final _list = RegExp(
    r"^(what are (?:the |some )?(?:best|top|good|main|biggest|most)|best |top \d|list |recommend|suggest|ideas? for|options? for|alternatives? to|which .+ should i)|\b(best|top \d+|recommendations?|alternatives)\b.*\b(for|to|in)\b",
  );
  static final _figure = RegExp(
    r"\b(how (?:much|many|old|tall|far|long|big|fast)|what(?:'s| is) the (?:price|cost|population|score|rate|temperature|version|date|capital)|price of|cost of|latest version|when (?:is|was|did|does|will)|what time|what year|exchange rate|stock price|score of|final score)\b",
  );
  static final _person = RegExp(r"^(who (?:is|was|are|were)\b)");
  static final _explain = RegExp(
    r"^(explain|describe|what is|what are|what was|why|how does|how do .+ work|how did|tell me (?:more )?about|tell me more|more (?:about|on|details)|elaborate|expand on|go deeper|details (?:on|about)|give me an overview|overview of|summari[sz]e|what happened)",
  );

  /// The working instruction that travels with web evidence.
  /// [local] asks for a tighter answer: a phone decodes ~25 tokens a second.
  static String instructions(
    AnswerShape shape, {
    bool timely = false,
    String? topic,
    bool local = false,
    int? sources,
    String question = '',
  }) {
    // The valid range, spelled out: small models otherwise carry numbers
    // over from earlier answers in the chat.
    final cite =
        'After each fact, cite its source number in square brackets, like [2]; use only the numbered sources above${sources == null || sources < 1
            ? ''
            : sources == 1
            ? ' (only [1] exists)'
            : ' ([1] to [$sources])'}.';
    final requestedSentences = RegExp(
      r'\b(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|une?|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|una?|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez)\s+(?:sentences?|phrases?|oraciones?|frases?)\b',
      caseSensitive: false,
    ).hasMatch(question);
    final base = requestedSentences
        ? 'Follow the exact sentence count requested in the question. Write a single paragraph, with citations within those sentences. Do not add headings, bullet points, or a second summary.'
        : switch (shape) {
            AnswerShape.briefing =>
              'Write a news briefing from the stories above. Pick the ${local ? '5 or 6' : '6 to 10'} most important distinct stories, the most significant and most widely reported first. '
                  'For each: a **bold headline** in your own words, then ${local ? 'one short sentence (under 30 words)' : 'one or two sentences'} on what happened${local ? '' : ' and why it matters'}, ending with its source number like [3]. '
                  'When stories fall into clear areas (world, national, business, sport) you may group them under short headings. '
                  'Mention the day when a story is not from today. Do not add stories that are not in the sources, and do not repeat a story.',
            AnswerShape.topicNews =>
              'Summarise the latest news about ${topic ?? 'the subject'}: start with the most recent development in one or two sentences, '
                  'then ${local ? '3 to 5' : '4 to 7'} bullet points with the other key developments, newest first, each with its date and source number. '
                  'End with one line on what to watch next if the sources say.',
            AnswerShape.figure =>
              'Start with the exact figure or date in the first sentence, with its source number. Then add ${local ? (concise ? 'one short sentence' : 'one or two short points') : 'two to four short points'} of context (what it refers to, when it was measured, how it changed).',
            AnswerShape.howTo =>
              'Answer with numbered steps a person can follow, including exact commands, menu names or values from the sources. Add a short note on prerequisites or pitfalls if the sources give them.',
            AnswerShape.comparison =>
              'Compare the options point by point: a short introduction, then a compact Markdown table or bullets for the differences that matter, then a one-line conclusion on which suits what.',
            AnswerShape.list =>
              'Answer with a bulleted list of ${local ? '4 to 6' : '5 to 8'} items, each in bold with a one-line reason from the sources, best first.',
            AnswerShape.person =>
              'Start with who they are in one or two sentences, then bullet points with the key facts (role, notable work, recent news) from the sources.',
            AnswerShape.explanation =>
              'Give a clear, well-organised explanation: a two-sentence summary first, then the key points as ${local && concise ? 'up to three short bullets' : 'short paragraphs or bullets'}${local ? '' : ', with a heading per part if it is long'}.',
            AnswerShape.fact =>
              local && concise
                  ? 'Answer the question directly in the first sentence, then add the one or two details that matter most, in one short sentence each.'
                  : 'Answer the question directly in the first sentence, then add the supporting details that matter (${local ? 'two or three' : 'three to five'} short points or a short paragraph).',
            AnswerShape.spoken =>
              'Speak, do not write: one to three short sentences, the direct answer first, then the one detail that matters most. No lists, headings, bold or tables.',
          };
    final b = StringBuffer('$base $cite ');
    if (RegExp(
      r'\b(?:only|exactly|json|csv|bullets?|paragraphs?|words?|uniquement|seulement|mots|solo|solamente|palabras)\b',
      caseSensitive: false,
    ).hasMatch(question)) {
      b.write('Obey the question\'s explicit format and length requirements. ');
    }
    b.write(
      // Gemma 4 E2B answered "11 March" for the WHO's pandemic declaration
      // (app quality probe, 2026-10-20).
      'Copy figures exactly as the sources give them; never round them. '
      'Write a date in full, with its year. '
      'If the sources do not contain the answer, say what is missing instead of guessing, and never claim you cannot access the web — the sources are already here. Write the answer once; do not repeat it.',
    );
    if (timely && shape != AnswerShape.briefing) {
      b.write(
        " For anything that changes over time, say the date it is as of, taken from the source's updated, published or read date. "
        'If sources give different figures or dates, say so and prefer the most recently published one.',
      );
    }
    return b.toString();
  }
}
