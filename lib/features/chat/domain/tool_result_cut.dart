// Adapted from DeepSeek Harness's tool-result pruner (MIT),
// @deepseek-ai/dsh-compaction-tool-result-pruner: 4096 head / 1024 tail.

const toolCutMarker = '\n[… middle cut to fit the context …]\n';

/// Keeps at most [keep] original code points, plus one middle marker.
/// Nearby line breaks snap inward so the retained text stays within budget.
String cutMiddle(String text, int keep, {String marker = toolCutMarker}) {
  if (keep < 0) throw RangeError.value(keep, 'keep');
  final parts = text.split(marker);
  final head = parts.first.runes.toList();
  final tail = parts.length == 1 ? head : parts.last.runes.toList();
  final length = parts.length == 1 ? head.length : head.length + tail.length;
  if (length <= keep) return text;

  final headBudget = keep * 4 ~/ 5;
  final tailBudget = keep - headBudget;
  var headEnd = headBudget.clamp(0, head.length);
  var tailStart = (tail.length - tailBudget).clamp(0, tail.length);
  final headSlop = headBudget ~/ 10;
  final tailSlop = tailBudget ~/ 10;
  // A line break near the cut first, else a space: no word is split.
  int? snapHead(bool Function(int) at) {
    for (var i = headEnd - 1; i >= headEnd - headSlop && i >= 0; i--) {
      if (at(head[i])) return i;
    }
    return null;
  }

  int? snapTail(bool Function(int) at) {
    for (var i = tailStart; i < tailStart + tailSlop && i < tail.length; i++) {
      if (at(tail[i])) return i + 1;
    }
    return null;
  }

  bool line(int c) => c == 10;
  bool space(int c) => c == 32 || c == 9 || c == 10;
  if (headEnd < head.length) {
    headEnd = snapHead(line) ?? snapHead(space) ?? headEnd;
  }
  if (tailStart > 0) {
    tailStart = snapTail(line) ?? snapTail(space) ?? tailStart;
  }
  return String.fromCharCodes(head.take(headEnd)) +
      marker +
      String.fromCharCodes(tail.skip(tailStart));
}
