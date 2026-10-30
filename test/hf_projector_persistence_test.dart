import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Manager extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'custom projector is registered as vision and kept until its last model is deleted',
    () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('hf-vision-');
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(dir.path);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelManagerProvider.overrideWith(_Manager.new),
        ],
      );
      try {
        const projector = VisionProjector(
          fileName: 'shared-mmproj.gguf',
          downloadUrl:
              'https://huggingface.co/publisher/repo/resolve/revision/mmproj.gguf',
          sha256: 'abc',
          sizeBytes: 16,
        );
        ModelInfo model(String id) => ModelInfo(
          id: id,
          displayName: id,
          fileName: '$id.gguf',
          sizeBytes: 16,
          family: ModelFamily.qwen,
          quantization: ModelQuantization.q4_k_m,
          projector: projector,
        );
        final manager = container.read(modelManagerProvider.notifier);
        final first = model('custom-first');
        final second = model('custom-second');
        await manager.save(first);
        await manager.save(second);
        final file = await ModelStorage.modelFile(projector.fileName);
        await file.writeAsBytes(List.filled(16, 0));
        await manager.refreshVision();
        expect(
          container.read(modelManagerProvider).vision,
          containsAll([first.id, second.id]),
        );
        await manager.deleteModel(first);
        expect(await file.exists(), isTrue);
        expect(await db.getModel(first.id), isNull);
        await manager.deleteModel(second);
        expect(await file.exists(), isFalse);
      } finally {
        container.dispose();
        await db.close();
        PathProviderPlatform.instance = previousPaths;
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'v14 records migrate without a projector, new projector survives reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('hf-projector-');
      final file = File('${dir.path}/models.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        await db.upsertModel(
          ModelsCompanion.insert(
            id: 'custom',
            displayName: 'Custom',
            fileName: 'model.gguf',
            sizeBytes: 100,
            family: 'qwen',
            quantization: 'q4_k_m',
          ),
        );
        await db.close();
        final old = sqlite.sqlite3.open(file.path);
        old.execute('ALTER TABLE models DROP COLUMN projector_json');
        old.execute('ALTER TABLE models DROP COLUMN parts_json');
        old.execute('PRAGMA user_version = 14');
        old.close();
        db = AppDatabase.forTesting(NativeDatabase(file));
        expect((await db.getModel('custom'))!.projectorJson, isNull);
        const projector = VisionProjector(
          fileName: 'mmproj.gguf',
          downloadUrl:
              'https://huggingface.co/publisher/repo/resolve/revision/mmproj.gguf',
          sha256: 'abc',
          sizeBytes: 900,
        );
        await (db.update(db.models)..where((t) => t.id.equals('custom'))).write(
          ModelsCompanion(projectorJson: Value(jsonEncode(projector.toJson()))),
        );
        await db.close();
        db = AppDatabase.forTesting(NativeDatabase(file));
        final saved = VisionProjector.fromJson(
          jsonDecode((await db.getModel('custom'))!.projectorJson!)
              as Map<String, dynamic>,
        );
        expect(saved.toJson(), projector.toJson());
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
