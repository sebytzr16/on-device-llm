import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/app_design.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/settings/presentation/widgets/settings_widgets.dart';

void main() {
  testWidgets(
    'a large grouped list builds only visible rows and scrolls to later items',
    (tester) async {
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SettingsGroup.sliver(
                  itemCount: 1000,
                  itemBuilder: (context, index) {
                    builds++;
                    return SettingsRow(
                      key: Key('lazy-$index'),
                      title: Text('Row $index'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(builds, lessThan(50));
      expect(find.byKey(const Key('lazy-999')), findsNothing);
      await tester.scrollUntilVisible(find.byKey(const Key('lazy-99')), 600);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lazy-99')), findsOneWidget);
      expect(find.byKey(const Key('lazy-999')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['en', 'fr', 'es']) {
    for (final dark in [true, false]) {
      testWidgets('settings wrap at large text in $locale, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var changes = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MotionScope(
              choice: MotionChoice.off,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => ListView(
                  padding: const EdgeInsets.all(AppDesign.lg),
                  children: [
                    SettingsSection(
                      label: context.l10n.sectionAssistant,
                      children: [
                        SettingsRow(
                          title: Text(context.l10n.knowledgeLibrary),
                          subtitle: Text(context.l10n.knowledgeIntro),
                          onTap: () => changes++,
                        ),
                        SettingsSwitchRow(
                          key: const Key('switch'),
                          title: Text(context.l10n.rememberAboutMe),
                          subtitle: Text(context.l10n.rememberAboutMeHint),
                          value: false,
                          onChanged: (_) => changes++,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('switch')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('switch')));
        await tester.pumpAndSettle();
        expect(changes, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
