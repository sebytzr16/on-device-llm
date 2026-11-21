import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/adapters/adapter_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// A manifest with one imported adapter and one attachment, plus the adapter
/// file on disk.
Future<File> seedManifest(Directory support) async {
  final manifest = File(
    await ModelStorage.resourcePath(AdaptersNotifier.manifestName),
  );
  await manifest.parent.create(recursive: true);
  final adapter = LoraAdapter(
    id: 'lora-a',
    name: 'Style',
    fileName: 'lora-a.gguf',
    architecture: 'qwen3',
    alpha: 16,
    sha256: 'a' * 64,
    sizeBytes: 3,
    importedAt: DateTime(2026, 1, 1),
  );
  await (await ModelStorage.modelFile(adapter.fileName)).writeAsString('lora');
  await manifest.writeAsString(
    jsonEncode({
      'v': 1,
      'adapters': [adapter.toJson()],
      'attachments': {
        'model-1': [const AdapterAttachment('lora-a', 0.8).toJson()],
      },
    }),
  );
  return manifest;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late PathProviderPlatform previousPaths;
  late bool previousDesktop;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('adapter-manifest-');
    previousPaths = PathProviderPlatform.instance;
    previousDesktop = DesktopHost.active;
    DesktopHost.active = false;
    PathProviderPlatform.instance = _Paths(support.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    DesktopHost.active = previousDesktop;
    await support.delete(recursive: true);
  });

  test(
    'attach before the manifest load cannot overwrite it with an empty list',
    () async {
      final manifest = await seedManifest(support);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(adaptersProvider.notifier);

      // The adapters screen is open and the user taps attach before the disk
      // read finished: the save must wait for it (audit 08c-1).
      await notifier.attach('model-2', 'lora-a', 1.0);

      final saved = jsonDecode(await manifest.readAsString()) as Map;
      expect((saved['adapters'] as List), hasLength(1));
      final attachments = saved['attachments'] as Map;
      expect(attachments.keys, containsAll(['model-1', 'model-2']));
    },
  );

  test('resolved() waits for the manifest before answering', () async {
    await seedManifest(support);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(adaptersProvider.notifier);

    // The engine asks for the adapters of the first load after app start.
    final resolved = await notifier.resolved('model-1');

    expect(resolved, hasLength(1));
    expect(p.basename(resolved.single.path), 'lora-a.gguf');
    expect(resolved.single.scale, 0.8);
  });

  test(
    'a corrupt manifest is never overwritten from the empty state',
    () async {
      final manifest = File(
        await ModelStorage.resourcePath(AdaptersNotifier.manifestName),
      );
      await manifest.parent.create(recursive: true);
      // A killed write leaves truncated JSON. Saving the empty state read
      // from it would erase every imported adapter and attachment.
      await manifest.writeAsString('{"v": 1, "adapters": [');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(adaptersProvider.notifier);

      await expectLater(
        notifier.attach('model-1', 'lora-a', 1.0),
        throwsStateError,
      );
      // The stored bytes stay untouched, so a reload can still recover them.
      expect(await manifest.readAsString(), '{"v": 1, "adapters": [');

      // A successful reload unblocks saving again.
      await seedManifest(support);
      await notifier.reload();
      await notifier.attach('model-2', 'lora-a', 1.0);
      final saved = jsonDecode(await manifest.readAsString()) as Map;
      expect(saved['adapters'] as List, hasLength(1));
      expect((saved['attachments'] as Map).keys, contains('model-2'));
    },
  );

  test('a model with no attachment still resolves to nothing', () async {
    await seedManifest(support);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(adaptersProvider.notifier).resolved('model-9'),
      isEmpty,
    );
  });

  test('a failed save reports in state and resetUnreadable recovers', () async {
    final manifest = File(
      await ModelStorage.resourcePath(AdaptersNotifier.manifestName),
    );
    await manifest.parent.create(recursive: true);
    await manifest.writeAsString('{"v": 1, "adapters": [');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(adaptersProvider.notifier);

    await expectLater(
      notifier.attach('model-1', 'lora-a', 1.0),
      throwsStateError,
    );
    // The store records the kind of failure and keeps no English text; the
    // adapters page turns it into its own localized sentence (review #4).
    final failed = container.read(adaptersProvider);
    expect(failed.failure, AdaptersFailure.unreadable);
    expect(failed.error, isNull);

    await notifier.resetUnreadable();
    final recovered = container.read(adaptersProvider);
    expect(recovered.failure, isNull);
    expect(recovered.error, isNull);
    expect(recovered.adapters, isEmpty);
    // The unreadable bytes are kept aside for recovery, not thrown away.
    final aside = File('${manifest.path}.unreadable');
    expect(await aside.readAsString(), '{"v": 1, "adapters": [');
    expect(await manifest.exists(), isFalse);

    // The reset unblocked saving: attach now reaches the manifest.
    await notifier.attach('model-1', 'lora-a', 1.0);
    final saved = jsonDecode(await manifest.readAsString()) as Map;
    expect((saved['attachments'] as Map).keys, contains('model-1'));
  });
}
