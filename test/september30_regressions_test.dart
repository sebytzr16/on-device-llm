import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:ondevice_llm/core/design/markdown_math.dart';
import 'package:ondevice_llm/core/design/markdown_tables.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/domain/message_deletion.dart';
import 'package:ondevice_llm/features/memory/domain/user_memory.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence_audit.dart';
import 'package:ondevice_llm/features/chat/domain/research_recipes.dart';

void main() {
  test('camera weather sealing is product research, not a forecast', () {
    expect(
      ResearchRecipe.forQuestion('Is the Nikon Z30 weather-sealed?').id,
      'product',
    );
    expect(
      ResearchRecipe.forQuestion('Canon R50 specifications').id,
      'product',
    );
    expect(
      ResearchRecipe.forQuestion('Compare Canon R50 to Pixel 9').id,
      'product',
    );
    expect(
      ResearchRecipe.forQuestion('Weather forecast in Toronto').id,
      'weather',
    );
  });
  testWidgets('explicit math delimiters render and malformed math falls back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: r'$$42$$ and \(a+b\) and \[x^2\] and $\invalidcommand{x}$',
            inlineSyntaxes: [MathSyntax()],
            builders: {'math': MathBuilder()},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsNWidgets(4));
    expect(find.text(r'\invalidcommand{x}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('ordinary world questions do not receive personal notes', () {
    const notes = ['The user owns a Pixel phone', 'The user is a chef'];
    expect(UserMemory.relevant('Which Pixel phone is newest?', notes), isEmpty);
    expect(UserMemory.relevant('Is my Pixel phone old?', notes), [0]);
    expect(
      UserMemory.relevant('Which Pixel phone is newest?', notes, pinned: {1}),
      [1],
    );
    expect(
      UserMemory.relevant('my Pixel phone', List.filled(8, notes[0])),
      hasLength(3),
    );
  });
  test('a cited feature needs matching source polarity', () {
    expect(
      EvidenceAudit.check('The Z30 is weather-sealed [1].', [
        'The Z9 is weather-sealed.',
      ]).passes,
      isFalse,
    );
    expect(
      EvidenceAudit.check('The Z30 is weather-sealed [1].', [
        'The Z30 is not weather-sealed. The Z9 is weather-sealed.',
      ]).passes,
      isFalse,
    );
    expect(
      EvidenceAudit.check(
        'The Z30 has no viewfinder and is weather-sealed [1].',
        ['The Z30 has no viewfinder and is weather-sealed.'],
      ).passes,
      isTrue,
    );
    expect(
      EvidenceAudit.check('The Z30 is weather-sealed [1].', [
        'The Z30 is not weather-sealed.',
      ]).passes,
      isFalse,
    );
    expect(
      EvidenceAudit.check('The Z30 is not weather-sealed [1].', [
        'The Z30 is not weather-sealed.',
      ]).passes,
      isTrue,
    );
    expect(
      EvidenceAudit.check('Weather sealing is unverified [1].', [
        'No specifications available.',
      ]).passes,
      isTrue,
    );
  });
  test(
    'delete answer restores an earlier version and undo preserves later rows',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.now();
      await db.upsertChat(
        ChatsCompanion.insert(
          id: 'c',
          title: 'Chat',
          createdAt: now,
          updatedAt: now,
        ),
      );
      Future<void> row(
        String id,
        int seq,
        String role,
        String? parent, [
        String status = 'complete',
      ]) => db.insertMessage(
        MessagesCompanion.insert(
          id: id,
          chatId: 'c',
          role: role,
          content: id,
          timestamp: now,
          sequence: seq,
          parentId: Value(parent),
          status: Value(status),
        ),
      );
      await row('q', 0, 'user', null);
      await row('old', 1, 'assistant', 'q', 'superseded:b:complete');
      await row('a', 2, 'assistant', 'q');
      await row('q2', 3, 'user', 'a');
      final deletion = (await MessageDeletion.delete(db, 'c', 'a'))!;
      var rows = await db.getMessages('c');
      expect(rows.where((r) => r.id == 'a'), isEmpty);
      expect(rows.firstWhere((r) => r.id == 'old').status, 'complete');
      expect(rows.firstWhere((r) => r.id == 'q2').parentId, 'old');
      await row('new', 4, 'assistant', 'q2');
      expect(await deletion.undo(db), isTrue);
      rows = await db.getMessages('c');
      expect(rows.firstWhere((r) => r.id == 'q2').parentId, 'a');
      expect(
        rows.firstWhere((r) => r.id == 'old').status,
        'superseded:b:complete',
      );
      expect(rows.any((r) => r.id == 'new'), isTrue);
      expect(await deletion.undo(db), isFalse);
      final pair = (await MessageDeletion.delete(db, 'c', 'a', pair: true))!;
      expect((await db.getMessages('c')).map((r) => r.id), ['q2', 'new']);
      expect(await pair.undo(db), isTrue);
    },
  );
  testWidgets('math, prices, code and wide tables render without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MarkdownBody(
              data:
                  r'Price $20 and $30. Code `$x=2$`. Formula $17 \times 20 = 340$.'
                  '\n\n'
                  '| Product | Description |\n|---|---|\n| Camera | A very long description that should wrap without clipping the next column |',
              inlineSyntaxes: [MathSyntax()],
              builders: {'math': MathBuilder()},
              styleSheet: MarkdownStyleSheet(
                tableColumnWidth: markdownTableColumns(context),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsOneWidget);
    expect(tester.takeException(), isNull);
    final scroller = find.byType(SingleChildScrollView).last;
    await tester.drag(scroller, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
