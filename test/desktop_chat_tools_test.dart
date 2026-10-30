import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/chat/domain/chat_copy_repository.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/export/desktop_chat_export.dart';

void main() {
  final date = DateTime.utc(2026, 1, 2, 3, 4, 5);
  final messages = [
    ChatMessage(
      id: 'u',
      role: ChatRole.user,
      content: 'Question',
      timestamp: date,
      attachments: const [
        Attachment(
          id: 'a',
          kind: AttachmentKind.document,
          name: 'notes.txt',
          mime: 'text/plain',
          path: 'private-file',
          sizeBytes: 3,
        ),
      ],
    ),
    ChatMessage(
      id: 'a',
      role: ChatRole.assistant,
      content: 'Answer [1]',
      timestamp: date,
      modelId: 'model',
      reasoning: 'Think <carefully>',
      sourcesJson: jsonEncode([
        {'title': 'Evidence [one]', 'url': 'https://example.com/a(b)'},
        {'title': 'Unsafe', 'url': 'javascript:alert(1)'},
      ]),
    ),
  ];
  DesktopChatExport document(List<ChatMessage> turns) => DesktopChatExport(
    title: 'Chat\n# title',
    model: 'model',
    date: date,
    messages: turns,
  );

  test(
    'Markdown has metadata, ordered role headings, collapsed thinking and source links',
    () {
      final markdown = document(messages).markdown;
      expect(
        markdown,
        startsWith(
          '# Chat \\# title\n\nModel: model\nDate: 2026-01-02T03:04:05.000Z',
        ),
      );
      expect(
        markdown.indexOf('## user'),
        lessThan(markdown.indexOf('## assistant')),
      );
      expect(
        markdown,
        contains(
          '<details>\n<summary>Thinking</summary>\n\nThink &lt;carefully&gt;\n\n</details>',
        ),
      );
      expect(
        markdown,
        contains('[Evidence \\[one\\]](<https://example.com/a%28b%29>)'),
      );
      expect(markdown, contains('notes.txt'));
      expect(markdown, isNot(contains('javascript:')));
      expect(markdown, isNot(contains('private-file')));
    },
  );

  test(
    'JSON v1 has stable keys, UTC dates, model and attachment names only',
    () {
      final json = jsonDecode(document(messages).json) as Map<String, dynamic>;
      expect(json.keys, ['version', 'title', 'model', 'date', 'messages']);
      expect(json['version'], 1);
      expect(json['date'], '2026-01-02T03:04:05.000Z');
      final turns = json['messages'] as List;
      expect(turns.first['role'], 'user');
      expect(turns.first['attachments'], ['notes.txt']);
      expect(turns.last['timestamp'], json['date']);
      expect(turns.last['model'], 'model');
      expect(turns.last['thinking'], 'Think <carefully>');
      expect(document(messages).json, isNot(contains('private-file')));
    },
  );

  test('empty exports and malformed source data are supported', () {
    expect(jsonDecode(document([]).json)['messages'], isEmpty);
    final broken = ChatMessage(
      id: 'broken',
      role: ChatRole.system,
      content: 'Instructions',
      timestamp: date,
      sourcesJson: '{}',
    );
    expect(document([broken]).markdown, contains('## system'));
    expect(
      jsonDecode(document([broken]).json)['messages'][0]['sources'],
      isEmpty,
    );
  });

  test('Markdown labels can be localized without changing the JSON schema', () {
    final export = DesktopChatExport(
      title: 'Chat',
      model: 'model',
      date: date,
      messages: messages,
      modelLabel: 'Mod\u00e8le',
      dateLabel: 'Date',
      thinkingLabel: 'R\u00e9flexion',
      roleLabels: const {
        ChatRole.user: 'Utilisateur',
        ChatRole.assistant: 'Assistant',
      },
    );
    expect(export.markdown, contains('Mod\u00e8le: model'));
    expect(export.markdown, contains('## Utilisateur'));
    expect(export.markdown, contains('<summary>R\u00e9flexion</summary>'));
    expect(jsonDecode(export.json)['messages'][0]['role'], 'user');
  });

  group('stored conversation copies', () {
    late AppDatabase db;
    late Directory directory;
    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      directory = await Directory.systemTemp.createTemp('chat-copy-test-');
      final file = await File(
        '${directory.path}/notes.txt',
      ).writeAsString('notes');
      await db.upsertChat(
        ChatsCompanion.insert(
          id: 'chat',
          title: 'Original',
          createdAt: date,
          updatedAt: date,
          modelId: const Value('model'),
          overridesJson: const Value('{"temperature":0.5}'),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'm$i',
            chatId: 'chat',
            role: i.isEven ? 'user' : 'assistant',
            content: 'message $i',
            timestamp: date,
            sequence: i,
            parentId: Value(i == 0 ? null : 'm${i - 1}'),
            reasoning: i == 1 ? const Value('thinking') : const Value.absent(),
            sourcesJson: const Value(
              '[{"title":"Source","url":"https://example.com"}]',
            ),
            attachmentsJson: Value(
              i == 0
                  ? jsonEncode([
                      Attachment(
                        id: 'file',
                        kind: AttachmentKind.document,
                        name: 'notes.txt',
                        mime: 'text/plain',
                        path: file.path,
                        sizeBytes: 5,
                      ).toJson(),
                    ])
                  : '[]',
            ),
          ),
        );
      }
    });
    tearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });

    test(
      'duplicate preserves data with new identities and remapped ancestry',
      () async {
        final id = await ChatCopyRepository(
          db,
        ).copy('chat', title: 'Original (copy)');
        final copy = await db.getMessages(id);
        final source = await db.getMessages('chat');
        expect(copy.map((m) => m.content), source.map((m) => m.content));
        expect(copy.map((m) => m.sequence), [0, 1, 2]);
        expect(
          copy
              .map((m) => m.id)
              .toSet()
              .intersection(source.map((m) => m.id).toSet()),
          isEmpty,
        );
        expect(copy.first.parentId, isNull);
        expect(copy[1].parentId, copy.first.id);
        expect(copy.last.parentId, copy[1].id);
        expect(copy[1].reasoning, 'thinking');
        expect(copy[1].sourcesJson, source[1].sourcesJson);
        expect((await db.getChat(id))!.overridesJson, '{"temperature":0.5}');
        expect((await db.getChat(id))!.modelId, 'model');
        expect((await db.getChat(id))!.title, 'Original (copy)');
      },
    );

    test('branch includes cutoff and leaves original unchanged', () async {
      final id = await ChatCopyRepository(
        db,
      ).copy('chat', title: 'Original (branch)', throughMessageId: 'm1');
      expect((await db.getMessages(id)).map((m) => m.content), [
        'message 0',
        'message 1',
      ]);
      expect((await db.getChat(id))!.title, 'Original (branch)');
      expect(await db.getMessages('chat'), hasLength(3));
    });

    test('branch from an older answer copies only its own path', () async {
      // A regenerated answer to m0 (stored later) and a question under it.
      for (final (id, role, parent, sequence) in [
        ('alt', 'assistant', 'm0', 3),
        ('m4', 'user', 'alt', 4),
      ]) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: id,
            chatId: 'chat',
            role: role,
            content: id,
            timestamp: date,
            sequence: sequence,
            parentId: Value(parent),
            status: Value(
              id == 'alt' ? 'alternative' : 'superseded:b1:complete',
            ),
          ),
        );
      }
      final older = await ChatCopyRepository(
        db,
      ).copy('chat', title: 'Branch', throughMessageId: 'm1');
      expect((await db.getMessages(older)).map((m) => m.content), [
        'message 0',
        'message 1',
      ]);
      final alternative = await ChatCopyRepository(
        db,
      ).copy('chat', title: 'Branch', throughMessageId: 'alt');
      final copy = await db.getMessages(alternative);
      expect(copy.map((m) => m.content), ['message 0', 'alt']);
      // The fork's path is live in the new chat; the original is unchanged.
      expect(copy.map((m) => m.status), ['complete', 'complete']);
      final m4 = await ChatCopyRepository(
        db,
      ).copy('chat', title: 'Branch', throughMessageId: 'm4');
      expect((await db.getMessages(m4)).map((m) => m.status), [
        'complete',
        'complete',
        'complete',
      ]);
      expect(
        (await db.getMessages('chat')).firstWhere((m) => m.id == 'alt').status,
        'alternative',
      );
      expect(copy.last.parentId, copy.first.id);
    });

    test('branch at the first message copies exactly one turn', () async {
      final id = await ChatCopyRepository(
        db,
      ).copy('chat', title: 'Branch', throughMessageId: 'm0');
      expect(await db.getMessages(id), hasLength(1));
    });

    test('attachment files survive removal of originals', () async {
      final id = await ChatCopyRepository(db).copy('chat', title: 'Copy');
      final source =
          jsonDecode((await db.getMessages('chat')).first.attachmentsJson)[0]
              as Map;
      final copied =
          jsonDecode((await db.getMessages(id)).first.attachmentsJson)[0]
              as Map;
      expect(copied['id'], isNot(source['id']));
      expect(copied['path'], isNot(source['path']));
      await File(source['path'] as String).delete();
      await db.deleteChat('chat');
      expect(await File(copied['path'] as String).readAsString(), 'notes');
    });

    test(
      'invalid cutoff and missing chat do not create conversations',
      () async {
        await expectLater(
          ChatCopyRepository(
            db,
          ).copy('chat', title: 'Copy', throughMessageId: 'missing'),
          throwsStateError,
        );
        await expectLater(
          ChatCopyRepository(db).copy('missing', title: 'Copy'),
          throwsStateError,
        );
        expect(await db.allChats(), hasLength(1));
      },
    );

    test(
      'failed attachment copy rolls back the new chat and copied files',
      () async {
        await File('${directory.path}/notes.txt').delete();
        await expectLater(
          ChatCopyRepository(db).copy('chat', title: 'Copy'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await db.allChats(), hasLength(1));
        expect(await directory.list().toList(), isEmpty);
      },
    );
  });
}
