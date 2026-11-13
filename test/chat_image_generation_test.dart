import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/desktop/chat_image_generation.dart';
import 'package:ondevice_llm/desktop/image_gen_page.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/inference/engine/sd_engine.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;
  late bool previousDesktop;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('chat-image-');
    previousPaths = PathProviderPlatform.instance;
    previousDesktop = DesktopHost.active;
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    DesktopHost.active = previousDesktop;
    await root.delete(recursive: true);
  });

  test(
    'on the phone the tool says image generation needs the desktop',
    () async {
      DesktopHost.active = false;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(chatImageGeneratorProvider)
            .generate(prompt: 'a cat on a bike', localeCode: 'en'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            stringsFor('en').chatImageNeedsDesktop,
          ),
        ),
      );
    },
  );

  test('with no image model installed the tool refuses cleanly', () async {
    DesktopHost.active = true;
    final container = ProviderContainer(
      overrides: [desktopImageEngineProvider.overrideWithValue(SdEngine())],
    );
    addTearDown(container.dispose);
    await expectLater(
      container
          .read(chatImageGeneratorProvider)
          .generate(prompt: 'a cat on a bike', localeCode: 'en'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          stringsFor('en').chatImageNoModel,
        ),
      ),
    );
  });

  test(
    'the tool call reaches the image engine with the prompt and size',
    () async {
      DesktopHost.active = false;
      final calls = <String>[];
      Map<String, dynamic>? request;
      final engine = SdEngine(
        invoke: (op, args) async {
          calls.add(op);
          if (op == 'load') return 123;
          request = jsonDecode(args.first as String) as Map<String, dynamic>;
          return [
            TransferableTypedData.fromList([Uint8List(4 * 4 * 4)]),
            4,
            4,
            1,
            0,
          ];
        },
      );
      final model = ImageGenModel(
        id: 'fixture',
        displayName: 'Fixture',
        blurb: '',
        license: '',
        kind: ImageGenKind.image,
        width: 256,
        height: 256,
        steps: 3,
        cfgScale: 6,
        files: [
          for (final role in [
            ImageGenRole.diffusion,
            ImageGenRole.vae,
            ImageGenRole.llm,
          ])
            ImageGenComponent(
              role: role,
              fileName: '${role.name}.gguf',
              url: '',
              sha256: '',
              sizeBytes: 16,
            ),
        ],
      );
      for (final file in model.files) {
        await (await ModelStorage.modelFile(
          file.fileName,
        )).writeAsBytes(List.filled(16, 0));
      }
      try {
        final result = await runImageGeneration(
          engine: engine,
          model: model,
          request: const ImageGenRequest(
            prompt: 'a cat on a bike',
            negativePrompt: '',
            width: 256,
            height: 256,
            steps: 3,
            seed: 1,
            frames: 1,
            cfgScale: 6,
          ),
          t: stringsFor('en'),
        );
        expect(calls, ['load', 'image']);
        expect(request!['prompt'], 'a cat on a bike');
        expect(request!['width'], 256);
        expect(request!['height'], 256);
        expect(request!['steps'], 3);
        expect((result.width, result.height), (4, 4));
      } finally {
        await engine.dispose();
      }
    },
  );

  test('a generated picture is kept as a message attachment', () async {
    DesktopHost.active = false;
    final png = await encodePicturePng(
      SdResult(Uint8List.fromList([255, 0, 0, 255]), 1, 1),
    );
    expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final attachment = await AttachmentStore.saveGenerated(
      png,
      name: stringsFor('en').generatedImageName,
    );
    try {
      expect(attachment.isImage, isTrue);
      expect(attachment.mime, 'image/png');
      expect(attachment.name, stringsFor('en').generatedImageName);
      expect(await File(attachment.path).exists(), isTrue);
    } finally {
      await AttachmentStore.delete(attachment);
    }
  });
}
