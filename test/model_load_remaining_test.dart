import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/storage/model_file_leases.dart';
import 'package:ondevice_llm/data/storage/model_folders.dart';
import 'package:ondevice_llm/desktop/models_page.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/inference/engine/sd_engine.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Stop during image or video load never marks the engine loaded',
    () async {
      final pending = Completer<Object?>();
      final engine = SdEngine(invoke: (_, _) => pending.future);
      final loading = engine.load(key: 'video', modelPath: 'video.gguf');
      engine.cancel();
      final stopped = expectLater(loading, throwsA(isA<SdOperationStopped>()));
      pending.complete(123);
      await stopped;
      expect(engine.isLoaded, isFalse);
      await engine.dispose();
    },
  );

  for (final operation in ['image', 'video', 'upscale']) {
    test('Stop discards a completed $operation before publishing', () async {
      final pending = Completer<Object?>();
      final engine = SdEngine(
        invoke: (op, _) async {
          if (op == 'load') return 123;
          return await pending.future;
        },
      );
      await engine.load(key: 'model');
      final output = operation == 'upscale'
          ? engine.upscale('upscaler.pth', SdResult(Uint8List(4), 1, 1))
          : engine.generate({}, video: operation == 'video');
      await Future<void>.delayed(Duration.zero);
      engine.cancel();
      final stopped = expectLater(output, throwsA(isA<SdOperationStopped>()));
      pending.complete([
        TransferableTypedData.fromList([Uint8List(4)]),
        1,
        1,
        if (operation != 'upscale') ...[1, 0],
      ]);
      await stopped;
      await engine.dispose();
    });
  }

  test('loaded Create files refuse mutation until runtime disposal', () async {
    final engine = SdEngine(invoke: (_, _) async => 123);
    await engine.load(
      key: 'picture',
      modelPath: 'weights.gguf',
      settings: {'llmPath': 'encoder.gguf'},
    );
    for (final path in ['weights.gguf', 'encoder.gguf']) {
      expect(
        () => ModelFileLeases.instance.beginMutation([path]),
        throwsStateError,
      );
    }
    await engine.dispose();
    ModelFileLeases.instance.beginMutation([
      'weights.gguf',
      'encoder.gguf',
    ]).release();
  });

  test(
    'reloading Create releases previous files after native completion',
    () async {
      final engine = SdEngine(invoke: (_, _) async => 123);
      await engine.load(key: 'first', modelPath: 'first.gguf');
      await engine.load(key: 'second', modelPath: 'second.gguf');
      ModelFileLeases.instance.beginMutation(['first.gguf']).release();
      expect(
        () => ModelFileLeases.instance.beginMutation(['second.gguf']),
        throwsStateError,
      );
      await engine.dispose();
    },
  );

  test(
    'directory mutation refuses active files and prevents new file leases',
    () async {
      final root = await Directory.systemTemp.createTemp('lease-folder-');
      addTearDown(() => root.delete(recursive: true));
      final leases = ModelFileLeases();
      final lease = leases.acquire([
        '${root.path}/model.gguf',
      ], owner: 'server');
      expect(
        () => leases.beginDirectoryMutation([root.path]),
        throwsStateError,
      );
      lease.release();
      final guard = leases.beginDirectoryMutation([root.path]);
      expect(
        () => leases.acquire(['${root.path}/new.gguf'], owner: 'vector'),
        throwsStateError,
      );
      guard.release();
      leases.acquire(['${root.path}/new.gguf'], owner: 'vector').release();
    },
  );

  test(
    'model manager refuses deleting or moving a server-leased file',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('manager-lease-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(temp.path);
      DesktopHost.active = true;
      final c = ProviderContainer(
        overrides: [modelManagerProvider.overrideWith(_Models.new)],
      );
      final root = await Directory('${temp.path}/models').create();
      final file = await File('${root.path}/model.gguf').writeAsString('model');
      final lease = ModelFileLeases.instance.acquire([
        file.path,
      ], owner: 'server');
      addTearDown(() async {
        lease.release();
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
        manager.deleteModel(
          ModelInfo(
            id: 'test',
            displayName: 'Test',
            fileName: 'model.gguf',
            sizeBytes: 5,
            family: ModelFamily.qwen,
            quantization: ModelQuantization.q4_k_m,
            isDownloaded: true,
            localPath: file.path,
          ),
        ),
        throwsA(inUse),
      );
      await expectLater(
        manager.changeModelsFolder(Directory('${temp.path}/next'), move: true),
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
    'embedding, media, reranker, and vision deletes refuse another runtime lease',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('companion-lease-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(temp.path);
      DesktopHost.active = true;
      final c = ProviderContainer(
        overrides: [modelManagerProvider.overrideWith(_Models.new)],
      );
      final root = await Directory('${temp.path}/models').create();
      addTearDown(() async {
        c.dispose();
        DesktopHost.active = false;
        PathProviderPlatform.instance = previous;
        await temp.delete(recursive: true);
      });
      final manager = c.read(modelManagerProvider.notifier);
      for (final (name, remove) in <(String, Future<void> Function())>[
        (embeddingModel.fileName, manager.deleteEmbedding),
        (embeddingModel.projector!.fileName, manager.deleteEmbeddingMedia),
        (supportCheckModel.fileName, manager.deleteSupportCheck),
        (
          supportCheckModel.fileName,
          () => manager.deleteVision(
            const ModelInfo(
              id: 'vision',
              displayName: 'Vision',
              fileName: 'vision.gguf',
              sizeBytes: 1,
              family: ModelFamily.qwen,
              quantization: ModelQuantization.q4_k_m,
              projector: supportCheckModel,
            ),
          ),
        ),
      ]) {
        final file = await File('${root.path}/$name').writeAsString('model');
        final lease = ModelFileLeases.instance.acquire([
          file.path,
        ], owner: 'other runtime');
        try {
          await expectLater(
            remove(),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'reason',
                contains('in use'),
              ),
            ),
          );
          expect(await file.readAsString(), 'model');
        } finally {
          lease.release();
        }
      }
    },
  );

  test(
    'All files inventory includes MTP heads, drafts, and nested model files',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('all-model-files-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(temp.path);
      DesktopHost.active = true;
      final c = ProviderContainer(
        overrides: [modelManagerProvider.overrideWith(_Models.new)],
      );
      addTearDown(() async {
        c.dispose();
        DesktopHost.active = false;
        PathProviderPlatform.instance = previous;
        await temp.delete(recursive: true);
      });
      await Directory('${temp.path}/models/nested').create(recursive: true);
      for (final name in [
        'mtp-head.gguf',
        'draft.gguf',
        'nested/vae.safetensors',
        'ignore.part',
      ]) {
        await File('${temp.path}/models/$name').writeAsString('test');
      }
      final subscription = c.listen(desktopModelFilesProvider, (_, _) {});
      addTearDown(subscription.close);
      final files = await c.read(desktopModelFilesProvider.future);
      expect(
        files.map((f) => f.uri.pathSegments.last),
        unorderedEquals(['mtp-head.gguf', 'draft.gguf', 'vae.safetensors']),
      );
    },
  );
}
