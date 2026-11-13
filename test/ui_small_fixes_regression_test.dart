import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/desktop/advanced_toggle.dart';
import 'package:ondevice_llm/desktop/image_gen_page.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/inference/engine/sd_engine.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoadedModel extends ModelManagerNotifier {
  @override
  ModelManagerState build() =>
      const ModelManagerState(loadedModelId: 'Test LLM');
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Placeholder component files: loading needs them present (not verified).
Future<void> _placeholderImageFiles() async {
  for (final m in [...imageGenCatalog, ...upscalerTools]) {
    for (final f in m.files) {
      final file = await ModelStorage.modelFile(f.fileName);
      if (!await file.exists()) await file.create(recursive: true);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('C11 arithmetic is local and never needs a freshness notice', () {
    for (final input in [
      '2+2',
      'What is 2+2?',
      'what is 17 * 23',
      'Calculate (2026 - 2025) * 3?',
      '-2.5 / (4 + 1)',
    ]) {
      expect(RetrievalPlan.localTask(input), isTrue, reason: input);
      expect(
        RetrievalPlan.of(input, webEnabled: false).wantsWeb,
        isFalse,
        reason: input,
      );
    }
    for (final input in [
      'What is the population in 2026?',
      'What is the price of 2 apples?',
      'What happened in 2025?',
      '2 + 2 population',
      'search for 2+2',
      '2026',
    ]) {
      expect(RetrievalPlan.localTask(input), isFalse, reason: input);
    }
    expect(RetrievalPlan.smallTalk('Hello!'), isTrue);
    expect(RetrievalPlan.mayNeedTools('17 * 23'), isTrue);
  });

  for (final failure in ['load', 'image', 'upscale']) {
    final upscale = failure == 'upscale';
    test('C08 $failure failure names loaded LLM and recovery', () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('ui-image-error-');
      final previousPaths = PathProviderPlatform.instance;
      final previousDesktop = DesktopHost.active;
      PathProviderPlatform.instance = _Paths(root.path);
      DesktopHost.active = false;
      await _placeholderImageFiles();
      final calls = <String>[];
      final engine = SdEngine(
        invoke: (op, args) async {
          calls.add(op);
          if (op == 'dispose') return null;
          if (op == 'load' && failure != 'load') return 1;
          throw StateError('GPU allocation failed');
        },
      );
      final container = ProviderContainer(
        overrides: [
          modelManagerProvider.overrideWith(_LoadedModel.new),
          desktopImageEngineProvider.overrideWithValue(engine),
        ],
      );
      try {
        final notifier = container.read(desktopImageGenProvider.notifier);
        if (upscale) {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(Colors.red, BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(1, 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          await notifier.upscale(
            bytes!.buffer.asUint8List(),
            2,
            upscalerTools.first,
          );
        } else {
          await notifier.generate(
            const ImageGenRequest(
              prompt: 'cat',
              negativePrompt: '',
              width: 512,
              height: 512,
              steps: 1,
              seed: 1,
              frames: 1,
              cfgScale: 1,
            ),
          );
        }
        expect(calls, contains(failure));
        final error = container.read(desktopImageGenProvider).errorMessage!;
        expect(error, contains('Test LLM'));
        expect(error.toLowerCase(), contains('eject'));
        expect(error.toLowerCase(), contains('retry'));
      } finally {
        container.dispose();
        await engine.dispose();
        PathProviderPlatform.instance = previousPaths;
        DesktopHost.active = previousDesktop;
        await root.delete(recursive: true);
      }
    });
  }

  testWidgets(
    'C10 selector fits narrow width at 140 percent without wrapping',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(width: 160, child: DesktopAdvancedToggle()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Basic', 'Advanced']) {
        expect(
          tester.getSize(find.text(label)).height,
          lessThan(30),
          reason: label,
        );
      }
    },
  );
}
