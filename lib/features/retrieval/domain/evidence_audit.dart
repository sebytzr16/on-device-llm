import 'evidence.dart';
import 'claim_support.dart';

/// Mechanical evidence checks, not a claim that the answer is factually true.
/// Numbers are checked against the sources actually cited beside the claim.
class EvidenceAudit {
  final List<int> invalidCitations;
  final List<String> unsupportedFigures;
  final List<String> unsupportedClaims;
  final int citedClaims;
  final bool hasCitations;
  const EvidenceAudit({
    this.invalidCitations = const [],
    this.unsupportedFigures = const [],
    this.unsupportedClaims = const [],
    this.citedClaims = 0,
    this.hasCitations = false,
  });

  bool get passes =>
      invalidCitations.isEmpty &&
      unsupportedFigures.isEmpty &&
      unsupportedClaims.isEmpty;
  static final marker = RegExp(r'\[(\d+(?:\s*,\s*\d+)*)\]');
  static Set<int> citations(String text) => {
    for (final m in marker.allMatches(text))
      for (final n in m[1]!.split(',')) int.parse(n.trim()),
  };

  static EvidenceAudit check(String answer, List<String> evidence) {
    final cited = citations(answer);
    final invalid = cited.where((n) => n < 1 || n > evidence.length).toList()
      ..sort();
    final missing = <String>{};
    final unsupported = <String>{};
    var claims = 0;
    // Keep a citation following sentence punctuation with its preceding claim.
    final units = answer.split(
      RegExp(r'\n|(?<=[.!?])\s+(?=[\p{L}*])', unicode: true),
    );
    for (final unit in units) {
      final refs = citations(unit).where((n) => n > 0 && n <= evidence.length);
      if (refs.isEmpty) continue;
      claims++;
      unsupported.addAll(
        ClaimSupport.unsupported(
          unit.replaceAll(marker, ''),
          refs.map((n) => evidence[n - 1]),
        ),
      );
      missing.addAll(
        EvidenceRanker.unsupportedFigures(
          unit.replaceAll(marker, ''),
          refs.map((n) => evidence[n - 1]),
        ),
      );
    }
    return EvidenceAudit(
      invalidCitations: invalid,
      unsupportedFigures: missing.toList(),
      unsupportedClaims: unsupported.toList(),
      citedClaims: claims,
      hasCitations: cited.isNotEmpty,
    );
  }

  Map<String, dynamic> toJson() => {
    'invalidCitations': invalidCitations,
    'unsupportedFigures': unsupportedFigures,
    'unsupportedClaims': unsupportedClaims,
    'semanticSupportRequiresReview': true,
    'citedClaims': citedClaims,
    'hasCitations': hasCitations,
    'mechanicalChecksPassed': passes,
  };
}
