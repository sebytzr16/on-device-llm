/// Reader mode for a shared (or pasted) article: when the message box holds
/// one link and little else (a page shared from the browser arrives as
/// "title + link"), the composer offers to summarise it, list its key
/// points or explain it. The link is then read directly by the retrieval
/// pipeline (no search) and the answer cites it.
class ReaderActions {
  static final _url = RegExp(r'https?://[^\s<>"\)\]]+', caseSensitive: false);

  /// The one link [text] is about, or null when there is none, several, or
  /// the text is a real question around a link.
  static String? linkIn(String text) {
    final urls = _url.allMatches(text).map((m) => m[0]!).toSet();
    if (urls.length != 1) return null;
    final rest = text.replaceAll(_url, '').trim();
    // A title line is fine; a paragraph is a question the user is writing.
    if (rest.length > 160 || rest.contains('?')) return null;
    return urls.single;
  }
}
