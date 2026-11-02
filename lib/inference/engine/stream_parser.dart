import 'dart:async';

/// Splits a token stream into `thinking` and `answer` streams based on
/// `<think>…</think>` markers, handling tags split across token boundaries
/// via buffer-with-safe-emit.
class ThinkingStreamParser {
  static const openTag = '<think>';
  static const closeTag = '</think>';

  final _thinkCtrl = StreamController<String>.broadcast(sync: true);
  final _answerCtrl = StreamController<String>.broadcast(sync: true);

  Stream<String> get thinkingStream => _thinkCtrl.stream;
  Stream<String> get answerStream => _answerCtrl.stream;

  final _thinkBuf = StringBuffer();
  final _answerBuf = StringBuffer();
  bool _insideThink = false;
  bool _closed = false;

  void add(String token) {
    if (_closed) return;
    if (_insideThink) {
      _thinkBuf.write(token);
      _processThink();
    } else {
      _answerBuf.write(token);
      _processAnswer();
    }
  }

  void _processAnswer() {
    final content = _answerBuf.toString();
    final idx = content.indexOf(openTag);
    if (idx != -1) {
      final before = content.substring(0, idx);
      if (before.isNotEmpty) _answerCtrl.add(before);
      _insideThink = true;
      _answerBuf.clear();
      _thinkBuf
        ..clear()
        ..write(content.substring(idx + openTag.length));
      _processThink();
      return;
    }
    final keep = _partialTag(content, openTag);
    if (content.length == keep) return;
    _answerCtrl.add(content.substring(0, content.length - keep));
    _answerBuf
      ..clear()
      ..write(content.substring(content.length - keep));
  }

  void _processThink() {
    final content = _thinkBuf.toString();
    final idx = content.indexOf(closeTag);
    if (idx != -1) {
      final think = content.substring(0, idx);
      if (think.isNotEmpty) _thinkCtrl.add(think);
      _insideThink = false;
      _thinkBuf.clear();
      final after = content.substring(idx + closeTag.length);
      _answerBuf
        ..clear()
        ..write(after);
      // FIX: route through the safe-emit path instead of emitting `after`
      // directly. Emitting here AND leaving `after` in _answerBuf caused it
      // to be re-emitted on the next add() (the double-emission bug).
      _processAnswer();
      return;
    }
    final keep = _partialTag(content, closeTag);
    if (content.length == keep) return;
    _thinkCtrl.add(content.substring(0, content.length - keep));
    _thinkBuf
      ..clear()
      ..write(content.substring(content.length - keep));
  }

  /// Length of the longest end of [content] that could still grow into
  /// [tag]; only that much is held back, so ordinary text shows at once
  /// (P3-05).
  static int _partialTag(String content, String tag) {
    for (var n = tag.length - 1; n > 0; n--) {
      if (n <= content.length && content.endsWith(tag.substring(0, n))) {
        return n;
      }
    }
    return 0;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_insideThink) {
      if (_thinkBuf.isNotEmpty) _thinkCtrl.add(_thinkBuf.toString());
    } else {
      if (_answerBuf.isNotEmpty) _answerCtrl.add(_answerBuf.toString());
    }
    _thinkCtrl.close();
    _answerCtrl.close();
  }
}
