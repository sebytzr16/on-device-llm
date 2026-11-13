import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app.dart';
import 'core/model_licences.dart';
import 'core/logging/developer_logs.dart';
import 'core/platform/desktop_host.dart';
import 'core/platform/frame_timing_log.dart';
import 'core/storage/staging_cleanup.dart';
import 'core/storage/app_directories.dart';
import 'core/storage/database_encryption.dart';
import 'core/storage/device_encryption.dart';
import 'package:path/path.dart' as p;
import 'core/storage/startup_recovery.dart';
import 'data/local/database/app_database.dart';
import 'desktop/desktop_app.dart';
import 'desktop/desktop_window.dart';
import 'features/backup/local_backup_service.dart';
import 'features/goals/goal_watch_background.dart';

/// Retained by AOT for Android's scheduled watch JobService.
@pragma('vm:entry-point')
Future<void> goalWatchBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runGoalWatchBackground();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Set before anything opens the database: it decides where data lives.
  final desktop = Platform.isWindows;
  DesktopHost.active = desktop;
  if (FrameTimingLog.enabled) unawaited(FrameTimingLog().start());

  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    developerLogBuffer.record(r);
    // ignore: avoid_print
    print('[${r.level.name}] ${r.loggerName}: ${r.message}');
    // The error itself: "Uncaught" alone tells nothing on a phone.
    if (r.error != null) {
      final stack = '${r.stackTrace ?? ''}'.split('\n').take(8).join('\n');
      // ignore: avoid_print
      print('  ${r.error}\n$stack');
    }
  });

  registerModelLicences();

  // Build and layout errors reach the Logs page too: a release build shows
  // a failed widget as an empty gap with no other trace (owner 2026-11-12:
  // Recommended stayed empty).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Logger('flutter').severe(details.exceptionAsString(), null, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Logger('main').severe('Uncaught', error, stack);
    return true;
  };

  runApp(StartupRecoveryApp(initialize: () => _initialize(desktop)));
}

Future<Widget> _initialize(bool desktop) async {
  AppDatabase? db;
  try {
    try {
      await StagingCleanup.sweep();
    } catch (error, stack) {
      Logger('main').warning('Staging cleanup failed', error, stack);
    }
    final encryption = DeviceEncryption.instance;
    final databaseFile = File(
      p.join((await appDataDirectory()).path, 'ondevice_llm.sqlite'),
    );
    final databaseEncryption = DatabaseEncryption(encryption);
    // Resolve any interrupted database rename before a restore replaces it.
    if (await File('${databaseFile.path}.dbenc-original').exists() ||
        await File('${databaseFile.path}.dbenc-pending').exists()) {
      await databaseEncryption.prepare(databaseFile);
    } else {
      await databaseEncryption.verifyExisting(databaseFile);
    }
    await LocalBackupService.applyPendingRestore();
    final encrypt = await encryption.enabled();
    if (encrypt || await encryption.migrationPending()) {
      await encryption.setEnabled(encrypt);
    }
    // Restores install a portable plaintext database. Apply local policy before
    // opening Drift, including when resuming an interrupted restore.
    await databaseEncryption.prepare(databaseFile);
    db = AppDatabase();
    await LocalBackupService.finishRestore(db);
    await encryption.completeMigration();
    await db.markInterruptedRuns();
    if (desktop) await DesktopWindow.init();
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: desktop ? const DesktopApp() : const OnDeviceLlmApp(),
    );
  } catch (error, stack) {
    Logger('main').severe('Startup failed', error, stack);
    // Release SQLite/WAL handles before retry, raw backup or reset.
    try {
      await db?.close();
    } catch (closeError, closeStack) {
      Logger('main').warning('Closing failed database', closeError, closeStack);
    }
    rethrow;
  }
}
