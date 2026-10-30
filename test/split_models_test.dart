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
