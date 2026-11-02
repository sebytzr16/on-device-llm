import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_preferences.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/models_page.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _big = ModelInfo(
  id: 'big',
  displayName: 'Big Model',
  fileName: 'big.gguf',
  sizeBytes: 1000,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  downloadUrl: 'https://huggingface.co/x/y/resolve/main/big.gguf',
  sha256: 'ab',
);

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(catalog: [_big]);
  }

  void show({
    DownloadStatus? status,
    bool preparing = false,
    bool done = false,
  }) => state = state.copyWith(
    catalog: [
      done ? _big.copyWith(isDownloaded: true, localPath: 'big.gguf') : _big,
    ],
    downloads: {
      if (status != null)
        'big': DownloadProgress(
          modelId: 'big',
          status: status,
          received: 1000,
          total: 1000,
          error: status == DownloadStatus.failed ? 'Disk full' : null,
        ),
    },
    preparing: {if (preparing) 'big'},
  );
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'desktop_advanced': true}),
  );

  testWidgets('a finished download says Verifying, then Analyzing, never just '
      'Download', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [modelManagerProvider.overrideWith(_Models.new)],
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
    final models = container.read(modelManagerProvider.notifier) as _Models;
    final row = find.byKey(const ValueKey('model-row-big'));
    expect(
      find.descendant(of: row, matching: find.text('Download')),
      findsOneWidget,
    );

    // Hashing the finished file: the bar names it, no Download button.
    models.show(status: DownloadStatus.verifying, preparing: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('SHA-256'), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Download')),
      findsNothing,
    );

    // Saved and being read for its settings.
    models.show(status: DownloadStatus.completed, preparing: true, done: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Analyzing…'), findsOneWidget);

    // A failed download offers Retry with the reason on hover.
    models.show(status: DownloadStatus.failed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Disk full'), findsOneWidget);
  });

  test('a verified file drops the stale .part beside it', () async {
    final dir = await Directory.systemTemp.createTemp('stale_part');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/m.gguf')..writeAsStringSync('done');
    final part = File('${file.path}.part')..writeAsStringSync('half');
    await DownloadManager.dropStalePart(file);
    expect(part.existsSync(), isFalse);
    expect(file.existsSync(), isTrue);
    // No part: nothing to do, no error.
    await DownloadManager.dropStalePart(file);
  });
}
