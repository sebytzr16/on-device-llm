import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/engine/stream_parser.dart';

(String, String) parse(List<String> chunks) {
  final p = ThinkingStreamParser();
  final answer = StringBuffer(), think = StringBuffer();
  p.answerStream.listen(answer.write);
  p.thinkingStream.listen(think.write);
  for (final c in chunks) {
    p.add(c);
  }
  p.close();
  p.close();
  p.add('ignored');
  return (answer.toString(), think.toString());
}

void main() {
  test(
    'every possible split preserves answer and reasoning without duplication',
    () {
      const text = 'before<think>理由 🧠</think>after<think>second</think>end';
      for (var i = 0; i <= text.length; i++) {
        expect(parse([text.substring(0, i), text.substring(i)]), (
          'beforeafterend',
          '理由 🧠second',
        ));
      }
      expect(parse(text.split('')), ('beforeafterend', '理由 🧠second'));
    },
  );
  test('flushes short tails and unclosed reasoning synchronously', () {
    expect(parse(['hi']), ('hi', ''));
    expect(parse(['<think>', 'unfinished']), ('', 'unfinished'));
    expect(parse(['x<thi']), ('x<thi', ''));
    expect(parse(['<think>x</think>z']), ('z', 'x'));
  });
}
