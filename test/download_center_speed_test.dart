import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/download_center.dart';

class _Downloading extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState(
    downloads: {
      'active': DownloadProgress(
        modelId: 'active',
        status: DownloadStatus.downloading,
        total: 12 * 1048576,
        received: 4 * 1048576,
        bytesPerSecond: 2.0 * 1048576,
      ),
    },
  );
}

class _Verifying extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState(
    downloads: {
      'active': DownloadProgress(
        modelId: 'active',
        status: DownloadStatus.verifying,
        total: 12 * 1048576,
        received: 12 * 1048576,
        bytesPerSecond: 2.0 * 1048576,
      ),
    },
  );
}

class _Preparing extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState(preparing: {'queued'});
}

class _QueuedWhilePreparing extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState(
    downloads: {
      'active': DownloadProgress(
        modelId: 'active',
        status: DownloadStatus.queued,
        total: 12 * 1048576,
      ),
    },
    preparing: {'active'},
  );
}

class _Cancelling extends ModelManagerNotifier {
  String? cancelled;
  @override
  ModelManagerState build() => const ModelManagerState(preparing: {'queued'});
  @override
  Future<void> cancelDownload(String id) async {
    cancelled = id;
    state = const ModelManagerState();
  }
}

Future<void> _pump(
  WidgetTester tester,
  ModelManagerNotifier Function() create,
) async {
  final container = ProviderContainer(
    overrides: [modelManagerProvider.overrideWith(create)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: DownloadCenter())),
    ),
  );
  await tester.pump();
  // Indeterminate bars never settle: pump the history future, don't settle.
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an in-flight row shows percent, bytes, speed and time left', (
    tester,
  ) async {
    await _pump(tester, _Downloading.new);
    expect(find.text('active'), findsOneWidget);
    expect(find.text('33.3%'), findsOneWidget);
    expect(
      find.text('4 MB / 12 MB \u00b7 2.0 MB/s \u00b7 4s left'),
      findsOneWidget,
    );
  });

  testWidgets('a verifying row hides the speed and the time left', (
    tester,
  ) async {
    await _pump(tester, _Verifying.new);
    expect(find.text('Verifying SHA-256…'), findsOneWidget);
    expect(find.textContaining('MB/s'), findsNothing);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets('a tapped download appears while it is preparing', (
    tester,
  ) async {
    await _pump(tester, _Preparing.new);
    expect(find.text('queued'), findsOneWidget);
    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text('No active downloads'), findsNothing);
  });

  testWidgets('a preparing row can be cancelled', (tester) async {
    final models = _Cancelling();
    await _pump(tester, () => models);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(models.cancelled, 'queued');
    expect(find.text('Preparing…'), findsNothing);
  });

  test('a model with an active row is not listed as preparing again', () {
    for (final key in ['active', 'active:vision']) {
      final state = ModelManagerState(
        downloads: {
          key: DownloadProgress(modelId: key, status: DownloadStatus.queued),
        },
        preparing: {'active'},
      );
      expect(preparingDownloads(state), isEmpty, reason: key);
    }
    expect(preparingDownloads(const ModelManagerState(preparing: {'idle'})), [
      'idle',
    ]);
  });

  testWidgets('a queued row is not repeated as a preparing row', (
    tester,
  ) async {
    await _pump(tester, _QueuedWhilePreparing.new);
    expect(find.text('active'), findsOneWidget);
    expect(find.text('Preparing…'), findsNothing);
    expect(find.byTooltip('Cancel'), findsOneWidget);
  });
}
