import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/storage/gguf_split.dart';
import 'package:ondevice_llm/data/storage/model_file_leases.dart';
import 'package:ondevice_llm/data/storage/model_folders.dart';
import 'package:ondevice_llm/features/adapters/adapter_store.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState();
  }
}

class _Adapters extends AdaptersNotifier {
  final AdaptersState initial;
  _Adapters(this.initial);
  @override
  AdaptersState build() {
    ready = Future.value();
    return initial;
  }
}

/// The delete guard's path expansion: every split part of [fileName] in
/// [dir], exactly like the manager's `_guardModelPaths` and the engines'
/// acquire both expand through [GgufSplit].
List<String> guardPaths(String dir, String fileName) => [
  for (final name in GgufSplit.parse(fileName)?.names ?? [fileName])
    p.join(dir, name),
];

ModelInfo modelOf(String id, String fileName, String path) => ModelInfo(
  id: id,
  displayName: id,
  fileName: fileName,
  sizeBytes: 5,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: path,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('delete guard refuses every runtime holder and names them', () {
    final leases = ModelFileLeases();
    final path = p.join(Directory.systemTemp.path, 'pooled.gguf');
    final pool = leases.acquire([path], owner: 'server pool');
    final vector = leases.acquire([path], owner: 'vector engine');
    final image = leases.acquire([path], owner: 'Image/video engine');
    final draft = leases.acquire([path], owner: 'llama.cpp draft');
    expect(leases.holders([path]), {
      'server pool',
      'vector engine',
      'Image/video engine',
      'llama.cpp draft',
    });
    expect(
      () => leases.beginMutation([path]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('in use'), contains('server pool')),
        ),
      ),
    );
    pool.release();
    vector.release();
    image.release();
    // The draft model's runtime still holds the file.
    expect(() => leases.beginMutation([path]), throwsStateError);
    draft.release();
    // Unleased: the delete guard goes through and blocks new loads meanwhile.
    final guard = leases.beginMutation([path]);
    expect(() => leases.acquire([path], owner: 'new load'), throwsStateError);
    guard.release();
    leases.acquire([path], owner: 'new load').release();
  });

  test(
    'split GGUF parts share one guard, like engine lease and delete',
    () async {
      final leases = ModelFileLeases();
      final dir = await Directory.systemTemp.createTemp('split-lease-');
      addTearDown(() => dir.delete(recursive: true));
      // The engine leases every part of the set when it loads one part name.
      final lease = leases.acquire(
        guardPaths(dir.path, 'model-00001-of-00002.gguf'),
        owner: 'llama.cpp',
      );
      // The delete guard expands the same way and refuses any part.
      expect(
        () => leases.beginMutation(
          guardPaths(dir.path, 'model-00002-of-00002.gguf'),
        ),
        throwsStateError,
      );
      lease.release();
      leases
          .beginMutation(guardPaths(dir.path, 'model-00001-of-00002.gguf'))
          .release();
    },
  );

  test(
    'folder move refuses a leased file inside and blocks new leases',
    () async {
      final leases = ModelFileLeases();
      final root = await Directory.systemTemp.createTemp('move-lease-');
      addTearDown(() => root.delete(recursive: true));
      final lease = leases.acquire([
        p.join(root.path, 'model.gguf'),
      ], owner: 'server pool');
      expect(
        () => leases.beginDirectoryMutation([root.path]),
        throwsStateError,
      );
      lease.release();
      final guard = leases.beginDirectoryMutation([root.path]);
      expect(
        () => leases.acquire([
          p.join(root.path, 'next.gguf'),
        ], owner: 'vector engine'),
        throwsStateError,
      );
      guard.release();
      leases.acquire([
        p.join(root.path, 'next.gguf'),
      ], owner: 'vector engine').release();
    },
  );

  test(
    'deleteModel refuses a file leased by a server pool or used as a draft',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('delete-lease-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(temp.path);
      DesktopHost.active = true;
      final c = ProviderContainer(
        overrides: [modelManagerProvider.overrideWith(_Models.new)],
      );
      final root = await Directory(p.join(temp.path, 'models')).create();
      final model = await File(
        p.join(root.path, 'model.gguf'),
      ).writeAsString('model');
      final draft = await File(
        p.join(root.path, 'draft.gguf'),
      ).writeAsString('draft');
      final pool = ModelFileLeases.instance.acquire([
        model.path,
      ], owner: 'server pool');
      final draftLease = ModelFileLeases.instance.acquire([
        draft.path,
      ], owner: 'llama.cpp');
      addTearDown(() async {
        pool.release();
        draftLease.release();
        c.dispose();
        DesktopHost.active = false;
        PathProviderPlatform.instance = previous;
        await temp.delete(recursive: true);
      });
      final manager = c.read(modelManagerProvider.notifier);
      final inUse = isA<StateError>().having(
        (e) => e.message,
        'reason',
        contains('in use'),
      );
      await expectLater(
        manager.deleteModel(modelOf('main', 'model.gguf', model.path)),
        throwsA(inUse),
      );
      // A file another loaded model uses as its draft is equally protected.
      await expectLater(
        manager.deleteModel(modelOf('draft', 'draft.gguf', draft.path)),
        throwsA(inUse),
      );
      expect(await model.readAsString(), 'model');
      expect(await draft.readAsString(), 'draft');
    },
  );

  test(
    'changeModelsFolder refuses the move while a runtime holds a file',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('folder-lease-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(temp.path);
      DesktopHost.active = true;
      final c = ProviderContainer(
        overrides: [modelManagerProvider.overrideWith(_Models.new)],
      );
      final root = await Directory(p.join(temp.path, 'models')).create();
      final file = await File(
        p.join(root.path, 'model.gguf'),
      ).writeAsString('model');
      final lease = ModelFileLeases.instance.acquire([
        file.path,
      ], owner: 'vector engine');
      addTearDown(() async {
        lease.release();
        c.dispose();
        DesktopHost.active = false;
        PathProviderPlatform.instance = previous;
        await temp.delete(recursive: true);
      });
      final manager = c.read(modelManagerProvider.notifier);
      await expectLater(
        manager.changeModelsFolder(
          Directory(p.join(temp.path, 'next')),
          move: true,
        ),
        throwsA(
          isA<ModelFolderException>().having(
            (e) => e.reason,
            'reason',
            ModelFolderFailure.busy,
          ),
        ),
      );
      expect(await file.readAsString(), 'model');
    },
  );

  test(
    'LoRA adapter remove refuses a live lease, deletes after release',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('lora-lease-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(temp.path);
      DesktopHost.active = true;
      final adapter = LoraAdapter(
        id: 'lora-test',
        name: 'Test',
        fileName: 'lora-test.gguf',
        architecture: 'qwen3',
        alpha: 16,
        sha256: 'abc',
        sizeBytes: 4,
        importedAt: DateTime(2026),
      );
      final c = ProviderContainer(
        overrides: [
          adaptersProvider.overrideWith(
            () => _Adapters(AdaptersState(adapters: [adapter])),
          ),
        ],
      );
      final root = await Directory(p.join(temp.path, 'models')).create();
      final file = await File(
        p.join(root.path, adapter.fileName),
      ).writeAsString('lora');
      final lease = ModelFileLeases.instance.acquire([
        file.path,
      ], owner: 'server pool');
      addTearDown(() async {
        lease.release();
        c.dispose();
        DesktopHost.active = false;
        PathProviderPlatform.instance = previous;
        await temp.delete(recursive: true);
      });
      final notifier = c.read(adaptersProvider.notifier);
      await expectLater(
        notifier.remove(adapter.id),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('in use'),
          ),
        ),
      );
      expect(await file.exists(), isTrue);
      expect(c.read(adaptersProvider).adapters, hasLength(1));
      lease.release();
      await notifier.remove(adapter.id);
      expect(await file.exists(), isFalse);
      expect(c.read(adaptersProvider).adapters, isEmpty);
    },
  );
}
