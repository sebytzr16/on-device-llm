import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/data/storage/model_file_leases.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_recommendations_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  final String root;
  _Paths(this.root);
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

// Sampling discovery is independent of split-file storage. Keep the seed's
// background reader from holding a Windows file handle during test cleanup.
class _Recommendations extends ModelRecommendationsNotifier {
  @override
  Future<void> learnFromFile(ModelInfo m, {bool force = false}) async {}
}

class _UnresolvableDirectory implements Directory {
  final Directory directory;
  _UnresolvableDirectory(this.directory);

  @override
  String get path => directory.path;

  @override
  Future<Directory> create({bool recursive = false}) =>
      directory.create(recursive: recursive);

  @override
  Future<String> resolveSymbolicLinks() async =>
      throw FileSystemException('Cannot resolve models root', path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, source, models;
  late AppDatabase db;
  late ProviderContainer container;
  late PathProviderPlatform originalPaths;
  var available = 1 << 40;
  const desktop = MethodChannel('ondevice_llm/desktop');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('split-models-');
    source = await Directory(p.join(root.path, 'source')).create();
    models = await Directory(p.join(root.path, 'models')).create();
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    DesktopHost.active = true;
    available = 1 << 40;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          desktop,
          (call) async => call.method == 'availableBytes' ? available : null,
        );
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        modelRecommendationsProvider.overrideWith(_Recommendations.new),
      ],
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(desktop, null);
    container.dispose();
    await db.close();
    PathProviderPlatform.instance = originalPaths;
    DesktopHost.active = false;
    await root.delete(recursive: true);
  });
  // Minimal, valid GGUF v3 headers with different payloads for each part.
  List<int> bytes(int part) => [
    71,
    71,
    85,
    70,
    3,
    0,
    0,
    0,
    ...List.filled(16, 0),
    ...List.filled(part * 10, part),
  ];
  Future<List<File>> weights(Directory dir, {int count = 3}) async => [
    for (var i = 1; i <= count; i++)
      await File(
        p.join(dir.path, 'model-Q4_K_M-0000$i-of-00003.gguf'),
      ).writeAsBytes(bytes(i)),
  ];
  Future<ModelManagerNotifier> manager() async {
    final notifier = container.read(modelManagerProvider.notifier);
    await notifier.ready;
    return notifier;
  }

  test(
    'importing any shard copies all parts and the paired vision projector',
    () async {
      final sources = await weights(source);
      final projector = await File(
        p.join(source.path, 'mmproj-model-F16.gguf'),
      ).writeAsBytes(bytes(1));
      final notifier = await manager();
      await notifier.importFile(sources[1].path, ModelFamily.qwen);
      expect(container.read(modelManagerProvider).error, isNull);
      final row = (await db.allModels()).singleWhere(
        (r) => r.id.startsWith('local-'),
      );
      final hash = sha256.convert(bytes(1)).toString().substring(0, 20);
      expect(row.fileName, 'local-$hash-00001-of-00003.gguf');
      expect(row.localPath, p.join(models.path, row.fileName));
      expect(
        row.sizeBytes,
        bytes(1).length + bytes(2).length + bytes(3).length,
      );
      final imported = await ModelStorage.ggufFilesBeside(row.localPath!);
      for (var i = 0; i < 3; i++) {
        expect(await imported[i].readAsBytes(), bytes(i + 1));
        expect(await sources[i].exists(), true);
      }
      final vision = VisionProjector.fromJson(jsonDecode(row.projectorJson!));
      expect(
        await File(p.join(models.path, vision.fileName)).readAsBytes(),
        await projector.readAsBytes(),
      );
      // A repeat import from another part addresses the same first-part hash.
      await notifier.importFile(sources[2].path, ModelFamily.qwen);
      expect(
        (await db.allModels()).where((r) => r.id.startsWith('local-')),
        hasLength(1),
      );
    },
  );

  test(
    'importing a file inside a managed models subfolder stays in place',
    () async {
      final sub = await Directory(p.join(models.path, 'sub')).create();
      final single = await File(
        p.join(sub.path, 'single.gguf'),
      ).writeAsBytes(bytes(1));
      final notifier = await manager();
      await notifier.importFile(single.path, ModelFamily.qwen);
      expect(container.read(modelManagerProvider).error, isNull);
      final hash = sha256.convert(bytes(1)).toString().substring(0, 20);
      final row = (await db.allModels()).singleWhere(
        (r) => r.id.startsWith('local-'),
      );
      // In place: localPath is the original file, its own name is kept
      // (audit 2026-11-20 P1-3), and nothing is copied or renamed.
      expect(row.localPath, single.path);
      expect(row.fileName, 'single.gguf');
      expect(await File(single.path).exists(), true);
      expect(
        await File(p.join(models.path, 'local-$hash.gguf')).exists(),
        false,
      );
      // Remove deletes the file the row points at, not the same-named file
      // a basename lookup would pick under the models root.
      final decoy = await File(
        p.join(models.path, 'single.gguf'),
      ).writeAsBytes(bytes(2));
      await Future<void>.delayed(Duration.zero);
      final info = container
          .read(modelManagerProvider)
          .catalog
          .singleWhere((r) => r.id == row.id);
      await notifier.deleteModel(info);
      expect(await File(single.path).exists(), false);
      expect(await decoy.exists(), true);
      expect(await db.getModel(row.id), isNull);
    },
  );

  test(
    'an in-place split import keeps the real part names and deletes them',
    () async {
      final sources = await weights(models);
      final notifier = await manager();
      await notifier.importFile(sources[1].path, ModelFamily.qwen);
      expect(container.read(modelManagerProvider).error, isNull);
      final row = (await db.allModels()).singleWhere(
        (r) => r.id.startsWith('local-'),
      );
      // The row names the file it points at, part one of the real set.
      expect(row.fileName, 'model-Q4_K_M-00001-of-00003.gguf');
      expect(row.localPath, sources.first.path);
      await Future<void>.delayed(Duration.zero);
      final info = container
          .read(modelManagerProvider)
          .catalog
          .singleWhere((r) => r.id == row.id);
      await notifier.deleteModel(info);
      for (final source in sources) {
        expect(await source.exists(), false);
      }
      expect(await db.getModel(row.id), isNull);
    },
  );

  test('missing import shard gives a filename and copies nothing', () async {
    final sources = await weights(source, count: 2);
    final notifier = await manager();
    await notifier.importFile(sources[1].path, ModelFamily.qwen);
    expect(
      container.read(modelManagerProvider).error,
      contains('Missing split GGUF part: model-Q4_K_M-00003-of-00003.gguf'),
    );
    expect(models.listSync(), isEmpty);
    expect(
      (await db.allModels()).where((r) => r.id.startsWith('local-')),
      isEmpty,
    );
  });

  test('import checks capacity for the entire split set', () async {
    final sources = await weights(source);
    final notifier = await manager();
    available = 128 * 1024 * 1024 + bytes(1).length + 1;
    await notifier.importFile(sources.first.path, ModelFamily.qwen);
    expect(
      container.read(modelManagerProvider).error,
      contains('Not enough free storage'),
    );
    expect(models.listSync(), isEmpty);
  });

  test(
    'orphan scan adopts only part one with the sum and ignores incomplete sets',
    () async {
      final sources = await weights(models);
      await File(
        p.join(models.path, 'incomplete-00001-of-00002.gguf'),
      ).writeAsBytes(bytes(1));
      await manager();
      final rows = (await db.allModels()).where((r) => r.isDownloaded).toList();
      expect(rows, hasLength(1));
      expect(rows.single.localPath, sources.first.path);
      expect(rows.single.displayName, 'model');
      expect(
        rows.single.sizeBytes,
        bytes(1).length + bytes(2).length + bytes(3).length,
      );
    },
  );

  test(
    'deleting an in-place import keeps its own projector, not the one under the root',
    () async {
      final sub = await Directory(p.join(models.path, 'vision')).create();
      final single = await File(
        p.join(sub.path, 'vision-model.gguf'),
      ).writeAsBytes(bytes(1));
      final beside = await File(
        p.join(sub.path, 'mmproj-vision-model.gguf'),
      ).writeAsBytes(bytes(2));
      // A same-named projector in the models root belongs to another model:
      // it must survive, and the one beside the weights must go.
      final decoy = await File(
        p.join(models.path, 'mmproj-vision-model.gguf'),
      ).writeAsBytes(bytes(3));
      final notifier = await manager();
      await notifier.importFile(single.path, ModelFamily.qwen);
      expect(container.read(modelManagerProvider).error, isNull);
      final row = (await db.allModels()).singleWhere(
        (r) => r.id.startsWith('local-'),
      );
      expect(row.localPath, single.path);
      final vision = VisionProjector.fromJson(jsonDecode(row.projectorJson!));
      expect(vision.fileName, 'mmproj-vision-model.gguf');
      await Future<void>.delayed(Duration.zero);
      final info = container
          .read(modelManagerProvider)
          .catalog
          .singleWhere((r) => r.id == row.id);
      await notifier.deleteModel(info);
      expect(await beside.exists(), false);
      expect(await decoy.exists(), true);
      expect(await single.exists(), false);
      expect(await db.getModel(row.id), isNull);
    },
  );

  test(
    'a lease on a same-named file under the root does not block an in-place removal',
    () async {
      final sub = await Directory(p.join(models.path, 'pinned')).create();
      final single = await File(
        p.join(sub.path, 'pinned.gguf'),
      ).writeAsBytes(bytes(1));
      final notifier = await manager();
      await notifier.importFile(single.path, ModelFamily.qwen);
      expect(container.read(modelManagerProvider).error, isNull);
      final row = (await db.allModels()).singleWhere(
        (r) => r.id.startsWith('local-'),
      );
      await Future<void>.delayed(Duration.zero);
      final info = container
          .read(modelManagerProvider)
          .catalog
          .singleWhere((r) => r.id == row.id);
      final decoy = await File(
        p.join(models.path, 'pinned.gguf'),
      ).writeAsBytes(bytes(2));
      // The decoy is another model's file; leasing it must not protect (or
      // block) the row that points inside the subfolder (audit 2026-11-20
      // P2-3).
      final lease = ModelFileLeases.instance.acquire([
        decoy.path,
      ], owner: 'server pool');
      addTearDown(lease.release);
      await notifier.deleteModel(info);
      expect(await single.exists(), false);
      expect(await decoy.exists(), true);
    },
  );

  test(
    'removing a missing imported projector keeps the same-named file',
    () async {
      final sub = await Directory(p.join(models.path, 'vision')).create();
      final single = await File(
        p.join(sub.path, 'vision.gguf'),
      ).writeAsBytes(bytes(1));
      final name = 'mmproj-vision.gguf';
      final beside = await File(p.join(sub.path, name)).writeAsBytes(bytes(2));
      final notifier = await manager();
      await notifier.importFile(single.path, ModelFamily.qwen);
      await beside.delete();
      final decoy = await File(
        p.join(models.path, name),
      ).writeAsBytes(bytes(2));
      final partial = await File('${beside.path}.part').writeAsBytes(bytes(3));
      final row = (await db.allModels()).singleWhere(
        (r) => r.localPath == single.path,
      );
      await Future<void>.delayed(Duration.zero);
      final info = container
          .read(modelManagerProvider)
          .catalog
          .singleWhere((m) => m.id == row.id);
      await notifier.deleteModel(info);
      expect(await decoy.exists(), isTrue);
      expect(await partial.exists(), isFalse);
      expect(await db.getModel(row.id), isNull);
    },
  );

  test('an unresolvable managed root prevents adoption and deletion', () async {
    // The file appears after start-up, so the start-up orphan scan (which runs
    // outside the overrides below) cannot adopt it first.
    final notifier = await manager();
    final sub = await Directory(p.join(models.path, 'unverified')).create();
    final single = await File(
      p.join(sub.path, 'model.gguf'),
    ).writeAsBytes(bytes(1));
    final zone = Zone.current;
    await IOOverrides.runZoned(
      () async {
        await notifier.importFile(single.path, ModelFamily.qwen);
        expect(container.read(modelManagerProvider).error, isNull);
        final row = (await db.allModels()).singleWhere(
          (r) => r.id.startsWith('local-'),
        );
        expect(row.localPath, isNot(single.path));
        expect(await File(row.localPath!).exists(), isTrue);
        await notifier.deleteModel(
          ModelInfo(
            id: 'unverified',
            displayName: 'Unverified',
            fileName: 'model.gguf',
            sizeBytes: bytes(1).length,
            family: ModelFamily.qwen,
            quantization: ModelQuantization.unknown,
            isDownloaded: true,
            localPath: single.path,
          ),
        );
        expect(await single.exists(), isTrue);
      },
      createDirectory: (path) => p.equals(path, models.path)
          ? _UnresolvableDirectory(models)
          : zone.run(() => Directory(path)),
    );
  });

  test(
    'removing a row recorded outside the models folders keeps its file',
    () async {
      final outside = await File(
        p.join(source.path, 'legacy.gguf'),
      ).writeAsBytes(bytes(1));
      final notifier = await manager();
      // A row that points outside the library (an older import through a
      // junction, say) must not let Remove delete the user's own file (audit
      // 2026-11-20 P1-3).
      await notifier.deleteModel(
        ModelInfo(
          id: 'legacy',
          displayName: 'legacy',
          fileName: 'legacy.gguf',
          sizeBytes: bytes(1).length,
          family: ModelFamily.qwen,
          quantization: ModelQuantization.q4_k_m,
          isDownloaded: true,
          localPath: outside.path,
        ),
      );
      expect(await outside.exists(), true);
    },
  );

  test(
    'deleting an imported set removes all managed parts and leaves sources and other sets',
    () async {
      final sources = await weights(source);
      final notifier = await manager();
      await notifier.importFile(sources.last.path, ModelFamily.qwen);
      await Future<void>.delayed(Duration.zero);
      final info = container
          .read(modelManagerProvider)
          .catalog
          .singleWhere((r) => r.id.startsWith('local-'));
      final files = await ModelStorage.ggufFilesBeside(info.localPath!);
      for (final f in files) {
        await File('${f.path}.part').writeAsString('partial');
      }
      final other = await File(
        p.join(models.path, 'another-00002-of-00003.gguf'),
      ).writeAsBytes(bytes(2));
      await notifier.deleteModel(info);
      for (final f in files) {
        expect(await f.exists(), false);
        expect(await File('${f.path}.part').exists(), false);
      }
      expect(await other.exists(), true);
      for (final f in sources) {
        expect(await f.exists(), true);
      }
      await expectLater(
        ModelStorage.delete('../source/model-Q4_K_M-00001-of-00003.gguf'),
        throwsFormatException,
      );
    },
  );

  test('v15 libraries upgrade with nullable split manifests', () async {
    final path = File(p.join(root.path, 'migration.sqlite'));
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(path));
    await db.allModels();
    await db.customStatement('ALTER TABLE models DROP COLUMN parts_json');
    await db.customStatement('PRAGMA user_version = 15');
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(path));
    await db.upsertModel(
      ModelsCompanion.insert(
        id: 'split',
        displayName: 'split',
        fileName: 'split-00001-of-00002.gguf',
        sizeBytes: 200,
        family: 'qwen',
        quantization: 'q4_k_m',
      ),
    );
    expect((await db.getModel('split'))!.partsJson, isNull);
    final columns = await db.customSelect('PRAGMA table_info(models)').get();
    expect(columns.any((r) => r.read<String>('name') == 'parts_json'), true);
  });

  test('split download manifests survive a model row round trip', () async {
    final notifier = await manager();
    final repo = HfRepoFiles(
      repo: 'publisher/model',
      revision: 'pinned',
      license: 'test',
      files: [
        for (var i = 1; i <= 2; i++)
          HfFile(
            name: 'Q4/model-0000$i-of-00002.gguf',
            size: i * 100,
            sha256: '$i' * 64,
          ),
      ],
    );
    final info = HuggingFace.modelFor(repo, repo.files.first, ModelFamily.qwen);
    await notifier.save(info);
    await Future<void>.delayed(Duration.zero);
    final saved = container
        .read(modelManagerProvider)
        .catalog
        .singleWhere((r) => r.id == info.id);
    expect(
      saved.parts.map((p) => p.toJson()),
      info.parts.map((p) => p.toJson()),
    );
    expect(saved.sizeBytes, 300);
  });
}
