import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../../data/local/database/app_database.dart';
import '../../attachments/data/attachment_store.dart';
import '../../attachments/domain/attachment.dart';
import '../../knowledge/document_embedding_cache.dart';
import '../../knowledge/knowledge_store.dart';
import 'chat_draft_store.dart';
import 'export/document_draft_store.dart';

/// Removes the files and derived data a deleted chat, turn, document or
/// project owns, but only where no surviving message, composer draft or
/// knowledge document still refers to the same file (audit S13-S16).
class DeletionCleanup {
  DeletionCleanup._();
  static final _log = Logger('deletion');

  /// Deletes [chatId] with its attachment files, composer drafts, generated
  /// document revisions and cached vectors. The row removal happens even when
  /// the private file storage is unavailable; that cleanup is retried by the
  /// next deletion.
  static Future<void> deleteChat(
    AppDatabase db,
    String chatId, {
    ChatDraftStore? drafts,
    DocumentEmbeddingCache? vectors,
  }) async {
    final store = drafts ?? ChatDraftStore();
    final candidates = <String>{};
    for (final row in await db.getMessages(chatId)) {
      candidates.addAll(_pathsIn(row.attachmentsJson));
    }
    final deleted = <String>[];
    try {
      for (final key in await store.keys()) {
        if (!_belongsToChat(key, chatId)) continue;
        deleted.add(key);
        final paths = await _draftPaths(store, key);
        if (paths != null) candidates.addAll(paths);
      }
    } catch (error, stack) {
      _log.warning('Could not read chat drafts', error, stack);
    }
    await db.deleteChat(chatId);
    try {
      for (final key in deleted) {
        await store.delete(key);
      }
      await DocumentDraftStore(drafts: store).deleteForChat(chatId);
    } catch (error, stack) {
      _log.warning('Could not remove chat drafts', error, stack);
    }
    try {
      await (vectors ?? DocumentEmbeddingCache()).deleteOwner(
        DocumentEmbeddingCache.chatOwner(chatId),
      );
    } catch (error, stack) {
      _log.warning('Could not remove cached vectors', error, stack);
    }
    try {
      await deleteUnreferenced(db, candidates, drafts: store);
    } catch (error, stack) {
      _log.warning('Could not remove chat attachments', error, stack);
    }
  }

  /// Deletes a knowledge collection and its original files; the passages and
  /// their vectors go with the document rows' cascade (S13/S14).
  static Future<void> deleteKnowledgeCollection(
    AppDatabase db,
    String collection,
  ) async {
    final name = collection.trim();
    if (name.isEmpty) return;
    await KnowledgeStore(db).removeCollection(name);
  }

  /// Deletes [candidates] that no message, knowledge document or draft still
  /// references, and returns how many files went. A failed removal is left
  /// for the next attempt and is never exported by a backup.
  static Future<int> deleteUnreferenced(
    AppDatabase db,
    Iterable<String> candidates, {
    ChatDraftStore? drafts,
  }) async {
    final paths = candidates.toSet();
    if (paths.isEmpty) return 0;
    final Set<String> live;
    try {
      live = await liveAttachmentPaths(db, drafts: drafts);
    } catch (error, stack) {
      // Without the full live set nothing is provably unreferenced: keep
      // every file for the next attempt.
      _log.warning('Could not list live attachments', error, stack);
      return 0;
    }
    var deleted = 0;
    for (final path in paths) {
      try {
        final file = await AttachmentStore.ownedFile(path);
        if (file == null || live.contains(p.normalize(file.path))) continue;
        await file.delete();
        deleted++;
      } on FileSystemException catch (error, stack) {
        _log.warning(
          'Could not delete attachment ${p.basename(path)}',
          error,
          stack,
        );
      }
    }
    return deleted;
  }

  /// Normalised paths of every attachment file a live chat row, knowledge
  /// document or composer draft still owns: the explicit set a backup keeps
  /// and a deletion must respect.
  static Future<Set<String>> liveAttachmentPaths(
    AppDatabase db, {
    ChatDraftStore? drafts,
  }) async {
    final live = <String>{};
    final root = p.normalize(
      p.absolute((await AttachmentStore.directory()).path),
    );
    for (final row in await db.select(db.messages).get()) {
      live.addAll(_pathsIn(row.attachmentsJson));
    }
    for (final doc in await db.select(db.knowledgeDocs).get()) {
      final original = doc.originalFile;
      if (original != null) live.add(p.normalize(p.join(root, original)));
      // The bounded WAV a voice note's passages embed from.
      live.add(p.normalize(p.join(root, '${doc.id}.audio.wav')));
    }
    final store = drafts ?? ChatDraftStore();
    for (final key in await store.keys()) {
      final paths = await _draftPaths(store, key);
      if (paths != null) live.addAll(paths);
    }
    return live;
  }

  /// The normalised file paths a stored draft owns, or null when the draft
  /// cannot be read (an unreadable optional draft never blocks a deletion).
  static Future<List<String>?> _draftPaths(
    ChatDraftStore store,
    String key,
  ) async {
    try {
      return [
        for (final a in (await store.read(key)).attachments)
          p.normalize(p.absolute(a.path)),
      ];
    } on FormatException catch (error, stack) {
      _log.warning('Unreadable draft', error, stack);
      return null;
    } on TypeError catch (error, stack) {
      _log.warning('Unreadable draft', error, stack);
      return null;
    }
  }

  /// Composer drafts are keyed by chat id (and `desktop:` in the desktop
  /// pane); generated document revisions are removed by [DocumentDraftStore].
  static bool _belongsToChat(String key, String chatId) =>
      key == chatId || key == 'desktop:$chatId';

  static List<String> _pathsIn(String attachmentsJson) {
    try {
      return [
        for (final a in Attachment.listFromJson(jsonDecode(attachmentsJson)))
          p.normalize(p.absolute(a.path)),
      ];
    } on FormatException catch (error, stack) {
      _log.warning('Unreadable attachment list', error, stack);
      return const [];
    } on TypeError catch (error, stack) {
      _log.warning('Unreadable attachment list', error, stack);
      return const [];
    }
  }
}
