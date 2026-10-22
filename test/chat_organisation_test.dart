import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed(
    String id,
    String title,
    String body, {
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    await db.upsertChat(
      ChatsCompanion.insert(
        id: id,
        title: title,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm-$id',
        chatId: id,
        role: 'user',
        content: body,
        timestamp: now,
        sequence: 0,
      ),
    );
  }

  test('search results carry an excerpt with the match marked', () async {
    await seed('a', 'Trip', 'Book the ferry to Nanaimo on Friday');
    await seed('b', 'Recipes', 'Sourdough needs a long cold proof');
    final hits = await db.searchSnippets('nanaimo');
    expect(hits.keys, ['a']);
    expect(
      hits['a'],
      contains('${AppDatabase.matchStart}Nanaimo${AppDatabase.matchEnd}'),
    );
    expect(await db.searchSnippets('   '), isEmpty);
    final long = 'x' * 200;
    final cut = AppDatabase.excerpt('$long needle $long', 'needle');
    expect(cut, startsWith('…'));
    expect(cut, endsWith('…'));
    expect(cut.length, lessThan(130));
  });

  test('search finds words inside messages, not only titles', () async {
    await seed('a', 'Trip', 'Book the ferry to Nanaimo on Friday');
    await seed('b', 'Recipes', 'Sourdough needs a long cold proof');
    await seed('c', 'Ferry timetable', 'nothing');
    // Force the FTS path to be exercised when this SQLite has FTS5.
    await db.customSelect('SELECT 1').get();
    final byBody = await db.searchChats('nanaimo');
    expect(byBody.map((c) => c.id), ['a']);
    final byTitle = await db.searchChats('ferry');
    expect(byTitle.map((c) => c.id).toSet(), {'a', 'c'});
    // Every word must match; prefixes do.
    expect((await db.searchChats('cold proo')).map((c) => c.id), ['b']);
    expect(await db.searchChats('cold ferry'), isEmpty);
    // Edits are reflected.
    await db.updateMessage(
      'm-b',
      const MessagesCompanion(content: Value('Brioche instead')),
    );
    expect(await db.searchChats('sourdough'), isEmpty);
    expect((await db.searchChats('brioche')).map((c) => c.id), ['b']);
  });

  test('pinned chats lead, folders and tags round-trip', () async {
    // Drift stores DateTime at second precision.
    await seed('old', 'Old', 'x', at: DateTime(2026, 9, 1));
    await seed('new', 'New', 'y', at: DateTime(2026, 9, 2));
    expect((await db.allChats()).map((c) => c.id), ['new', 'old']);
    await db.setPinned('old', true);
    expect((await db.allChats()).map((c) => c.id), ['old', 'new']);
    await db.setFolder('new', ' Work ');
    await db.setTags('new', ['ideas', 'q4']);
    await db.renameChat('new', 'Renamed');
    final chat = (await db.getChat('new'))!;
    expect(chat.folder, 'Work');
    expect(AppDatabase.tagsOf(chat), ['ideas', 'q4']);
    expect(chat.title, 'Renamed');
    expect(await db.folders(), ['Work']);
    await db.setFolder('new', '');
    expect(await db.folders(), isEmpty);
    expect(
      AppDatabase.ftsQuery('hello "there" wo'),
      '"hello"* """there"""* "wo"*',
    );
  });
}
