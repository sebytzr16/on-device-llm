import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/local/database/app_database.dart';
import '../../domain/user_memory.dart';
import '../../domain/memory_statements.dart';

/// Stored facts, newest first.
final memoriesProvider = StreamProvider<List<Memory>>(
  (ref) => ref.watch(appDatabaseProvider).watchMemories(),
);

/// Writes: add (by hand or from extraction), edit, delete, clear.
class MemoryStore {
  final AppDatabase _db;
  Future<int>? _historyScan;
  MemoryStore(this._db);

  /// Explicit recovery action, rather than silently recreating deleted notes
  /// every time a chat is reopened. This never calls a remote or local model.
  Future<int> scanSavedChats({required bool Function() enabled}) =>
      _historyScan ??= _scanSavedChats(
        enabled,
      ).whenComplete(() => _historyScan = null);

  Future<int> _scanSavedChats(bool Function() enabled) async {
    if (!enabled()) return 0;
    final known = [
      for (final m in await all())
        if (m.expiresAt == null || m.expiresAt!.isAfter(DateTime.now()))
          m.content,
    ];
    final messages =
        await (_db.select(_db.messages)
              ..where((t) => t.role.equals('user'))
              ..orderBy([(t) => drift.OrderingTerm.asc(t.timestamp)]))
            .get();
    final candidates = <(String, Message)>[];
    for (final message in messages) {
      if (!enabled()) break;
      if (message.status.startsWith('superseded:') ||
          message.status.startsWith('alternative:') ||
          message.content.trimLeft().startsWith('/')) {
        continue;
      }
      candidates.removeWhere(
        (c) => MemoryStatements.retracts(c.$1, message.content),
      );
      for (final fact in UserMemory.explicitFacts(
        message.content,
        existing: [...known, for (final c in candidates) c.$1],
      )) {
        candidates.add((fact, message));
      }
    }
    var count = 0;
    for (final (fact, message) in candidates) {
      if (!enabled()) return count;
      if (UserMemory.parseFacts(fact, existing: await facts()).isEmpty) {
        continue;
      }
      await add(
        fact,
        sourceChatId: message.chatId,
        sourceMessageId: message.id,
        notedAt: message.timestamp,
      );
      known.add(fact);
      count++;
    }
    return count;
  }

  Future<List<String>> facts() async =>
      (await _db.allMemories()).map((m) => m.content).toList();

  /// Newest first, with when each was written.
  Future<List<Memory>> all() => _db.allMemories();

  Future<Memory> add(
    String content, {
    String? sourceChatId,
    String? sourceMessageId,
    DateTime? notedAt,
  }) async {
    final now = notedAt ?? DateTime.now();
    final id = const Uuid().v4();
    await _db.upsertMemory(
      MemoriesCompanion.insert(
        id: id,
        content: content.trim(),
        sourceChatId: drift.Value(sourceChatId),
        sourceMessageId: drift.Value(sourceMessageId),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _trim();
    return Memory(
      id: id,
      content: content.trim(),
      sourceChatId: sourceChatId,
      sourceMessageId: sourceMessageId,
      pinned: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> edit(Memory m, String content) => _db.upsertMemory(
    MemoriesCompanion(
      id: drift.Value(m.id),
      content: drift.Value(content.trim()),
      sourceChatId: drift.Value(m.sourceChatId),
      createdAt: drift.Value(m.createdAt),
      updatedAt: drift.Value(DateTime.now()),
    ),
  );

  Future<void> remove(String id) => _db.deleteMemory(id);
  Future<void> pin(Memory m, bool value) =>
      (_db.update(_db.memories)..where((t) => t.id.equals(m.id))).write(
        MemoriesCompanion(pinned: drift.Value(value)),
      );
  Future<void> expire(Memory m, DateTime? at) =>
      (_db.update(_db.memories)..where((t) => t.id.equals(m.id))).write(
        MemoriesCompanion(expiresAt: drift.Value(at)),
      );

  Future<void> clear() => _db.clearMemories();

  /// Keeps the newest [UserMemory.maxFacts].
  Future<void> _trim() async {
    final all = await _db.allMemories();
    final unpinned = all.where((m) => !m.pinned).toList();
    for (final m in unpinned.skip(
      (UserMemory.maxFacts - all.where((m) => m.pinned).length).clamp(
        0,
        UserMemory.maxFacts,
      ),
    )) {
      await _db.deleteMemory(m.id);
    }
  }
}

final memoryStoreProvider = Provider<MemoryStore>(
  (ref) => MemoryStore(ref.watch(appDatabaseProvider)),
);
