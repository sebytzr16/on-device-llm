import 'dart:convert';
import 'dart:io';
import '../../../core/storage/device_encryption.dart';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../data/local/database/app_database.dart';
import '../../attachments/domain/attachment.dart';

/// Copies stored conversations without sharing attachment file ownership.
class ChatCopyRepository {
  final AppDatabase db;
  const ChatCopyRepository(this.db);

  /// A null cutoff duplicates every stored turn; a cutoff copies the
  /// conversation that led to that message, inclusive: its parent chain, so
  /// other branches and regenerated alternatives stay behind. Chats stored
  /// before branching (no parents) copy the ordered prefix. Missing cutoffs
  /// never create rows.
  Future<String> copy(
    String chatId, {
    String? throughMessageId,
    required String title,
  }) async {
    final createdFiles = <File>[];
    try {
      return await db.transaction(() async {
        final source = await db.getChat(chatId);
        if (source == null) throw StateError('Conversation no longer exists');
        final rows = await db.getMessages(chatId);
        final at = throughMessageId == null
            ? rows.length - 1
            : rows.indexWhere((m) => m.id == throughMessageId);
        if (throughMessageId != null && at < 0) {
          throw StateError('Message no longer exists');
        }
        final selected = throughMessageId == null
            ? rows
            : _ancestry(rows, rows[at]);
        final ids = {for (final row in selected) row.id: const Uuid().v4()};
        final id = const Uuid().v4();
        final now = DateTime.now();
        await db.upsertChat(
          ChatsCompanion.insert(
            id: id,
            title: title.length > 200 ? title.substring(0, 200) : title,
            modelId: Value(source.modelId),
            createdAt: now,
            updatedAt: now,
            overridesJson: Value(source.overridesJson),
          ),
        );
        for (var i = 0; i < selected.length; i++) {
          final row = selected[i];
          final attachments = Attachment.listFromJson(
            jsonDecode(row.attachmentsJson),
          );
          final copied = <Map<String, dynamic>>[];
          for (final a in attachments) {
            final attachmentId = const Uuid().v4();
            final path = p.join(
              p.dirname(a.path),
              '$attachmentId${p.extension(a.path)}',
            );
            final file = File(path);
            createdFiles.add(file);
            await DeviceEncryption.instance.write(
              file,
              await DeviceEncryption.instance.read(File(a.path)),
            );
            copied.add({...a.toJson(), 'id': attachmentId, 'path': path});
          }
          await db.insertMessage(
            row
                .copyWith(
                  id: ids[row.id]!,
                  chatId: id,
                  sequence: i,
                  parentId: Value(ids[row.parentId]),
                  // A branch's path is the new chat's live conversation.
                  status: throughMessageId == null
                      ? row.status
                      : _live(row.status),
                  attachmentsJson: jsonEncode(copied),
                )
                .toCompanion(false),
          );
        }
        return id;
      });
    } catch (_) {
      for (final file in createdFiles) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  /// The status a set-aside turn had before it was set aside:
  /// `superseded:<branch>:<status>`, `alternative:<status>` or the bare
  /// legacy forms.
  static String _live(String status) {
    if (status.startsWith('superseded')) {
      final parts = status.split(':');
      return parts.length >= 3 ? parts.sublist(2).join(':') : 'complete';
    }
    if (status == 'alternative') return 'complete';
    if (status.startsWith('alternative:')) {
      return status.substring('alternative:'.length);
    }
    return status;
  }

  static List<Message> _ancestry(List<Message> rows, Message target) {
    final at = rows.indexOf(target);
    if (rows.every((r) => r.parentId == null)) {
      return rows.take(at + 1).toList();
    }
    final byId = {for (final r in rows) r.id: r};
    final chain = <Message>[];
    final seen = <String>{};
    for (
      Message? m = target;
      m != null && seen.add(m.id);
      m = byId[m.parentId]
    ) {
      chain.add(m);
    }
    return chain.reversed.toList();
  }
}
