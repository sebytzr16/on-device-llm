/// One line of recognised text and its box on the image, in pixels.
class OcrLine {
  final String text;
  final double left, top, right, bottom;

  /// The line's tilt in degrees; ML Kit reports 0 for level text.
  final double angle;
  const OcrLine(
    this.text, {
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.angle = 0,
  });

  static OcrLine? fromJson(Object? value) {
    if (value is! Map) return null;
    final text = value['text'];
    double? n(String key) => (value[key] as num?)?.toDouble();
    final left = n('left'), top = n('top'), right = n('right');
    final bottom = n('bottom');
    if (text is! String ||
        left == null ||
        top == null ||
        right == null ||
        bottom == null ||
        bottom <= top) {
      return null;
    }
    return OcrLine(
      text,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      angle: n('angle') ?? 0,
    );
  }
}

/// Recognised text in reading order with each amount next to its label.
/// ML Kit lists a receipt's label column and amount column as separate
/// blocks: "Total : CHF" and its "54.50" came out nine lines apart, and
/// Qwen3.5 0.8B, which cannot see the photo, answered with another amount
/// (media probe, 2026-10-21).
class OcrLayout {
  /// [lines] in ML Kit's order. A short line holding a number moves to
  /// the end of the nearest line to its left on the same row. Prose lines
  /// stay where they are, so two columns of text are not interleaved.
  /// Null when the lines cannot be laid out (none, or tilted text).
  static String? paired(List<OcrLine> lines) {
    if (lines.isEmpty || lines.any((l) => l.angle.abs() > 8)) return null;
    final after = <int, List<int>>{};
    final moved = <int>{};
    for (var i = 0; i < lines.length; i++) {
      final amount = lines[i];
      if (!_amount(amount.text)) continue;
      int? best;
      var gap = double.infinity;
      for (var j = 0; j < lines.length; j++) {
        final label = lines[j];
        if (j == i || _amount(label.text)) continue;
        final distance = amount.left - label.right;
        // Boxes may touch or overlap by a few pixels.
        if (distance < -_height(amount) || !_sameRow(amount, label)) {
          continue;
        }
        if (distance < gap) {
          gap = distance;
          best = j;
        }
      }
      if (best != null) {
        (after[best] ??= []).add(i);
        moved.add(i);
      }
    }
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (moved.contains(i)) continue;
      final amounts = (after[i] ?? [])
        ..sort((a, b) => lines[a].left.compareTo(lines[b].left));
      out.add([i, ...amounts].map((k) => lines[k].text.trim()).join('  '));
    }
    return out.join('\n');
  }

  static double _height(OcrLine l) => l.bottom - l.top;

  /// Their vertical spans overlap by at least half the shorter one.
  static bool _sameRow(OcrLine a, OcrLine b) {
    final overlap =
        (a.bottom < b.bottom ? a.bottom : b.bottom) -
        (a.top > b.top ? a.top : b.top);
    final shorter = _height(a) < _height(b) ? _height(a) : _height(b);
    return overlap >= shorter / 2;
  }

  /// "54.50", "18.50 CHF", "x2", "-3,20 €": a number with at most a
  /// currency or multiplier beside it. "1xChässpätzli" is a label.
  static bool _amount(String text) => _number.hasMatch(text.trim());

  static final _number = RegExp(
    r"^(?:[a-z]{3}|[$€£¥]|x)?\s*[-+]?\d[\d.,' ]*\s*(?:[a-z]{3}|[$€£¥%])?$",
    caseSensitive: false,
  );
}
