import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/storage/model_folders.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/data/remote_key_store.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState();
  }
}

class _MemoryKeys implements RemoteKeyStore {
  @override
  Future<Map<String, String>> readAll() async => const {};

  @override
  Future<void> write(String profileId, String key) async {}

  @override
  Future<void> delete(String profileId) async {}

  @override
  Future<Map<String, Map<String, String>>> readAllHeaders() async => const {};

  @override
  Future<void> writeHeaders(
    String profileId,
    Map<String, String> values,
  ) async {}

  @override
  Future<void> deleteHeaders(String profileId) async {}
}

/// The real settings store, with its first [failures] settings writes failing
/// like a full or unwritable profile. The folder move commits the catalog
/// before it saves the moved MTP head path.
class _FailingSettingsStore extends InMemorySharedPreferencesStore {
  _FailingSettingsStore(super.data, {this.failures = 1}) : super.withData();

  final int failures;
  int writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('inference_settings_v1')) {
      writes++;
      if (writes <= failures) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ondevice_llm/desktop');
  late Directory temp;
  late PathProviderPlatform previousPaths;
  late bool previousDesktop;
  late AppDatabase db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('folder-atomic-');
    previousPaths = PathProviderPlatform.instance;
    previousDesktop = DesktopHost.active;
    PathProviderPlatform.instance = _Paths(temp.path);
    DesktopHost.active = true;
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'availableBytes' ? 1 << 40 : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
    PathProviderPlatform.instance = previousPaths;
    DesktopHost.active = previousDesktop;
    await temp.delete(recursive: true);
  });

  /// Seeds one downloaded model and the settings' hand-picked MTP head that
  /// points at it, then moves the folder.
  Future<
    ({
      File source,
      Directory target,
      _FailingSettingsStore store,
      ProviderContainer container,
    })
  >
  prepare({required int failures}) async {
    final modelsDir = await ModelStorage.modelsDir();
    final source = await File(
      p.join(modelsDir.path, 'model.gguf'),
    ).writeAsString('model');
    final head = 'mtp:${source.path}';
    final store = _FailingSettingsStore({
      'flutter.inference_settings_v1': jsonEncode(
        const InferenceSettings().copyWith(draftModelId: head).toJson(),
      ),
    }, failures: failures);
    SharedPreferencesStorePlatform.instance = store;
    // Reading the models directory above already built the cached
    // [SharedPreferences] from the empty mock store: reload so the settings
    // notifier loads (and writes) through this failing store.
    await (await SharedPreferences.getInstance()).reload();
    await db
        .into(db.models)
        .insert(
          ModelsCompanion(
            id: const Value('test'),
            displayName: const Value('Test'),
            fileName: const Value('model.gguf'),
            sizeBytes: const Value(5),
            family: const Value('qwen'),
            quantization: const Value('q4_k_m'),
            isDownloaded: const Value(true),
            localPath: Value(source.path),
          ),
        );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        modelManagerProvider.overrideWith(_Models.new),
        remoteKeyStoreProvider.overrideWithValue(_MemoryKeys()),
      ],
    );
    addTearDown(container.dispose);
    // The real notifier loads the saved MTP head from the store.
    await container.read(settingsProvider.notifier).ready;
    expect(store.writes, 0);
    return (
      source: source,
      target: Directory(p.join(temp.path, 'moved')),
      store: store,
      container: container,
    );
  }

  Future<String?> savedHead() async =>
      (jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'inference_settings_v1',
                )!,
              )
              as Map<String, dynamic>)['draftModelId']
          as String?;

  test(
    'a settings failure after the catalog write reverts the catalog',
    () async {
      final setup = await prepare(failures: 1);

      await expectLater(
        setup.container
            .read(modelManagerProvider.notifier)
            .changeModelsFolder(setup.target, move: true),
        // The rolled-back move reports the failed save, not an unwritable
        // folder (release review 1.8.0 #5).
        throwsA(
          isA<ModelFolderException>().having(
            (e) => e.reason,
            'reason',
            ModelFolderFailure.saveFailed,
          ),
        ),
      );

      // The first write failed, the rollback's write went through.
      expect(setup.store.writes, 2);
      // The copies are rolled back, so the catalog must not keep pointing at
      // them: a dangling localPath hides every model (audit 09-2).
      final row = await db.getModel('test');
      expect(row!.localPath, setup.source.path);
      expect(await File(row.localPath!).exists(), isTrue);
      expect(
        await File(p.join(setup.target.path, 'model.gguf')).exists(),
        isFalse,
      );
      // The saved hand-picked head still resolves to a file on disk.
      final head = await savedHead();
      expect(head, 'mtp:${setup.source.path}');
      expect(await File(head!.substring('mtp:'.length)).exists(), isTrue);
    },
  );

  test('a rollback that cannot save the head keeps the moved copies', () async {
    final setup = await prepare(failures: 1000);

    await expectLater(
      setup.container
          .read(modelManagerProvider.notifier)
          .changeModelsFolder(setup.target, move: true),
      // The failed rollback is the same failed save, not a wrong folder
      // cause (release review 1.8.0 #5).
      throwsA(
        isA<ModelFolderException>().having(
          (e) => e.reason,
          'reason',
          ModelFolderFailure.saveFailed,
        ),
      ),
    );

    // The saved paths may still point at the moved files, so they stay
    // (audit 09-2); the originals are retained on every failure.
    expect(await setup.source.exists(), isTrue);
    expect(
      await File(p.join(setup.target.path, 'model.gguf')).exists(),
      isTrue,
    );
    // Every path the app can resolve from still exists.
    final row = await db.getModel('test');
    expect(await File(row!.localPath!).exists(), isTrue);
    final head = await savedHead();
    expect(await File(head!.substring('mtp:'.length)).exists(), isTrue);
  });
}
