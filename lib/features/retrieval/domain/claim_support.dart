/// Conservative checks for commonly invented product features. This is an
/// additional support check, not a general semantic truth detector.
class ClaimSupport {
  static final _model = RegExp(
    r'\b[A-Za-z][A-Za-z0-9]*(?:[- ][A-Za-z]+)?[- ]?\d[A-Za-z0-9-]*(?: (?:II|III|IV|V))?\b',
  );
  static String? _subject(String text, Match feature) {
    final prefix = text.substring(
      (feature.start - 500).clamp(0, text.length),
      feature.start,
    );
    final name = _model.allMatches(prefix).lastOrNull?[0];
    return name?.toLowerCase().replaceAll(RegExp(r'[ -]'), '');
  }

  static final _features = [
    RegExp(
      r'weather[ -]seal(?:ed|ing)?|tropicalis[ée]|sellad[oa] contra',
      caseSensitive: false,
    ),
    RegExp(r'waterproof|étanche|impermeable', caseSensitive: false),
    RegExp(
      r'in.body (?:image )?stabili[sz]ation|\bIBIS\b',
      caseSensitive: false,
    ),
    RegExp(
      r'global shutter|obturateur global|obturador global',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:built.in |electronic |optical )?viewfinder\b|viseur|visor',
      caseSensitive: false,
    ),
  ];
  static final _negative = RegExp(
    r"\b(?:not|no|without|lacks?|absent|pas|sans|aucun|sin)\b|isn['’]t|doesn['’]t",
    caseSensitive: false,
  );
  static final _uncertain = RegExp(
    r'unknown|unverified|not (?:confirmed|established|specified)|cannot confirm|inconnu|non confirmé|desconocido|no confirmado',
    caseSensitive: false,
  );

  static List<String> unsupported(String claim, Iterable<String> evidence) {
    if (_uncertain.hasMatch(claim)) return const [];
    final out = <String>[];
    for (final feature in _features) {
      final match = feature.firstMatch(claim);
      if (match == null) continue;
      // Negation belongs to the feature's local clause, not an unrelated
      // clause elsewhere on a long page.
      bool polarity(String text, Match at) {
        final start = (at.start - 50).clamp(0, text.length);
        final clause = text
            .substring(start, at.end)
            .split(
              RegExp(
                r'[.;\n]|\b(?:and|but|et|mais|y|pero)\b',
                caseSensitive: false,
              ),
            )
            .last;
        return _negative.hasMatch(
          clause.replaceAll(RegExp(r'\bnot only\b', caseSensitive: false), ''),
        );
      }

      final negative = polarity(claim, match);
      final subject = _subject(claim, match);
      final supported = evidence.any(
        (text) => feature
            .allMatches(text)
            .any(
              (at) =>
                  polarity(text, at) == negative &&
                  (subject == null || _subject(text, at) == subject),
            ),
      );
      if (!supported) out.add(match[0]!);
    }
    return out;
  }
}
