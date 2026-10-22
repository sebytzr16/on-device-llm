import 'evidence.dart';
import 'claim_passages.dart';

/// Citations for an answer written from sources that cites none: small
/// models drop the [n] markers (phone, 2026-10-04: the WHO pandemic date,
/// right and from five sources, cited none of them). Each sentence gets the
/// source that shares most of its words and holds every figure it states;
/// a sentence no source supports stays uncited. Code, tables and headings
/// are left as written.
class CitationMatch {
  static final _marker = RegExp(r'\[\d+(?:\s*,\s*\d+)*\]');
  // Not inside "the U.S. is": a lowercase word goes on the sentence
  // (phone, 2026-10-08: "in the U.S [1]. is $499.99").
  static final _sentence = RegExp(
    r'(?<=[.!?])\s+(?=[\p{Lu}\p{Lt}\p{Lo}\p{N}*"(])',
    unicode: true,
  );
  static final _tail = RegExp(r'([.!?:;]*[*_)"]*)\s*$');

  /// Fewest content words a sentence needs before it is matched.
  static const minWords = 3;

  static bool hasCitations(String answer) => _marker.hasMatch(answer);

  /// [answer] with " [n]" after each sentence a source of [sources]
  /// supports, numbered from 1 in [sources] order. Unchanged when the
  /// answer already cites or nothing matches; with [fill], an answer that
  /// cites only some sentences gets the uncited ones matched too.
  static String attach(
    String answer,
    List<String> sources, {
    bool fill = false,
  }) {
    if (sources.isEmpty || (!fill && hasCitations(answer))) return answer;
    final prepared = ClaimPassages.prepare(sources);
    final lines = answer.split('\n');
    var code = false;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('```')) {
        code = !code;
        continue;
      }
      if (code || trimmed.startsWith('|') || trimmed.startsWith('#')) continue;
      lines[i] = lines[i]
          .split(_sentence)
          .map((s) => _marker.hasMatch(s) ? s : _cite(s, prepared))
          .join(' ');
    }
    return lines.join('\n');
  }

  static String _cite(String sentence, List<Object> prepared) {
    final words = EvidenceRanker.terms(sentence).toSet();
    if (words.length < minWords) return sentence;
    final match = ClaimPassages.best(sentence, prepared);
    if (match == null || !match.states) return sentence;
    final tail = _tail.firstMatch(sentence)!;
    return '${sentence.substring(0, tail.start)} [${match.source + 1}]${tail[1]}';
  }
}
