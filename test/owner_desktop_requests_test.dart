import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/desktop/chat_pane.dart';
import 'package:ondevice_llm/desktop/desktop_app.dart';
import 'package:ondevice_llm/desktop/sidebar.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/screens/model_details_page.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/desktop_chat_harness.dart';

void main() {
  testWidgets(
    'desktop starts temporary chat, marks it, and returns to saved chat',
    (tester) async {
      final search = FocusNode();
      final composer = FocusNode();
      addTearDown(search.dispose);
      addTearDown(composer.dispose);
      final container = await mountDesktopChat(tester, const SizedBox());
      container
          .read(desktopSectionProvider.notifier)
          .show(DesktopSection.models);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: DesktopSidebar(
                      searchFocus: search,
                      onNewChat: () =>
                          container.read(chatProvider.notifier).newChat(),
                    ),
                  ),
                  Expanded(child: DesktopChatPane(composerFocus: composer)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('desktop-new-temporary')));
      await tester.pumpAndSettle();
      expect(container.read(chatProvider).temporary, isTrue);
      expect(container.read(desktopSectionProvider), DesktopSection.chat);
      expect(
        find.byKey(const Key('desktop-temporary-indicator')),
        findsOneWidget,
      );
      expect(find.textContaining('Temporary chat'), findsWidgets);
      await tester.tap(find.widgetWithText(OutlinedButton, 'New chat'));
      await tester.pumpAndSettle();
      expect(container.read(chatProvider).temporary, isFalse);
      expect(
        find.byKey(const Key('desktop-temporary-indicator')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final desktop in [true, false]) {
    testWidgets(
      'model details uses ${desktop ? 'desktop dialog' : 'phone page'} with scrollable content',
      (tester) async {
        final previous = DesktopHost.active;
        DesktopHost.active = desktop;
        addTearDown(() => DesktopHost.active = previous);
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(modelProfilesProvider.notifier).ready;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => openModelDetails(
                      context,
                      const ModelInfo(
                        id: 'test',
                        displayName: 'Example model',
                        fileName: 'test.gguf',
                        sizeBytes: 1024,
                        family: ModelFamily.qwen,
                        quantization: ModelQuantization.q4_k_m,
                      ),
                    ),
                    child: const Text('Open details'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open details'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), desktop ? findsOneWidget : findsNothing);
        expect(find.text('Example model'), findsOneWidget);
        if (desktop) {
          final size = tester.getSize(find.byType(ModelDetailsPage));
          expect(size.width, 720);
          expect(size.height, 800);
          expect(find.byType(CloseButton), findsOneWidget);
        } else {
          expect(find.byType(BackButton), findsOneWidget);
        }
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(find.text('Uses recommended defaults'), findsOneWidget);
        await tester.tap(find.byType(desktop ? CloseButton : BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(ModelDetailsPage), findsNothing);
        expect(find.text('Open details'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
