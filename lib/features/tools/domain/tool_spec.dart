import 'dart:convert';

/// A typed tool the model may call (roadmap P2 "typed bounded tools"). The
/// host owns the permission: a spec is only offered to the model when its
/// gate is open, and every call is bounded by rounds, time and result size.
class ToolSpec {
  final String name;
  final String description;

  /// JSON Schema (object) of the arguments.
  final Map<String, dynamic> parameters;
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'parameters': parameters,
  };

  /// OpenAI wire shape for remote servers.
  Map<String, dynamic> toOpenAi() => {'type': 'function', 'function': toJson()};
}

/// One call the model made. [arguments] is the raw JSON text the model
/// produced; [args] decodes it leniently (an unparsable body is `{}`).
class ToolCall {
  final String id;
  final String name;
  final String arguments;
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  Map<String, dynamic> get args => _parsed ?? const {};

  /// [arguments] as JSON a chat template can render. A call cut off inside
  /// its arguments ('{"minutes": 5, "label": "') failed the next round:
  /// llama.cpp parses every earlier call's arguments while rendering
  /// (second phone sweep, 2026-10-20). Closed when that is enough, else
  /// `{}`.
  String get jsonArguments {
    final text = _repaired;
    if (text == null) return '{}';
    return text == arguments ? arguments : jsonEncode(jsonDecode(text));
  }

  Map<String, dynamic>? get _parsed {
    final text = _repaired;
    if (text == null) return null;
    final v = jsonDecode(text);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// [arguments], or it closed with the quote and braces it lacks; null
  /// when neither parses.
  String? get _repaired {
    for (final end in const ['', '"', '}', '"}', '}}', '"}}']) {
      final text = end.isEmpty ? arguments : arguments.trimRight() + end;
      try {
        if (jsonDecode(text) is Map) return text;
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
  };

  factory ToolCall.fromJson(Map<String, dynamic> j) => ToolCall(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    arguments: j['arguments'] is String
        ? j['arguments'] as String
        : jsonEncode(j['arguments'] ?? const {}),
  );
}

/// What a tool returned, kept with the answer for the replay record.
class ToolResult {
  final ToolCall call;
  final String output;
  final bool ok;
  final int elapsedMs;
  const ToolResult({
    required this.call,
    required this.output,
    required this.ok,
    required this.elapsedMs,
  });

  Map<String, dynamic> toJson() => {
    'call': call.toJson(),
    'output': output,
    'ok': ok,
    'elapsedMs': elapsedMs,
  };

  factory ToolResult.fromJson(Map<String, dynamic> j) => ToolResult(
    call: ToolCall.fromJson(Map<String, dynamic>.from(j['call'] as Map)),
    output: (j['output'] as String?) ?? '',
    ok: j['ok'] == true,
    elapsedMs: (j['elapsedMs'] as num?)?.toInt() ?? 0,
  );
}
