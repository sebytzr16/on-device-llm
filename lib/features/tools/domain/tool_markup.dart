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
  /// Code is kept as written: a `<tool_call>` example in a code block is
  /// part of the answer (audit P2-52).
  static String strip(String text) => _outsideCode(text, (t) {
    for (final r in _blocks) {
      t = t.replaceAll(r, '');
    }
    return t.replaceAll(_orphans, '');
  }).trim();

  /// [text] without closing tags whose block is gone.
  static String stripOrphans(String text) =>
      _outsideCode(text, (t) => t.replaceAll(_orphans, '')).trim();

  /// Fenced (but not ```tool) and inline code.
  static final _code = RegExp(
    r'```(?!tool)[^\n]*\n[\s\S]*?(?:```|$)|`[^`\n]+`',
  );

  /// [text] with [edit] applied to everything but code.
  static String _outsideCode(String text, String Function(String) edit) {
    final out = StringBuffer();
    var at = 0;
    for (final m in _code.allMatches(text)) {
      out
        ..write(edit(text.substring(at, m.start)))
        ..write(m[0]);
      at = m.end;
    }
    out.write(edit(text.substring(at)));
    return out.toString();
  }

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

  /// What closes a call opened by one of [_starts] (Mistral and Llama
  /// calls run to the end of the turn).
  static const _ends = [
    '</tool_call>',
    '<tool_call|>',
    '<|tool_calls_section_end|>',
    '<｜tool▁calls▁end｜>',
    '</function>',
    '</invoke>',
  ];

  /// Call headers that name the tool before its arguments.
  static final _headers = [
    RegExp(r'^<\|tool_call>\s*call:([\w.\-]+)'),
    RegExp(r'^<function=([\w.\-]+)'),
    RegExp(r'''^<(?:function|invoke)\s+name\s*=\s*["']?([\w.\-]+)'''),
    // Mistral v11+: [TOOL_CALLS]search_web[ARGS]{…}
    RegExp(r'^\[TOOL_CALLS\]([\w.\-]+)\['),
  ];

  /// Sections that hold several calls, each opened by its own marker; the
  /// call being written is the last one. Its header, never its arguments,
  /// names the tool.
  static final _sections = [
    (
      // Kimi K2: <|tool_call_begin|>functions.search_web:0<|tool_call_argument_begin|>…
      section: '<|tool_calls_section_begin|>',
      begin: '<|tool_call_begin|>',
      end: '<|tool_call_end|>',
      header: RegExp(r'^\s*(?:functions\.)?([\w\-]+):'),
    ),
    (
      // DeepSeek V3: function<｜tool▁sep｜>name\n```json…; V3.1: name<｜tool▁sep｜>{…}
      section: '<｜tool▁calls▁begin｜>',
      begin: '<｜tool▁call▁begin｜>',
      end: '<｜tool▁call▁end｜>',
      header: RegExp(
        r'^\s*(?:function<｜tool▁sep｜>([\w.\-]+)|(?!function<｜tool▁sep｜>)([\w.\-]+)<｜tool▁sep｜>)',
      ),
    ),
  ];

  static String _sectionCall(
    String call,
    ({String section, String begin, String end, RegExp header}) s,
  ) {
    final at = call.lastIndexOf(s.begin);
    if (at < 0) return '';
    final inner = call.substring(at + s.begin.length);
    if (inner.contains(s.end)) return '';
    final m = s.header.firstMatch(inner);
    return m == null ? '' : (m.group(1) ?? m.group(2) ?? '');
  }

  /// The `"name"` key of the call's own JSON object, never one inside its
  /// arguments (`{"arguments": {"name": "report"}, "name": "create_file"}`).
  static String? _topLevelName(String call) {
    final open = call.indexOf('{');
    if (open < 0) return null;
    var depth = 0;
    var inString = false;
    for (var i = open; i < call.length; i++) {
      final c = call[i];
      if (inString) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        if (--depth == 0) return null;
      } else if (c == '"') {
        if (depth == 1) {
          final m =
              _jsonName.matchAsPrefix(call, i) ??
              _functionName.matchAsPrefix(call, i);
          if (m != null) return m.group(1);
        }
        inString = true;
      }
    }
    return null;
  }

  static final _jsonName = RegExp(r'"name"\s*:\s*"([\w.\-]+)"');

  /// OpenAI-style wrapper: `{"function": {"name": "search_web", …}}`.
  static final _functionName = RegExp(
    r'"function"\s*:\s*\{\s*"name"\s*:\s*"([\w.\-]+)"',
  );

  /// While a streaming answer writes a tool call: the tool's name once it
  /// has arrived, '' before that. Null when no call is being written (none
  /// started, or the last one is complete). After lmstudio-js (MIT), which
  /// reports a call's name as soon as it streams instead of after the JSON.
  static String? writing(String text) {
    var at = -1;
    for (final s in _starts) {
      final i = text.lastIndexOf(s);
      if (i > at) at = i;
    }
    if (at < 0) return null;
    final call = text.substring(at);
    if (_ends.any(call.contains) ||
        (call.startsWith('```') && call.indexOf('```', 3) >= 0)) {
      return null;
    }
    for (final s in _sections) {
      if (call.startsWith(s.section)) return _sectionCall(call, s);
    }
    for (final r in _headers) {
      final m = r.firstMatch(call);
      if (m != null) return m.group(1)!;
    }
    return _topLevelName(call) ?? '';
  }
}

/// Tracks an append-only answer, scanning new text for markers and keeping
/// only the last call (or a possible marker prefix) for [ToolMarkup.writing].
class ToolWritingTracker {
  int _length = 0, _marker = -1;
  static final _overlap =
      ToolMarkup._starts.map((s) => s.length).reduce((a, b) => a > b ? a : b) -
      1;

  void reset() {
    _length = 0;
    _marker = -1;
  }

  String? writing(String text) {
    if (text.length < _length) reset();
    final from = (_length - _overlap).clamp(0, text.length);
    final tail = text.substring(from);
    for (final start in ToolMarkup._starts) {
      final at = tail.lastIndexOf(start);
      if (at >= 0 && from + at > _marker) _marker = from + at;
    }
    _length = text.length;
    return _marker < 0 ? null : ToolMarkup.writing(text.substring(_marker));
  }
}
