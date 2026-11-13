import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/memory/presentation/providers/memory_provider.dart';

class _HeldDatabase extends AppDatabase {
  _HeldDatabase() : super.forTesting(NativeDatabase.memory());
  Completer<void>? readGate;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  final readStarted = Completer<void>();
  int reads = 0;
  int? holdRead;

  @override
  Future<List<Memory>> allMemories() async {
    if (++reads == holdRead) {
      readStarted.complete();
      await readGate!.future;
    }
    return super.allMemories();
  }

  @override
  Future<void> upsertMemory(MemoriesCompanion row) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writeGate != null) await writeGate!.future;
    await super.upsertMemory(row);
  }
}

void main() {
  test('clear invalidates queued writes before clear SQL completes', () async {
    final db = _HeldDatabase();
    addTearDown(db.close);
    final store = MemoryStore(db);
    final generation = store.writeGeneration;
    final queued = store.addIfCurrent('old extraction', generation: generation);
    final clear = store.clear();
    expect(store.writeGeneration, greaterThan(generation));
    expect(await queued, isNull);
    await clear;
    expect(await store.facts(), isEmpty);
    expect(
      await store.addIfCurrent(
        'new extraction',
        generation: store.writeGeneration,
      ),
      isNotNull,
    );
  });

  test('clear waits behind an insert already in SQL then removes it', () async {
    final db = _HeldDatabase()..writeGate = Completer<void>();
    addTearDown(db.close);
    final store = MemoryStore(db);
    final write = store.addIfCurrent(
      'old extraction',
      generation: store.writeGeneration,
    );
    await db.writeStarted.future;
    final clear = store.clear();
    db.writeGate!.complete();
    await write;
    await clear;
    expect(await store.facts(), isEmpty);
  });

  test(
    'clear during history deduplication read prevents the next add',
    () async {
      final db = _HeldDatabase();
      addTearDown(db.close);
      final now = DateTime.now();
      await db.upsertChat(
        ChatsCompanion.insert(
          id: 'chat',
          title: 'Chat',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'message',
          chatId: 'chat',
          role: 'user',
          content: 'I am a chef.',
          timestamp: now,
          sequence: 0,
        ),
      );
      db.holdRead = 2;
      db.readGate = Completer<void>();
      final store = MemoryStore(db);
      final scan = store.scanSavedChats(enabled: () => true);
      await db.readStarted.future;
      await store.clear();
      db.readGate!.complete();
      expect(await scan, 0);
      expect(await store.facts(), isEmpty);
    },
  );
}
