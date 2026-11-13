import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/desktop/history_store.dart';

HistoryEntry entry(int time, {String kind = 'picture'}) => HistoryEntry(
  id: 'item-$time',
  createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: time)),
  data: {
    'kind': kind,
    'prompt': 'chat é gato $time',
    'modelId': 'model',
    'negativePrompt': 'blur',
    'width': 32,
    'height': 48,
    'steps': 8,
    'guidance': 1.5,
    'seed': 42,
    'durationMs': 1200,
  },
);

void main() {
  group('creation history', () {
    late Directory root;
    late CreationHistoryStore store;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('creation-history-');
      store = CreationHistoryStore(root, cap: 2);
    });
    tearDown(() async => root.delete(recursive: true));
    Future<void> save(HistoryEntry e) => store.save(
      e,
      thumbnailPng: [4, 5],
      writeMedia: (path) async {
        await File(path).writeAsBytes([1, 2, 3]);
      },
    );

    test('saves metadata and media, newest first across reopening', () async {
      await save(entry(2, kind: 'video'));
      await save(entry(1));
      final loaded = await CreationHistoryStore(root).list();
      expect(loaded.map((e) => e.id), ['item-2', 'item-1']);
      expect(loaded.first.toJson(), entry(2, kind: 'video').toJson());
      expect(store.media(loaded.first).path, endsWith('.avi'));
      expect(await store.thumbnail(loaded.first).readAsBytes(), [4, 5]);
      expect(await store.sizeBytes(), greaterThan(5));
    });
    test(
      'cap removes old media, thumbnails and sidecars; delete removes one',
      () async {
        await save(entry(1));
        await save(entry(3));
        await save(entry(2));
        expect((await store.list()).map((e) => e.id), ['item-3', 'item-2']);
        expect(await store.media(entry(1)).exists(), false);
        expect(await store.thumbnail(entry(1)).exists(), false);
        expect(await File('${root.path}/item-1.json').exists(), false);
        await store.delete(entry(3));
        expect((await store.list()).single.id, 'item-2');
        await store.delete(entry(2));
        expect(await store.sizeBytes(), 0);
      },
    );
    test(
      'serializes concurrent saves and cleans up failed media writes',
      () async {
        await Future.wait([save(entry(1)), save(entry(2)), save(entry(3))]);
        expect((await store.list()).length, 2);
        await expectLater(
          store.save(
            entry(4),
            thumbnailPng: [],
            writeMedia: (path) async {
              await File(path).writeAsBytes([1]);
              throw const FileSystemException('disk full');
            },
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await store.media(entry(4)).exists(), false);
        await save(entry(5));
        expect((await store.list()).first.id, 'item-5');
      },
    );
  });
  group('compare history database', () {
    late AppDatabase db;
    late CompareHistoryStore store;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      store = CompareHistoryStore(db, cap: 2);
    });
    tearDown(() async => db.close());
    test('saves both answers, errors and stats; sorts newest first', () async {
      final run = HistoryEntry(
        id: 'run',
        createdAt: DateTime.utc(2026),
        data: {
          'prompt': 'Question',
          'systemPrompt': 'Answer briefly',
          'mode': 'parallel',
          'sides': [
            {
              'modelId': 'a',
              'answer': 'One',
              'metrics': {
                'firstTokenMs': 15,
                'tokensPerSecond': 9.5,
                'tokens': 8,
              },
              'totalMs': 900,
              'error': null,
            },
            {
              'modelId': 'b',
              'answer': '',
              'metrics': {},
              'totalMs': null,
              'error': 'load failed',
            },
          ],
        },
      );
      await store.save(entry(1));
      await store.save(run);
      expect((await store.list()).map((e) => e.id), ['item-1', 'run']);
      expect((await store.list()).last.toJson(), run.toJson());
    });
    test('cap, delete one and clear all', () async {
      await store.save(entry(1));
      await store.save(entry(3));
      await store.save(entry(2));
      expect((await store.list()).map((e) => e.id), ['item-3', 'item-2']);
      await store.delete('item-3');
      expect((await store.list()).single.id, 'item-2');
      await store.clear();
      expect(await store.list(), isEmpty);
    });
    test('upgrades a v16 database without losing existing data', () async {
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        "INSERT INTO chats (id, title, created_at, updated_at) VALUES ('kept', 'Before upgrade', 1, 1)",
      );
      await db.customStatement('DROP TABLE compare_history');
      await db.migration.onUpgrade(db.createMigrator(), 16, 17);
      expect(
        (await db
                .customSelect("SELECT title FROM chats WHERE id = 'kept'")
                .getSingle())
            .read<String>('title'),
        'Before upgrade',
      );
      await store.save(entry(1));
      expect((await store.list()).single.id, 'item-1');
    });
    test('skips malformed rows and reports damaged ids', () async {
      await store.save(entry(1));
      await store.save(entry(2));
      // A malformed row inserted after the last save (the cap of 2 would
      // otherwise prune it as the oldest).
      await db.customStatement(
        'INSERT INTO compare_history (id, created_at, payload) VALUES (?, ?, ?)',
        ['bad-row', 0, 'not valid json'],
      );
      // The malformed row should not hide the valid ones.
      final list = await store.list();
      expect(list.map((e) => e.id), ['item-2', 'item-1']);
      // damagedIds should report the bad row.
      final damaged = await store.damagedIds();
      expect(damaged, ['bad-row']);
      // repair should remove the bad row.
      final removed = await store.repair();
      expect(removed, 1);
      expect(await store.damagedIds(), isEmpty);
      expect((await store.list()).map((e) => e.id), ['item-2', 'item-1']);
    });
  });
}
