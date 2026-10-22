import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/inference_contract_page.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/scan_settings_page.dart';
import 'package:ondevice_llm/features/hosting/host_discovery.dart';
import 'package:ondevice_llm/features/hosting/presentation/nearby_hosts_page.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'chat_test.dart' show TestSettings;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Inter', 'Fraunces', 'JetBrainsMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final language in ['en', 'fr', 'es']) {
    for (final dark in [false, true]) {
      for (final page in ['settings', 'scan', 'nearby']) {
        testWidgets('$page fits 320px in $language ${dark ? 'dark' : 'light'}', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = const Size(320, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                HostDiscovery.channel,
                (_) async => [
                  {'name': 'OnDevice LLM', 'host': '192.168.1.2', 'port': 8787},
                ],
              );
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(HostDiscovery.channel, null),
          );
          final container = ProviderContainer(
            overrides: [settingsProvider.overrideWith(TestSettings.new)],
          );
          addTearDown(container.dispose);
          final home = switch (page) {
            'settings' => const InferenceContractPage(),
            'scan' => const ScanSettingsPage(),
            _ => const NearbyHostsPage(),
          };
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                locale: Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: RepaintBoundary(key: const Key('capture'), child: home),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (page == 'settings') {
            await tester.tap(find.byKey(const Key('override-batchSize')));
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextField), '256');
            await tester.tap(find.byType(FilledButton));
            await tester.pumpAndSettle();
            expect(container.read(settingsProvider).batchSize, 256);
          }
          expect(tester.takeException(), isNull);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final picture = await boundary.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('artifacts/build-completion-ui')
              ..createSync(recursive: true);
            await File(
              '${directory.path}/$page-$language-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        });
      }
    }
  }
}
