import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/memory_banner.dart';

/// Records what the dialog decided; nothing touches the database here.
class _Chat extends ChatNotifier {
  final edits = <List<String>>[];
  final discards = <bool>[];
  @override
  ChatState build() => const ChatState();
  @override
  Future<void> dismissLearned({bool discard = false}) async {
    discards.add(discard);
  }

  @override
  Future<void> editLearned(List<String> contents) async {
    edits.add(contents);
  }
}

void main() {
  final date = DateTime(2026, 1, 1);

  Future<_Chat> open(WidgetTester tester) async {
    final chat = _Chat();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatProvider.overrideWith(() => chat)],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MemoryBanner([
              Memory(
                id: 'm1',
                content: 'Likes tea',
                pinned: false,
                createdAt: date,
                updatedAt: date,
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('memory-edit')));
    await tester.pumpAndSettle();
    return chat;
  }

  testWidgets('the review field outlives the dialog closing animation', (
    tester,
  ) async {
    final chat = await open(tester);
    await tester.enterText(
      find.byKey(const Key('memory-edit-field')),
      'Likes green tea',
    );
    await tester.tap(find.byKey(const Key('memory-save')));
    // The route's future completes on pop, before the exit transition ends:
    // the dialog's field is still in the tree and must still be usable.
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('memory-edit-field')),
    );
    expect(
      field.controller!.text,
      'Likes green tea',
      reason: 'the field is still mounted, so its controller is still alive',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('memory-edit-field')), findsNothing);
    expect(chat.edits.single, ['Likes green tea']);
    expect(chat.discards, isEmpty);
  });
}
