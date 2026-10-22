import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/export/chat_document.dart';
import 'package:ondevice_llm/features/chat/domain/export/document_blocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('combined turns keep citation identities and changed snapshots', () {
    ChatMessage sourced(String id, String url, String excerpt) => ChatMessage(
      id: id,
      role: ChatRole.assistant,
      timestamp: DateTime(2026),
      content: 'Finding [1]. Unknown [9].',
      sourcesJson: jsonEncode([
        {'number': 1, 'url': url, 'excerpt': excerpt},
      ]),
    );
    final result = ChatDocument(
      title: 'Research',
      messages: [
        sourced('one', 'https://example.com/a', 'First evidence'),
        sourced('two', 'https://example.com/b', 'Second evidence'),
        sourced('three', 'https://example.com/a', 'Changed evidence'),
        sourced('four', 'https://example.com/a', 'First evidence'),
      ],
    ).normalizedCitations();
    expect(result.messages.map((m) => m.content), [
      'Finding [1]. Unknown [unverified source].',
      'Finding [2]. Unknown [unverified source].',
      'Finding [3]. Unknown [unverified source].',
      'Finding [1]. Unknown [unverified source].',
    ]);
    expect(
      jsonDecode(result.messages[2].sourcesJson).single['excerpt'],
      'Changed evidence',
    );
  });

  ChatMessage message(
    String id,
    String content, {
    String status = 'complete',
    String? reasoning,
  }) => ChatMessage(
    id: id,
    role: ChatRole.assistant,
    content: content,
    timestamp: DateTime.utc(2026, 9, 22),
    status: status,
    reasoning: reasoning,
    sourcesJson: '[{"number":1,"title":"Paper","url":"https://example.org"}]',
  );

  test(
    'all formats use the visible selection and omit reasoning by default',
    () async {
      final document = ChatDocument.select(
        title: 'Research & notes',
        chatId: 'chat-1',
        messages: [
          message(
            'live',
            '# Result\nEvidence <confirmed>',
            reasoning: 'private',
          ),
          message('old', 'old branch', status: 'superseded:b:complete'),
          message('comparison', 'alternative', status: 'alternative'),
        ],
      );
      expect(document.messages.map((m) => m.id), ['live']);
      for (final output in [document.text, document.markdown, document.html]) {
        expect(output, contains('Evidence'));
        expect(output, isNot(contains('private')));
        expect(output, isNot(contains('old branch')));
        expect(output, isNot(contains('alternative')));
        expect(output, contains('https://example.org'));
      }
      final data = jsonDecode(document.json) as Map<String, dynamic>;
      expect(data['version'], 2);
      expect(data['messages'], hasLength(1));
      expect((data['messages'] as List).single, isNot(contains('reasoning')));

      final archive = ZipDecoder().decodeBytes(document.docx);
      final entry = archive.findFile('word/document.xml');
      expect(entry, isNotNull);
      final xml = utf8.decode(entry!.content as List<int>);
      expect(xml, contains('Research &amp; notes'));
      expect(xml, contains('Evidence &lt;confirmed&gt;'));
      expect(xml, isNot(contains('private')));

      final pdf = await document.pdf();
      expect(utf8.decode(pdf.take(5).toList()), '%PDF-');
      expect(pdf.length, greaterThan(1000));
    },
  );

  test('branches and reasoning require explicit options', () {
    final document = ChatDocument.select(
      messages: [
        message('live', 'Current', reasoning: 'steps'),
        message('old', 'Earlier', status: 'superseded:b:complete'),
      ],
      includeBranches: true,
      includeReasoning: true,
      selectedIds: {'old'},
    );
    expect(document.messages.map((m) => m.id), ['old']);
    expect(document.text, contains('Earlier'));
    expect(document.text, isNot(contains('Current')));
  });

  test('redaction covers body, reasoning and source metadata', () {
    final document = ChatDocument.select(
      title: 'Private Alice',
      chatId: 'Alice-chat',
      messages: [
        ChatMessage(
          id: 'Alice-private',
          role: ChatRole.assistant,
          modelId: 'Alice-model',
          content: 'Alice wrote this',
          reasoning: 'Alice checked it',
          timestamp: DateTime.utc(2026),
          sourcesJson:
              '[{"number":1,"title":"Alice profile","url":"https://example.org/Alice"}]',
        ),
      ],
      includeReasoning: true,
    ).redacted(['Alice']);
    for (final output in [
      document.text,
      document.markdown,
      document.html,
      document.json,
    ]) {
      expect(output, isNot(contains('Alice')));
      expect(output, contains('[redacted]'));
    }
  });
  test('Markdown blocks preserve headings, lists, code and tables', () async {
    const content =
        '# Heading\n\n- One\n- Two\n\n1. Third\n\n'
        '```dart\nfinal x = 1;\n```\n\n'
        '| Name | Value |\n| --- | --- |\n| A | B |';
    final blocks = DocumentBlocks.parse(content);
    expect(blocks.map((b) => b.kind), [
      DocumentBlockKind.heading,
      DocumentBlockKind.bullet,
      DocumentBlockKind.bullet,
      DocumentBlockKind.numbered,
      DocumentBlockKind.code,
      DocumentBlockKind.table,
    ]);
    final document = ChatDocument(
      messages: [message('one', content)],
      title: 'Test',
    );
    final archive = ZipDecoder().decodeBytes(document.docx);
    final xml = utf8.decode(
      archive.findFile('word/document.xml')!.content as List<int>,
    );
    expect(xml, contains('<w:tbl>'));
    expect(xml, contains('Courier New'));
    expect(xml, contains('• One'));
    expect(xml, isNot(contains('```')));
    final pdf = await document.pdf();
    expect(utf8.decode(pdf.take(5).toList()), '%PDF-');
  });
}
