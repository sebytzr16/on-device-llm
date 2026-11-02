import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/memory/presentation/providers/memory_provider.dart';
import 'package:ondevice_llm/features/memory/domain/user_memory.dart';

void main() {
  test(
    'expired notes including pinned notes cannot evict older live notes',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.now();
      for (var i = 0; i < UserMemory.maxFacts; i++) {
        await db.upsertMemory(
          MemoriesCompanion.insert(
            id: 'live-$i',
            content: 'live $i',
            createdAt: now.subtract(Duration(days: i + 1)),
            updatedAt: now.subtract(Duration(days: i + 1)),
          ),
        );
      }
      for (var i = 0; i < 5; i++) {
        await db.upsertMemory(
          MemoriesCompanion.insert(
            id: 'expired-$i',
            content: 'expired',
            pinned: Value(i == 0),
            expiresAt: Value(now.subtract(const Duration(seconds: 1))),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await MemoryStore(db).add('newest');
      final notes = await db.allMemories();
      expect(notes, hasLength(UserMemory.maxFacts));
      expect(notes.where((m) => m.id.startsWith('expired')), isEmpty);
      expect(
        notes.any((m) => m.id == 'live-${UserMemory.maxFacts - 2}'),
        isTrue,
      );
      expect(
        notes.any((m) => m.id == 'live-${UserMemory.maxFacts - 1}'),
        isFalse,
      );
    },
  );
}
