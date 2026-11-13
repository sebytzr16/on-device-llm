import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_downloads.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_imports.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_model_widgets.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/download_center.dart';

ImageGenModel imported(String name) => importedImageGenModel(
  repo: 'owner/repo',
  revision: 'main',
  file: HfFile(name: name, size: 1000, sha256: ''),
  license: 'Apache-2.0',
  mode: ImageGenMode.image,
);

class _Downloads extends ImageGenDownloadsNotifier {
  final ImageGenDownloadsState initial;
  String? resumed, pausedId, cancelled;
  _Downloads(this.initial);
  @override
  ImageGenDownloadsState build() => initial;
  @override
  Future<void> download(ImageGenModel model) async {
    resumed = model.id;
  }

  @override
  Future<void> pause(ImageGenModel model) async {
    pausedId = model.id;
  }

  @override
  Future<void> cancel(ImageGenModel model) async {
    cancelled = model.id;
  }
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'legacy imported Qwen file reuses companions and preserves diffusion',
    () {
      final original = imported('qwen-image-2.1-Q8_0.gguf');
      final restored = imageGenModelFromJson(imageGenModelJson(original))!;
      final resolved = resolveImageGenCompanions(restored);
      expect(
        resolved.file(ImageGenRole.diffusion)!.fileName,
        original.files.single.fileName,
      );
      for (final role in [
        ImageGenRole.llm,
        ImageGenRole.vae,
        ImageGenRole.upscaler,
      ]) {
        expect(resolved.file(role), imageGenCatalog.first.file(role));
      }
      expect(
        resolveImageGenCompanions(resolved).files.length,
        resolved.files.length,
      );
      final paths = {
        for (final f in resolved.files) f.role: '/models/${f.fileName}',
      };
      expect(resolved.loadSettings(paths)['llmPath'], paths[ImageGenRole.llm]);
      expect(imageGenNeedsCompanions(resolved), isFalse);
      expect(
        imageGenModelForDownload(
          '${original.downloadKey}:${original.files.single.fileName}',
          [original],
        )!.id,
        original.id,
      );
      expect(
        imageGenModelForDownload(
          'image-gen:qwen-image-2.1-q4k:qwen_image_2.1-Q4_K.gguf',
          [],
        )!.id,
        imageGenCatalog[1].id,
      );
    },
  );

  test('video companions use compatible family defaults', () {
    for (final (name, family) in [
      ('Wan2.2-TI2V-5B-Q8_0.gguf', imageGenCatalog[2]),
      ('ltx-2.3-22b-distilled-Q8_0.gguf', imageGenCatalog[3]),
    ]) {
      final model = resolveImageGenCompanions(imported(name));
      expect(model.kind, ImageGenKind.video);
      expect(model.file(ImageGenRole.vae), family.file(ImageGenRole.vae));
      expect(model.samplerExtras, family.samplerExtras);
    }
  });

  test(
    'unknown diffusion fails before accessing files or native engine',
    () async {
      final model = imported('unknown-Q4.gguf');
      expect(await ImageGenDownloadsNotifier.isReady(model), isFalse);
      await expectLater(
        ImageGenDownloadsNotifier.paths(model),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            stringsFor('en').imageCompanionsUnknown,
          ),
        ),
      );
      expect(stringsFor('en').chatImageNoModel, contains('Qwen-Image 2.1'));
      expect(stringsFor('en').chatImageNoModel, contains('Create'));
    },
  );

  testWidgets(
    'picker badges show ready, size and inline progress for all models',
    (tester) async {
      final models = imageGenSelectableModels([
        imported('qwen-image-2.1-Q8_0.gguf'),
      ]);
      final downloads = _Downloads(
        ImageGenDownloadsState({
          models[0].id: const ImageGenModelState(ImageGenModelStatus.ready),
          models[1].id: ImageGenModelState(
            ImageGenModelStatus.downloading,
            received: models[1].sizeBytes ~/ 2,
          ),
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageGenDownloadsProvider.overrideWith(() => downloads)],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  for (final model in models) ImageGenModelOption(model: model),
                ],
              ),
            ),
          ),
        ),
      );
      expect(models.length, imageGenCatalog.length + 1);
      for (final model in models) {
        expect(find.text(model.displayName), findsOneWidget);
      }
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(
        find.textContaining('Download '),
        findsNWidgets(imageGenCatalog.length + 1 - 2),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Downloads lists image packs with percent, speed, pause, resume and cancel',
    (tester) async {
      final first = imageGenCatalog[0], second = imageGenCatalog[1];
      final downloads = _Downloads(
        ImageGenDownloadsState({
          first.id: ImageGenModelState(
            ImageGenModelStatus.downloading,
            received: first.sizeBytes ~/ 2,
            bytesPerSecond: 1048576,
          ),
          second.id: const ImageGenModelState(
            ImageGenModelStatus.missing,
            received: 1000,
            paused: true,
          ),
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageGenDownloadsProvider.overrideWith(() => downloads),
            modelManagerProvider.overrideWith(_Models.new),
          ],
          child: const MaterialApp(home: Scaffold(body: DownloadCenter())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(first.displayName), findsOneWidget);
      expect(find.text(second.displayName), findsOneWidget);
      expect(find.textContaining('50.0%'), findsOneWidget);
      expect(find.textContaining('1 MB/s'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      expect(downloads.pausedId, first.id);
      await tester.tap(find.byTooltip('Resume download'));
      expect(downloads.resumed, second.id);
      await tester.tap(find.byTooltip('Cancel').first);
      expect(downloads.cancelled, first.id);
      expect(tester.takeException(), isNull);
    },
  );
}
