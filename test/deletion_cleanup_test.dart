import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ondevice_llm/core/storage/staging_cleanup.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/attachments/domain/document_passages.dart';
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';
import 'package:ondevice_llm/features/chat/domain/deletion_cleanup.dart';
import 'package:ondevice_llm/features/chat/domain/export/document_draft_store.dart';
import 'package:ondevice_llm/features/chat/domain/message_deletion.dart';
import 'package:ondevice_llm/features/knowledge/document_embedding_cache.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_embedder.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';

class _Paths extends PathProviderPlatform {
  final String support, documents;
  _Paths(this.support, this.documents);
  @override
  Future<String?> getApplicationSupportPath() async => support;
  @override
  Future<String?> getApplicationDocumentsPath() async => documents;
}

class _FakeEmbedder extends TextEmbedder {
  @override
  String get modelId => 'fake-embedding:1';
  @override
  Future<List<Float32List>?> embedDocuments(List<String> texts) async => [
    for (final _ in texts) Float32List.fromList([1, 0]),
  ];
  @override
  Future<List<Float32List>?> embedQueries(List<String> texts) async => [
    for (final _ in texts) Float32List.fromList([1, 0]),
  ];
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, documents, support;
  late PathProviderPlatform previousPaths;
  late AppDatabase db;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('deletion-cleanup-');
    documents = await Directory(p.join(root.path, 'documents')).create();
    support = await Directory(p.join(root.path, 'support')).create();
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path, documents.path);
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  Future<Attachment> storedFile(String name) async {
    final dir = await AttachmentStore.directory();
    final file = File(p.join(dir.path, '$name.txt'));
    await file.writeAsString(name);
    return Attachment(
      id: name,
      kind: AttachmentKind.document,
      name: '$name.txt',
      mime: 'text/plain',
      path: file.path,
      sizeBytes: name.length,
    );
  }

  Future<void> chat(String id) => db.upsertChat(
    ChatsCompanion.insert(
      id: id,
      title: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );

  Future<void> message(
    String chatId,
    String id, {
    List<Attachment> attachments = const [],
    int sequence = 0,
  }) => db.insertMessage(
    MessagesCompanion.insert(
      id: id,
      chatId: chatId,
      role: 'user',
      content: 'turn $id',
      timestamp: DateTime(2026),
      sequence: sequence,
      attachmentsJson: drift.Value(
        jsonEncode([for (final a in attachments) a.toJson()]),
      ),
    ),
  );

  Future<List<File>> cacheFiles() async {
    final dir = Directory(p.join(support.path, 'document_embeddings'));
    if (!await dir.exists()) return const [];
    return dir
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();
  }

  test('S13/S14: deleting a chat removes only the files and derived data '
      'it owns', () async {
    await chat('c1');
    await chat('c2');
    final shared = await storedFile('shared');
    final exclusive = await storedFile('exclusive');
    final draftOnly = await storedFile('draft-only');
    final other = await storedFile('other');
    await message('c1', 'm1', attachments: [shared, exclusive]);
    await message('c2', 'm2', attachments: [shared, other], sequence: 1);

    final drafts = ChatDraftStore();
    await drafts.save(
      'c1',
      ChatDraft(text: 'unsent', attachments: [draftOnly]),
    );
    await drafts.save('c2', ChatDraft(text: 'other', attachments: [other]));
    final revisions = DocumentDraftStore(drafts: drafts);
    await revisions.save('c1', 'report', 'Chat one revision');
    await revisions.save('c2', 'report', 'Chat two revision');

    Future<List<Float32List>?> compute() async => [
      Float32List.fromList([1, 0]),
    ];
    final cache = DocumentEmbeddingCache();
    await cache.vectors(
      'model',
      ['chunk'],
      compute,
      owner: DocumentEmbeddingCache.chatOwner('c1'),
    );
    await cache.vectors(
      'model',
      ['chunk'],
      compute,
      owner: DocumentEmbeddingCache.chatOwner('c2'),
    );
    expect(await cacheFiles(), hasLength(2));

    await DeletionCleanup.deleteChat(db, 'c1');

    expect(await File(shared.path).exists(), isTrue);
    expect(await File(exclusive.path).exists(), isFalse);
    expect(await File(draftOnly.path).exists(), isFalse);
    final keys = await drafts.keys();
    expect(keys, isNot(contains('c1')));
    expect(keys, isNot(contains('desktop:c1')));
    expect(keys, contains('c2'));
    expect(await revisions.read('c1', 'report'), isEmpty);
    expect(await revisions.read('c2', 'report'), hasLength(1));
    // The surviving cache file belongs to c2: deleting that owner empties it.
    await cache.deleteOwner(DocumentEmbeddingCache.chatOwner('c2'));
    expect(await cacheFiles(), isEmpty);
    expect(await db.getChat('c1'), isNull);
    expect(await db.getMessages('c1'), isEmpty);
    expect(await db.getMessages('c2'), hasLength(1));
  });

  test('S13: a deleted turn keeps its files until Undo closes, then drops '
      'only the unreferenced ones', () async {
    await chat('c1');
    final shared = await storedFile('turn-shared');
    final exclusive = await storedFile('turn-exclusive');
    await message('c1', 'm1', attachments: [shared, exclusive]);
    await message('c1', 'm2', attachments: [shared], sequence: 1);

    final deletion = (await MessageDeletion.delete(db, 'c1', 'm1'))!;
    expect(deletion.undone, isFalse);
    expect(await File(exclusive.path).exists(), isTrue);
    expect(await deletion.purgeAttachments(db), 1);
    expect(await File(exclusive.path).exists(), isFalse);
    expect(await File(shared.path).exists(), isTrue);

    final undone = (await MessageDeletion.delete(db, 'c1', 'm2'))!;
    expect(await undone.undo(db), isTrue);
    expect(await undone.purgeAttachments(db), 0);
    expect(await File(shared.path).exists(), isTrue);
  });

  test('S13/S14: removing a knowledge document drops its original, derived '
      'audio and vectors', () async {
    final store = KnowledgeStore(db);
    final doc = await store.import(
      collection: 'Manuals',
      name: 'manual.txt',
      bytes: _bytes(
        'Boiler manual.\n'
        '${'The pressure gauge reads between one and two bar when cold. ' * 30}',
      ),
    );
    final original = (await store.original(doc))!;
    final chunks = await db.select(db.knowledgeChunks).get();
    expect(chunks, isNotEmpty);
    await db.storeKnowledgeVectors({
      chunks.first.id: Uint8List.fromList([0, 0, 0, 0]),
    }, 'model');
    final derived = File(
      p.join((await AttachmentStore.directory()).path, '${doc.id}.audio.wav'),
    );
    await derived.writeAsString('audio');

    await store.remove(doc.id);

    expect(await original.exists(), isFalse);
    expect(await derived.exists(), isFalse);
    expect(await db.select(db.knowledgeChunks).get(), isEmpty);
    expect(await db.knowledgeDocsIn('Manuals'), isEmpty);
  });

  test('S13/S14: deleting a project collection removes its documents and '
      'originals but keeps other collections', () async {
    final store = KnowledgeStore(db);
    final one = await store.import(
      collection: 'ProjectX',
      name: 'one.txt',
      bytes: _bytes('First project document. ${'Detail. ' * 40}'),
    );
    final two = await store.import(
      collection: 'ProjectX',
      name: 'two.txt',
      bytes: _bytes('Second project document. ${'Detail. ' * 40}'),
    );
    final kept = await store.import(
      collection: 'Keep',
      name: 'keep.txt',
      bytes: _bytes('Unrelated library document. ${'Detail. ' * 40}'),
    );
    final originals = [
      (await store.original(one))!,
      (await store.original(two))!,
    ];
    final keptOriginal = (await store.original(kept))!;

    await DeletionCleanup.deleteKnowledgeCollection(db, 'ProjectX');

    expect(await db.knowledgeDocsIn('ProjectX'), isEmpty);
    for (final file in originals) {
      expect(await file.exists(), isFalse);
    }
    expect(await keptOriginal.exists(), isTrue);
    expect(await db.knowledgeDocsIn('Keep'), hasLength(1));
  });

  test('S14/S15: cached vectors are owner-scoped and a memory-only cache '
      'writes nothing', () async {
    Future<List<Float32List>?> compute() async => [
      Float32List.fromList([1, 0]),
    ];
    final persistent = DocumentEmbeddingCache();
    await persistent.vectors('m', ['a'], compute, owner: 'chat:one');
    await persistent.vectors('m', ['a'], compute, owner: 'chat:two');
    expect(await cacheFiles(), hasLength(2));
    await persistent.deleteOwner('chat:one');
    expect(await cacheFiles(), hasLength(1));
    await persistent.deleteOwner('chat:two');
    expect(await cacheFiles(), isEmpty);

    final memory = DocumentEmbeddingCache.memoryOnly();
    expect(await memory.vectors('m', ['a'], compute), isNotNull);
    expect(await cacheFiles(), isEmpty);
  });

  test(
    'S15: temporary document fitting uses the memory-only vector cache',
    () async {
      final text = [
        for (var i = 0; i < 40; i++)
          'Section $i\n${'Detail about topic ${i % 3}. ' * 40}',
      ].join('\n\n');
      final embedder = _FakeEmbedder();
      await DocumentPassages.fit(
        text,
        'What is in section 3?',
        4000,
        embedder: embedder,
        owner: DocumentPassages.cacheOwner('chat-persistent'),
      );
      expect(await cacheFiles(), hasLength(1));
      await DocumentPassages.fit(
        text,
        'What is in section 3?',
        4000,
        embedder: embedder,
        owner: DocumentPassages.cacheOwner('chat-temporary'),
        persistVectors: false,
      );
      expect(await cacheFiles(), hasLength(1));
    },
  );

  test('S16: startup sweep removes only app-owned crash staging', () async {
    final tempRoot = await Directory(p.join(root.path, 'temp')).create();
    Future<Directory> staged(Directory parent, String name) =>
        Directory(p.join(parent.path, name)).create(recursive: true);
    final working = await staged(support, 'backup-working-crash');
    final verify = await staged(support, 'backup-verify-crash');
    final pending = await staged(support, 'restore_pending');
    final upload = await staged(tempRoot, 'ondevice-workspace-crash');
    final images = await staged(tempRoot, 'desktopServe-crash');
    final unrelated = await staged(tempRoot, 'unrelated');
    await File(p.join(working.path, 'data.sqlite')).writeAsString('plain');
    await File(p.join(pending.path, 'ready')).writeAsString('1');
    await File(p.join(unrelated.path, 'keep.txt')).writeAsString('keep');

    await StagingCleanup.sweep(
      support: () async => support,
      temporary: tempRoot,
    );

    expect(await working.exists(), isFalse);
    expect(await verify.exists(), isFalse);
    expect(await upload.exists(), isFalse);
    expect(await images.exists(), isFalse);
    expect(await pending.exists(), isTrue);
    expect(await File(p.join(pending.path, 'ready')).exists(), isTrue);
    expect(
      await File(p.join(unrelated.path, 'keep.txt')).readAsString(),
      'keep',
    );
  });

  test(
    'S13: live-reference set keeps every owned attachment for a backup',
    () async {
      await chat('c1');
      final direct = await storedFile('direct');
      final draft = await storedFile('draft');
      final dirty = await storedFile('unreferenced');
      await message('c1', 'm1', attachments: [direct]);
      final drafts = ChatDraftStore();
      await drafts.save('c1', ChatDraft(text: 'draft', attachments: [draft]));

      final live = await DeletionCleanup.liveAttachmentPaths(
        db,
        drafts: drafts,
      );

      expect(live, contains(p.normalize(direct.path)));
      expect(live, contains(p.normalize(draft.path)));
      expect(live, isNot(contains(p.normalize(dirty.path))));
    },
  );
}
