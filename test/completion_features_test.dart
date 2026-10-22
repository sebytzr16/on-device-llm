import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/features/chat/domain/context_summary.dart';
import 'package:ondevice_llm/features/chat/domain/conversation_workspace.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/research_recipes.dart';
import 'package:ondevice_llm/features/chat/domain/temporary_files.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/search_misses.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/memory/presentation/providers/memory_provider.dart';
import 'package:ondevice_llm/features/chat/domain/entities/turn_run.dart';

import 'chat_test.dart' show TestEngine, TestModels, MemoryTestSettings;
import 'download_test.dart' show Adapter;
import 'local_backup_service_test.dart' show BackupPaths;

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

class _MemoryTools extends MemoryTestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(toolsEnabled: true);
}

class _LargerModels extends TestModels {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(
      catalog: [
        ModelInfo(
          id: 'test',
          displayName: 'Test 4B',
          fileName: 'test.gguf',
          sizeBytes: 100,
          parameterCountB: 4,
          family: ModelFamily.qwen,
          quantization: ModelQuantization.q4_k_m,
          isDownloaded: true,
          localPath: 'test.gguf',
        ),
      ],
      loadedModelId: 'test',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'project context follows membership changes without copying conversation rows',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = TestEngine();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          modelManagerProvider.overrideWith(TestModels.new),
          settingsProvider.overrideWith(MemoryTestSettings.new),
        ],
      );
      try {
        final workspace = container.read(
          conversationWorkspaceProvider.notifier,
        );
        await workspace.saveProject(
          name: 'First',
          instructions: 'Use metric units.',
        );
        final first = container
            .read(conversationWorkspaceProvider)
            .projects
            .single
            .id;
        final chat = container.read(chatProvider.notifier);
        chat.newChat(projectId: first);
        await chat.send('Hello');
        final id = container.read(chatProvider).chatId!;
        expect(
          container.read(conversationWorkspaceProvider).memberships[id],
          first,
        );
        expect(
          engine.receivedMessages!.first['content'],
          contains('Use metric units.'),
        );
        await workspace.saveProject(
          name: 'Second',
          instructions: 'Use imperial units.',
        );
        final second = container
            .read(conversationWorkspaceProvider)
            .projects
            .last
            .id;
        await workspace.assign([id], second);
        await chat.send('Explain length units');
        expect(
          engine.receivedMessages!.first['content'],
          contains('Use imperial units.'),
        );
        expect(
          engine.receivedMessages!.first['content'],
          isNot(contains('Use metric units.')),
        );
        expect(await db.allChats(), hasLength(1));
        expect(await db.getMessages(id), hasLength(4));
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );

  test(
    'larger local model recalls at most three notes and records their use',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = TestEngine()
        ..toolBlock =
            '```tool\n{"name":"recall","arguments":{"query":"dog"}}\n```';
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          modelManagerProvider.overrideWith(_LargerModels.new),
          settingsProvider.overrideWith(_MemoryTools.new),
        ],
      );
      try {
        for (var i = 0; i < 5; i++) {
          await container
              .read(memoryStoreProvider)
              .add('The user owns a dog named Buddy$i');
        }
        expect(
          await container
              .read(chatProvider.notifier)
              .send('What do you remember about my dog?'),
          isTrue,
        );
        expect(
          engine.receivedMessages!.first['content'],
          contains('Recall saved facts'),
        );
        expect(
          engine.toolMessages!.last['content'],
          contains('dog named Buddy'),
        );
        final run = TurnRun.decode(
          container.read(chatProvider).messages.last.runJson,
        )!;
        expect(run.metrics['memoryUsed'], hasLength(3));
        expect(run.toolTrace.single['ok'], isTrue);
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );

  test(
    'pinned memory applies to a greeting while ordinary notes stay out',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = TestEngine();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          modelManagerProvider.overrideWith(TestModels.new),
          settingsProvider.overrideWith(MemoryTestSettings.new),
        ],
      );
      try {
        final store = container.read(memoryStoreProvider);
        final pinned = await store.add('The user has a dog named Buddy');
        await store.pin(pinned, true);
        await store.add('The user has a cat named Milo');
        await container.read(chatProvider.notifier).send('Hello');
        final system = engine.receivedMessages!.first['content'] as String;
        expect(system, contains('dog named Buddy'));
        expect(system, isNot(contains('cat named Milo')));
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );

  test(
    'transient download response retries before verifying the file',
    () async {
      final dir = await Directory.systemTemp.createTemp('download-retry-test-');
      final data = [
        71,
        71,
        85,
        70,
        3,
        0,
        0,
        0,
        ...List.generate(1024, (i) => i % 256),
      ];
      var attempts = 0;
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (_) => ++attempts == 1
              ? ResponseBody.fromString('Unavailable', 503)
              : ResponseBody.fromBytes(data, 200),
        );
      final manager = DownloadManager(
        dio: dio,
        resolve: (name) async => File(p.join(dir.path, name)),
        storage: () async => null,
      );
      try {
        await manager.download(
          modelId: 'test',
          url: 'https://example.org/model.gguf',
          fileName: 'model.gguf',
          expectedSha256: sha256.convert(data).toString(),
          expectedSize: data.length,
        );
        expect(attempts, 2);
        expect(await File(p.join(dir.path, 'model.gguf')).readAsBytes(), data);
      } finally {
        manager.dispose();
        await dir.delete(recursive: true);
      }
    },
  );

  test('projects and bulk states persist without changing chat rows', () async {
    var container = ProviderContainer();
    final n = container.read(conversationWorkspaceProvider.notifier);
    await n.saveProject(
      name: 'Manuals',
      instructions: 'Keep units explicit.',
      collection: 'Library',
    );
    final id = container.read(conversationWorkspaceProvider).projects.single.id;
    await Future.wait([
      n.assign(['a', 'b'], id),
      n.setState(['a'], 'archived'),
      n.setState(['b'], 'trash'),
    ]);
    container.dispose();
    container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(conversationWorkspaceProvider.notifier).ready;
    final workspace = container.read(conversationWorkspaceProvider);
    expect(workspace.projectFor('a')!.instructions, 'Keep units explicit.');
    expect(workspace.stateOf('a'), 'archived');
    expect(workspace.stateOf('b'), 'trash');
    await container
        .read(conversationWorkspaceProvider.notifier)
        .removeProject(id);
    expect(container.read(conversationWorkspaceProvider).memberships, isEmpty);
    expect(container.read(conversationWorkspaceProvider).stateOf('b'), 'trash');
  });

  test(
    'summary requires the unchanged source prefix and serializes updates',
    () async {
      ChatMessage row(String id, String text) => ChatMessage(
        id: id,
        role: ChatRole.user,
        content: text,
        timestamp: DateTime(2026),
      );
      final first = row('a', 'My plan'), second = row('b', 'Next question');
      await Future.wait([
        ContextSummary.save('one', 'Approved plan', [first]),
        ContextSummary.save('two', 'Another plan', [first]),
      ]);
      final summary = (await ContextSummary.read('one'))!;
      expect((await ContextSummary.read('two'))!.text, 'Another plan');
      expect(summary.validFor([first, second]), isTrue);
      expect(
        summary.validFor([first.copyWith(content: 'Edited'), second]),
        isFalse,
      );
      expect(summary.validFor([second, first]), isFalse);
      expect(summary.validFor([first]), isFalse);
      await ContextSummary.remove('one');
      expect(await ContextSummary.read('one'), isNull);
      expect(await ContextSummary.read('two'), isNotNull);
    },
  );

  test(
    'temporary chat sends, regenerates and closes without saving chat or memory',
    () async {
      final dir = await Directory.systemTemp.createTemp('temporary-chat-test-');
      final original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = BackupPaths(dir.path, dir.path);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = TestEngine();
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          modelManagerProvider.overrideWith(TestModels.new),
          settingsProvider.overrideWith(MemoryTestSettings.new),
        ],
      );
      try {
        final n = c.read(chatProvider.notifier);
        n.newChat(temporary: true);
        expect(await n.send('My name is Ada'), isTrue);
        expect(c.read(chatProvider).messages, hasLength(2));
        expect(await n.regenerate(), isTrue);
        expect(await n.searchAgain(), isTrue);
        await c.read(searchMissesProvider.notifier).ready;
        expect(c.read(searchMissesProvider), isEmpty);
        expect(await db.allChats(), isEmpty);
        expect(
          await db
              .customSelect('SELECT count(*) AS n FROM memories')
              .getSingle()
              .then((r) => r.read<int>('n')),
          0,
        );
        expect(
          (engine.receivedMessages!.first['content'] as String),
          isNot(contains('Background notes')),
        );
        n.newChat();
        expect(c.read(chatProvider).temporary, isFalse);
        expect(c.read(chatProvider).messages, isEmpty);
        expect(await n.send('Hello'), isTrue);
        expect(await db.allChats(), hasLength(1));
      } finally {
        c.dispose();
        await db.close();
        // Finish serialized cleanup before removing its sandbox.
        await TemporaryFiles.clear();
        PathProviderPlatform.instance = original;
        await dir.delete(recursive: true);
      }
    },
  );

  test('temporary cleanup cannot delete a path outside attachments', () async {
    final dir = await Directory.systemTemp.createTemp('temporary-files-test-');
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = BackupPaths(dir.path, dir.path);
    try {
      final attachments = Directory(p.join(dir.path, 'attachments'))
        ..createSync();
      final saved = File(p.join(attachments.path, 'saved.txt'))
        ..writeAsStringSync('saved');
      final temp = File(p.join(attachments.path, 'temp.txt'))
        ..writeAsStringSync('private');
      final outside = File(p.join(dir.path, 'outside.txt'))
        ..writeAsStringSync('safe');
      await TemporaryFiles.remember([temp.path, outside.path]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(TemporaryFiles.key, [
        ...prefs.getStringList(TemporaryFiles.key)!,
        '../outside.txt',
      ]);
      await TemporaryFiles.clear();
      expect(await temp.exists(), isFalse);
      expect(await saved.exists(), isTrue);
      expect(await outside.exists(), isTrue);
    } finally {
      PathProviderPlatform.instance = original;
      await dir.delete(recursive: true);
    }
  });

  test(
    'knowledge retains originals, excludes old versions and restores newest remaining',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'knowledge-version-test-',
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final store = KnowledgeStore(db, null, () async => dir);
        final first = await store.import(
          collection: 'Manuals',
          name: 'guide.txt',
          bytes: _bytes('Boiler pressure is one bar.'),
        );
        final second = await store.import(
          collection: 'Manuals',
          name: 'guide.txt',
          bytes: _bytes('Boiler pressure is two bar.'),
        );
        final third = await store.import(
          collection: 'Manuals',
          name: 'guide.txt',
          bytes: _bytes('Boiler pressure is three bar.'),
        );
        expect(second.previousVersionId, first.id);
        expect(third.previousVersionId, second.id);
        expect(
          await (await store.original(first))!.readAsString(),
          'Boiler pressure is one bar.',
        );
        expect(
          (await store.search('Manuals', 'boiler pressure')).map((r) => r.url),
          ['knowledge://${third.id}'],
        );
        await store.remove(third.id);
        expect(
          (await store.docsIn('Manuals')).where((d) => d.active).single.id,
          second.id,
        );
        await store.activate(first);
        expect(
          (await store.search('Manuals', 'boiler pressure')).single.url,
          'knowledge://${first.id}',
        );
        expect(await store.docsIn('Manuals'), hasLength(2));
        await store.removeCollection('Manuals');
        expect(dir.listSync(), isEmpty);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'concurrent imports of revisions leave a single active version',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final store = KnowledgeStore(db);
      await Future.wait([
        store.import(
          collection: 'Manuals',
          name: 'guide.txt',
          bytes: _bytes('Boiler pressure is one bar.'),
        ),
        store.import(
          collection: 'Manuals',
          name: 'guide.txt',
          bytes: _bytes('Boiler pressure is two bar.'),
        ),
      ]);
      final docs = await store.docsIn('Manuals');
      expect(docs, hasLength(2));
      expect(docs.where((d) => d.active), hasLength(1));
      expect(docs.where((d) => d.previousVersionId != null), hasLength(1));
    },
  );

  test(
    'PDF provenance uses actual page markers rather than chunk ordinal',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final store = KnowledgeStore(db);
      await store.import(
        collection: 'Manuals',
        name: 'guide.pdf',
        bytes: _bytes('%PDF sample'),
        pdfText: (_) async =>
            '--- Page 4 ---\nBoiler pressure is two bar.\n--- Page 7 (OCR) ---\nReset the boiler with the red button.',
      );
      final result = await store.search('Manuals', 'reset boiler');
      expect(result.single.pageText, contains('Page 7'));
      expect(result.single.pageText, isNot(contains('Page 2')));
    },
  );

  test(
    'v11 knowledge migration preserves documents and existing chat data',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'knowledge-migration-test-',
      );
      final file = File(p.join(dir.path, 'old.sqlite'));
      var db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final doc = await KnowledgeStore(db).import(
          collection: 'Manuals',
          name: 'old.txt',
          bytes: _bytes('Old boiler guide.'),
        );
        await db.close();
        final old = sqlite3.open(file.path);
        try {
          for (final column in [
            'original_file',
            'previous_version_id',
            'active',
          ]) {
            old.execute('ALTER TABLE knowledge_docs DROP COLUMN $column');
          }
          old.execute('ALTER TABLE knowledge_chunks DROP COLUMN page_number');
          // v10-v13 kept a page cache, dropped at v14.
          old.execute('CREATE TABLE web_pages (url TEXT PRIMARY KEY)');
          old.execute('PRAGMA user_version = 11');
        } finally {
          old.close();
        }
        db = AppDatabase.forTesting(NativeDatabase(file));
        final restored = (await db.knowledgeDocsIn('Manuals')).single;
        expect(restored.id, doc.id);
        expect(restored.active, isTrue);
        expect(restored.originalFile, isNull);
        expect(
          (await KnowledgeStore(
            db,
          ).search('Manuals', 'boiler')).single.pageText,
          contains('Passage 1'),
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'primary queries retain each exact model and ignore lookalike domains',
    () {
      const question = 'compare Nikon Z30 to Sony ZV-E10 II';
      final recipe = ResearchRecipe.forQuestion(question);
      List<String> queries(List<SearchResult> results) => recipe.primaryQueries(
        question,
        results,
        urlOf: (r) => r.url,
        textOf: (r) => '${r.title} ${r.snippet}',
      );
      expect(queries([]), [
        'site:nikon.com Nikon Z30 specifications',
        'site:sony.com Sony ZV-E10 II specifications',
      ]);
      expect(
        queries(const [
          SearchResult(
            title: 'Nikon Z30 specifications',
            url: 'https://nikon.com/z30',
            snippet: '',
            rank: 1,
          ),
        ]),
        ['site:sony.com Sony ZV-E10 II specifications'],
      );
      expect(
        queries(const [
          SearchResult(
            title: 'Nikon Z30 specifications',
            url: 'https://nikon.com.evil.test/z30',
            snippet: '',
            rank: 1,
          ),
        ]),
        hasLength(2),
      );
      expect(
        queries(const [
          SearchResult(
            title: 'Sony ZV-E10 specifications',
            url: 'https://sony.com/zv-e10',
            snippet: '',
            rank: 1,
          ),
        ]),
        hasLength(2),
      );
    },
  );

  test(
    'download queue pauses a waiting request and runs only two transfers',
    () async {
      final dir = await Directory.systemTemp.createTemp('download-queue-test-');
      final bytes = [
        71,
        71,
        85,
        70,
        3,
        0,
        0,
        0,
        ...List.generate(1024, (i) => i % 256),
      ];
      final gates = <StreamController<Uint8List>>[];
      final started = Completer<void>();
      final dio = Dio()
        ..httpClientAdapter = Adapter((_) {
          final gate = StreamController<Uint8List>();
          gates.add(gate);
          if (gates.length == 2) started.complete();
          return ResponseBody(gate.stream, 200);
        });
      final manager = DownloadManager(
        dio: dio,
        resolve: (name) async => File(p.join(dir.path, name)),
        storage: () async => null,
      );
      final waiting = <DownloadStatus>[];
      final subscription = manager
          .progressStream('third')
          .listen((p) => waiting.add(p.status));
      Future<void> run(String id) => manager.download(
        modelId: id,
        url: 'https://example.org/$id',
        fileName: '$id.gguf',
        expectedSha256: sha256.convert(bytes).toString(),
        expectedSize: bytes.length,
      );
      try {
        final first = run('first'), second = run('second');
        await started.future;
        final third = run('third');
        final thirdCheck = expectLater(third, throwsA(isA<DioException>()));
        await manager.pause('third');
        await thirdCheck;
        expect(waiting, [DownloadStatus.queued, DownloadStatus.paused]);
        expect(gates, hasLength(2));
        for (final gate in gates) {
          gate.add(Uint8List.fromList(bytes));
          await gate.close();
        }
        await Future.wait([first, second]);
        expect(await File(p.join(dir.path, 'third.gguf')).exists(), isFalse);
      } finally {
        await subscription.cancel();
        manager.dispose();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'download disk preflight rejects before network or file promotion',
    () async {
      final dir = await Directory.systemTemp.createTemp('download-space-test-');
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = Adapter((_) {
          requests++;
          return ResponseBody.fromBytes([], 200);
        });
      final manager = DownloadManager(
        dio: dio,
        resolve: (name) async => File(p.join(dir.path, name)),
        storage: () async =>
            const DeviceStorage(totalBytes: 1024, availableBytes: 10),
      );
      try {
        await expectLater(
          manager.download(
            modelId: 'test',
            url: 'https://example.org/model.gguf',
            fileName: 'model.gguf',
            expectedSha256: 'a' * 64,
            expectedSize: 100,
          ),
          throwsException,
        );
        expect(requests, 0);
        expect(dir.listSync(), isEmpty);
      } finally {
        manager.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
