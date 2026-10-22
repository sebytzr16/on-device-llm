import 'dart:convert';
import '../chat_draft_store.dart';

class DocumentRevision {
  final String content;
  final DateTime savedAt;
  const DocumentRevision(this.content, this.savedAt);
}

/// Saved revisions share the atomic, ordered local draft storage.
class DocumentDraftStore {
  final ChatDraftStore drafts;
  Future<void> _saving = Future.value();
  DocumentDraftStore({ChatDraftStore? drafts})
    : drafts = drafts ?? ChatDraftStore();
  String _key(String chat, String template) => 'document:$chat:$template';
  Future<List<DocumentRevision>> read(String chat, String template) async {
    final draft = await drafts.read(_key(chat, template));
    if (draft.text.isEmpty) return const [];
    final raw = jsonDecode(draft.text);
    if (raw is! List) throw const FormatException('Invalid document draft.');
    return [
      for (final row in raw)
        if (row is Map && row['content'] is String && row['savedAt'] is String)
          DocumentRevision(
            row['content'] as String,
            DateTime.parse(row['savedAt'] as String),
          ),
    ];
  }

  Future<void> save(String chat, String template, String content) {
    final result = _saving.then((_) => _save(chat, template, content));
    _saving = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _save(String chat, String template, String content) async {
    if (content.trim().isEmpty) return;
    final versions = await read(chat, template);
    if (versions.isNotEmpty && versions.first.content == content) return;
    final next = [
      DocumentRevision(content, DateTime.now()),
      ...versions,
    ].take(8);
    await drafts.save(
      _key(chat, template),
      ChatDraft(
        text: jsonEncode([
          for (final row in next)
            {
              'content': row.content,
              'savedAt': row.savedAt.toUtc().toIso8601String(),
            },
        ]),
      ),
    );
  }
}
