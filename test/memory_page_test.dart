import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/memory_page.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

import 'remote_memory_learning_test.dart' show RemoteMemoryTestSettings;

void main() {
  testWidgets(
    'Memory shows and updates the active connection opt-ins at phone width',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWith(
            () => RemoteMemoryTestSettings(
              const RemoteProfile(
                id: 'test',
                name: 'My Gemini connection',
                baseUrl: 'https://example.com',
                model: 'fixture',
              ),
            ),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.dark, home: const MemoryPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My Gemini connection'), findsOneWidget);
      SwitchListTile control(String key) =>
          tester.widget<SwitchListTile>(find.byKey(Key(key)));
      expect(control('memory-remote-share').value, isFalse);
      expect(control('memory-remote-learn').onChanged, isNull);
      await tester.ensureVisible(find.byKey(const Key('memory-remote-share')));
      await tester.tap(find.byKey(const Key('memory-remote-share')));
      await tester.pumpAndSettle();
      expect(control('memory-remote-learn').onChanged, isNotNull);
      await tester.ensureVisible(find.byKey(const Key('memory-remote-learn')));
      await tester.tap(find.byKey(const Key('memory-remote-learn')));
      await tester.pumpAndSettle();
      expect(
        container.read(settingsProvider).activeRemoteProfile!.learnMemory,
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const Key('memory-remote-share')));
      await tester.tap(find.byKey(const Key('memory-remote-share')));
      await tester.pumpAndSettle();
      expect(
        container.read(settingsProvider).activeRemoteProfile!.shareMemory,
        isFalse,
      );
      expect(
        container.read(settingsProvider).activeRemoteProfile!.learnMemory,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
