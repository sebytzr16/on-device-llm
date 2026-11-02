import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/storage/model_file_leases.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/backup/local_backup_service.dart';
import 'package:ondevice_llm/features/goals/goal_watch.dart';
import 'package:ondevice_llm/features/goals/goal_watch_store.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';

import 'local_backup_service_test.dart' show BackupPaths;
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, documents, support;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('data-safety-');
    documents = await Directory(p.join(root.path, 'documents')).create();
    support = await Directory(p.join(root.path, 'support')).create();
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = BackupPaths(support.path, documents.path);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  test(
    'leases refuse mutation until every holder releases and block new loads',
    () {
      final leases = ModelFileLeases();
      final path = p.join(root.path, 'model.gguf');
      final a = leases.acquire([path], owner: 'chat');
      final b = leases.acquire([path], owner: 'server');
      expect(() => leases.beginMutation([path]), throwsStateError);
      a.release();
      expect(leases.holders([path]), {'server'});
      expect(() => leases.beginMutation([path]), throwsStateError);
      b.release();
      final guard = leases.beginMutation([path]);
      expect(() => leases.acquire([path], owner: 'vectors'), throwsStateError);
      guard.release();
      guard.release();
      leases.acquire([path], owner: 'image generation').release();
    },
  );

  test('attachment delete refuses outside paths and traversal', () async {
    final victim = await File(
      p.join(root.path, 'keep.txt'),
    ).writeAsString('keep');
    final dir = await AttachmentStore.directory();
    for (final path in [
      victim.path,
      p.join(dir.path, '..', '..', 'keep.txt'),
    ]) {
      await AttachmentStore.delete(
        Attachment(
          id: 'bad',
          kind: AttachmentKind.document,
          name: 'bad.txt',
          mime: 'text/plain',
          path: path,
          sizeBytes: 4,
        ),
      );
    }
    expect(await victim.readAsString(), 'keep');
    expect(await AttachmentStore.ownedFile(victim.path), isNull);
  });

  test('desktop knowledge keeps originals in app attachment storage', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final desktop = DesktopHost.active;
    DesktopHost.active = true;
    addTearDown(() => DesktopHost.active = desktop);
    final store = KnowledgeStore(db);
    final bytes = Uint8List.fromList(
      utf8.encode('A useful original document.'),
    );
    final doc = await store.import(
      collection: 'Manuals',
      name: 'note.txt',
      bytes: bytes,
    );
    final file = (await store.original(doc))!;
    expect(p.dirname(file.path), (await AttachmentStore.directory()).path);
    expect(await file.readAsBytes(), bytes);
  });

  Future<Uint8List> backup({String? attachmentPath}) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1 FROM chats').get();
      await db.customStatement(
        'INSERT INTO chats (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
        ['chat', 'Restored', 1, 1],
      );
      if (attachmentPath != null) {
        await db.customStatement(
          'INSERT INTO messages (id, chat_id, role, content, timestamp, sequence, attachments_json) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            'm',
            'chat',
            'user',
            'Read',
            1,
            1,
            jsonEncode([
              {'path': attachmentPath},
            ]),
          ],
        );
      }
      return await LocalBackupService.create(db, 'test password');
    } finally {
      await db.close();
    }
  }

  test(
    'crafted backup attachment path outside its declared root is rejected',
    () async {
      final victim = await File(
        p.join(root.path, 'keep.txt'),
      ).writeAsString('keep');
      final bytes = await backup(attachmentPath: victim.path);
      await expectLater(
        LocalBackupService.stage(bytes, 'test password'),
        throwsFormatException,
      );
      expect(await victim.readAsString(), 'keep');
      expect(
        await Directory(p.join(support.path, 'restore_pending')).exists(),
        isFalse,
      );
    },
  );

  test('crafted backup draft cannot point outside app storage', () async {
    final victim = await File(
      p.join(root.path, 'keep.txt'),
    ).writeAsString('keep');
    await ChatDraftStore().save(
      'chat',
      ChatDraft(
        attachments: [
          Attachment(
            id: 'bad',
            kind: AttachmentKind.document,
            name: 'bad.txt',
            mime: 'text/plain',
            path: victim.path,
            sizeBytes: 4,
          ),
        ],
      ),
    );
    final bytes = await backup();
    await expectLater(
      LocalBackupService.stage(bytes, 'test password'),
      throwsFormatException,
    );
    expect(await victim.readAsString(), 'keep');
  });

  test(
    'backup restores goal history watches baselines variants and string lists',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('goal_history_v1', '[{"objective":"Finished"}]');
      await prefs.setString(
        'model_sampling_variants_v1',
        '{"model":{"variants":[{"name":"Precise"}]}}',
      );
      await prefs.setStringList('text_recognition_options_v1', ['en', 'fr']);
      final watch = GoalWatch(
        id: 7,
        objective: 'Price',
        query: 'Price',
        hour: 9,
        minute: 0,
        createdAt: DateTime(2026),
        last: GoalWatchSnapshot(DateTime(2026), const []),
        seen: const ['https://example.com/item'],
      );
      await GoalWatchStore.put(watch);
      final bytes = await backup();
      await prefs.clear();
      await LocalBackupService.stage(bytes, 'test password');
      await LocalBackupService.applyPendingRestore();
      final db = AppDatabase();
      try {
        await LocalBackupService.finishRestore(db);
      } finally {
        await db.close();
      }
      expect(prefs.getString('goal_history_v1'), contains('Finished'));
      expect(
        prefs.getString('model_sampling_variants_v1'),
        contains('Precise'),
      );
      expect(prefs.getStringList('text_recognition_options_v1'), ['en', 'fr']);
      expect((await GoalWatchStore.list()).single.toJson(), watch.toJson());
    },
  );

  for (final phase in [
    'journal',
    'save:data.sqlite',
    'save:data.sqlite-wal',
    'save:data.sqlite-shm',
    'save:attachments',
    'save:drafts',
    'install:data.sqlite',
    'install:attachments',
    'install:drafts',
    'installed',
    'settings',
    'complete',
  ]) {
    test('restore recovers on next start after $phase', () async {
      final bytes = await backup();
      await File(
        p.join(documents.path, 'ondevice_llm.sqlite'),
      ).writeAsString('old database');
      for (final suffix in ['-wal', '-shm']) {
        await File(
          p.join(documents.path, 'ondevice_llm.sqlite$suffix'),
        ).writeAsString('old sidecar');
      }
      await File(
        p.join((await AttachmentStore.directory()).path, 'old.txt'),
      ).writeAsString('old');
      final drafts = await Directory(p.join(support.path, 'drafts')).create();
      await File(p.join(drafts.path, 'old.json')).writeAsString('{}');
      await LocalBackupService.stage(bytes, 'test password');
      var interrupted = false;
      void crash(String point) {
        if (point == phase) {
          interrupted = true;
          throw StateError('simulated crash');
        }
      }

      try {
        await LocalBackupService.applyPendingRestore(checkpoint: crash);
        final db = AppDatabase();
        try {
          await LocalBackupService.finishRestore(db, checkpoint: crash);
        } finally {
          await db.close();
        }
      } on StateError {
        /* The next invocation is a new start. */
      }
      expect(interrupted, isTrue);
      await LocalBackupService.applyPendingRestore();
      final restored = AppDatabase();
      try {
        await LocalBackupService.finishRestore(restored);
        expect(
          (await restored.customSelect('SELECT title FROM chats').get()).single
              .read<String>('title'),
          'Restored',
        );
      } finally {
        await restored.close();
      }
      expect(
        await File(p.join(support.path, 'restore_rewrite.json')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(support.path, 'restore_previous')).exists(),
        isFalse,
      );
    });
  }

  test('interrupted staging is discarded before opening live data', () async {
    await Directory(p.join(support.path, 'restore_pending')).create();
    await LocalBackupService.applyPendingRestore();
    expect(
      await Directory(p.join(support.path, 'restore_pending')).exists(),
      isFalse,
    );
  });

  test('persisted preference keys are backed up or deliberately excluded', () {
    final known = {
      ...LocalBackupService.backedUpPreferenceKeys,
      ...LocalBackupService.excludedPreferenceKeys.keys,
    };
    final definitions = RegExp(
      r"(?:const|final)\s+(?:String\s+)?(?:_?k?\w*[Kk]ey|key|_key)\s*=\s*'([^']+)'",
      multiLine: true,
    );
    // Source inventory deliberately reads code, never preference values.
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('.g.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      if (!source.contains('package:shared_preferences/')) continue;
      for (final match in definitions.allMatches(source)) {
        expect(known, contains(match[1]), reason: file.path);
      }
    }
    expect(
      known,
      containsAll([
        'goal_history_v1',
        'goal_watches_v1',
        'model_sampling_variants_v1',
      ]),
    );
  });
}
