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

  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) {
    Logger('main').severe('Uncaught', error, stack);
    return true;
  };

  // A validated restore is applied before SQLite opens its WAL files.
  try {
    await LocalBackupService.applyPendingRestore();
  } catch (error, stack) {
    Logger('main').severe('Restore could not be applied', error, stack);
  }
  // WAL + foreign keys now live inside the DB's MigrationStrategy.
  final db = AppDatabase();
  await LocalBackupService.finishRestore(db);
  // CHAT-01: a run the OS killed mid-answer becomes an interrupted message.
  await db.markInterruptedRuns();

  // Windows gets its own window-shaped interface over the same providers.
  if (desktop) await DesktopWindow.init();

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: desktop ? const DesktopApp() : const OnDeviceLlmApp(),
    ),
  );
}
