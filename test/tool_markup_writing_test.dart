import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/tools/domain/tool_markup.dart';

void main() {
  test('incremental writing matches full scans at every stream boundary', () {
    final samples = [
      'plain prose ' * 500,
      r'<tool_call>{"arguments":{"name":"report","text":"\"x\""},"name":"create_file"}</tool_call>'
          '\n<tool_call>{"name":"read_url"}',
      '<|tool_call>call:read_url{url:"x"}<tool_call|>',
      '```tool\n{"name":"calc"}\n```',
      '<function=get_time></function><invoke name="read_url"></invoke>',
      '[TOOL_CALLS]get_time[ARGS]{}',
      '<|python_tag|>{"name":"python"}',
      '<|tool_calls_section_begin|><|tool_call_begin|>functions.search_web:0'
          '<|tool_call_argument_begin|>{}<|tool_call_end|>'
          '<|tool_call_begin|>functions.read_url:1<|tool_call_argument_begin|>{}'
          '<|tool_calls_section_end|>',
      '<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>function<｜tool▁sep｜>'
          'create_file\n```json\n{"name":"report"}<｜tool▁call▁end｜><｜tool▁calls▁end｜>',
      '<tool_call>{"function":{"name":"search_web","arguments":{}}}</tool_call>',
    ];
    for (final sample in samples) {
      for (final step in [1, 2, 7, 40]) {
        final tracker = ToolWritingTracker();
        final text = 'Intro with no tool markers. $sample';
        for (var i = 0; i <= text.length; i += step) {
          final prefix = text.substring(0, i);
          expect(
            tracker.writing(prefix),
            ToolMarkup.writing(prefix),
            reason: prefix,
          );
        }
        expect(tracker.writing(text), ToolMarkup.writing(text));
        tracker.reset();
        expect(tracker.writing('replacement'), isNull);
      }
    }
  });
  test('no call being written', () {
    expect(ToolMarkup.writing('The capital is Paris.'), isNull);
    expect(ToolMarkup.writing(''), isNull);
  });

  test('Qwen call: empty before the name, the name once it arrives', () {
    expect(ToolMarkup.writing('Let me check.\n<tool_call>\n{"na'), '');
    expect(
      ToolMarkup.writing('<tool_call>\n{"name": "search_web", "argu'),
      'search_web',
    );
    expect(
      ToolMarkup.writing(
        '<tool_call>\n{"name": "search_web", "arguments": {}}\n</tool_call>',
      ),
      isNull,
    );
  });

  test('Gemma 4 call', () {
    expect(ToolMarkup.writing('<|tool_call>call:read_url{url:'), 'read_url');
    expect(
      ToolMarkup.writing('<|tool_call>call:read_url{url:"x"}<tool_call|>'),
      isNull,
    );
  });

  test('a second call after a complete one', () {
    expect(
      ToolMarkup.writing(
        '<tool_call>{"name": "a"}</tool_call>\n<tool_call>{"name": "b',
      ),
      '',
    );
    expect(
      ToolMarkup.writing(
        '<tool_call>{"name": "a"}</tool_call>\n<tool_call>{"name": "b"',
      ),
      'b',
    );
  });

  test('fenced protocol and XML calls', () {
    expect(ToolMarkup.writing('```tool\n{"name": "calc", "ar'), 'calc');
    expect(ToolMarkup.writing('```tool\n{"name": "calc"}\n```'), isNull);
    expect(ToolMarkup.writing('<invoke name="get_time">'), 'get_time');
    expect(ToolMarkup.writing('<function=get_time>\n<para'), 'get_time');
    expect(ToolMarkup.writing('<function=get_time></function>'), isNull);
  });

  test('the name comes from the call, never from its arguments', () {
    expect(
      ToolMarkup.writing(
        '<tool_call>{"arguments": {"name": "report"}, "name": "create_file", ',
      ),
      'create_file',
    );
    expect(
      ToolMarkup.writing('<tool_call>{"arguments": {"name": "report"}, '),
      '',
    );
    expect(
      ToolMarkup.writing(
        '<tool_call>{"arguments": {"text": "a \\"name\\": \\"x\\""',
      ),
      '',
    );
  });

  test('Kimi and Mistral headers', () {
    expect(
      ToolMarkup.writing(
        '<|tool_calls_section_begin|><|tool_call_begin|>functions.search_web:0'
        '<|tool_call_argument_begin|>{"name": "x"',
      ),
      'search_web',
    );
    expect(ToolMarkup.writing('[TOOL_CALLS]get_time[ARGS]{'), 'get_time');
    expect(
      ToolMarkup.writing('[TOOL_CALLS][{"name": "get_time", "ar'),
      'get_time',
    );
  });

  test('a section with several calls names the one being written', () {
    expect(
      ToolMarkup.writing(
        '<|tool_calls_section_begin|><|tool_call_begin|>functions.search_web:0'
        '<|tool_call_argument_begin|>{"query": "x"}<|tool_call_end|>'
        '<|tool_call_begin|>functions.read_url:1<|tool_call_argument_begin|>{',
      ),
      'read_url',
    );
    // Between two calls nothing is named yet.
    expect(
      ToolMarkup.writing(
        '<|tool_calls_section_begin|><|tool_call_begin|>functions.search_web:0'
        '<|tool_call_argument_begin|>{}<|tool_call_end|>',
      ),
      '',
    );
  });

  test('DeepSeek headers name the tool, never the arguments', () {
    expect(
      ToolMarkup.writing(
        '<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>function<｜tool▁sep｜>'
        'create_file\n```json\n{"name": "report",',
      ),
      'create_file',
    );
    expect(
      ToolMarkup.writing(
        '<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>create_file<｜tool▁sep｜>'
        '{"name": "report",',
      ),
      'create_file',
    );
    expect(
      ToolMarkup.writing(
        '<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>function<｜tool▁sep｜>',
      ),
      '',
    );
  });

  test('an OpenAI-style function wrapper is named', () {
    expect(
      ToolMarkup.writing(
        '<tool_call>{"function":{"name":"search_web","arguments":{',
      ),
      'search_web',
    );
  });
}
