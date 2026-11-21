import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/backup/backup_page.dart';
import 'package:ondevice_llm/features/backup/local_backup_service.dart';
import 'package:ondevice_llm/l10n/app_localizations_en.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('Backup page shows password min length helper text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.dark, home: const BackupPage()),
      ),
    );
    await tester.pumpAndSettle();

    // The helper text should show "At least 12 characters"
    expect(find.text('At least 12 characters'), findsOneWidget);

    // The counter should show "0/12" initially
    expect(find.text('0/12'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'short');
    await tester.pumpAndSettle();
    expect(find.text('5/12'), findsOneWidget);
    // Long enough: the counter goes away.
    await tester.enterText(find.byType(TextField).first, 'testpassword');
    await tester.pumpAndSettle();
    expect(find.text('12/12'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('an oversize Android save never reads the archive into memory', (
    tester,
  ) async {
    // Real file IO never completes inside a widget test's fake-async zone, so
    // every dart:io await runs through tester.runAsync.
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('backup-cap-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final archive = File(p.join(dir.path, 'ondevice-llm-backup.odllm'));
    // A sparse archive just over the cap: reading it would cost the RAM the
    // phone save path must not spend.
    await tester.runAsync(() async {
      final raf = await archive.open(mode: FileMode.write);
      await raf.truncate(LocalBackupService.androidSaveLimitBytes + 1);
      await raf.close();
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    // A context under the page's Scaffold: toasts fall back to a snackbar.
    final context = tester.element(find.byType(Scaffold));

    var reads = 0;
    // The save path stats the archive (real IO) before the cap check.
    final saved = await tester.runAsync(
      () => saveBackupArchive(
        context,
        archive,
        AppLocalizationsEn(),
        android: true,
        read: () async {
          reads++;
          return Uint8List(0);
        },
      ),
    );
    await tester.pumpAndSettle();

    // False sends the page back to the action picker with the same archive,
    // where Share is offered; the bytes were never read (audit 08d-2).
    expect(saved, isFalse);
    expect(reads, 0);
    expect(
      find.textContaining('too large to save through the Android'),
      findsOneWidget,
    );
  });
}
