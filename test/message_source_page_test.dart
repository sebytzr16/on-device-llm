import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/presentation/screens/message_source_page.dart';

/// Only `isGenerating` matters to this page: a turn starting or stopping is
/// what rebuilds it, which used to issue the message query again.
class _Chat extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
  void turnRunning(bool running) =>
      state = state.copyWith(isGenerating: running);
}

/// Counts the message queries: the page must read its rows once, not once per
/// build (review 2026-11-20).
class _CountingDatabase extends AppDatabase {
  _CountingDatabase() : super.forTesting(NativeDatabase.memory());
  int messageQueries = 0;

  @override
  Future<List<Message>> getMessages(String chatId) {
    messageQueries++;
    return super.getMessages(chatId);
  }
}

void main() {
  late _CountingDatabase db;
  late _Chat chat;
  late ProviderContainer container;
  final date = DateTime(2026, 1, 1);

  setUp(() async {
    db = _CountingDatabase();
    chat = _Chat();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chatProvider.overrideWith(() => chat),
      ],
    );
    await db
        .into(db.chats)
        .insert(
          ChatsCompanion.insert(
            id: 'c1',
            title: 'Chat',
            createdAt: date,
            updatedAt: date,
          ),
        );
    for (final (i, text) in ['first question', 'second answer'].indexed) {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'm${i + 1}',
          chatId: 'c1',
          role: i.isEven ? 'user' : 'assistant',
          content: text,
          timestamp: date,
          sequence: i,
        ),
      );
    }
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets('a rebuild asks the database once, not again per rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MessageSourcePage(chatId: 'c1', messageId: 'm2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    String shown() => tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? '')
        .join('\n');
    expect(shown(), contains('second answer'));
    expect(db.messageQueries, 1, reason: 'opening the page loads the rows');

    // The chat state changes while the page is open: a turn starts and the
    // page rebuilds. On the old code that rebuild ran `getMessages` again.
    chat.turnRunning(true);
    await tester.pump();
    expect(
      db.messageQueries,
      1,
      reason: 'a turn starting must not query the rows again',
    );
    expect(
      shown(),
      contains('second answer'),
      reason: 'the rows stay while a turn runs',
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Any rebuild, here a window resize, keeps both the rows and the count.
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump();
    expect(db.messageQueries, 1, reason: 'a resize must not query again');
    expect(shown(), contains('second answer'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    chat.turnRunning(false);
    await tester.pump();
    expect(db.messageQueries, 1, reason: 'a turn ending must not query again');
    expect(shown(), contains('second answer'));
  });
}
