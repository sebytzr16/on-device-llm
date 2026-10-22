/// A persisted criterion assessment with a trace back to researched steps.
class GoalCriterion {
  final String text, explanation, quote;
  final bool satisfied;
  final List<int> steps;
  final List<GoalCriterionEvidence> evidence;
  final List<GoalCriterionQuote> quotes;
  final String validationError;
  const GoalCriterion({
    required this.text,
    this.satisfied = false,
    this.explanation = '',
    this.quote = '',
    this.steps = const [],
    this.evidence = const [],
    this.quotes = const [],
    this.validationError = '',
  });
  Map<String, dynamic> toJson() => {
    'text': text,
    'satisfied': satisfied,
    'explanation': explanation,
    'quote': quote,
    'steps': steps,
    'evidence': [for (final item in evidence) item.toJson()],
    if (quotes.isNotEmpty) 'quotes': [for (final item in quotes) item.toJson()],
    if (validationError.isNotEmpty) 'validationError': validationError,
  };
  factory GoalCriterion.fromJson(Map<String, dynamic> j) => GoalCriterion(
    text: j['text'] as String? ?? '',
    satisfied: j['satisfied'] == true,
    explanation: j['explanation'] as String? ?? '',
    quote: j['quote'] as String? ?? '',
    steps: [
      for (final n in j['steps'] as List? ?? const [])
        if (n is int) n,
    ],
    evidence: [
      for (final item
          in j['evidence'] is List ? j['evidence'] as List : const [])
        if (item is Map && item['source'] is int && item['quote'] is String)
          GoalCriterionEvidence(item['source'] as int, item['quote'] as String),
    ],
    quotes: [
      for (final item in j['quotes'] is List ? j['quotes'] as List : const [])
        if (item is Map && item['step'] is int && item['quote'] is String)
          GoalCriterionQuote(item['step'] as int, item['quote'] as String),
    ],
    validationError: j['validationError'] as String? ?? '',
  );
}

class GoalCriterionQuote {
  final int step;
  final String quote;
  const GoalCriterionQuote(this.step, this.quote);
  Map<String, dynamic> toJson() => {'step': step, 'quote': quote};
}

class GoalCriterionEvidence {
  final int source;
  final String quote;
  const GoalCriterionEvidence(this.source, this.quote);
  Map<String, dynamic> toJson() => {'source': source, 'quote': quote};
}
