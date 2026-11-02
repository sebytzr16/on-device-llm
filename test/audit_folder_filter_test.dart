import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/conversations_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Chat extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}

Chat _chat(String id, String title, String? folder) => Chat(
  id: id,
  title: title,
  folder: folder,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  pinned: false,
  tags: '[]',
  overridesJson: '{}',
);

void main() {
  testWidgets(
    'empty results keep folder controls and removed folders clear (P2-45)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final chats = StreamController<List<Chat>>();
      final work = _chat('work', 'Work notes', 'Work');
      final home = _chat('home', 'Home notes', null);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          chatProvider.overrideWith(_Chat.new),
          chatsProvider.overrideWith((_) => chats.stream),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await chats.close();
        await db.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: ConversationsSheet()),
          ),
        ),
      );
      chats.add([work, home]);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Work'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('chat-search')), 'Home');
      await tester.pump();
      expect(find.byKey(const Key('folder-bar')), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pump();
      expect(find.text('Home notes'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('chat-search')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Work'));
      await tester.pumpAndSettle();
      chats.add([home]);
      await tester.pumpAndSettle();
      expect(find.text('Home notes'), findsOneWidget);
      chats.add([work, home]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All'))
            .selected,
        isTrue,
      );
      expect(find.text('Home notes'), findsOneWidget);
      expect(find.text('Work notes'), findsOneWidget);
    },
  );
}
