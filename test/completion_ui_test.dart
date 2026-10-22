import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/domain/conversation_workspace.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/presentation/screens/conversation_workspace_page.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'chat_test.dart' show TestEngine, TestModels, TestSettings;

class _Workspace extends ConversationWorkspaceNotifier {
  @override
  ConversationWorkspace build() {
    ready = Future.value();
    return const ConversationWorkspace(
      projects: [
        ChatProject(
          'project',
          'Camera comparisons',
          instructions: 'Use manufacturer specifications.',
        ),
      ],
      memberships: {'chat': 'project'},
    );
  }
}

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
      testWidgets(
        'workspace fits a small phone in $language ${dark ? 'dark' : 'light'}',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = const Size(320, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final db = AppDatabase.forTesting(NativeDatabase.memory());
          final container = ProviderContainer(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              llamaEngineProvider.overrideWithValue(TestEngine()),
              settingsProvider.overrideWith(TestSettings.new),
              modelManagerProvider.overrideWith(TestModels.new),
              conversationWorkspaceProvider.overrideWith(_Workspace.new),
              chatsProvider.overrideWith(
                (_) => Stream.value([
                  Chat(
                    id: 'chat',
                    title: 'Compare Nikon Z30 and Sony ZV-E10',
                    createdAt: DateTime(2026),
                    updatedAt: DateTime(2026),
                    pinned: false,
                    tags: '[]',
                    overridesJson: '{}',
                  ),
                ]),
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
              child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                locale: Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: const RepaintBoundary(
                  key: Key('capture'),
                  child: ConversationWorkspacePage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Camera comparisons').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(Checkbox).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.text('Compare Nikon Z30 and Sony ZV-E10'),
            findsOneWidget,
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final picture = await boundary.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory('artifacts/completion-ui')
              ..createSync(recursive: true);
            await File(
              '${dir.path}/workspace-$language-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        },
      );
    }
  }
  testWidgets('a deleted final answer leaves a regenerate control', (
    tester,
  ) async {
    var regenerated = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ChatBubble(
            message: ChatMessage(
              id: 'question',
              role: ChatRole.user,
              content: 'Explain this',
              timestamp: DateTime(2026),
            ),
            onRegenerate: () => regenerated = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('regenerate-missing-answer')));
    expect(regenerated, isTrue);
  });
}
