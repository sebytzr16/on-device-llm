import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/search_terms.dart';

import 'tables/chats_table.dart';
import 'tables/knowledge_tables.dart';
import 'tables/memories_table.dart';
import 'tables/messages_table.dart';
import 'tables/models_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Chats, Messages, Models, Memories, KnowledgeDocs, KnowledgeChunks],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  static const currentSchemaVersion = 14;
  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // North Star §6.5: unique (chatId, sequence).
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_chat_seq '
        'ON messages (chat_id, sequence);',
      );
    },
    onUpgrade: (m, from, to) async {
      // v2: attachments on messages. Existing rows read back as "[]".
      if (from < 2) await m.addColumn(messages, messages.attachmentsJson);
      // v3: user memory.
      if (from < 3) await m.createTable(memories);
      // v4: chat organisation.
      if (from < 4) {
        await m.addColumn(chats, chats.pinned);
        await m.addColumn(chats, chats.folder);
        await m.addColumn(chats, chats.tags);
      }
      // v5: knowledge library.
      if (from < 5) {
        await m.createTable(knowledgeDocs);
        await m.createTable(knowledgeChunks);
      }
      // v6: semantic index on knowledge passages.
      if (from >= 5 && from < 6) {
        await m.addColumn(knowledgeChunks, knowledgeChunks.embedding);
        await m.addColumn(knowledgeChunks, knowledgeChunks.embeddingModel);
      }
      // v7: message ancestry (nested branches).
      if (from < 7) {
        await m.addColumn(messages, messages.parentId);
        await backfillParents();
      }
      // v8: per-turn run snapshot on answers.
      if (from < 8) await m.addColumn(messages, messages.runJson);
      // v9: chat-level setting overrides.
      if (from < 9) await m.addColumn(chats, chats.overridesJson);
      // v10 added a persistent web page cache (web_pages); it was disabled
      // after the release heap corruption and v14 drops it.
      if (from < 11) {
        if (from >= 5) {
          await m.addColumn(knowledgeDocs, knowledgeDocs.contentHash);
          await m.addColumn(knowledgeDocs, knowledgeDocs.extractionFormat);
          await m.addColumn(knowledgeDocs, knowledgeDocs.extractionWarning);
        }
        if (from >= 3) {
          await m.addColumn(memories, memories.sourceMessageId);
          await m.addColumn(memories, memories.pinned);
          await m.addColumn(memories, memories.expiresAt);
        }
      }
      if (from >= 5 && from < 12) {
        await m.addColumn(knowledgeDocs, knowledgeDocs.originalFile);
        await m.addColumn(knowledgeDocs, knowledgeDocs.previousVersionId);
        await m.addColumn(knowledgeDocs, knowledgeDocs.active);
        await m.addColumn(knowledgeChunks, knowledgeChunks.pageNumber);
      }
      // v14: the web page cache is gone.
      if (from < 14) await customStatement('DROP TABLE IF EXISTS web_pages;');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode=WAL;');
      // Required for ON DELETE CASCADE to actually fire.
      await customStatement('PRAGMA foreign_keys=ON;');
      await _ensureFts(freshlyCreated: details.wasCreated);
    },
  );

  /// Whether full-text search over messages is available (FTS5 compiled
  /// into this SQLite). Without it search falls back to LIKE on titles.
  bool ftsAvailable = false;

  /// FTS5 index over message text, kept in step by triggers. Built on first
  /// open after the upgrade from the existing rows; a SQLite without FTS5
  /// just leaves [ftsAvailable] false.
  Future<void> _ensureFts({required bool freshlyCreated}) async {
    try {
      final existed =
          (await customSelect(
            "SELECT count(*) AS n FROM sqlite_master WHERE type='table' AND name='messages_fts'",
          ).getSingle()).read<int>('n') >
          0;
      await customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts '
        'USING fts5(content, chat_id UNINDEXED, message_id UNINDEXED);',
      );
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS messages_fts_ai AFTER INSERT ON messages BEGIN '
        'INSERT INTO messages_fts(content, chat_id, message_id) VALUES (new.content, new.chat_id, new.id); END;',
      );
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS messages_fts_ad AFTER DELETE ON messages BEGIN '
        'DELETE FROM messages_fts WHERE message_id = old.id; END;',
      );
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS messages_fts_au AFTER UPDATE OF content ON messages BEGIN '
        'DELETE FROM messages_fts WHERE message_id = old.id; '
        'INSERT INTO messages_fts(content, chat_id, message_id) VALUES (new.content, new.chat_id, new.id); END;',
      );
      if (!existed && !freshlyCreated) {
        await customStatement(
          'INSERT INTO messages_fts(content, chat_id, message_id) '
          'SELECT content, chat_id, id FROM messages;',
        );
      }
      ftsAvailable = true;
    } catch (_) {
      ftsAvailable = false;
    }
    // Knowledge passages (FX-02): same mechanism, ranked by FTS5's bm25().
    try {
      await customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts '
        'USING fts5(text, doc_id UNINDEXED, chunk_id UNINDEXED);',
      );
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS knowledge_fts_ai AFTER INSERT ON knowledge_chunks BEGIN '
        'INSERT INTO knowledge_fts(text, doc_id, chunk_id) VALUES (new.content, new.doc_id, new.id); END;',
      );
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS knowledge_fts_ad AFTER DELETE ON knowledge_chunks BEGIN '
        'DELETE FROM knowledge_fts WHERE chunk_id = old.id; END;',
      );
      knowledgeFtsAvailable = true;
    } catch (_) {
      knowledgeFtsAvailable = false;
    }
  }

  bool knowledgeFtsAvailable = false;

  /// FTS5 query for retrieval: any word may match (OR), as a prefix; the
  /// bm25 rank decides. Recall matters more than precision here because the
  /// chat re-ranks the passages it is given.
  static String ftsAnyQuery(String text) => unicodeWords(
    text,
  ).where((w) => w.length > 1).toSet().map((w) => '"$w"*').join(' OR ');

  // ----- Knowledge library -----
  Stream<List<KnowledgeDoc>> watchKnowledgeDocs() =>
      (select(knowledgeDocs)..orderBy([
            (t) => OrderingTerm.desc(t.addedAt),
            (_) => OrderingTerm(
              expression: const CustomExpression<int>('rowid'),
              mode: OrderingMode.desc,
            ),
          ]))
          .watch();

  Future<List<KnowledgeDoc>> knowledgeDocsIn(String collection) =>
      (select(knowledgeDocs)
            ..where((t) => t.collection.equals(collection))
            ..orderBy([
              (t) => OrderingTerm.desc(t.addedAt),
              (_) => OrderingTerm(
                expression: const CustomExpression<int>('rowid'),
                mode: OrderingMode.desc,
              ),
            ]))
          .get();

  Future<List<String>> knowledgeCollections() async {
    final q = selectOnly(knowledgeDocs, distinct: true)
      ..addColumns([knowledgeDocs.collection]);
    return [for (final r in await q.get()) r.read(knowledgeDocs.collection)!]
      ..sort();
  }

  Future<void> insertKnowledgeDoc(
    KnowledgeDocsCompanion doc,
    List<KnowledgeChunksCompanion> chunks,
  ) => transaction(() async {
    await into(knowledgeDocs).insert(doc);
    await batch((b) => b.insertAll(knowledgeChunks, chunks));
  });

  Future<void> deleteKnowledgeDoc(String id) =>
      (delete(knowledgeDocs)..where((t) => t.id.equals(id))).go();

  /// Passages of [collection] still lacking a vector from [model].
  Future<List<KnowledgeChunk>> unindexedKnowledgeChunks(
    String collection,
    String model, {
    int limit = 64,
  }) async {
    final ids = [
      for (final d in await knowledgeDocsIn(collection))
        if (d.active) d.id,
    ];
    if (ids.isEmpty) return const [];
    return (select(knowledgeChunks)
          ..where(
            (t) =>
                t.docId.isIn(ids) &
                (t.embedding.isNull() | t.embeddingModel.equals(model).not()),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.docId),
            (t) => OrderingTerm.asc(t.ordinal),
          ])
          ..limit(limit))
        .get();
  }

  Future<int> countUnindexedKnowledgeChunks(
    String collection,
    String model,
  ) async {
    final ids = [
      for (final d in await knowledgeDocsIn(collection))
        if (d.active) d.id,
    ];
    if (ids.isEmpty) return 0;
    final count = knowledgeChunks.id.count();
    final q = selectOnly(knowledgeChunks)
      ..addColumns([count])
      ..where(
        knowledgeChunks.docId.isIn(ids) &
            (knowledgeChunks.embedding.isNull() |
                knowledgeChunks.embeddingModel.equals(model).not()),
      );
    return (await q.getSingle()).read(count) ?? 0;
  }

  /// How many passages of each document carry a vector from [model].
  Future<Map<String, int>> knowledgeIndexedCounts(String model) async {
    final count = knowledgeChunks.id.count();
    final q = selectOnly(knowledgeChunks)
      ..addColumns([knowledgeChunks.docId, count])
      ..where(knowledgeChunks.embeddingModel.equals(model))
      ..groupBy([knowledgeChunks.docId]);
    return {
      for (final r in await q.get())
        r.read(knowledgeChunks.docId)!: r.read(count) ?? 0,
    };
  }

  Future<void> storeKnowledgeVectors(
    Map<String, Uint8List> vectors,
    String model,
  ) => batch((b) {
    for (final e in vectors.entries) {
      b.update(
        knowledgeChunks,
        KnowledgeChunksCompanion(
          embedding: Value(e.value),
          embeddingModel: Value(model),
        ),
        where: (t) => t.id.equals(e.key),
      );
    }
  });

  /// Photo and voice-note passages lose their vectors so the indexer embeds
  /// them again, from the media itself, once the projector is on disk
  /// (until then they were indexed from their text).
  Future<void> clearKnowledgeMediaVectors() async {
    final media =
        await (select(knowledgeDocs)
              ..where((t) => t.mime.like('image/%') | t.mime.like('audio/%')))
            .map((d) => d.id)
            .get();
    if (media.isEmpty) return;
    await (update(knowledgeChunks)..where((t) => t.docId.isIn(media))).write(
      const KnowledgeChunksCompanion(
        embedding: Value(null),
        embeddingModel: Value(null),
      ),
    );
  }

  /// Every indexed passage of [collection] with its vector, for the
  /// in-memory cosine scan (collections are phone-sized, not corpora).
  Future<List<KnowledgeChunk>> knowledgeVectors(
    String collection,
    String model,
  ) async {
    final ids = [
      for (final d in await knowledgeDocsIn(collection))
        if (d.active) d.id,
    ];
    if (ids.isEmpty) return const [];
    return (select(knowledgeChunks)..where(
          (t) =>
              t.docId.isIn(ids) &
              t.embedding.isNotNull() &
              t.embeddingModel.equals(model),
        ))
        .get();
  }

  Future<void> deleteKnowledgeCollection(String collection) => (delete(
    knowledgeDocs,
  )..where((t) => t.collection.equals(collection))).go();

  /// Best passages of [collection] for [query]: FTS5 bm25 when available,
  /// otherwise a LIKE scan scored by term hits. Returns (chunk, doc) pairs,
  /// best first.
  Future<List<(KnowledgeChunk, KnowledgeDoc)>> searchKnowledge(
    String collection,
    String query, {
    int limit = 12,
  }) async {
    final docs = {
      for (final d in await knowledgeDocsIn(collection))
        if (d.active) d.id: d,
    };
    if (docs.isEmpty) return const [];
    final ids = docs.keys.toList();
    if (knowledgeFtsAvailable) {
      final q = ftsAnyQuery(query);
      if (q.isEmpty) return const [];
      try {
        final rows = await customSelect(
          'SELECT chunk_id FROM knowledge_fts WHERE knowledge_fts MATCH ? '
          'AND doc_id IN (${List.filled(ids.length, '?').join(',')}) '
          'ORDER BY bm25(knowledge_fts) LIMIT ?',
          variables: [
            Variable.withString(q),
            for (final id in ids) Variable.withString(id),
            Variable.withInt(limit),
          ],
        ).get();
        final order = [for (final r in rows) r.read<String>('chunk_id')];
        if (order.isEmpty) return const [];
        final chunks = await (select(
          knowledgeChunks,
        )..where((t) => t.id.isIn(order))).get();
        final byId = {for (final c in chunks) c.id: c};
        return [
          for (final id in order)
            if (byId[id] != null) (byId[id]!, docs[byId[id]!.docId]!),
        ];
      } catch (_) {
        // Fall through to the scan.
      }
    }
    final terms = unicodeWords(
      query,
      cjkBigrams: true,
    ).where((w) => w.length > 1).toSet();
    if (terms.isEmpty) return const [];
    final all = await (select(
      knowledgeChunks,
    )..where((t) => t.docId.isIn(ids))).get();
    final scored = <(int, KnowledgeChunk)>[];
    for (final c in all) {
      final lower = c.content.toLowerCase();
      final hits = terms.where(lower.contains).length;
      if (hits > 0) scored.add((hits, c));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final e in scored.take(limit)) (e.$2, docs[e.$2.docId]!)];
  }

  /// FTS5 query from free text: every word required, as a prefix.
  static String ftsQuery(String text) => text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '"${w.replaceAll('"', '""')}"*')
      .join(' ');

  // ----- Chats -----
  Future<List<Chat>> allChats() =>
      (select(chats)..orderBy([
            (t) => OrderingTerm.desc(t.pinned),
            (t) => OrderingTerm.desc(t.updatedAt),
          ]))
          .get();

  Stream<List<Chat>> watchAllChats() =>
      (select(chats)..orderBy([
            (t) => OrderingTerm.desc(t.pinned),
            (t) => OrderingTerm.desc(t.updatedAt),
          ]))
          .watch();

  static List<String> tagsOf(Chat c) => [
    if (c.tags.isNotEmpty)
      for (final t in (jsonDecode(c.tags) as List? ?? const []))
        if (t is String) t,
  ];

  Future<Chat?> getChat(String id) =>
      (select(chats)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertChat(ChatsCompanion c) =>
      into(chats).insertOnConflictUpdate(c);

  Future<void> deleteChat(String id) =>
      (delete(chats)..where((t) => t.id.equals(id))).go();

  /// Chats whose title matches or whose messages contain every word of
  /// [query] (FTS5 prefix search, LIKE when FTS is unavailable), pinned and
  /// newest first.
  Future<List<Chat>> searchChats(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return allChats();
    // Wildcards typed by the user only widen the match, which is acceptable.
    final needle = '%$trimmed%';
    Set<String> ids;
    if (ftsAvailable) {
      try {
        final rows = await customSelect(
          'SELECT DISTINCT chat_id FROM messages_fts WHERE messages_fts MATCH ?',
          variables: [Variable.withString(ftsQuery(trimmed))],
        ).get();
        ids = {for (final r in rows) r.read<String>('chat_id')};
      } catch (_) {
        ids = await _likeIds(needle);
      }
    } else {
      ids = await _likeIds(needle);
    }
    return (select(chats)
          ..where((t) => t.title.like(needle) | t.id.isIn(ids))
          ..orderBy([
            (t) => OrderingTerm.desc(t.pinned),
            (t) => OrderingTerm.desc(t.updatedAt),
          ]))
        .get();
  }

  /// Marks around the matched words in [searchSnippets] excerpts.
  static const matchStart = '\u0002', matchEnd = '\u0003';

  /// Target ids use the same FTS predicate as drawer snippets. Navigation
  /// opens a bounded source view instead of guessing a lazy-list offset.
  Future<Map<String, String>> searchMessageIds(String query) async {
    if (query.trim().isEmpty) return const {};
    final out = <String, String>{};
    if (ftsAvailable) {
      try {
        final rows = await customSelect(
          'SELECT chat_id, message_id FROM messages_fts WHERE messages_fts MATCH ? LIMIT 300',
          variables: [Variable.withString(ftsQuery(query.trim()))],
        ).get();
        for (final row in rows) {
          out.putIfAbsent(
            row.read<String>('chat_id'),
            () => row.read<String>('message_id'),
          );
        }
        return out;
      } catch (_) {
        /* Fall back for hosts without FTS5. */
      }
    }
    final rows =
        await (select(messages)
              ..where((t) => t.content.like('%${query.trim()}%'))
              ..limit(300))
            .get();
    for (final row in rows) {
      out.putIfAbsent(row.chatId, () => row.id);
    }
    return out;
  }

  /// A short excerpt of the first matching message per chat for [query]
  /// (drawer search), matched words wrapped in [matchStart]/[matchEnd].
  Future<Map<String, String>> searchSnippets(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const {};
    final out = <String, String>{};
    if (ftsAvailable) {
      try {
        final rows = await customSelect(
          "SELECT chat_id, snippet(messages_fts, 0, '$matchStart', '$matchEnd', '…', 12) AS s "
          'FROM messages_fts WHERE messages_fts MATCH ? LIMIT 300',
          variables: [Variable.withString(ftsQuery(trimmed))],
        ).get();
        for (final r in rows) {
          out.putIfAbsent(r.read<String>('chat_id'), () => r.read<String>('s'));
        }
        return out;
      } catch (_) {
        // LIKE below.
      }
    }
    final rows =
        await (select(messages)
              ..where((t) => t.content.like('%$trimmed%'))
              ..limit(300))
            .get();
    for (final m in rows) {
      out.putIfAbsent(m.chatId, () => excerpt(m.content, trimmed));
    }
    return out;
  }

  /// About [radius] characters either side of the first [needle] in
  /// [text], with the match marked.
  static String excerpt(String text, String needle, {int radius = 50}) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    final at = flat.toLowerCase().indexOf(needle.toLowerCase());
    if (at < 0) {
      return flat.length > radius * 2
          ? '${flat.substring(0, radius * 2)}…'
          : flat;
    }
    final from = (at - radius).clamp(0, flat.length);
    final to = (at + needle.length + radius).clamp(0, flat.length);
    return '${from > 0 ? '…' : ''}${flat.substring(from, at)}'
        '$matchStart${flat.substring(at, at + needle.length)}$matchEnd'
        '${flat.substring(at + needle.length, to)}${to < flat.length ? '…' : ''}';
  }

  Future<Set<String>> _likeIds(String needle) async {
    final q = selectOnly(messages, distinct: true)
      ..addColumns([messages.chatId])
      ..where(messages.content.like(needle));
    return {for (final r in await q.get()) r.read(messages.chatId)!};
  }

  Future<void> setPinned(String id, bool pinned) =>
      (update(chats)..where((t) => t.id.equals(id))).write(
        ChatsCompanion(pinned: Value(pinned)),
      );

  Future<void> setFolder(String id, String? folder) =>
      (update(chats)..where((t) => t.id.equals(id))).write(
        ChatsCompanion(
          folder: Value(folder?.trim().isEmpty ?? true ? null : folder!.trim()),
        ),
      );

  Future<void> setTags(String id, List<String> tags) =>
      (update(chats)..where((t) => t.id.equals(id))).write(
        ChatsCompanion(tags: Value(jsonEncode(tags))),
      );

  Future<void> renameChat(String id, String title) =>
      (update(chats)..where((t) => t.id.equals(id))).write(
        ChatsCompanion(title: Value(title.trim())),
      );

  /// Distinct folder names in use, alphabetical.
  Future<List<String>> folders() async {
    final q = selectOnly(chats, distinct: true)
      ..addColumns([chats.folder])
      ..where(chats.folder.isNotNull());
    return [for (final r in await q.get()) r.read(chats.folder)!]..sort();
  }

  // ----- Messages -----
  Stream<List<Message>> watchMessages(String chatId) =>
      (select(messages)
            ..where((t) => t.chatId.equals(chatId))
            ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
          .watch();

  Future<List<Message>> getMessages(String chatId) =>
      (select(messages)
            ..where((t) => t.chatId.equals(chatId))
            ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
          .get();

  Future<void> insertMessage(MessagesCompanion m) =>
      into(messages).insertOnConflictUpdate(m);

  Future<void> deleteMessagesForChat(String chatId) =>
      (delete(messages)..where((t) => t.chatId.equals(chatId))).go();

  /// Derives parents for rows written before schema v7 from storage order:
  /// live rows chain in sequence; the turns of one retained branch chain
  /// among themselves and hang off the last live row before them; a
  /// comparison answer hangs off the question it answers.
  Future<void> backfillParents() async {
    final all =
        await (select(messages)
              ..where((t) => t.parentId.isNull())
              ..orderBy([
                (t) => OrderingTerm.asc(t.chatId),
                (t) => OrderingTerm.asc(t.sequence),
              ]))
            .get();
    final parents = <String, String?>{};
    String? chat, lastLive, lastUser;
    final branchTail = <String, String>{};
    for (final r in all) {
      if (r.chatId != chat) {
        chat = r.chatId;
        lastLive = null;
        lastUser = null;
        branchTail.clear();
      }
      if (r.status.startsWith('alternative')) {
        parents[r.id] = lastUser;
        continue;
      }
      if (r.status.startsWith('superseded')) {
        final parts = r.status.split(':');
        final branch = parts.length >= 2 ? parts[1] : 'legacy';
        parents[r.id] = branchTail[branch] ?? lastLive;
        branchTail[branch] = r.id;
        continue;
      }
      parents[r.id] = lastLive;
      lastLive = r.id;
      if (r.role == 'user') lastUser = r.id;
    }
    await batch((b) {
      for (final e in parents.entries) {
        if (e.value == null) continue;
        b.update(
          messages,
          MessagesCompanion(parentId: Value(e.value)),
          where: (t) => t.id.equals(e.key),
        );
      }
    });
  }

  /// Partial-output checkpoint or final write for an in-flight assistant row.
  Future<void> updateMessage(String id, MessagesCompanion m) =>
      (update(messages)..where((t) => t.id.equals(id))).write(m);

  Future<void> deleteMessage(String id) =>
      (delete(messages)..where((t) => t.id.equals(id))).go();

  /// Only one generation runs per process, so any row still marked
  /// `generating` when the app starts belongs to a run the OS killed.
  /// Returns how many rows were marked.
  Future<int> markInterruptedRuns() => transaction(() async {
    final regular =
        await (update(messages)..where((t) => t.status.equals('generating')))
            .write(const MessagesCompanion(status: Value('interrupted')));
    final comparisons =
        await (update(
          messages,
        )..where((t) => t.status.equals('alternative:generating'))).write(
          const MessagesCompanion(status: Value('alternative:interrupted')),
        );
    return regular + comparisons;
  });

  // ----- Memories -----
  Stream<List<Memory>> watchMemories() => (select(
    memories,
  )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).watch();

  Future<List<Memory>> allMemories() => (select(
    memories,
  )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();

  Future<void> upsertMemory(MemoriesCompanion m) =>
      into(memories).insertOnConflictUpdate(m);

  Future<void> deleteMemory(String id) =>
      (delete(memories)..where((t) => t.id.equals(id))).go();

  Future<void> clearMemories() => delete(memories).go();

  // ----- Models -----
  Stream<List<Model>> watchAllModels() => select(models).watch();

  Future<List<Model>> allModels() => select(models).get();

  Future<Model?> getModel(String id) =>
      (select(models)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertModel(ModelsCompanion m) =>
      into(models).insertOnConflictUpdate(m);

  Future<void> deleteModel(String id) =>
      (delete(models)..where((t) => t.id.equals(id))).go();
}

LazyDatabase _openConnection() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'ondevice_llm.sqlite'));
  return NativeDatabase.createInBackground(file);
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Override in main()');
});
