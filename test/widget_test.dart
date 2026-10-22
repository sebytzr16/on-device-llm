import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/app.dart';
import 'package:ondevice_llm/core/providers/first_launch_provider.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_picker_sheet.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'chat_test.dart' show TestModels, TestSettings, TestEngine;

class Onboarded extends OnboardingNotifier {
  final bool done;
  Onboarded(this.done);
  @override
  Future<bool> build() async => done;
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required bool onboarded,
    AppDatabase? db,
  }) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    db ??= AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(TestEngine()),
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          onboardingDoneProvider.overrideWith(() => Onboarded(onboarded)),
        ],
        child: const OnDeviceLlmApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'chat, conversations, library and settings render at phone width',
    (tester) async {
      await pumpApp(tester, onboarded: true);
      expect(tester.takeException(), isNull, reason: 'Chat layout');
      expect(
        find.text('A little more intelligence.\nA lot more privacy.'),
        findsOneWidget,
      );
      // The home page offers only what typing cannot: goal, photo, file.
      expect(find.byKey(const Key('empty-goal')), findsOneWidget);
      expect(find.byKey(const Key('ask-photo')), findsOneWidget);
      expect(find.byKey(const Key('ask-file')), findsOneWidget);

      // Conversations side sheet.
      await tester.tap(find.byTooltip('Conversations'));
      await tester.pumpAndSettle();
      expect(find.text('Stored only on this device'), findsOneWidget);
      // Request 2026-10-04: new chat, temporary chat, goals and
      // projects each have their own clearly labelled place.
      for (final key in [
        'drawer-new-chat',
        'drawer-new-temporary',
        'drawer-goals',
        'drawer-workspace',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.text('WORKSPACE'), findsOneWidget);
      await tester.tapAt(const Offset(400, 450)); // dismiss drawer
      await tester.pumpAndSettle();

      // Overflow menu → Models → back → Settings. What moved to the drawer
      // is no longer repeated here.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Temporary chat'), findsNothing);
      expect(find.text('Goals'), findsNothing);
      await tester.tap(find.text('Models'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Model layout');
      expect(find.text('Your model library'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Private by default'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('first launch shows onboarding and Skip lands in chat', (
    tester,
  ) async {
    await pumpApp(tester, onboarded: false);
    expect(tester.takeException(), isNull, reason: 'Onboarding layout');
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(
      find.text('A little more intelligence.\nA lot more privacy.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the model picker scrolls every model and keeps its footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(TestEngine()),
          settingsProvider.overrideWith(_CrowdedSettings.new),
          modelManagerProvider.overrideWith(_CrowdedModels.new),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModelPickerSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The footer is pinned whatever the list length.
    expect(find.byKey(const Key('picker-remote-settings')), findsOneWidget);
    expect(find.byKey(const Key('unload-model')), findsOneWidget);
    // Every local model and every connection can be scrolled to.
    for (final key in [
      for (var i = 0; i < 6; i++) 'picker-model-m$i',
      for (var i = 0; i < 6; i++) 'picker-remote-r$i',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });
}

class _CrowdedModels extends TestModels {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(
      catalog: [
        for (var i = 0; i < 6; i++)
          ModelInfo(
            id: 'm$i',
            displayName: 'Local model $i',
            fileName: 'm$i.gguf',
            sizeBytes: 100,
            family: ModelFamily.qwen,
            quantization: ModelQuantization.q4_k_m,
            isDownloaded: true,
            localPath: 'm$i.gguf',
          ),
      ],
      loadedModelId: 'm0',
    );
  }
}

class _CrowdedSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(
    remoteProfiles: [
      for (var i = 0; i < 6; i++)
        RemoteProfile(
          id: 'r$i',
          name: 'Server $i',
          baseUrl: 'http://192.168.1.$i:1234/v1',
          model: 'model-$i',
        ),
    ],
  );
}
