import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/backup/local_backup_service.dart';
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';

class BackupPaths extends PathProviderPlatform {
  final String support;
  String documents;
  BackupPaths(this.support, this.documents);
  @override
  Future<String?> getApplicationSupportPath() async => support;
  @override
  Future<String?> getApplicationDocumentsPath() async => documents;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final streamed in [false, true]) {
    test(
      '${streamed ? 'Streamed v10' : 'Legacy'} backup restores chats, attachments and settings into a new sandbox',
      () async {
        final root = await Directory.systemTemp.createTemp('odllm-backup-');
        final originalProvider = PathProviderPlatform.instance;
        final source = Directory(p.join(root.path, 'source'))..createSync();
        final target = Directory(p.join(root.path, 'target'))..createSync();
        final support = Directory(p.join(root.path, 'support'))..createSync();
        final paths = BackupPaths(support.path, source.path);
        PathProviderPlatform.instance = paths;
        SharedPreferences.setMockInitialValues({
          'inference_settings_v1': '{"temperature":0.2}',
          // Goals v2, shortcuts and chat pins were not in the backup before.
          'active_goal_v2': '{"objective":"EV report"}',
          'prompt_shortcuts_v1': '[{"name":"tldr","template":"TL;DR {input}"}]',
          'chat_model_pins_v1': '{"chat-1":"coder"}',
          'goal_draft_v1': '{"objective":"Unsent Goal"}',
        });
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        try {
          await db.customSelect('SELECT count(*) FROM chats').get();
          await db.customStatement(
            'INSERT INTO chats (id, title, created_at, updated_at) '
            'VALUES (?, ?, ?, ?)',
            ['chat-1', 'Saved research', 1, 1],
          );
          final attachmentDir = Directory(p.join(source.path, 'attachments'))
            ..createSync();
          final photo = File(p.join(attachmentDir.path, 'photo.png'));
          await photo.writeAsBytes([1, 2, 3]);
          await File(
            p.join(attachmentDir.path, 'temporary.txt'),
          ).writeAsString('private temporary content');
          final sourcePrefs = await SharedPreferences.getInstance();
          await sourcePrefs.setStringList('temporary_attachment_cleanup_v1', [
            'temporary.txt',
          ]);
          await db.customStatement(
            'INSERT INTO messages '
            '(id, chat_id, role, content, timestamp, sequence, attachments_json) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              'message-1',
              'chat-1',
              'user',
              'Read this',
              1,
              1,
              jsonEncode([
                {
                  'id': 'photo',
                  'kind': 'image',
                  'name': 'photo.png',
                  'mime': 'image/png',
                  'path': photo.path,
                  'sizeBytes': 3,
                },
              ]),
            ],
          );
          File? encryptedFile;
          List<int>? encryptedBytes;
          if (streamed) {
            await ChatDraftStore().save(
              'chat-1',
              ChatDraft(
                text: 'An unsent question',
                attachments: [
                  Attachment(
                    id: 'photo',
                    kind: AttachmentKind.image,
                    name: 'photo.png',
                    mime: 'image/png',
                    path: photo.path,
                    sizeBytes: 3,
                  ),
                ],
              ),
            );
            // Recreate the actual previous schema, then migrate authenticated staging.
            for (final column in [
              'content_hash',
              'extraction_format',
              'extraction_warning',
              'original_file',
              'previous_version_id',
              'active',
            ]) {
              await db.customStatement(
                'ALTER TABLE knowledge_docs DROP COLUMN $column',
              );
            }
            for (final column in [
              'source_message_id',
              'pinned',
              'expires_at',
            ]) {
              await db.customStatement(
                'ALTER TABLE memories DROP COLUMN $column',
              );
            }
            await db.customStatement('PRAGMA user_version = 10');
            await db.customStatement(
              'ALTER TABLE knowledge_chunks DROP COLUMN page_number',
            );
            // v10-v13 kept a page cache, dropped at v14.
            await db.customStatement(
              'CREATE TABLE web_pages (url TEXT PRIMARY KEY)',
            );
            encryptedFile = await LocalBackupService.createFile(
              db,
              'a strong backup password',
            );
            await ChatDraftStore().save(
              'chat-1',
              const ChatDraft(text: 'Changed after backup'),
            );
          } else {
            encryptedBytes = await LocalBackupService.create(
              db,
              'a strong backup password',
            );
          }
          await db.close();
          if (streamed) {
            await LocalBackupService.stageFile(
              encryptedFile!,
              'a strong backup password',
            );
          } else {
            await LocalBackupService.stage(
              Uint8List.fromList(encryptedBytes!),
              'a strong backup password',
            );
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('inference_settings_v1', 'changed');
          await prefs.remove('active_goal_v2');
          await prefs.setString('prompt_shortcuts_v1', '[]');
          await prefs.remove('chat_model_pins_v1');
          paths.documents = target.path;
          await LocalBackupService.applyPendingRestore();
          final restored = AppDatabase();
          try {
            await LocalBackupService.finishRestore(restored);
            final chats = await restored
                .customSelect('SELECT title FROM chats')
                .get();
            expect(chats.single.read<String>('title'), 'Saved research');
            final rows = await restored
                .customSelect('SELECT attachments_json FROM messages')
                .get();
            final attachments =
                jsonDecode(rows.single.read<String>('attachments_json'))
                    as List;
            expect(
              attachments.single['path'],
              p.join(target.path, 'attachments', 'photo.png'),
            );
            expect(
              await File(
                p.join(target.path, 'attachments', 'photo.png'),
              ).readAsBytes(),
              [1, 2, 3],
            );
            expect(
              prefs.getString('inference_settings_v1'),
              '{"temperature":0.2}',
            );
            expect(
              await File(
                p.join(target.path, 'attachments', 'temporary.txt'),
              ).exists(),
              isFalse,
            );
            expect(
              prefs.getString('active_goal_v2'),
              '{"objective":"EV report"}',
            );
            expect(prefs.getString('prompt_shortcuts_v1'), contains('tldr'));
            expect(prefs.getString('chat_model_pins_v1'), '{"chat-1":"coder"}');
            expect(
              prefs.getString('goal_draft_v1'),
              '{"objective":"Unsent Goal"}',
            );
            if (streamed) {
              final draft = await ChatDraftStore().read('chat-1');
              expect(draft.text, 'An unsent question');
              expect(
                draft.attachments.single.path,
                p.join(target.path, 'attachments', 'photo.png'),
              );
              final columns = await restored
                  .customSelect('PRAGMA table_info(memories)')
                  .get();
              expect(
                columns.map((row) => row.read<String>('name')),
                containsAll(['source_message_id', 'pinned', 'expires_at']),
              );
            }
          } finally {
            await restored.close();
          }
        } finally {
          PathProviderPlatform.instance = originalProvider;
          await root.delete(recursive: true);
        }
      },
    );
  }
}
