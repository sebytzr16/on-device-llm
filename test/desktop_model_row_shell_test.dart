import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_preferences.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/model_library_rows.dart';
import 'package:ondevice_llm/desktop/model_row_shell.dart';
import 'package:ondevice_llm/desktop/models_page.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_downloads.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_imports.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_categories.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_capabilities.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(
      catalog: [
        ModelInfo(
          id: 'chat',
          displayName: 'Chat model',
          fileName: 'chat.gguf',
          sizeBytes: 1000,
          family: ModelFamily.qwen,
          quantization: ModelQuantization.q4_k_m,
          downloadUrl: 'https://example.com/chat.gguf',
        ),
      ],
    );
  }
}

class _Downloads extends ImageGenDownloadsNotifier {
  _Downloads(this.model);
  final ImageGenModel model;
  String? resumed, pausedId, cancelled, deleted;
  @override
  ImageGenDownloadsState build() => ImageGenDownloadsState({
    model.id: ImageGenModelState(
      ImageGenModelStatus.missing,
      received: model.sizeBytes ~/ 4,
      paused: true,
    ),
  });
  void downloading() => state = ImageGenDownloadsState({
    model.id: ImageGenModelState(
      ImageGenModelStatus.downloading,
      received: model.sizeBytes ~/ 2,
    ),
  });
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

  @override
  Future<void> delete(ImageGenModel model) async {
    deleted = model.id;
  }
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'desktop_advanced': true}),
  );

  testWidgets(
    'desktop library sections share table, row and partial progress',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('desktop_row_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final files = [
        for (final name in [
          'draft.gguf',
          'embedding.gguf',
          'reranker.gguf',
          'mmproj.gguf',
          'whisper.onnx',
        ])
          File('${dir.path}/$name')..writeAsBytesSync(List.filled(1000, 0)),
      ];
      final image = imageGenManagedModels(const []).first;
      final downloads = _Downloads(image);
      final container = ProviderContainer(
        overrides: [
          modelManagerProvider.overrideWith(_Models.new),
          imageGenDownloadsProvider.overrideWith(() => downloads),
          modelInventoryFilesProvider.overrideWith((ref) async => files),
          for (final file in files)
            modelMetadataProvider(file.path).overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);
      await container.read(desktopPreferencesProvider.notifier).ready;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            home: const Scaffold(body: DesktopModelsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chat = find.byKey(const ValueKey('model-row-chat'));
      expect(
        find.descendant(of: chat, matching: find.byType(ModelRowShell)),
        findsOneWidget,
      );
      final imageRow = find.byKey(ValueKey(image.downloadKey));
      await tester.scrollUntilVisible(
        imageRow,
        450,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(imageRow, findsOneWidget);
      expect(
        find.ancestor(of: imageRow, matching: find.byType(ModelRowTable)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: imageRow, matching: find.byType(ModelRowProgress)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: imageRow, matching: find.text('25.0%')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: imageRow, matching: find.text('Resume')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('image-gen-delete-${image.id}')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: imageRow, matching: find.text('Resume')),
      );
      expect(downloads.resumed, image.id);
      final video = imageGenManagedModels(
        const [],
      ).firstWhere((model) => model.kind == ImageGenKind.video);
      final videoRow = find.byKey(ValueKey(video.downloadKey));
      await tester.scrollUntilVisible(
        videoRow,
        450,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget(videoRow), isA<ModelRowShell>());
      expect(
        find.ancestor(of: videoRow, matching: find.byType(ModelRowTable)),
        findsOneWidget,
      );
      for (final file in files) {
        final delete = find.byKey(ValueKey('inventory-delete-${file.path}'));
        await tester.scrollUntilVisible(
          delete,
          450,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final row = find.ancestor(
          of: delete,
          matching: find.byType(ModelRowShell),
        );
        expect(row, findsOneWidget);
        expect(
          find.ancestor(of: row, matching: find.byType(ModelRowTable)),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: row, matching: find.byType(ListTile)),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop image row preserves pause, cancel and confirmed delete',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final image = imageGenManagedModels(const []).first;
      final downloads = _Downloads(image);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageGenDownloadsProvider.overrideWith(() => downloads)],
          child: MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            home: Scaffold(
              body: ModelRowTable(children: [DesktopImageGenRow(model: image)]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('image-gen-delete-${image.id}')));
      await tester.pumpAndSettle();
      expect(downloads.deleted, isNull);
      await tester.tap(find.byKey(const Key('image-gen-delete-confirm')));
      await tester.pumpAndSettle();
      expect(downloads.deleted, image.id);
      downloads.downloading();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      expect(downloads.pausedId, image.id);
      await tester.tap(find.text('Cancel'));
      expect(downloads.cancelled, image.id);
      expect(find.byType(ModelRowProgress), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
