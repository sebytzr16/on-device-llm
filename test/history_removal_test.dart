import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/data/storage/download_history.dart';
import 'package:ondevice_llm/desktop/benchmark_receipt.dart';
import 'package:ondevice_llm/desktop/model_tune_section.dart';

BenchmarkReceipt receipt(String model, String date) => BenchmarkReceipt({
  'modelId': model,
  'timestamp': date,
  'modelFile': '$model.gguf',
});

DownloadRecord download(String attempt, String result) => DownloadRecord(
  attempt: attempt,
  modelId: 'same-model',
  name: 'model.gguf',
  result: result,
  size: 42,
  date: DateTime(2026, 11, 7),
);

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'model_profiles_v1': 'profile sentinel',
      'installed_models': 'model sentinel',
    }),
  );

  test('receipt removal is scoped, selects by identity and persists', () async {
    final c = ProviderContainer();
    final store = c.read(benchmarkReceiptsProvider.notifier);
    final a = receipt('a', '1');
    final duplicate = receipt('a', '1');
    final b = receipt('b', '1');
    await Future.wait([store.save(a), store.save(duplicate), store.save(b)]);
    await store.remove('a', [a, b]);
    expect(c.read(benchmarkReceiptsProvider), [duplicate, b]);
    await store.remove('a', [a]); // Already deleted: no-op.
    c.dispose();
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(benchmarkReceiptsProvider.notifier).ready;
    expect(restored.read(benchmarkReceiptsProvider).map((r) => r.json), [
      duplicate.json,
      b.json,
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('model_profiles_v1'), 'profile sentinel');
    expect(prefs.getString('installed_models'), 'model sentinel');
  });

  test(
    'bulk deletion and clear preserve other models and serialize saves',
    () async {
      final c = ProviderContainer();
      final store = c.read(benchmarkReceiptsProvider.notifier);
      final rows = [
        receipt('a', '1'),
        receipt('a', '2'),
        receipt('a', '3'),
        receipt('b', '1'),
      ];
      for (final row in rows) {
        await store.save(row);
      }
      await store.remove('a', rows.take(2));
      expect(c.read(benchmarkReceiptsProvider), rows.skip(2).toList());
      await Future.wait([store.clearModel('a'), store.save(receipt('b', '2'))]);
      await store.clearModel('missing');
      c.dispose();
      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      await restored.read(benchmarkReceiptsProvider.notifier).ready;
      expect(
        restored.read(benchmarkReceiptsProvider).map((r) => r.json['modelId']),
        ['b', 'b'],
      );
    },
  );

  test(
    'download removal deletes one attempt and emits a persisted change',
    () async {
      await DownloadHistory.put(download('1', 'completed'));
      await DownloadHistory.put(download('2', 'completed'));
      final changed = DownloadHistory.changes.stream.first;
      await DownloadHistory.remove('1');
      await changed;
      await DownloadHistory.remove('missing');
      expect((await DownloadHistory.read()).map((r) => r.attempt), ['2']);
      final prefs = await SharedPreferences.getInstance();
      expect(
        (jsonDecode(prefs.getString(DownloadHistory.key)!) as List)
            .single['attempt'],
        '2',
      );
      expect(prefs.getString('model_profiles_v1'), 'profile sentinel');
      expect(prefs.getString('installed_models'), 'model sentinel');
    },
  );

  test(
    'clear finished preserves paused/interrupted/active and queued writes',
    () async {
      for (final status in [
        'completed',
        'failed',
        'cancelled',
        'paused',
        'interrupted',
        'downloading',
      ]) {
        await DownloadHistory.put(download(status, status));
      }
      await Future.wait([
        DownloadHistory.clearFinished(),
        DownloadHistory.put(download('new', 'completed')),
      ]);
      expect((await DownloadHistory.read()).map((r) => r.attempt), [
        'new',
        'downloading',
        'interrupted',
        'paused',
      ]);
      await DownloadHistory.clearFinished();
      expect((await DownloadHistory.read()).map((r) => r.attempt), [
        'downloading',
        'interrupted',
        'paused',
      ]);
    },
  );

  testWidgets('phone history button opens a scrollable per-model history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(benchmarkReceiptsProvider.notifier);
    for (var i = 0; i < 20; i++) {
      await store.save(receipt('a', '$i'));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: BenchmarkHistoryButton(modelId: 'a')),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Speed benchmark history'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(20));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
    await tester.pumpAndSettle();
    expect(c.read(benchmarkReceiptsProvider), isEmpty);
    expect(find.text('No speed benchmark history yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'receipts require confirmation for single, selected and clear on phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final store = c.read(benchmarkReceiptsProvider.notifier);
      for (final date in ['1', '2', '3', '4']) {
        await store.save(receipt('a', date));
      }
      await store.save(receipt('b', 'other'));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: BenchmarkReceiptSection(modelId: 'a'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Benchmark receipt · 4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete receipt').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.read(benchmarkReceiptsProvider), hasLength(5));
      await tester.tap(find.text('Delete receipt').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete receipts'));
      await tester.pumpAndSettle();
      expect(c.read(benchmarkReceiptsProvider), hasLength(4));
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete selected (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete receipts'));
      await tester.pumpAndSettle();
      expect(c.read(benchmarkReceiptsProvider), hasLength(2));
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();
      expect(c.read(benchmarkReceiptsProvider).single.json['modelId'], 'b');
      expect(tester.takeException(), isNull);
    },
  );
}
