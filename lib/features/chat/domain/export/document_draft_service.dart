import '../../../../inference/engine/text_engine.dart';
import '../../../settings/domain/entities/inference_settings.dart';
import 'chat_document.dart';

enum DocumentTemplate {
  transcript,
  report,
  letter,
  meetingNotes,
  studyGuide,
  summary,
}

class DocumentDraftService {
  static const maxInputChars = 24000;

  static String label(DocumentTemplate template) => switch (template) {
    DocumentTemplate.transcript => 'Conversation transcript',
    DocumentTemplate.report => 'Research report',
    DocumentTemplate.letter => 'Letter',
    DocumentTemplate.meetingNotes => 'Meeting notes',
    DocumentTemplate.studyGuide => 'Study guide',
    DocumentTemplate.summary => 'Executive summary',
  };

  static String instruction(DocumentTemplate template) => switch (template) {
    DocumentTemplate.transcript => 'Preserve the conversation in order.',
    DocumentTemplate.report =>
      'Create a structured report with an overview, methods or context, '
          'findings, limitations, conclusion, and sources.',
    DocumentTemplate.letter =>
      'Draft a coherent letter with a greeting, purpose, body, and closing. '
          'Do not invent names or addresses.',
    DocumentTemplate.meetingNotes =>
      'Create meeting notes with decisions, open questions, action items, '
          'owners only when stated, and source references.',
    DocumentTemplate.studyGuide =>
      'Create a study guide with key ideas, definitions, examples, '
          'questions for review, and sources.',
    DocumentTemplate.summary =>
      'Create a concise executive summary with key points, evidence, '
          'uncertainties, and recommended next steps only if supported.',
  };

  static Future<String> generate({
    required TextEngine engine,
    required InferenceSettings settings,
    required ChatDocument source,
    required DocumentTemplate template,
    required String fallbackTemplate,
  }) async {
    if (template == DocumentTemplate.transcript) return source.markdown;
    final context = source.markdown;
    final bounded = context.length <= maxInputChars
        ? context
        : context.substring(context.length - maxInputChars);
    final raw = await engine
        .generate(
          messages: [
            {
              'role': 'system',
              'content':
                  'Turn the supplied chat into a document. '
                  'Follow the requested format. Use Markdown headings, lists, '
                  'tables and code blocks where useful. Preserve source links and '
                  'citation numbers. Never invent facts, citations, decisions, '
                  'owners or action items. Clearly mark missing information. '
                  'Return only the document.',
            },
            {
              'role': 'user',
              'content':
                  'Document type: ${label(template)}\nInstructions: ${instruction(template)}\nSource chat:\n$bounded',
            },
          ],
          fallbackTemplate: fallbackTemplate,
          settings: settings.copyWith(
            maxTokens: 4096,
            temperature: 0.3,
            thinkingModeEnabled: false,
            responseFormat: ResponseFormat.text,
            toolsEnabled: false,
          ),
        )
        .join();
    return raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  }
}
