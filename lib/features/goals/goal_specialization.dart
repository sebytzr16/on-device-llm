/// What kind of research a goal is: it shapes how the planner splits the
/// goal, which sources each step prefers, how the report is laid out and
/// the sampling the steps run with. General is today's behaviour.
enum GoalSpecialization {
  general(
    label: 'General',
    emoji: '🧭',
    description: 'Any topic: a balanced, cited report',
    criteriaHint: 'The goal answered completely, each claim with a source',
  ),
  code(
    label: 'Code',
    emoji: '💻',
    description: 'APIs, errors, libraries: working code and versions',
    criteriaHint:
        'A working approach with code, the versions it applies to and known pitfalls',
    planHint:
        'Ask about the exact APIs, error messages, library versions, official documentation, changelogs and known issues involved. Always name the language, framework or library and its version.',
    stepInstruction:
        'Prefer official documentation, release notes, the project\'s GitHub repository and issues, and well-voted Stack Overflow answers. Give exact API names and version numbers, and short code snippets in fenced blocks with the language named when the sources show them. Say when an answer depends on the version.',
    reportFormat:
        'Start with a two-sentence summary of the recommended approach. Then sections: Approach; Code (complete, fenced, language-tagged, runnable where possible); Versions and pitfalls; Alternatives.',
    turnOverrides: {'temperature': 0.2},
  ),
  science(
    label: 'Scientific',
    emoji: '🔬',
    description: 'What the evidence says: studies, consensus, limits',
    criteriaHint:
        'The main findings with study type, year and size, where scientists agree and disagree, and the limitations',
    planHint:
        'Ask what peer-reviewed studies and systematic reviews found, what the scientific consensus is, where findings disagree, and what remains open. Name the phenomenon, population or organism precisely.',
    stepInstruction:
        'Prefer peer-reviewed papers, systematic reviews and meta-analyses, and university, journal and public-agency sites (for example PubMed, arXiv, Nature, NIH, WHO). For each finding give the study type, year, sample size and effect size when the source states them. Separate established results from preliminary ones, and never overstate a single study.',
    reportFormat:
        'Start with a short summary of what the evidence shows and how strong it is. Then sections: Background; Evidence (study by study or theme by theme, with year and study type); Consensus and disagreements; Limitations; Open questions.',
    turnOverrides: {'temperature': 0.3},
  ),
  math(
    label: 'Math',
    emoji: '📐',
    description: 'Definitions, derivations, checked results',
    criteriaHint:
        'The final result, every step of the derivation, and a check of the answer',
    planHint:
        'Split the problem into the definitions and theorems it needs, known results or formulas to look up, and the steps of the computation or proof.',
    stepInstruction:
        'State definitions, theorems and formulas exactly, with their conditions. Show each derivation step. Use the calculator tool for any non-trivial arithmetic. Check every result by substitution, a special case or a second method, and say which.',
    reportFormat:
        'Start with the final answer in one line. Then sections: Definitions and known results; Step-by-step solution (numbered steps, formulas in plain notation); Verification; Notes and edge cases.',
    turnOverrides: {'temperature': 0.1},
  ),
  news(
    label: 'Current events',
    emoji: '📰',
    description: 'What happened, when, who says what',
    criteriaHint:
        'A dated timeline, the people and organisations involved, their positions, and what comes next',
    planHint:
        'Ask what happened and when, who is involved, what each side says, the background, and what is expected next. Include the place and the time frame in every question.',
    stepInstruction:
        'Prefer established news organisations and official statements. Give the date of every event. Keep confirmed facts apart from claims, and name who makes each claim. Say when reports disagree.',
    reportFormat:
        'Start with a three-sentence summary. Then sections: Timeline (dated bullets, newest last); Who is involved; Positions and reactions; What to watch next.',
  ),
  product(
    label: 'Product comparison',
    emoji: '⚖️',
    description: 'Options side by side, then a pick',
    criteriaHint:
        'Price, key specifications, strengths and weaknesses of each option, and which suits whom',
    // "First ask which options are worth comparing" made the planner ask it
    // of two cameras the tester had already named (phone, 2026-09-24).
    planHint:
        'When the goal names the products, ask about those exact products only: one question per criterion (price, key specifications, independent reviews, strengths and weaknesses), naming both products in each. Only when the goal names none, first ask which options are worth comparing. Give the region for prices and the year.',
    stepInstruction:
        'Prefer manufacturer specification pages and independent reviews and tests. Give prices with the currency, the region and the date seen, and exact specifications with units. Attribute every figure to the product the source names; a figure for a different model or generation does not count.',
    reportFormat:
        'Start with a one-paragraph recommendation. Then a Markdown comparison table (one row per option, one column per criterion), pros and cons for each option, and a closing "Which one for whom". When the goal is about a single product, give its facts as a short list instead of a table, and no "Which one for whom".',
    turnOverrides: {'temperature': 0.3},
  );

  final String label, emoji, description, criteriaHint;

  /// Added to the planner's instructions.
  final String planHint;

  /// Added to every research step's hidden instruction.
  final String stepInstruction;

  /// Replaces the report's layout sentence.
  final String reportFormat;

  /// Settings for the step turns (sampling, tools), over the user's own.
  final Map<String, dynamic> turnOverrides;

  const GoalSpecialization({
    required this.label,
    required this.emoji,
    required this.description,
    required this.criteriaHint,
    this.planHint = '',
    this.stepInstruction = '',
    this.reportFormat =
        'Write a well-organised report in Markdown that meets the success criteria: a short summary first, then sections with headings, bullet points where they help, and a short conclusion.',
    this.turnOverrides = const {},
  });

  static GoalSpecialization byName(String? name) =>
      values.asNameMap()[name] ?? general;

  /// The likely kind for a request, from its wording; general when nothing
  /// stands out. Only a starting point: the user picks on the Goals page.
  static GoalSpecialization guess(String text) {
    final t = text.toLowerCase();
    bool has(String pattern) => RegExp(pattern).hasMatch(t);
    if (has(
      r'\b(prove|proof|theorem|equation|integral|derivative|solve for|probability|matrix|lemma)\b',
    )) {
      return math;
    }
    if (has(
      r'\b(code|api|sdk|library|framework|compile|exception|stack trace|python|javascript|typescript|kotlin|swift|dart|flutter|rust|java|sql|regex|bug)\b',
    )) {
      return code;
    }
    if (has(
      r'\b(studies|study|evidence|peer.reviewed|clinical|trial|meta.analysis|scientific|paper|papers|research on)\b',
    )) {
      return science;
    }
    if (has(
      r'\b(compare|comparison|versus|vs\.?|which .{1,40} (buy|choose)|best .{1,40} for)\b',
    )) {
      return product;
    }
    if (has(r'\b(news|latest|this week|today|happened|election|announced)\b')) {
      return news;
    }
    return general;
  }

  /// A message that reads like a research project rather than a question
  /// for one answer: long enough, and asking to compare, research, analyse
  /// or plan. The chat offers to run it as a goal; it never switches alone.
  static bool looksLikeGoal(String text) {
    final t = text.trim().toLowerCase();
    if (t.length < 80) return false;
    return RegExp(
      r'\b(compare|research|investigate|analy[sz]e|analysis|pros and cons|in depth|in-depth|report on|overview of|literature|find out|look into|plan (a|my|the)|step.by.step plan)\b',
    ).hasMatch(t);
  }
}
