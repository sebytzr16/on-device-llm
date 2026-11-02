import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/export/chat_document.dart';
import 'package:ondevice_llm/features/chat/domain/export/document_draft_service.dart';
import 'package:ondevice_llm/features/chat/domain/export/document_draft_store.dart';

ChatDocument _doc(String text) => ChatDocument(
  title: 'Doc',
  messages: [
    ChatMessage(
      id: 'a',
      role: ChatRole.assistant,
      content: text,
      timestamp: DateTime.utc(2026),
    ),
  ],
);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('drafts'));
  tearDown(() async => dir.delete(recursive: true));

  test('drafts of a temporary chat stay in memory (P1-21)', () async {
    final store = DocumentDraftStore(
      drafts: ChatDraftStore(root: () async => dir),
      persist: false,
    );
    await store.save('new', 'report', 'secret draft');
    expect((await store.read('new', 'report')).single.content, 'secret draft');
    final files = Directory('${dir.path}/drafts');
    expect(
      files.existsSync() ? files.listSync() : const <FileSystemEntity>[],
      isEmpty,
    );
  });

  test('another redaction or selection gets its own revisions (P2-37)', () {
    final full = _doc('My card is 1234.');
    final masked = full.redacted(['1234']);
    expect(
      DocumentDraftStore.sourceKey('chat', full),
      isNot(DocumentDraftStore.sourceKey('chat', masked)),
    );
    expect(
      DocumentDraftStore.sourceKey('chat', masked),
      DocumentDraftStore.sourceKey('chat', full.redacted(['1234'])),
    );
  });

  test('a source past the limit is reported as trimmed (P2-43)', () {
    expect(DocumentDraftService.truncates(_doc('short')), isFalse);
    expect(
      DocumentDraftService.truncates(
        _doc('x' * (DocumentDraftService.maxInputChars + 1)),
      ),
      isTrue,
    );
  });
}
