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
    'history deletion confirms and keeps active transfers and files',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'installed_models': 'keep files',
      });
      for (final status in ['paused', 'cancelled', 'failed', 'completed']) {
        await DownloadHistory.put(
          DownloadRecord(
            attempt: status,
            modelId: status,
            name: '$status.gguf',
            result: status,
            size: 100,
            date: DateTime(2026, 11, 7),
          ),
        );
      }
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
      await tester.tap(find.byTooltip('Remove history row').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('downloaded model file will be kept'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await DownloadHistory.read(), hasLength(4));
      await tester.tap(find.byTooltip('Remove history row').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove history row'));
      await tester.pumpAndSettle();
      expect(find.text('completed.gguf'), findsNothing);
      expect(await DownloadHistory.read(), hasLength(3));
      await tester.tap(find.text('Clear finished history'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Clear finished history'),
      );
      await tester.pumpAndSettle();
      expect((await DownloadHistory.read()).single.result, 'paused');
      expect(find.text('active'), findsOneWidget);
      expect(
        (container.read(modelManagerProvider.notifier) as _Models).cancelled,
        false,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('installed_models'),
        'keep files',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
