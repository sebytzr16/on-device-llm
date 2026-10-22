/// The markup models write when they call a tool through their chat
/// template. The native parser turns it into structured calls; the text
/// itself must neither reach the screen nor be sent back as the assistant
/// turn's content next to those structured calls (the template renders the
/// call again from `tool_calls`, so the model saw every call twice).
class ToolMarkup {
  static final _blocks = [
    // Qwen / Hermes (JSON or <function=…> inside).
    RegExp(r'<tool_call>[\s\S]*?(?:</tool_call>|$)'),
    // Gemma 4.
    RegExp(r'<\|tool_call>[\s\S]*?(?:<tool_call\|>|$)'),
    // Kimi K2.
    RegExp(
      r'<\|tool_calls_section_begin\|>[\s\S]*?(?:<\|tool_calls_section_end\|>|$)',
    ),
    // DeepSeek.
    RegExp(r'<｜tool▁calls▁begin｜>[\s\S]*?(?:<｜tool▁calls▁end｜>|$)'),
    // Mistral.
    RegExp(r'\[TOOL_CALLS\][\s\S]*$'),
    // Bare function tags.
    RegExp(r'<function=[\s\S]*?(?:</function>|$)'),
    // XML-style calls: <function name="…">, <invoke name="…">.
    RegExp(
      r'''<(function|invoke)\s+name\s*=\s*["']?[\w.\-]+["']?\s*>[\s\S]*?(?:</\1>|$)''',
    ),
    // Llama 3.x built-in tools.
    RegExp(r'<\|python_tag\|>[\s\S]*$'),
    // The plain-text protocol's fenced block.
    RegExp(r'```tool\s*\{[\s\S]*?(?:```|$)'),
  ];

  static const _starts = [
    '<tool_call>',
    '<|tool_call>',
    '<|tool_calls_section_begin|>',
    '<｜tool▁calls▁begin｜>',
    '[TOOL_CALLS]',
    '<function=',
    '<function name=',
    '<invoke name=',
    '<|python_tag|>',
    '```tool',
  ];

  /// Closing tags left without their block: Qwen3.5 0.8B ended an action
  /// turn with `</think>\n\n</tool_call>` as its whole answer (phone,
  /// 2026-10-08), which was saved and shown.
  static final _orphans = RegExp(
    r'<think>\s*</think>|</think>|</tool_call>|<tool_call\|>|</function>|</?tool_response>',
  );

  /// [text] without any tool-call block or stray closing tag.
  static String strip(String text) {
    var t = text;
    for (final r in _blocks) {
      t = t.replaceAll(r, '');
    }
    return stripOrphans(t);
  }

  /// [text] without closing tags whose block is gone.
  static String stripOrphans(String text) =>
      text.replaceAll(_orphans, '').trim();

  /// What may be shown of a streaming answer: everything before the first
  /// tool-call marker, holding back a marker that is still arriving.
  static String visible(String text) {
    var cut = text.length;
    for (final s in _starts) {
      final i = text.indexOf(s);
      if (i >= 0 && i < cut) cut = i;
    }
    if (cut == text.length) {
      // "<tool_c" at the very end may be the start of a marker.
      for (final s in _starts) {
        for (var n = s.length - 1; n >= 2; n--) {
          if (text.endsWith(s.substring(0, n))) {
            cut = text.length - n < cut ? text.length - n : cut;
            break;
          }
        }
      }
    }
    return text.substring(0, cut);
  }
}
