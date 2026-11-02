import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../chat_draft_store.dart';
import 'chat_document.dart';

class DocumentRevision {
  final String content;
  final DateTime savedAt;
  const DocumentRevision(this.content, this.savedAt);
}

/// Saved revisions share the atomic, ordered local draft storage.
///
/// With [persist] off (temporary or unsaved chats) revisions live only in
/// this object and nothing reaches the disk or backups (P1-21).
class DocumentDraftStore {
  final ChatDraftStore drafts;
  final bool persist;
  final _memory = <String, String>{};
  Future<void> _saving = Future.value();
  DocumentDraftStore({ChatDraftStore? drafts, this.persist = true})
    : drafts = drafts ?? ChatDraftStore();

  /// The revision key for [source] as selected and redacted: another message
  /// selection or redaction gets its own revisions, so Restore can never
  /// bring back text the new choice left out (P2-37).
  static String sourceKey(String chat, ChatDocument source) =>
      '$chat:${sha256.convert(utf8.encode(source.markdown)).toString().substring(0, 16)}';

  String _key(String chat, String template) => 'document:$chat:$template';

  Future<String> _readText(String key) async =>
      persist ? (await drafts.read(key)).text : _memory[key] ?? '';

  Future<List<DocumentRevision>> read(String chat, String template) async {
    final text = await _readText(_key(chat, template));
    if (text.isEmpty) return const [];
    final raw = jsonDecode(text);
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
    final text = jsonEncode([
      for (final row in next)
        {
          'content': row.content,
          'savedAt': row.savedAt.toUtc().toIso8601String(),
        },
    ]);
    if (!persist) {
      _memory[_key(chat, template)] = text;
      return;
    }
    await drafts.save(_key(chat, template), ChatDraft(text: text));
  }
}
