import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/storage/download_history.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/download_center.dart';

class _Models extends ModelManagerNotifier {
  bool cancelled = false;
  @override
  ModelManagerState build() => const ModelManagerState(
    downloads: {
      'active': DownloadProgress(
        modelId: 'active',
        status: DownloadStatus.downloading,
        total: 100,
        received: 30,
      ),
    },
  );
  @override
  Future<void> cancelDownload(String id) async {
    cancelled = true;
    state = const ModelManagerState();
  }
}

void main() {
  testWidgets(
    'active transfers cancel and history survives a new provider scope',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await DownloadHistory.put(
        DownloadRecord(
          attempt: '1',
          modelId: 'finished',
          name: 'finished.gguf',
          result: 'completed',
          size: 1000000,
          date: DateTime(2026, 11, 1),
        ),
      );
      final container = ProviderContainer(
        overrides: [modelManagerProvider.overrideWith(_Models.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: DownloadCenter())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('active'), findsOneWidget);
      expect(find.text('finished.gguf'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (container.read(modelManagerProvider.notifier) as _Models).cancelled,
        isTrue,
      );
      expect(find.text('No active downloads'), findsOneWidget);
      final fresh = ProviderContainer(
        overrides: [modelManagerProvider.overrideWith(_Models.new)],
      );
      addTearDown(fresh.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fresh,
          child: const MaterialApp(home: Scaffold(body: DownloadCenter())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('finished.gguf'), findsOneWidget);
    },
  );
}
