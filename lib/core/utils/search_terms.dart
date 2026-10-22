/// Script-aware word extraction shared by web evidence and local knowledge.
/// It deliberately avoids ASCII-only `\w`, which drops accented and non-Latin
/// queries. The ranges cover the scripts accepted by the app while excluding
/// the punctuation blocks that would otherwise glue sentences together.
final RegExp _word = RegExp(
  r'[0-9A-Za-z\u00C0-\u02AF\u0370-\u052F\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u0900-\u097F\u3041-\u3096\u30A1-\u30FA\u3400-\u9FFF\uAC00-\uD7AF]+',
  unicode: true,
);

final RegExp _cjk = RegExp(
  r'^[\u3041-\u3096\u30A1-\u30FA\u3400-\u9FFF\uAC00-\uD7AF]+$',
  unicode: true,
);

List<String> unicodeWords(String text, {bool cjkBigrams = false}) {
  final out = <String>[];
  for (final match in _word.allMatches(text.toLowerCase())) {
    final word = match.group(0)!;
    out.add(word);
    if (!cjkBigrams || !_cjk.hasMatch(word)) continue;
    final runes = word.runes.toList();
    for (var i = 0; i + 1 < runes.length; i++) {
      out.add(String.fromCharCodes(runes.sublist(i, i + 2)));
    }
  }
  return out;
}
