import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';

void main() {
  test('Create starts on the fastest picture model', () {
    expect(defaultImageGenModel(imageGenCatalog).id, 'qwen-image-2.1-q4k');
  });

  test('a downloaded picture model wins over one still to download', () {
    expect(
      defaultImageGenModel(
        imageGenCatalog,
        downloaded: {'qwen-image-2.1-q8', 'wan-2.2-ti2v-5b-q4km'},
      ).id,
      'qwen-image-2.1-q8',
    );
  });

  test('video models are never the default', () {
    expect(
      defaultImageGenModel(
        imageGenCatalog,
        downloaded: {'wan-2.2-ti2v-5b-q4km'},
      ).kind,
      ImageGenKind.image,
    );
  });

  test('one picture and one video model per card size', () {
    expect(recommendedImageGenModels(8192), {
      'qwen-image-2.1-q4k',
      'wan-2.2-ti2v-5b-q4km',
    });
    expect(recommendedImageGenModels(24576), {
      'qwen-image-2.1-q8',
      'ltx-2.3-22b-distilled-q4km',
    });
    expect(recommendedImageGenModels(4096), {
      'qwen-image-2.1-q4k',
      'wan-2.2-ti2v-5b-q4km',
    });
    expect(recommendedImageGenModels(0), isEmpty);
  });
}
