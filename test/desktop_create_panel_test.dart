import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/image_gen_page.dart';
import 'package:ondevice_llm/inference/ffi/sd_bindings.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_downloads.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_imports.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Downloads extends ImageGenDownloadsNotifier {
  @override
  ImageGenDownloadsState build() => ImageGenDownloadsState({
    for (final m in imageGenCatalog)
      m.id: ImageGenModelState(
        ImageGenModelStatus.missing,
        received: m.sizeBytes ~/ 500,
        paused: true,
        missingFiles: [for (final f in m.files) f.fileName],
      ),
  });
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SdBindings.debugAvailable = true;
  });
  tearDown(() => SdBindings.debugAvailable = null);

  for (final width in [1100.0, 1920.0]) {
    testWidgets('Create panel has no overflow at $width px with a long name', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final long = importedImageGenModel(
        repo: 'owner/repo',
        revision: 'main',
        file: const HfFile(
          name:
              'an-extremely-long-community-picture-model-name-with-many-words-Q8_0.gguf',
          size: 1000,
          sha256: '',
        ),
        license: 'Apache-2.0',
        mode: ImageGenMode.image,
      );
      SharedPreferences.setMockInitialValues({
        ImageGenImportsNotifier.prefsKey: jsonEncode([imageGenModelJson(long)]),
      });
      final container = ProviderContainer(
        overrides: [
          imageGenDownloadsProvider.overrideWith(_Downloads.new),
          modelManagerProvider.overrideWith(_Models.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(imageGenImportsProvider.notifier).ready;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            home: const Scaffold(body: DesktopImageGenPage()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      container.read(desktopImageGenProvider.notifier).selectModel(long);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('image-model-card')), findsOneWidget);
      expect(find.byKey(const Key('image-add-model')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
