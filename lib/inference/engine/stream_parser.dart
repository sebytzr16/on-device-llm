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
    const keep = openTag.length - 1;
    if (content.length <= keep) return;
    final emit = content.substring(0, content.length - keep);
    _answerCtrl.add(emit);
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
    const keep = closeTag.length - 1;
    if (content.length <= keep) return;
    final emit = content.substring(0, content.length - keep);
    _thinkCtrl.add(emit);
    _thinkBuf
      ..clear()
      ..write(content.substring(content.length - keep));
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
