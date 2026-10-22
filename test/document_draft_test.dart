import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/export/chat_document.dart';
import 'package:ondevice_llm/features/chat/domain/export/document_draft_service.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';

class DraftEngine implements TextEngine {
  List<Map<String, Object>>? received;
  @override
  Map<String, dynamic> get metrics => const {};
  @override
  void cancel() {}
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => const {};
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    received = messages;
    expect(settings.responseFormat, ResponseFormat.text);
    expect(settings.toolsEnabled, isFalse);
    yield '<think>hidden</think># Report\nVerified finding [1]';
  }
}

void main() {
  test(
    'document draft uses selected chat and strips hidden thinking',
    () async {
      final engine = DraftEngine();
      final source = ChatDocument.select(
        messages: [
          ChatMessage(
            id: 'a',
            role: ChatRole.assistant,
            content: 'A verified fact [1]',
            timestamp: DateTime.utc(2026),
            sourcesJson:
                '[{"number":1,"title":"Source","url":"https://example.org"}]',
          ),
        ],
      );
      final draft = await DocumentDraftService.generate(
        engine: engine,
        settings: const InferenceSettings(),
        source: source,
        template: DocumentTemplate.report,
        fallbackTemplate: '',
      );
      expect(draft, startsWith('# Report'));
      expect(draft, isNot(contains('hidden')));
      expect(engine.received!.last['content'], contains('https://example.org'));
    },
  );
}
