import '../../attachments/domain/attachment.dart';
import '../../memory/domain/user_memory.dart';

/// Chat titles: the first message until the model names the chat, the
/// naming prompts and the reply parsing.
class ChatTitles {
  const ChatTitles._();

  /// A new chat's title until the model names it: the first message, or
  /// the attached files' names.
  static String defaultTitle(String input, List<Attachment> attachments) =>
      input.isEmpty
      ? attachments.map((a) => a.name).join(', ')
      : input.length > 80
      ? input.substring(0, 80)
      : input;

  /// The prompt that names a chat: the question and the start of the
  /// answer, short enough to cost the phone about a second.
  static List<Map<String, Object>> titleMessages(
    String question,
    String answer,
  ) {
    String clip(String s, int n) {
      final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      return t.length > n ? '${t.substring(0, n)}…' : t;
    }

    return [
      {
        'role': 'system',
        'content': 'You write short, specific titles for conversations.',
      },
      {
        'role': 'user',
        'content':
            'Conversation:\nUser: ${clip(question, 400)}\nAssistant: ${clip(answer, 300)}\n\nWrite a title of 2 to 6 words naming the topic of this conversation, in the language of the user\'s message. Reply with the title only: no quotes, no "Title:", no full stop.',
      },
    ];
  }

  /// [titleMessages] and [UserMemory.extractionMessages] as one request,
  /// for a remote model after its first exchange: a free tier allows a few
  /// requests a minute and a searching turn has already used several
  /// (audit 2026-10-20). Read the reply with [splitTitleAndNotes].
  static List<Map<String, Object>> titleAndNotesMessages(
    String question,
    String answer, {
    required List<String> notes,
  }) {
    final conversation =
        titleMessages(question, answer)[1]['content'] as String;
    final known = notes.isEmpty
        ? '(none yet)'
        : notes.take(UserMemory.promptFacts).map((f) => '- $f').join('\n');
    return [
      {
        'role': 'system',
        'content':
            'You write short, specific titles for conversations and keep '
            'short long-term notes about the user. You never invent or '
            'infer.',
      },
      {
        'role': 'user',
        'content':
            '${conversation.substring(0, conversation.indexOf('\n\n'))}\n\n'
            'Notes about the user so far:\n$known\n\n'
            'First, write a title of 2 to 6 words naming the topic of this '
            "conversation, in the language of the user's message: no "
            'quotes, no full stop.\n'
            'Then the notes, from what the user wrote only:\n'
            '"""$question"""\n'
            '${UserMemory.extractionRules}\n\n'
            'Reply in exactly this form:\nTITLE: <the title>\nNOTES:\n'
            '<NONE, or the note lines>',
      },
    ];
  }

  /// The title and the notes part of a [titleAndNotesMessages] reply.
  static ({String? title, String notes}) splitTitleAndNotes(String raw) {
    final text = raw.replaceAll(
      RegExp(r'<think>[\s\S]*?(?:</think>|$)', caseSensitive: false),
      '',
    );
    final cut = RegExp(
      r'^[\s*#_]*notes[\s*_]*:[*_]*',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    final head = cut == null ? text : text.substring(0, cut.start);
    return (
      title: parseTitle(head),
      notes: cut == null ? 'NONE' : text.substring(cut.end),
    );
  }

  /// The title in a model's reply, or null when it wrote nothing usable:
  /// the first line, without quotes, Markdown, a "Title:" label, emoji
  /// or a full stop; at most eight words.
  static String? parseTitle(String raw) {
    final text = raw.replaceAll(
      RegExp(r'<think>[\s\S]*?(?:</think>|$)', caseSensitive: false),
      '',
    );
    final line = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    var t = line
        .replaceFirst(
          RegExp(
            r'^(?:#+\s*|\*\*)?(?:title|titre|t[íi]tulo)\s*:\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[*_`#]'), '')
        .replaceAll(RegExp(r'^["“”«»‘’\x27\s]+|["“”«»‘’\x27\s]+$'), '')
        .replaceAll(RegExp(r'[.。!]+$'), '')
        .replaceAll(
          RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final words = t.split(' ');
    if (words.length > 8) t = words.take(8).join(' ');
    if (t.length > 60) t = t.substring(0, 60).trimRight();
    if (t.length < 2) return null;
    return t;
  }
}
