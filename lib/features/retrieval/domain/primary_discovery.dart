/// One targeted discovery pass when an identified maker's product facts
/// are missing. Multi-maker comparisons keep the existing balanced search.
abstract final class PrimaryDiscovery {
  static const _makers = {
    'nikon': 'nikonusa.com',
    'canon': 'canon.com',
    'sony': 'sony.com',
    'fujifilm': 'fujifilm.com',
    'panasonic': 'panasonic.com',
    'samsung': 'samsung.com',
    'apple': 'apple.com',
  };
  static final _facts = RegExp(
    r'\b(weight|battery|dimensions?|specifications?|manual|sensor|capacity|sealed|poids|batterie|dimensions|manuel|peso|batería|dimensiones|manual|capacidad)\b',
    caseSensitive: false,
  );
  static String? query(
    String question,
    Iterable<String> missing, {
    required Iterable<String> subject,
  }) {
    if (!_facts.hasMatch('$question ${missing.join(' ')}')) return null;
    final words = question.toLowerCase().split(RegExp(r'[^a-z0-9]+')).toSet();
    final makers = _makers.keys.where(words.contains).toList();
    if (makers.length != 1) return null;
    final terms = subject.where((term) => term.trim().isNotEmpty).join(' ');
    if (terms.isEmpty) return null;
    return 'site:${_makers[makers.single]} $terms ${missing.join(' ')} specifications manual';
  }
}
