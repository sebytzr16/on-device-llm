// Real Android layout/keyboard checks without loading a model or calling a server.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ondevice_llm/core/design/app_dialog.dart';
import 'package:ondevice_llm/core/design/app_sheet.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/backup/backup_page.dart';
import 'package:ondevice_llm/features/models/presentation/screens/model_readiness_page.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_picker_sheet.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/presets/presentation/preset_sheet.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/advanced_pages.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/advanced_pages_2.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/effective_settings_page.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/knowledge_page.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/memory_page.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/remote_server_page.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/settings_screen.dart';
import 'package:ondevice_llm/features/shortcuts/presentation/shortcuts_page.dart';
import '../test/chat_test.dart' show TestModels, TestSettings, TestEngine;

class _Settings extends TestSettings {
  final String locale;
  final MotionChoice motion;
  _Settings(this.locale, this.motion);

  @override
  InferenceSettings build() =>
      super.build().copyWith(localeCode: locale, motion: motion);
}

// Optional focused reruns after the full matrix has passed.
const _localeFilter = String.fromEnvironment('TIDY_LOCALE');
const _motionFilter = String.fromEnvironment('TIDY_MOTION');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('tidy rich forms keep actions reachable in EN/FR/ES', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var converted = false;
    for (final locale in ['en', 'fr', 'es']) {
      if (_localeFilter.isNotEmpty && locale != _localeFilter) continue;
      for (final preset in [false, true]) {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              settingsProvider.overrideWith(
                () => _Settings(locale, MotionChoice.off),
              ),
              appDatabaseProvider.overrideWithValue(db),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (_, child) =>
                  MotionScope(choice: MotionChoice.off, child: child!),
              home: preset
                  ? Scaffold(
                      body: Builder(
                        builder: (context) => TextButton(
                          key: const Key('open-editor'),
                          onPressed: () => showPresetEditor(context),
                          child: const Text('Open'),
                        ),
                      ),
                    )
                  : const ShortcutsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key(preset ? 'open-editor' : 'shortcut-add')),
        );
        await tester.pump(AppMotion.glide);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pumpAndSettle();
        }
        final name = '$locale-${preset ? 'preset' : 'shortcut'}-dialog';
        final bytes = await binding.takeScreenshot(name);
        final images = Directory(
          '${(await getTemporaryDirectory()).path}/tidy-ui',
        );
        await images.create(recursive: true);
        await File('${images.path}/$name.png').writeAsBytes(bytes);
        final context = tester.element(find.byType(AlertDialog));
        if (!preset) {
          final helper = find.text(context.l10n.shortcutPromptHelp('{input}'));
          expect(
            tester.renderObject<RenderParagraph>(helper).didExceedMaxLines,
            isFalse,
          );
        }
        final cancel = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            preset ? context.l10n.cancel : context.l10n.commonCancel,
          ),
        );
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('tidy pages, sheets and real Android keyboard in EN/FR/ES', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final engine = TestEngine();
    final images = Directory('${(await getTemporaryDirectory()).path}/tidy-ui');
    await images.create(recursive: true);
    var converted = false;
    Future<void> capture(String name) async {
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
        await tester.pumpAndSettle();
      }
      final bytes = await binding.takeScreenshot(name);
      await File('${images.path}/$name.png').writeAsBytes(bytes);
    }

    Future<void> show(Widget page, String locale, MotionChoice motion) async {
      AppHaptics.enabled = motion != MotionChoice.off;
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey('$locale-${motion.name}'),
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            llamaEngineProvider.overrideWithValue(engine),
            settingsProvider.overrideWith(() => _Settings(locale, motion)),
            modelManagerProvider.overrideWith(TestModels.new),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) => MotionScope(choice: motion, child: child!),
            home: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    for (final locale in ['en', 'fr', 'es']) {
      if (_localeFilter.isNotEmpty && locale != _localeFilter) continue;
      for (final motion in MotionChoice.values) {
        if (_motionFilter.isNotEmpty && motion.name != _motionFilter) continue;
        for (final (name, page) in <(String, Widget)>[
          ('settings', const SettingsScreen()),
          ('context', const ContextBatchPage()),
          ('hardware', const HardwarePage()),
          ('sampling', const SamplingPage()),
          ('sampling-extras', const SamplingExtrasPage()),
          ('rope', const MemoryRopePage()),
          ('structured', const StructuredOutputPage()),
          ('appearance', const AppearancePage()),
          ('effective', const EffectiveSettingsPage()),
          ('memory', const MemoryPage()),
          ('knowledge', const KnowledgePage()),
          ('remote', const RemoteServerPage()),
          ('backup', const BackupPage()),
          ('shortcuts', const ShortcutsPage()),
          ('readiness', const ModelReadinessPage()),
        ]) {
          debugPrint('UI: $locale ${motion.name} $name');
          await show(page, locale, motion);
          if (motion == MotionChoice.off &&
              ['settings', 'sampling', 'readiness'].contains(name)) {
            await capture('$locale-$name');
          }
          final scrolls = find.byType(Scrollable);
          if (scrolls.evaluate().isNotEmpty) {
            await tester.drag(scrolls.first, const Offset(0, -500));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$locale ${motion.name} $name',
            );
          }
        }
        await show(
          Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    key: const Key('models'),
                    onPressed: () => showModelPickerSheet(context),
                    child: const Text('Models'),
                  ),
                  TextButton(
                    key: const Key('presets'),
                    onPressed: () => showPresetSheet(context),
                    child: const Text('Presets'),
                  ),
                  TextButton(
                    key: const Key('prompt'),
                    onPressed: () => promptText(
                      context,
                      title: context.l10n.rename,
                      confirmLabel: context.l10n.save,
                    ),
                    child: const Text('Prompt'),
                  ),
                  TextButton(
                    key: const Key('sheet'),
                    onPressed: () => showMorphSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => AppSheet(
                        title: context.l10n.customInstructions,
                        primary: FilledButton(
                          key: const Key('sheet-save'),
                          onPressed: () {},
                          child: Text(context.l10n.save),
                        ),
                        children: [
                          const TextField(key: Key('keyboard-field')),
                          for (var i = 0; i < 40; i++) Text('Row $i'),
                        ],
                      ),
                    ),
                    child: const Text('Sheet'),
                  ),
                ],
              ),
            ),
          ),
          locale,
          motion,
        );
        for (final key in ['models', 'presets']) {
          await tester.tap(find.byKey(Key(key)));
          await tester.pumpAndSettle();
          expect(find.byType(AppSheet), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (motion == MotionChoice.off) await capture('$locale-$key-sheet');
          await tester.tap(find.byIcon(Icons.close_rounded));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('prompt')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.byType(TextButton).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sheet')));
        await tester.pumpAndSettle();
        await tester.showKeyboard(find.byKey(const Key('keyboard-field')));
        await tester.pumpAndSettle();
        final fieldContext = tester.element(
          find.byKey(const Key('keyboard-field')),
        );
        var keyboard = MediaQuery.viewInsetsOf(fieldContext).bottom;
        for (var attempt = 0; keyboard == 0 && attempt < 20; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          keyboard = MediaQuery.viewInsetsOf(fieldContext).bottom;
        }
        expect(
          keyboard,
          greaterThan(0),
          reason: 'Android must actually show the keyboard',
        );
        // Android supplies several inset frames after the first nonzero one.
        // Let that transition and the sheet's padding settle before measuring.
        await tester.pump(AppMotion.glide);
        await tester.pumpAndSettle();
        keyboard = MediaQuery.viewInsetsOf(fieldContext).bottom;
        final height = MediaQuery.sizeOf(fieldContext).height;
        await capture('$locale-${motion.name}-keyboard-sheet');
        expect(
          tester.getRect(find.byKey(const Key('sheet-save'))).bottom,
          lessThanOrEqualTo(height - keyboard),
        );
        expect(tester.takeException(), isNull);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    engine.dispose();
    await db.close();
  });
}
