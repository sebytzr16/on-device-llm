import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime(2026, 11, 20);

  Future<void> seedChat(AppDatabase db, {String id = 'c1'}) => db
      .into(db.chats)
      .insert(
        ChatsCompanion.insert(
          id: id,
          title: 'Chat $id',
          createdAt: at,
          updatedAt: at,
        ),
      );

  Future<void> seedMessage(
    AppDatabase db, {
    required String id,
    required int sequence,
    String? parentId,
    String chat = 'c1',
  }) => db
      .into(db.messages)
      .insert(
        MessagesCompanion.insert(
          id: id,
          chatId: chat,
          role: 'user',
          content: 'text of $id',
          timestamp: at,
          sequence: sequence,
          parentId: Value(parentId),
        ),
      );

  test(
    'a v17 database keeps every message and gains the unique index on upgrade',
    () async {
      final dir = await Directory.systemTemp.createTemp('schema-seq-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v17.sqlite'));

      // A v17 database has the same tables but no unique (chat, sequence)
      // index, so it can hold colliding turns (audit 09-1).
      final v17 = AppDatabase.forTesting(NativeDatabase(file));
      await v17.customStatement('DROP INDEX IF EXISTS idx_messages_chat_seq');
      await seedChat(v17);
      await seedMessage(v17, id: 'm1', sequence: 0);
      await seedMessage(v17, id: 'm2', sequence: 0, parentId: 'm1');
      await seedMessage(v17, id: 'm3', sequence: 1, parentId: 'm2');
      await v17.customStatement('PRAGMA user_version = 17');
      await v17.close();

      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      // Opening a v17 file runs the upgrade to v18.
      await db.customStatement('SELECT 1');

      final rows = await db.getMessages('c1');
      // No message row is deleted: ids, text and parent links all survive.
      expect(rows.map((m) => m.id), ['m1', 'm2', 'm3']);
      expect(rows.map((m) => m.content), [
        'text of m1',
        'text of m2',
        'text of m3',
      ]);
      expect(rows.firstWhere((m) => m.id == 'm2').parentId, 'm1');
      // Colliding turns are renumbered in the order they were written.
      expect(rows.map((m) => m.sequence), [0, 1, 2]);
      final version = (await db.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version');
      expect(version, AppDatabase.currentSchemaVersion);
      final indexed =
          (await db
                  .customSelect(
                    "SELECT count(*) AS n FROM sqlite_master "
                    "WHERE type='index' AND name='idx_messages_chat_seq'",
                  )
                  .getSingle())
              .read<int>('n');
      expect(indexed, 1);
      await expectLater(
        seedMessage(db, id: 'm4', sequence: 0),
        throwsA(anything),
      );
    },
  );

  test(
    'the one-pass repair renumbers each colliding chat on its own',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement('DROP INDEX IF EXISTS idx_messages_chat_seq');
      await seedChat(db);
      await seedChat(db, id: 'c2');
      await seedChat(db, id: 'c3');
      // c1: collisions at two different turns, nothing else.
      await seedMessage(db, id: 'a1', sequence: 0);
      await seedMessage(db, id: 'a2', sequence: 0);
      await seedMessage(db, id: 'a3', sequence: 2);
      await seedMessage(db, id: 'a4', sequence: 2, parentId: 'a3');
      // c2: a single colliding turn.
      await seedMessage(db, id: 'b1', sequence: 5, chat: 'c2');
      await seedMessage(db, id: 'b2', sequence: 5, chat: 'c2');
      // c3: already unique, so it keeps its numbering untouched.
      await seedMessage(db, id: 'd1', sequence: 7, chat: 'c3');

      await db.createMessageSequenceIndex();

      final c1 = await db.getMessages('c1');
      expect(c1.map((m) => m.id), ['a1', 'a2', 'a3', 'a4']);
      expect(c1.map((m) => m.sequence), [0, 1, 2, 3]);
      expect(c1.firstWhere((m) => m.id == 'a4').parentId, 'a3');
      final c2 = await db.getMessages('c2');
      expect(c2.map((m) => m.id), ['b1', 'b2']);
      expect(c2.map((m) => m.sequence), [0, 1]);
      final c3 = await db.getMessages('c3');
      expect(c3.map((m) => m.sequence), [7]);
      await expectLater(
        seedMessage(db, id: 'd2', sequence: 7, chat: 'c3'),
        throwsA(anything),
      );
      // The unique index covers every chat after the repair.
      await expectLater(
        seedMessage(db, id: 'b3', sequence: 0, chat: 'c2'),
        throwsA(anything),
      );
    },
  );

  test(
    'the repair renumbers colliding turns instead of deleting them',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement('DROP INDEX IF EXISTS idx_messages_chat_seq');
      await seedChat(db);
      await seedMessage(db, id: 'm1', sequence: 0);
      await seedMessage(db, id: 'm2', sequence: 0, parentId: 'm1');

      await db.createMessageSequenceIndex();

      final rows = await db.getMessages('c1');
      expect(rows.map((m) => m.id), ['m1', 'm2']);
      expect(rows.map((m) => m.sequence), [0, 1]);
      await expectLater(
        seedMessage(db, id: 'm3', sequence: 0),
        throwsA(anything),
      );
    },
  );
}
