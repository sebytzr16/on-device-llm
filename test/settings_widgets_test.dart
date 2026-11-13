import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/settings_screen.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/settings_search_page.dart';

const testModel = ModelInfo(
  id: 'test',
  displayName: 'Test Model',
  fileName: 'test.gguf',
  sizeBytes: 100,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: 'test.gguf',
);

class TestSettings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings();
  }

  @override
  Future<void> update(InferenceSettings next) async {
    state = next;
  }
}

class TestModels extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(catalog: [testModel], loadedModelId: 'test');
  }
}

Widget harness() => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(TestSettings.new),
    modelManagerProvider.overrideWith(TestModels.new),
    detectedHardwareProvider.overrideWith((ref) async => null),
  ],
  child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
);

void main() {
  testWidgets(
    'settings screen renders privacy card, model row and advanced rows',
    (tester) async {
      tester.view.physicalSize = const Size(412, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness());
      await tester.pump();
      expect(find.text('Private by default'), findsOneWidget);
      // The model row, and Voice › Conversation model (the loaded model
      // answers when Qwen3.5 0.8B is not downloaded).
      expect(find.text('Test Model'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const Key('conversation-model')),
          matching: find.text('Test Model'),
        ),
        findsOneWidget,
      );
      expect(find.text('Advanced'), findsOneWidget);
      for (final row in [
        'Context & batch',
        'Hardware',
        'Sampling',
        'Reasoning & search',
      ]) {
        expect(find.text(row), findsOneWidget);
      }
      expect(find.text('4k ctx · auto batch · cache on'), findsOneWidget);
    },
  );
  testWidgets("Sampling opens the active model's own settings", (tester) async {
    // Sampling is per model (owner 2026-11-01): no app-wide page.
    tester.view.physicalSize = const Size(412, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.ensureVisible(find.text('Sampling'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sampling'));
    await tester.pumpAndSettle();
    expect(find.text('Test Model profile'), findsOneWidget);
    expect(find.text('More sampling'), findsNothing);
  });
  testWidgets('hardware explains the explicit OpenCL tradeoff', (tester) async {
    tester.view.physicalSize = const Size(412, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.ensureVisible(find.text('Hardware'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hardware'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Automatic uses CPU'), findsOneWidget);
    expect(find.textContaining('~2× faster prompt reading'), findsOneWidget);
    expect(find.textContaining('~15 % slower answers'), findsOneWidget);
  });
  testWidgets('enabling web search asks for confirmation first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.tap(find.text('Web research (keyless)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('web-mode-always')));
    await tester.pumpAndSettle();
    expect(find.text('Enable web search?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(settingsProvider).webMode, WebMode.off);
    // Accepting applies the picked mode.
    await tester.tap(find.text('Web research (keyless)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('web-mode-always')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).webMode, WebMode.always);
  });
  testWidgets('settings search finds and flips a main-page switch', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(TestSettings.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SettingsSearchPage(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'name chats');
    await tester.pump();
    expect(find.text('Name chats automatically'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(container.read(settingsProvider).autoTitles, isFalse);
    await tester.enterText(find.byType(TextField), 'wikipedia');
    await tester.pump();
    expect(find.text('Add the Wikipedia article'), findsOneWidget);
  });
}
