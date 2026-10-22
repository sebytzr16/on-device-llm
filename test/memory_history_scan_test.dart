import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/memory/presentation/providers/memory_provider.dart';

void main() {
  test(
    'local history recovery scans every user message and keeps provenance',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final noted = DateTime(2026, 9, 27);
      await db.upsertChat(
        ChatsCompanion.insert(
          id: 'chat',
          title: 'Personal chat',
          createdAt: noted,
          updatedAt: noted,
        ),
      );
      final inputs = [
        'Hi, I am a chef. What are you?',
        "I'm a self-taught IT technician, and I'm building two apps at the moment.",
        'I live in Paris.',
        'I do not live in Paris.',
        'Translate "I am a nurse".',
      ];
      for (var i = 0; i < inputs.length; i++) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'm$i',
            chatId: 'chat',
            role: 'user',
            content: inputs[i],
            timestamp: noted.add(Duration(minutes: i)),
            sequence: i,
          ),
        );
      }
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'assistant',
          chatId: 'chat',
          role: 'assistant',
          content: 'I am a doctor.',
          timestamp: noted,
          sequence: 6,
        ),
      );
      final store = MemoryStore(db);
      expect(await store.scanSavedChats(enabled: () => false), 0);
      expect(await store.scanSavedChats(enabled: () => true), 3);
      expect(
        await store.facts(),
        containsAll([
          'The user is a chef',
          'The user is a self-taught IT technician',
          'The user is building two apps',
        ]),
      );
      expect(await store.scanSavedChats(enabled: () => true), 0);
      final memories = await store.all();
      expect(
        memories.every(
          (m) => m.sourceChatId == 'chat' && m.sourceMessageId != null,
        ),
        isTrue,
      );
      expect(memories.first.createdAt, noted.add(const Duration(minutes: 1)));
    },
  );
}
