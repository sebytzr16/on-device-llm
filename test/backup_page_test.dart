import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/backup/backup_page.dart';

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
}
