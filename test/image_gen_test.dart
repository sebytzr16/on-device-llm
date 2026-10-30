import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/inference/engine/sd_engine.dart';

void main() {
  group('pictureSizePlan', () {
    test('square is drawn as asked', () {
      expect(pictureSizePlan(1024, 1024), (
        width: 1024,
        height: 1024,
        upscale: 1,
      ));
    });

    test('Full HD is drawn 1920x1088 and cropped', () {
      expect(pictureSizePlan(1920, 1080), (
        width: 1920,
        height: 1088,
        upscale: 1,
      ));
    });

    test('4K is drawn at half size and enlarged', () {
      expect(pictureSizePlan(3840, 2160), (
        width: 1920,
        height: 1088,
        upscale: 2,
      ));
    });

    test('every preset fits the 2048 limit once planned', () {
      for (final p in picturePresets) {
        final plan = pictureSizePlan(p.width, p.height);
        expect(plan.width, lessThanOrEqualTo(2048));
        expect(plan.height, lessThanOrEqualTo(2048));
        expect(plan.width % 32, 0);
        expect(plan.height % 32, 0);
        expect(plan.width * plan.upscale, greaterThanOrEqualTo(p.width));
        expect(plan.height * plan.upscale, greaterThanOrEqualTo(p.height));
      }
    });
  });

  test('cropCentre keeps the middle rows and columns', () {
    // 4x4 picture whose red channel is the pixel index.
    final rgba = Uint8List(4 * 4 * 4);
    for (var i = 0; i < 16; i++) {
      rgba[i * 4] = i;
    }
    final out = SdResult(rgba, 4, 4).cropCentre(2, 2);
    expect((out.width, out.height), (2, 2));
    expect([for (var i = 0; i < 4; i++) out.rgba[i * 4]], [5, 6, 9, 10]);
    expect(identical(SdResult(rgba, 4, 4).cropCentre(4, 4).rgba, rgba), true);
  });

  test('picture models carry the upscaler and share files', () {
    final q8 = imageGenCatalog.firstWhere((m) => m.id == 'qwen-image-2.1-q8');
    final q4 = imageGenCatalog.firstWhere((m) => m.id == 'qwen-image-2.1-q4k');
    expect(imageGenCatalog.first, q8);
    for (final m in [q8, q4]) {
      expect(m.files.map((f) => f.role), contains(ImageGenRole.upscaler));
    }
    // The upscaler is never passed to stable-diffusion.cpp's loader.
    final paths = {for (final f in q8.files) f.role: f.fileName};
    expect(
      q8.loadSettings(paths).values,
      isNot(contains(upscalerComponent.fileName)),
    );
    expect(ModelStorage.fileExtensions, contains('.pth'));
  });

  test('Models including LTX use the default text encoder backend', () {
    for (final m in imageGenCatalog) {
      final paths = {for (final f in m.files) f.role: f.fileName};
      expect(m.loadSettings(paths)['textEncoderOnCpu'], isNull, reason: m.id);
    }
  });

  test('Upscale mode offers Sharp first and both have one file', () {
    expect(upscalerTools.first.files.single, upscalerComponent);
    for (final m in upscalerTools) {
      expect(m.files.single.role, ImageGenRole.upscaler);
      expect(m.files.single.fileName, endsWith('.pth'));
      expect(imageGenCatalog, isNot(contains(m)));
    }
  });

  test('a missing image bridge fails the call instead of hanging', () async {
    // No ondevice_sd.dll is reachable from the test runner, so the worker
    // cannot open it; the call must fail and a later one must not hang either.
    final engine = SdEngine();
    final picture = SdResult(Uint8List(4), 1, 1);
    for (var i = 0; i < 2; i++) {
      await expectLater(
        engine
            .upscale('none.pth', picture)
            .timeout(const Duration(seconds: 20)),
        throwsA(isA<StateError>()),
      );
    }
    await engine.dispose();
  });
}
