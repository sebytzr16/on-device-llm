import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_imports.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_preferences.dart';

HfFile _file({String name = 'model.safetensors', int size = 1234567}) =>
    HfFile(name: name, size: size, sha256: 'a' * 64);

ImageGenModel _imported({
  ImageGenMode mode = ImageGenMode.image,
  String file = 'model.safetensors',
}) => importedImageGenModel(
  repo: 'owner/repo',
  revision: 'abc123',
  file: _file(name: file),
  license: 'Apache-2.0',
  mode: mode,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only GGUF and safetensors files are importable', () {
    expect(isSupportedImageGenFile('model.gguf'), isTrue);
    expect(isSupportedImageGenFile('nested/Model.SAFETENSORS'), isTrue);
    for (final name in [
      'model.bin',
      'model.onnx',
      'model.pth',
      'model.gguf.part',
      '',
    ]) {
      expect(isSupportedImageGenFile(name), isFalse, reason: name);
    }
  });

  test('an imported file becomes a pinned model in its mode', () {
    final model = _imported();
    expect(model.id, startsWith('imported:'));
    expect(model.id, _imported().id); // the same file keeps one identity
    expect(model.imported, isTrue);
    final file = model.files.single;
    expect(file.role, ImageGenRole.diffusion);
    expect(
      file.url,
      'https://huggingface.co/owner/repo/resolve/abc123/model.safetensors',
    );
    expect(file.fileName, startsWith('hf-'));
    expect(file.fileName, endsWith('model.safetensors'));
    expect(file.sizeBytes, 1234567);
    expect(model.sizeBytes, 1234567);
    expect(model.license, 'Apache-2.0');
    expect(ImageGenMode.of(model), ImageGenMode.image);
    expect(model.width, 1024);

    final video = _imported(mode: ImageGenMode.video);
    expect(ImageGenMode.of(video), ImageGenMode.video);
    expect(video.frames, 33);
    expect(video.fps, 16);

    final upscale = _imported(mode: ImageGenMode.upscale);
    expect(ImageGenMode.of(upscale), ImageGenMode.upscale);
    expect(upscale.files.single.role, ImageGenRole.upscaler);
    expect(upscale.width, 0);
  });

  test('an unsupported file is refused with a clear message', () {
    expect(
      () => importedImageGenModel(
        repo: 'owner/repo',
        revision: 'abc123',
        file: _file(name: 'model.bin'),
        license: 'Apache-2.0',
        mode: ImageGenMode.image,
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('GGUF or safetensors'),
        ),
      ),
    );
  });

  test('imported models are stored as a JSON list and loaded again', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final imports = container.read(imageGenImportsProvider.notifier);
    await imports.ready;
    final model = _imported();
    await imports.add(model);
    await imports.add(model);
    expect(container.read(imageGenImportsProvider), hasLength(1));

    final raw = (await SharedPreferences.getInstance()).getString(
      ImageGenImportsNotifier.prefsKey,
    );
    expect(raw, isNotNull);
    final rows = jsonDecode(raw!) as List;
    expect(rows, hasLength(1));
    expect((rows.single as Map)['id'], model.id);

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    final again = reloaded.read(imageGenImportsProvider.notifier);
    await again.ready;
    final loaded = reloaded.read(imageGenImportsProvider);
    expect(loaded.map((m) => m.id), [model.id]);
    expect(loaded.single.files.single.url, model.files.single.url);
    expect(loaded.single.files.single.sizeBytes, model.files.single.sizeBytes);
    expect(loaded.single.files.single.sha256, model.files.single.sha256);

    await again.remove(model.id);
    expect(reloaded.read(imageGenImportsProvider), isEmpty);
    final afterRemove =
        jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                ImageGenImportsNotifier.prefsKey,
              )!,
            )
            as List;
    expect(afterRemove, isEmpty);
  });

  test('the preferred model is remembered for each mode', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final preferences = container.read(imageGenPreferencesProvider.notifier);
    await preferences.ready;
    await preferences.remember(ImageGenMode.image, 'imported:image');
    await preferences.remember(ImageGenMode.video, 'builtin:video');
    await preferences.remember(ImageGenMode.upscale, 'imported:upscale');
    final state = container.read(imageGenPreferencesProvider);
    expect(state.of(ImageGenMode.image), 'imported:image');
    expect(state.of(ImageGenMode.video), 'builtin:video');
    expect(state.of(ImageGenMode.upscale), 'imported:upscale');
    expect(state.lastMode, ImageGenMode.upscale);

    final raw =
        jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                ImageGenPreferencesNotifier.prefsKey,
              )!,
            )
            as Map;
    expect(raw['image'], 'imported:image');
    expect(raw['video'], 'builtin:video');
    expect(raw['upscale'], 'imported:upscale');
    expect(raw['last'], 'upscale');

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    final again = reloaded.read(imageGenPreferencesProvider.notifier);
    await again.ready;
    final loaded = reloaded.read(imageGenPreferencesProvider);
    expect(loaded.of(ImageGenMode.image), 'imported:image');
    expect(loaded.of(ImageGenMode.video), 'builtin:video');
    expect(loaded.of(ImageGenMode.upscale), 'imported:upscale');
    expect(loaded.lastMode, ImageGenMode.upscale);
  });

  test('imported models are listed beside the built-in ones', () {
    final image = _imported();
    final upscale = _imported(
      mode: ImageGenMode.upscale,
      file: 'upscaler.safetensors',
    );
    final selectable = imageGenSelectableModels([image, upscale]);
    expect(selectable.take(imageGenCatalog.length), imageGenCatalog);
    expect(selectable, contains(image));
    expect(selectable, isNot(contains(upscale)));

    final upscalers = imageGenUpscalerModels([image, upscale]);
    expect(upscalers.take(upscalerTools.length), upscalerTools);
    expect(upscalers, contains(upscale));
    expect(upscalers, isNot(contains(image)));

    final managed = imageGenManagedModels([image, upscale]);
    expect(managed, containsAll([image, upscale]));
    expect(managed, containsAll(imageGenCatalog));
    expect(managed, containsAll(upscalerTools));
  });
}
