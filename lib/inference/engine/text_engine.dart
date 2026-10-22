import '../../features/settings/domain/entities/inference_settings.dart';
import '../../features/tools/domain/tool_spec.dart';

/// What the chat needs from whatever produces text: the on-device llama.cpp
/// worker or a remote OpenAI-compatible server the user pointed the app at.
abstract class TextEngine {
  /// Engine info after the last load/turn (backend, speeds, context use…).
  /// After a turn it also carries `finishReason` ("eog" | "stop" | "length"
  /// | "tool_calls" | "cancelled") and `toolCalls` (a list of
  /// `{id, name, arguments}`) when the model called tools.
  Map<String, dynamic> get metrics;

  /// Streams answer text; reasoning arrives wrapped in `<think>` … `</think>`.
  /// Each message is `{role, content}` plus, on a user turn with photos,
  /// `images: [paths]` and one [mediaMarker] in the content per photo.
  /// Assistant turns may carry `tool_calls: [{id, name, arguments}]`; tool
  /// results are `{role: 'tool', tool_call_id, name, content}`.
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  });

  /// Whether the rendered prompt plus the response reserve fits the context:
  /// `{promptTokens, contextSize, reservedTokens, availableTokens, fits}`.
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  });

  void cancel();

  /// Placeholder the bridge (libmtmd) replaces with an image's tokens.
  static const mediaMarker = '<__media__>';

  /// Tool calls a turn ended with, read from its [metrics].
  static List<ToolCall> toolCallsOf(Map<String, dynamic> metrics) => [
    for (final c in (metrics['toolCalls'] as List?) ?? const [])
      if (c is Map) ToolCall.fromJson(Map<String, dynamic>.from(c)),
  ];
}
