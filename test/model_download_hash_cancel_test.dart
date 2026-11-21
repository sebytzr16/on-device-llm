import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_recommendations_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// Sampling discovery is independent of the finish/cancel bookkeeping; keep it
/// from touching the file the test is still hashing.
class _Recommendations extends ModelRecommendationsNotifier {
  @override
  Future<void> learnFromFile(ModelInfo m, {bool force = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase db;
  late ProviderContainer container;
  late PathProviderPlatform originalPaths;
  const desktop = MethodChannel('ondevice_llm/desktop');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('download-hash-cancel-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    DesktopHost.active = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          desktop,
          (call) async => call.method == 'availableBytes' ? 1 << 40 : null,
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

  test('a Cancel during the file hash does not save the model', () async {
    final manager = container.read(modelManagerProvider.notifier);
    await manager.ready;
    // Several MB: the hash runs in an isolate and takes long enough for the
    // Cancel below to land while it is still hashing.
    final payload = Uint8List(4 << 20);
    for (var i = 0; i < payload.length; i++) {
      payload[i] = i % 256;
    }
    // A finished file of the right size is already on disk: the manager
    // verifies its hash instead of downloading it.
    final info = ModelInfo(
      id: 'cancel-hash',
      displayName: 'Cancel hash',
      fileName: 'cancel-hash.litertlm',
      sizeBytes: payload.length,
      family: ModelFamily.qwen,
      quantization: ModelQuantization.q4_k_m,
      downloadUrl: 'https://example.org/cancel-hash.litertlm',
      sha256: sha256.convert(payload).toString(),
    );
    await ModelStorage.modelsDir();
    final file = await ModelStorage.modelFile(info.fileName);
    await file.writeAsBytes(payload);

    final downloading = manager.downloadModel(info);
    // Catch the manager while it hashes: the verifying row is set right
    // before `validateAndHash` starts, and the Cancel reaches the manager
    // before the isolate answers.
    bool verifying() =>
        container.read(modelManagerProvider).downloads[info.id]?.status ==
        DownloadStatus.verifying;
    for (var i = 0; i < 2000 && !verifying(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(verifying(), isTrue, reason: 'the finished file reaches the hash');
    await manager.cancelDownload(info.id);
    await downloading;

    // The verified file must not be saved behind the cancelled history row
    // (release review 1.8.0 #6).
    expect(
      (await db.allModels()).where((r) => r.id == info.id),
      isEmpty,
      reason: 'a cancelled hash saved the model',
    );
    final state = container.read(modelManagerProvider);
    expect(state.preparing, isEmpty);
    expect(state.downloads.containsKey(info.id), isFalse);
    // The bytes stay on disk: the next download re-verifies them.
    expect(await file.exists(), isTrue);
  });
}
