import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/tool_result_cut.dart';

void main() {
  test('keeps four fifths head and one fifth tail', () {
    final text = List.generate(
      1000,
      (i) => String.fromCharCode(0x400 + i),
    ).join();
    final parts = cutMiddle(text, 100).split(toolCutMarker);
    expect(parts, [text.substring(0, 80), text.substring(980)]);
    expect(parts.join().runes.length, 100);
  });

  test('counts code points and never splits surrogate pairs', () {
    final emoji = String.fromCharCode(0x1f600);
    final text = List.filled(200, emoji).join();
    final parts = cutMiddle(text, 51).split(toolCutMarker);
    expect(parts[0], List.filled(40, emoji).join());
    expect(parts[1], List.filled(11, emoji).join());
    expect(parts.join().runes.every((r) => r == 0x1f600), isTrue);
  });

  test('snaps head and tail inward to nearby line breaks', () {
    final text = '${'a' * 75}\n${'b' * 105}\n${'z' * 18}';
    final parts = cutMiddle(text, 100).split(toolCutMarker);
    expect(parts, ['a' * 75, 'z' * 18]);
    expect(parts.join().runes.length, lessThanOrEqualTo(100));
  });

  test('does not snap to distant line breaks', () {
    final text = '${'a' * 50}\n${'b' * 100}\n${'z' * 48}';
    final parts = cutMiddle(text, 100).split(toolCutMarker);
    expect(parts[0].runes.length, 80);
    expect(parts[1].runes.length, 20);
  });

  test('repeated cuts preserve one marker and both original ends', () {
    var text = '${'a' * 800}${'z' * 200}';
    for (final keep in [500, 250, 100, 20, 1, 0]) {
      text = cutMiddle(text, keep);
      final parts = text.split(toolCutMarker);
      expect(parts.length, 2);
      expect(parts.join().runes.length, lessThanOrEqualTo(keep));
      expect(parts[0], 'a' * (keep * 4 ~/ 5));
      expect(parts[1], 'z' * (keep - keep * 4 ~/ 5));
    }
  });

  test('re-cut recognises a translated marker', () {
    const marker = '\n[translated cut]\n';
    final first = cutMiddle('a' * 1000, 100, marker: marker);
    final second = cutMiddle(first, 50, marker: marker);
    expect(second.split(marker), ['a' * 40, 'a' * 10]);
    expect(second, isNot(contains(toolCutMarker)));
  });

  test('short text, exact budgets and existing short cuts stay unchanged', () {
    expect(cutMiddle('short', 10), 'short');
    expect(cutMiddle('short', 5), 'short');
    expect(cutMiddle('', 0), '');
    final cut = 'head${toolCutMarker}tail';
    expect(cutMiddle(cut, 8), cut);
    expect(() => cutMiddle('text', -1), throwsRangeError);
  });

  test('without a line break near the cut, words stay whole', () {
    final words = List.generate(400, (i) => 'word$i').join(' ');
    final cut = cutMiddle(words, 600);
    final parts = cut.split(toolCutMarker);
    expect(parts.length, 2);
    final known = words.split(' ').toSet();
    for (final w in parts.join(' ').split(RegExp(r'\s+'))) {
      if (w.isNotEmpty) expect(known, contains(w));
    }
  });
}
