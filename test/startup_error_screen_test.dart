import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/storage/startup_recovery.dart';
import 'package:ondevice_llm/core/storage/startup_database_files.dart';

void main() {
  for (final failure in ['database open failed', 'migration failed']) {
    testWidgets('$failure renders recovery and retry succeeds', (tester) async {
      final gate = Completer<Widget>();
      var attempts = 0;
      await tester.pumpWidget(
        StartupRecoveryApp(
          initialize: () {
            attempts++;
            return attempts == 1
                ? gate.future
                : Future.value(const MaterialApp(home: Text('Ready')));
          },
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.completeError(StateError(failure));
      await tester.pumpAndSettle();
      expect(find.text('Startup failed'), findsOneWidget);
      expect(find.textContaining(failure), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
      expect(attempts, 2);
    });
  }

  testWidgets('export and confirmed reset use recovery actions', (
    tester,
  ) async {
    var exports = 0, resets = 0, attempts = 0;
    await tester.pumpWidget(
      StartupRecoveryApp(
        initialize: () async {
          attempts++;
          throw StateError('broken database');
        },
        exportDatabase: (_) async {
          exports++;
        },
        resetDatabase: () async {
          resets++;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export database files'));
    await tester.pumpAndSettle();
    expect(exports, 1);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(resets, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resets, 0);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(attempts, 2);
  });

  testWidgets('export failure remains recoverable', (tester) async {
    await tester.pumpWidget(
      StartupRecoveryApp(
        initialize: () async => throw StateError('open failed'),
        exportDatabase: (_) async =>
            throw const FileSystemException('disk full'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export database files'));
    await tester.pumpAndSettle();
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Retry'))
          .onPressed,
      isNotNull,
    );
  });

  test('reset never removes the database when the safety copy fails', () async {
    final root = await Directory.systemTemp.createTemp('startup-copy-failure-');
    addTearDown(() => root.delete(recursive: true));
    final database = File('${root.path}/ondevice_llm.sqlite');
    await database.writeAsString('corrupt but recoverable');
    // Prevent creating the backup directory without platform permissions.
    await File('${root.path}/database-recovery').writeAsString('blocked');
    await expectLater(
      StartupDatabaseFiles(directory: root).reset(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await database.readAsString(), 'corrupt but recoverable');
  });

  test(
    'raw export and reset preserve corrupt database and all sidecars',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'startup-recovery-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      for (final name in StartupDatabaseFiles.names) {
        await File('${root.path}/$name').writeAsString('original $name');
      }
      final files = StartupDatabaseFiles(directory: root);
      final exported = await files.exportFiles();
      expect(await exported.length(), greaterThan(0));
      for (final name in StartupDatabaseFiles.names) {
        expect(
          await File('${root.path}/$name').readAsString(),
          'original $name',
        );
        expect(
          await File('${exported.parent.path}/$name').readAsString(),
          'original $name',
        );
      }
      await files.reset();
      final snapshots = await Directory(
        '${root.path}/database-recovery',
      ).list().toList();
      expect(snapshots, hasLength(2));
      for (final name in StartupDatabaseFiles.names) {
        expect(await File('${root.path}/$name').exists(), isFalse);
        for (final snapshot in snapshots) {
          expect(
            await File('${snapshot.path}/$name').readAsString(),
            'original $name',
          );
        }
      }
    },
  );
}
