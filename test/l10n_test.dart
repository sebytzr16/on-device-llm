import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/app.dart';
import 'package:ondevice_llm/core/providers/first_launch_provider.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' show TestEngine, TestModels, TestSettings;
import 'widget_test.dart' show Onboarded;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'language choice persists; invalid saved locales follow the phone',
    () async {
      SharedPreferences.setMockInitialValues({});
      var container = ProviderContainer();
      await container.read(settingsProvider.notifier).ready;
      await container
          .read(settingsProvider.notifier)
          .update(const InferenceSettings(localeCode: 'fr'));
      container.dispose();
      container = ProviderContainer();
      await container.read(settingsProvider.notifier).ready;
      expect(container.read(settingsProvider).localeCode, 'fr');
      await container
          .read(settingsProvider.notifier)
          .update(container.read(settingsProvider).copyWith(localeCode: 'es'));
      container.dispose();
      container = ProviderContainer();
      await container.read(settingsProvider.notifier).ready;
      expect(container.read(settingsProvider).localeCode, 'es');
      await container
          .read(settingsProvider.notifier)
          .update(container.read(settingsProvider).copyWith(localeCode: ''));
      container.dispose();
      container = ProviderContainer();
      await container.read(settingsProvider.notifier).ready;
      expect(container.read(settingsProvider).localeCode, '');
      container.dispose();
      for (final code in ['de', 'fr-CA', 'broken', 12, null]) {
        expect(InferenceSettings.fromJson({'localeCode': code}).localeCode, '');
      }
    },
  );

  testWidgets(
    'system French and explicit English/French update the chat live',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.localesTestValue = [const Locale('fr', 'CA')];
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(TestEngine()),
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          onboardingDoneProvider.overrideWith(() => Onboarded(true)),
        ],
      );
      if (Platform.environment['CAPTURE_L10N'] == '1') {
        await tester.runAsync(() async {
          for (final family in ['Fraunces', 'Inter', 'JetBrainsMono']) {
            final loader = FontLoader(family)
              ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
            await loader.load();
          }
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      addTearDown(container.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundaryKey,
            child: const OnDeviceLlmApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Nouvelle discussion'), findsOneWidget);
      expect(find.text('Écrivez à votre modèle…'), findsOneWidget);
      expect(
        find.text(
          "Un peu plus d'intelligence.\nBeaucoup plus de confidentialité.",
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      if (Platform.environment['CAPTURE_L10N'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('artifacts').create(recursive: true);
          await File(
            'artifacts/chat-fr.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      // Settings and the model picker are translated too (FX-15 round 2).
      await tester.tap(find.byTooltip('Plus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réglages'));
      await tester.pumpAndSettle();
      expect(find.text('Mode réflexion'), findsOneWidget);
      expect(find.text('Bibliothèque de connaissances'), findsOneWidget);
      expect(find.text('Privé par défaut'), findsOneWidget);
      if (Platform.environment['CAPTURE_L10N'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'artifacts/settings-fr.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      Navigator.of(tester.element(find.text('Mode réflexion'))).pop();
      await tester.pumpAndSettle();

      final settings = container.read(settingsProvider.notifier);
      await tester.runAsync(
        () => settings.update(
          container.read(settingsProvider).copyWith(localeCode: 'en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('New chat'), findsOneWidget);
      expect(find.text('Message your model…'), findsOneWidget);

      // Exercise the real language picker, then return to the translated chat.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      // Language sits under Appearance & language, below the fold.
      await tester.scrollUntilVisible(
        find.byKey(const Key('language-row')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('language-row')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Français').last);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).localeCode, 'fr');
      expect(find.text('Réglages'), findsOneWidget);
      expect(find.text('Langue'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Discussions'));
      await tester.pumpAndSettle();
      expect(find.text('Conservé uniquement sur cet appareil'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('unsupported system locale resolves to English', (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context).newChat),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New chat'), findsOneWidget);
  });
}
