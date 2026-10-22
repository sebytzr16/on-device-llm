/// A preference the model asks about before planning a Goal. Answers stay
/// with the Goal so every later phase uses the same user context.
class GoalClarification {
  final String id, question, answer;
  final List<String> options;
  const GoalClarification({
    required this.id,
    required this.question,
    this.options = const [],
    this.answer = '',
  });

  GoalClarification answered(String text) => GoalClarification(
    id: id,
    question: question,
    options: options,
    answer: text.trim(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'options': options,
    'answer': answer,
  };

  /// Personal preferences help recommendations and plans. A bounded request
  /// for specific facts already has its scope; asking about budget or use
  /// would add an unrelated decision and delay the research.
  static bool preferencesMayMatter(String objective, String criteria) {
    if (criteria.trim().isEmpty) return true;
    return RegExp(
      r'\b(recommend\w*|suggest\w*|best|choose|choosing|buy|purchase|suitable|for me|my needs|my budget|priorit\w*|plan|planning|itinerary|trip|diet|workout|design|build|recommand\w*|meilleur\w*|choisir|acheter|voyage|recom\w*|mejor\w*|elegir|comprar|viaje|itinerario)\b',
      caseSensitive: false,
    ).hasMatch('$objective\n$criteria');
  }

  static List<GoalClarification> parse(Object? raw) {
    if (raw is! List) return const [];
    final result = <GoalClarification>[];
    for (final item in raw) {
      if (item is! Map || item['question'] is! String) continue;
      final question = (item['question'] as String).trim();
      if (question.isEmpty || question.length > 500) continue;
      if (result.any(
        (q) => q.question.toLowerCase() == question.toLowerCase(),
      )) {
        continue;
      }
      result.add(
        GoalClarification(
          id: 'Q${result.length + 1}',
          question: question,
          options: {
            for (final option
                in item['options'] is List ? item['options'] as List : const [])
              if (option is String &&
                  option.trim().isNotEmpty &&
                  option.length <= 160)
                option.trim(),
          }.take(3).toList(),
          answer: item['answer'] is String ? item['answer'] as String : '',
        ),
      );
      if (result.length == 3) break;
    }
    return result;
  }
}
