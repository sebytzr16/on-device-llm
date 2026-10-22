import '../../retrieval/domain/evidence.dart';

/// Keeps the parts of a long attachment that answer a focused question.
/// The complete extracted text remains stored with the attachment, so a later
/// question can choose different passages without re-reading the file.
class DocumentPassages {
  static const minChars = 12000;
  static const maxPassages = 8;

  static String select(String text, String question) {
    if (text.length < minChars || !_isQuestion(question)) return text;
    final query = EvidenceRanker.terms(question);
    if (query.isEmpty) return text;
    final chunks = EvidenceRanker.chunk(text, sourceIndex: 0);
    final ranked = EvidenceRanker.rank(
      question,
      chunks,
      perSource: maxPassages,
      maxChunks: maxPassages,
    );
    // A query with no lexical match needs broader context; the ordinary
    // tokenizer-based fit will handle that case.
    if (ranked.isEmpty || ranked.first.score <= 0) return text;
    final ordered = ranked.toList()
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return '[Selected passages from the attached file; other sections omitted. '
        'Ask a follow-up to inspect a different part.]\n'
        '${ordered.map((c) => '[Passage ${c.ordinal + 1}]\n${c.text}').join('\n[…]\n')}';
  }

  static bool _isQuestion(String input) {
    final text = input.trim();
    if (text.isEmpty) return false;
    // Broad tasks need the document as a whole, including its introduction
    // and conclusions. Selection is for locating a specific answer.
    if (RegExp(
      r'\b(summari[sz]e|overview|outline|review|translate|rewrite|compare the (?:whole|entire)|entire document|whole document)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return false;
    }
    return text.contains('?') ||
        RegExp(
          r'^(what|which|who|when|where|why|how|find|locate|identify|explain)\b',
          caseSensitive: false,
        ).hasMatch(text);
  }
}
