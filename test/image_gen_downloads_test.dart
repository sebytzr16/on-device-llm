import 'dart:async';
import 'package:dio/dio.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_downloads.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_imports.dart';

class _Paths extends PathProviderPlatform {
  final String root;
  _Paths(this.root);
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// A minimal valid GGUF header (v3) followed by [fill] bytes.
List<int> _gguf(int fill) => [
  0x47,
  0x47,
  0x55,
  0x46,
  3,
  0,
  0,
  0,
  ...List.filled(992, fill),
];

class _PackDownloader extends DownloadManager {
  final controller = StreamController<DownloadProgress>.broadcast();
  final started = Completer<void>();
  final stopped = Completer<void>();
  final List<int> bytes;
  final calls = <String>[];
  bool resume = false;
  _PackDownloader(this.bytes);
  @override
  Stream<DownloadProgress> progressStream(String id) => controller.stream;
  @override
  Future<void> download({
    required String modelId,
    required String url,
    required String fileName,
    required String expectedSha256,
    required int expectedSize,
  }) async {
    calls.add(fileName);
    final file = await ModelStorage.modelFile(fileName);
    if (!resume) {
      await File('${file.path}.part').writeAsBytes(bytes.take(400).toList());
      controller.add(
        DownloadProgress(
          modelId: modelId,
          status: DownloadStatus.downloading,
          received: 400,
          total: bytes.length,
          bytesPerSecond: 128,
        ),
      );
      started.complete();
      await stopped.future;
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      );
    }
    await file.writeAsBytes(bytes);
    final part = File('${file.path}.part');
    if (await part.exists()) await part.delete();
  }

  @override
  Future<void> pause(String id) async {
    if (!stopped.isCompleted) stopped.complete();
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PathProviderPlatform previousPaths;
  late bool previousDesktop;
  late List<int> bytes;
  late ImageGenModel model;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('odllm-img-gen-test-');
    previousPaths = PathProviderPlatform.instance;
    previousDesktop = DesktopHost.active;
    DesktopHost.active = false;
    PathProviderPlatform.instance = _Paths(dir.path);
    SharedPreferences.setMockInitialValues({});
    bytes = _gguf(7);
    model = ImageGenModel(
      id: 'test',
      displayName: 'Test',
      blurb: '',
      license: '',
      kind: ImageGenKind.image,
      files: [
        for (final role in [ImageGenRole.diffusion, ImageGenRole.vae])
          ImageGenComponent(
            role: role,
            fileName: '${role.name}.gguf',
            url: 'https://example.org/${role.name}.gguf',
            sha256: sha256.convert(bytes).toString(),
            sizeBytes: bytes.length,
          ),
      ],
      width: 512,
      height: 512,
      steps: 20,
      cfgScale: 7,
    );
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    DesktopHost.active = previousDesktop;
    await dir.delete(recursive: true);
  });

  Future<void> install() async {
    for (final component in model.files) {
      await (await ModelStorage.modelFile(
        component.fileName,
      )).writeAsBytes(bytes);
    }
  }

  test(
    'pack pause retains bytes and resume skips installed components',
    () async {
      final downloader = _PackDownloader(bytes);
      final container = ProviderContainer(
        overrides: [
          imageGenDownloadManagerProvider.overrideWithValue(downloader),
        ],
      );
      addTearDown(container.dispose);
      // An installed companion must be reused rather than fetched again.
      await (await ModelStorage.modelFile(
        model.files.last.fileName,
      )).writeAsBytes(bytes);
      final notifier = container.read(imageGenDownloadsProvider.notifier);
      final job = notifier.download(model);
      await downloader.started.future;
      await notifier.pause(model);
      await job;
      final paused = container.read(imageGenDownloadsProvider).of(model);
      expect(paused.status, ImageGenModelStatus.missing);
      expect(paused.paused, isTrue);
      expect(paused.received, bytes.length + 400);
      expect(paused.missingFiles, [model.files.first.fileName]);
      downloader.resume = true;
      await notifier.download(model);
      expect(
        container.read(imageGenDownloadsProvider).of(model).status,
        ImageGenModelStatus.ready,
      );
      expect(downloader.calls, [
        model.files.first.fileName,
        model.files.first.fileName,
      ]);
    },
  );

  test('cancel removes partial bytes and keeps installed companions', () async {
    final downloader = _PackDownloader(bytes);
    final container = ProviderContainer(
      overrides: [
        imageGenDownloadManagerProvider.overrideWithValue(downloader),
      ],
    );
    addTearDown(container.dispose);
    await (await ModelStorage.modelFile(
      model.files.last.fileName,
    )).writeAsBytes(bytes);
    final notifier = container.read(imageGenDownloadsProvider.notifier);
    final job = notifier.download(model);
    await downloader.started.future;
    await notifier.cancel(model);
    await job;
    final primary = await ModelStorage.modelFile(model.files.first.fileName);
    expect(await File('${primary.path}.part').exists(), isFalse);
    expect(await ModelStorage.exists(model.files.last.fileName), isTrue);
    expect(container.read(imageGenDownloadsProvider).of(model).paused, isFalse);
  });

  test(
    'refresh restores imported diffusion and partial companion progress',
    () async {
      final imported = importedImageGenModel(
        repo: 'owner/repo',
        revision: 'main',
        file: const HfFile(
          name: 'qwen-image-2.1-Q8_0.gguf',
          size: 1000,
          sha256: '',
        ),
        license: '',
        mode: ImageGenMode.image,
      );
      final resolved = resolveImageGenCompanions(imported);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final imports = container.read(imageGenImportsProvider.notifier);
      await imports.ready;
      await imports.add(imported);
      await (await ModelStorage.modelFile(
        imported.files.single.fileName,
      )).writeAsBytes(List.filled(1000, 0));
      final encoder = await ModelStorage.modelFile(
        resolved.file(ImageGenRole.llm)!.fileName,
      );
      await File('${encoder.path}.part').writeAsBytes(List.filled(200, 0));
      await container.read(imageGenDownloadsProvider.notifier).refresh();
      final state = container.read(imageGenDownloadsProvider).of(imported);
      expect(state.received, 1200);
      // Shared encoders alone do not create phantom paused catalog downloads.
      expect(
        container
            .read(imageGenDownloadsProvider)
            .of(imageGenCatalog.first)
            .paused,
        isFalse,
      );
      expect(state.paused, isTrue);
      expect(
        state.missingFiles,
        contains(resolved.file(ImageGenRole.vae)!.fileName),
      );
      expect(
        state.missingFiles,
        isNot(contains(imported.files.single.fileName)),
      );
      expect(state.missingBytes, resolved.sizeBytes - 1200);
      expect(await ImageGenDownloadsNotifier.isReady(imported), isFalse);
      await expectLater(
        ImageGenDownloadsNotifier.paths(imported),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Missing:'),
          ),
        ),
      );
    },
  );

  group('ImageGenDownloadsNotifier readiness', () {
    test('missing component is not ready', () async {
      await install();
      await (await ModelStorage.modelFile(model.files.last.fileName)).delete();
      expect(await ImageGenDownloadsNotifier.isReady(model), isFalse);
    });

    test('wrong-size component is not ready', () async {
      await install();
      final file = await ModelStorage.modelFile(model.files.last.fileName);
      for (final size in [0, 500, 1001]) {
        await file.writeAsBytes(List.filled(size, 65));
        expect(await ImageGenDownloadsNotifier.isReady(model), isFalse);
      }
    });

    test('all components with correct sizes and checksums are ready', () async {
      await install();
      expect(await ImageGenDownloadsNotifier.isReady(model), isTrue);
    });

    test(
      'same-size component with a different checksum is not ready',
      () async {
        await install();
        final file = await ModelStorage.modelFile(model.files.last.fileName);
        await file.writeAsBytes(_gguf(8));
        expect(await ImageGenDownloadsNotifier.isReady(model), isFalse);
      },
    );

    test(
      'a verified component is cached until its size or mtime changes',
      () async {
        await install();
        expect(await ImageGenDownloadsNotifier.isReady(model), isTrue);
        // Matches survive a restart: they are kept in preferences.
        final marks = (await SharedPreferences.getInstance()).getStringList(
          'imageGenVerifiedHashes',
        );
        expect(
          marks!.where((m) => m.startsWith(dir.path.split(r'').first)),
          isNotEmpty,
        );
        final file = await ModelStorage.modelFile(model.files.last.fileName);
        final original = await file.stat();
        await file.writeAsBytes(_gguf(8));
        await file.setLastModified(original.modified);
        // Same path, size and modification time: the receipt still stands.
        expect((await file.stat()).modified, original.modified);
        expect(await ImageGenDownloadsNotifier.isReady(model), isTrue);
        await file.setLastModified(
          original.modified.add(const Duration(seconds: 1)),
        );
        expect(await ImageGenDownloadsNotifier.isReady(model), isFalse);
      },
    );

    test('partial download cannot satisfy readiness', () async {
      await install();
      final file = await ModelStorage.modelFile(model.files.last.fileName);
      await file.rename('${file.path}.part');
      expect(await ImageGenDownloadsNotifier.isReady(model), isFalse);
    });

    test('download skips existing components with correct sizes', () async {
      await install();
      final container = ProviderContainer();
      try {
        await container
            .read(imageGenDownloadsProvider.notifier)
            .download(model);
        final state = container.read(imageGenDownloadsProvider).of(model);
        expect(state.status, ImageGenModelStatus.ready);
        expect(state.error, isNull);
      } finally {
        container.dispose();
      }
    });

    test(
      'download rejects wrong-size existing component without marking ready',
      () async {
        await install();
        final file = await ModelStorage.modelFile(model.files.last.fileName);
        await file.writeAsBytes(List.filled(500, 65));
        final container = ProviderContainer();
        try {
          await container
              .read(imageGenDownloadsProvider.notifier)
              .download(model);
          final state = container.read(imageGenDownloadsProvider).of(model);
          expect(state.status, ImageGenModelStatus.missing);
          expect(state.error, contains('unverified model already exists'));
          expect(await file.length(), 500);
          expect(await ImageGenDownloadsNotifier.isReady(model), isFalse);
        } finally {
          container.dispose();
        }
      },
    );

    test(
      'download rejects same-size existing component with a bad checksum',
      () async {
        await install();
        final file = await ModelStorage.modelFile(model.files.last.fileName);
        await file.writeAsBytes(_gguf(8));
        final container = ProviderContainer();
        try {
          await container
              .read(imageGenDownloadsProvider.notifier)
              .download(model);
          final state = container.read(imageGenDownloadsProvider).of(model);
          expect(state.status, ImageGenModelStatus.missing);
          expect(state.error, contains('unverified model already exists'));
          expect(await ImageGenDownloadsNotifier.isReady(model), isFalse);
        } finally {
          container.dispose();
        }
      },
    );
  });

  test('deleting an imported model forgets it in preferences', () async {
    final imported = importedImageGenModel(
      repo: 'owner/repo',
      revision: 'abc123',
      file: HfFile(name: 'model.safetensors', size: 1234567, sha256: 'a' * 64),
      license: 'Apache-2.0',
      mode: ImageGenMode.image,
    );
    final container = ProviderContainer();
    try {
      final imports = container.read(imageGenImportsProvider.notifier);
      await imports.ready;
      await imports.add(imported);
      await container.read(imageGenDownloadsProvider.notifier).delete(imported);
      expect(container.read(imageGenImportsProvider), isEmpty);
      expect(
        await ModelStorage.exists(imported.files.single.fileName),
        isFalse,
      );
    } finally {
      container.dispose();
    }
  });
}
