import 'package:drift/drift.dart';

import '../../../data/local/database/app_database.dart';

/// Undo stores only the affected rows. Other turns written afterwards are never
/// replaced by an old conversation snapshot.
class MessageDeletion {
  final String chatId;
  final List<Message> removed;
  final Map<String, (Message, Message)> changed;
  bool _undone = false;
  MessageDeletion(this.chatId, this.removed, this.changed);

  static Future<MessageDeletion?> delete(
    AppDatabase db,
    String chatId,
    String messageId, {
    bool pair = false,
  }) => db.transaction(() async {
    final rows = await db.getMessages(chatId);
    final target = rows.where((r) => r.id == messageId).firstOrNull;
    if (target == null) return null;
    final question = target.role == 'user'
        ? target
        : rows
              .where((r) => r.id == target.parentId && r.role == 'user')
              .firstOrNull;
    if (pair && question == null) return null;
    final removed = pair
        ? rows
              .where(
                (r) =>
                    r.id == question!.id ||
                    r.parentId == question.id && r.role == 'assistant',
              )
              .toList()
        : [target];
    final ids = {for (final r in removed) r.id};
    Message? replacement;
    if (!pair && target.role == 'assistant') {
      replacement = rows
          .where(
            (r) =>
                r.role == 'assistant' &&
                r.parentId == target.parentId &&
                r.status.startsWith('superseded:') &&
                !ids.contains(r.id),
          )
          .lastOrNull;
    }
    final changed = <String, (Message, Message)>{};
    final before = {for (final r in rows) r.id: r};
    for (final r in rows.where((r) => !ids.contains(r.id))) {
      var next = r;
      if (r.id == replacement?.id) {
        next = next.copyWith(status: r.status.split(':').skip(2).join(':'));
      }
      if (ids.contains(r.parentId)) {
        String? parent = replacement?.id;
        if (parent == null) {
          parent = before[r.parentId]?.parentId;
          final seen = <String>{};
          while (parent != null && ids.contains(parent) && seen.add(parent)) {
            parent = before[parent]?.parentId;
          }
        }
        next = next.copyWith(parentId: Value(parent));
      }
      if (next != r) {
        changed[r.id] = (r, next);
        await db.updateMessage(r.id, next.toCompanion(false));
      }
    }
    for (final row in removed) {
      await db.deleteMessage(row.id);
    }
    return MessageDeletion(chatId, removed, changed);
  });

  Future<bool> undo(AppDatabase db) => db.transaction(() async {
    if (_undone || await db.getChat(chatId) == null) return false;
    final current = await db.getMessages(chatId);
    // Branch restoration reorders storage. An undo from an older branch must
    // not append old turns to the wrong context or overwrite that new branch.
    final occupied = {for (final r in current) r.sequence};
    for (final r in removed) {
      if (current.any((c) => c.id == r.id) || occupied.contains(r.sequence)) {
        return false;
      }
    }
    for (final e in changed.entries) {
      final now = current.where((r) => r.id == e.key).firstOrNull;
      final expected = e.value.$2;
      if (now?.parentId != expected.parentId ||
          now?.status != expected.status ||
          now?.sequence != expected.sequence) {
        return false;
      }
    }
    for (final r in removed) {
      await db.insertMessage(r.toCompanion(false));
    }
    // Questions asked since deletion can descend from a promoted old answer.
    // Once that answer is superseded again, point those questions at the
    // restored answer so the live path stays coherent.
    for (final e in changed.entries.where(
      (e) =>
          e.value.$1.role == 'assistant' &&
          e.value.$1.status.startsWith('superseded:'),
    )) {
      final restoredAnswer = removed
          .where(
            (r) => r.role == 'assistant' && r.parentId == e.value.$1.parentId,
          )
          .firstOrNull;
      if (restoredAnswer == null) continue;
      for (final row in current.where(
        (r) => r.parentId == e.key && !changed.containsKey(r.id),
      )) {
        await db.updateMessage(
          row.id,
          MessagesCompanion(parentId: Value(restoredAnswer.id)),
        );
      }
    }
    for (final e in changed.entries) {
      final now = current.where((r) => r.id == e.key).firstOrNull;
      final expected = e.value.$2;
      if (now?.parentId == expected.parentId &&
          now?.status == expected.status) {
        await db.updateMessage(
          e.key,
          MessagesCompanion(
            parentId: Value(e.value.$1.parentId),
            status: Value(e.value.$1.status),
          ),
        );
      }
    }
    _undone = true;
    return true;
  });
}
