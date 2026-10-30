import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/constants/app_constants.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/l10n/app_localizations_fr.dart';
import 'package:ondevice_llm/l10n/app_localizations_es.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/platform/desktop_preferences.dart';
import 'package:ondevice_llm/desktop/advanced_toggle.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/desktop/desktop_app.dart';
import 'package:ondevice_llm/desktop/model_visibility.dart';
import 'package:ondevice_llm/desktop/server_page.dart';
import 'package:ondevice_llm/desktop/sidebar.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_server_logs_test.dart' show FakeDesktopHost;
import 'support/desktop_chat_harness.dart';

void main() {
  tearDown(() => DesktopHost.leanPrompt = true);

  test('desktop labels have French and Spanish translations', () {
    expect(AppLocalizationsFr().desktopAdvanced, 'Avancé');
    expect(AppLocalizationsEs().desktopBasic, 'Básico');
    expect(AppLocalizationsFr().desktopCreateTitle, 'Créer');
  });

  test(
    'desktop lean prompt is persisted and Android keeps its prompt',
    () async {
      SharedPreferences.setMockInitialValues({});
      final previous = DesktopHost.active;
      addTearDown(() => DesktopHost.active = previous);
      DesktopHost.active = true;
      final c = ProviderContainer();
      await c.read(desktopPreferencesProvider.notifier).ready;
      expect(AppConstants.defaultSystemPrompt, AppConstants.spokenSystemPrompt);
      await c.read(desktopPreferencesProvider.notifier).set(leanPrompt: false);
      expect(AppConstants.defaultSystemPrompt, AppConstants.fullSystemPrompt);
      c.dispose();
      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      await restored.read(desktopPreferencesProvider.notifier).ready;
      expect(restored.read(desktopPreferencesProvider).leanPrompt, isFalse);
      await restored
          .read(desktopPreferencesProvider.notifier)
          .set(leanPrompt: true);
      DesktopHost.active = false;
      expect(AppConstants.defaultSystemPrompt, AppConstants.fullSystemPrompt);
    },
  );

  test(
    'Bonsai and DiffusionGemma require Advanced without changing catalog',
    () {
      final basic = desktopCatalog.where(
        (m) => desktopModelVisible(m, advanced: false),
      );
      expect(basic.map((m) => m.id), isNot(contains('bonsai2-9b-q2_0')));
      expect(
        basic.map((m) => m.id),
        isNot(contains('diffusiongemma-26b-a4b-q4km')),
      );
      expect(
        desktopCatalog.where((m) => desktopModelVisible(m, advanced: true)),
        desktopCatalog,
      );
    },
  );

  testWidgets(
    'Basic hides Labs navigation, keeps Compare, and persists Advanced',
    (tester) async {
      final c = await mountDesktopChat(
        tester,
        const DesktopShell(),
        shell: true,
      );
      await c.read(desktopPreferencesProvider.notifier).ready;
      await tester.pumpAndSettle();
      final sidebar = find.byType(DesktopSidebar);
      Finder label(String text) =>
          find.descendant(of: sidebar, matching: find.text(text));
      final t = AppLocalizationsEn();
      expect(label(t.mcpTitle), findsNothing);
      expect(label(t.desktopLogsTitle), findsNothing);
      expect(label(t.desktopCompareTitle), findsOneWidget);
      expect(label(t.desktopCreateTitle), findsOneWidget);
      await tester.tap(label(t.desktopAdvanced));
      await tester.pumpAndSettle();
      expect(label(t.mcpTitle), findsOneWidget);
      expect(label(t.desktopLogsTitle), findsOneWidget);
      final restored = ProviderContainer();
      await restored.read(desktopPreferencesProvider.notifier).ready;
      expect(restored.read(desktopPreferencesProvider).advanced, isTrue);
      restored.dispose();
      c.read(desktopSectionProvider.notifier).show(DesktopSection.logs);
      await tester.pumpAndSettle();
      await tester.tap(label(t.desktopBasic));
      await tester.pumpAndSettle();
      expect(label(t.mcpTitle), findsNothing);
      expect(find.text(t.desktopChatExplanation), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('server internals follow the same Advanced switch', (
    tester,
  ) async {
    final c = await mountDesktopChat(tester, const SizedBox());
    await c.read(desktopPreferencesProvider.notifier).ready;
    // The server never starts as a consequence of changing display depth.
    final server = ProviderContainer(
      parent: c,
      overrides: [deviceHostingProvider.overrideWith(FakeDesktopHost.new)],
    );
    addTearDown(server.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: server,
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Column(
              children: [
                DesktopAdvancedToggle(),
                Expanded(child: DesktopServerPage()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-pool-jit')), findsNothing);
    await tester.tap(find.text(AppLocalizationsEn().desktopAdvanced));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-pool-jit')), findsOneWidget);
    expect(
      (server.read(deviceHostingProvider.notifier) as FakeDesktopHost).starts,
      0,
    );
  });
}
