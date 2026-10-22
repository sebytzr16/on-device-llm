import 'evidence_audit.dart';

/// Rule-based evaluation dimensions. Semantic factuality and entailment still
/// require an independently reviewed gold answer; keyword matches are diagnostic.
class ResearchEvaluation {
  final bool? factualRulesPassed;
  final bool citationNumbersValid, figuresSupported, hasCitations;
  final bool? appropriateAbstention;
  final List<String> missingFacts;
  final List<int> invalidCitations;
  final List<String> unsupportedFigures;
  const ResearchEvaluation({
    required this.factualRulesPassed,
    required this.citationNumbersValid,
    required this.figuresSupported,
    required this.hasCitations,
    required this.appropriateAbstention,
    required this.missingFacts,
    required this.invalidCitations,
    required this.unsupportedFigures,
  });

  /// Whether [text] states [phrase], ignoring case and Markdown emphasis:
  /// "**two** doses" states "two doses" (device run 2026-10-01).
  static bool matches(String text, String phrase) {
    if (phrase.trim().isEmpty) return false;
    text = text
        .replaceAll(RegExp(r'[*_`]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final end = RegExp(r'\d$').hasMatch(phrase.trim())
        ? r'(?![\p{L}\p{N}]|\.\d)'
        : r'(?![\p{L}\p{N}])';
    return RegExp(
      '(?<![\\p{L}\\p{N}])${RegExp.escape(phrase.trim())}$end',
      unicode: true,
      caseSensitive: false,
    ).hasMatch(text);
  }

  static const _month =
      r'(?:janvier|janv|january|jan|enero|ene|février|fevrier|févr|february|febrero|feb|fév|mars|march|marzo|mar|avril|april|abril|apr|avr|abr|mai|mayo|may|juin|june|junio|jun|juillet|juil|july|julio|jul|août|aout|august|agosto|aug|ago|septembre|september|septiembre|sept|sep|octobre|october|octubre|oct|novembre|november|noviembre|nov|décembre|decembre|december|diciembre|dec|déc|dic)';

  /// A date with day, month and year: "August 12, 2026", "2 août 2027",
  /// "10 de marzo de 1994".
  static final _fullDate = RegExp(
    '(?<![\\p{L}\\p{N}])(?:$_month\\.? \\d{1,2}(?:st|nd|rd|th)?,? \\d{4}|'
    '\\d{1,2}(?:st|nd|rd|th|er)? (?:of |de )?$_month\\.?,?(?: de)? \\d{4})'
    '(?!\\p{N})',
    unicode: true,
    caseSensitive: false,
  );

  static int? _monthOf(String name) {
    final n = name.toLowerCase();
    const starts = [
      ['jan', 'ene'],
      ['feb', 'fév', 'fev'],
      ['mar'],
      ['apr', 'avr', 'abr'],
      ['may', 'mai'],
      ['jun', 'juin'],
      ['jul', 'juil'],
      ['aug', 'aoû', 'aou', 'ago'],
      ['sep'],
      ['oct'],
      ['nov'],
      ['dec', 'déc', 'dic'],
    ];
    for (var m = 0; m < 12; m++) {
      if (starts[m].any(n.startsWith)) return m + 1;
    }
    return null;
  }

  /// Whether [date] (a [_fullDate] match) is [day].
  static bool _isDay(String date, DateTime day) {
    final year = RegExp(r'\d{4}').firstMatch(date)!.group(0)!;
    final d = RegExp(r'(?<!\d)\d{1,2}(?!\d)').firstMatch(date)?.group(0);
    final m = RegExp(_month, caseSensitive: false).firstMatch(date)?.group(0);
    return int.parse(year) == day.year &&
        d != null &&
        int.parse(d) == day.day &&
        m != null &&
        _monthOf(m) == day.month;
  }

  /// When the gold is a full date, the answer's lead counts: "The next
  /// eclipse is August 12, 2026 … (table) August 2, 2027" states the wrong
  /// date even though the right one appears further down (frozen-web run,
  /// 2026-10-11). A different full date stated before the first right one
  /// fails the fact; today's date (a clock line) does not count.
  static bool _statesOtherDateFirst(
    String answer,
    List<String> alternatives,
    DateTime today,
  ) {
    if (!alternatives.any((a) => _fullDate.hasMatch(a))) return false;
    final text = answer
        .replaceAll(RegExp(r'[*_`]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final date in _fullDate.allMatches(text)) {
      final said = date.group(0)!;
      if (alternatives.any((a) => matches(said, a))) return false;
      if (!_isDay(said, today)) return true;
    }
    return false;
  }

  static ResearchEvaluation score({
    required String answer,
    required List<String> evidence,
    required Map<String, dynamic> gold,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final audit = EvidenceAudit.check(answer, evidence);
    final rawFacts = gold['requiredFacts'];
    final facts = <List<String>>[
      if (rawFacts is List)
        for (final fact in rawFacts)
          if (fact is String)
            [fact]
          else if (fact is List)
            fact.whereType<String>().toList(),
    ];
    final missing = <String>[
      for (final alternatives in facts)
        if (alternatives.isEmpty ||
            !alternatives.any((phrase) => matches(answer, phrase)) ||
            _statesOtherDateFirst(answer, alternatives, now))
          alternatives.join(' / '),
    ];
    final forbidden = gold['forbiddenFacts'] is List
        ? (gold['forbiddenFacts'] as List).whereType<String>()
        : const <String>[];
    final currentGold =
        gold['current'] != true ||
        gold['goldAsOf'] ==
            DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final declines = RegExp(
      r"(?:cannot|can't|can ?not|unable to) (?:confirm|determine|establish|provide|verify|predict|know|give|say)|(?:do|does) not have|don't have|not enough (?:evidence|information|data)|not (?:found|established|available|possible to (?:know|predict|say))|unavailable|impossible to (?:know|predict|provide|give|say|forecast)|no (?:\w+ )?(?:data|forecasts?|records?) (?:exists?|is available)|unknown|unverified|insufficient evidence|cannot be known|(?:is|are) not (?:yet )?known|not known yet|(?:has|have) not (?:yet )?(?:happened|occurred|taken place)|(?:do|does) not contain|ne peut pas être (?:connu|prévu)|pas encore connu|ne peux pas (?:confirmer|fournir|vérifier|prédire|savoir|donner)|je n'ai pas|pas assez|impossible de (?:prévoir|prédire|savoir)|inconnu|indisponible|no puedo (?:confirmar|proporcionar|verificar|predecir|saber|dar)|no tengo|no hay suficiente|no es posible (?:saber|predecir)|no se puede saber|aún no se (?:sabe|conoce)|desconocido|no disponible",
      caseSensitive: false,
    ).hasMatch(answer);
    return ResearchEvaluation(
      factualRulesPassed: facts.isEmpty || !currentGold
          ? null
          : missing.isEmpty &&
                !forbidden.any((phrase) => matches(answer, phrase)),
      citationNumbersValid: audit.invalidCitations.isEmpty,
      figuresSupported: audit.unsupportedFigures.isEmpty,
      hasCitations: audit.hasCitations,
      appropriateAbstention: gold['unanswerable'] == true ? declines : null,
      missingFacts: missing,
      invalidCitations: audit.invalidCitations,
      unsupportedFigures: audit.unsupportedFigures,
    );
  }

  Map<String, dynamic> toJson() => {
    'factualRulesPassed': factualRulesPassed,
    'citationNumbersValid': citationNumbersValid,
    'figuresSupported': figuresSupported,
    'hasCitations': hasCitations,
    'appropriateAbstention': appropriateAbstention,
    'missingFacts': missingFacts,
    'invalidCitations': invalidCitations,
    'unsupportedFigures': unsupportedFigures,
    'semanticSupportRequiresReview': true,
  };
}
