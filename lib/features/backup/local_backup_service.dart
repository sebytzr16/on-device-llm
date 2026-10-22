import '../schedule/scheduled_prompt.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../data/local/database/app_database.dart';
import '../attachments/data/attachment_store.dart';
import '../chat/domain/temporary_files.dart';
import 'backup_cipher.dart';

/// Encrypted, local-only snapshot of chats, knowledge, attachments and
/// user settings. Multi-gigabyte model weights and secure-store API keys are
/// deliberately excluded.
class LocalBackupService {
  static const maxEntries = 10000;
  static const _prefs = [
    'text_recognition_options_v1',
    'conversation_workspace_v1',
    'context_summaries_v1',
    'inference_settings_v1',
    'presets_v1',
    'model_profiles_v1',
    // Kept so backups made before Goals v2 still validate.
    'active_goal_v1',
    'active_goal_v2',
    'goal_draft_v1',
    'onboarding_done_v1',
    'prompt_shortcuts_v1',
    'chat_model_pins_v1',
    _schedules,
  ];

  /// Scheduled prompts live on the Android side (their alarms must survive
  /// a reboot); they travel in the backup under this name and are handed
  /// back to the platform, which sets their alarms again, on restore.
  static const _schedules = 'scheduled_prompts';

  static Future<Directory> _support() => getApplicationSupportDirectory();

  /// File exports stream the SQLite snapshot, attachments, ZIP and AES-GCM.
  /// The returned encrypted file belongs to the caller and must be cleaned up.
  static Future<File> createFile(AppDatabase db, String password) async {
    final support = await _support();
    await support.create(recursive: true);
    final temp = await support.createTemp('backup-working-');
    final output = File(
      p.join(
        support.path,
        'backup-${DateTime.now().microsecondsSinceEpoch}.odllm',
      ),
    );
    try {
      final snapshot = File(p.join(temp.path, 'data.sqlite'));
      await db.customStatement('VACUUM INTO ?', [snapshot.path]);
      final attachments = await AttachmentStore.directory();
      final prefs = await SharedPreferences.getInstance();
      final temporaryFiles =
          (prefs.getStringList(TemporaryFiles.key) ?? <String>[]).toSet();
      final schedules = await ScheduleStore.list();
      final metadata = <String, Object?>{
        for (final key in _prefs)
          if (prefs.containsKey(key)) key: prefs.get(key),
        if (schedules.isNotEmpty)
          _schedules: jsonEncode([for (final s in schedules) s.toJson()]),
      };
      final prefsFile = File(p.join(temp.path, 'preferences.json'));
      await prefsFile.writeAsString(jsonEncode(metadata), flush: true);
      final manifest = File(p.join(temp.path, 'manifest.json'));
      await manifest.writeAsString(
        jsonEncode({
          'version': 1,
          'attachmentsRoot': attachments.path,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      final files = <(File, String)>[
        (snapshot, 'data.sqlite'),
        (prefsFile, 'preferences.json'),
        (manifest, 'manifest.json'),
      ];
      var total = await snapshot.length();
      await for (final file in attachments.list(followLinks: false)) {
        if (file is! File ||
            !_safeName(p.basename(file.path)) ||
            temporaryFiles.contains(p.basename(file.path))) {
          continue;
        }
        total += await file.length();
        files.add((file, 'attachments/${p.basename(file.path)}'));
        if (total > BackupCipher.maxFileBytes || files.length > maxEntries) {
          throw const FormatException(
            'Backup exceeds the 2 GB or 10,000-file limit.',
          );
        }
      }
      final drafts = Directory(p.join(support.path, 'drafts'));
      if (await drafts.exists()) {
        await for (final file in drafts.list(followLinks: false)) {
          final name = p.basename(file.path);
          if (file is! File || !_safeName(name) || !name.endsWith('.json')) {
            continue;
          }
          total += await file.length();
          files.add((file, 'drafts/$name'));
          if (total > BackupCipher.maxFileBytes || files.length > maxEntries) {
            throw const FormatException(
              'Backup exceeds the 2 GB or 10,000-file limit.',
            );
          }
        }
      }
      final zip = File(p.join(temp.path, 'archive.zip'));
      final encoder = ZipFileEncoder()..create(zip.path);
      try {
        for (final (file, name) in files) {
          await encoder.addFile(file, name);
        }
      } finally {
        await encoder.close();
      }
      await BackupCipher.encryptFile(zip, output, password);
      return output;
    } finally {
      await temp.delete(recursive: true);
    }
  }

  static Future<void> stageFile(File encrypted, String password) async {
    final support = await _support();
    final temp = await support.createTemp('backup-verify-');
    try {
      final zip = File(p.join(temp.path, 'archive.zip'));
      await BackupCipher.decryptFile(encrypted, zip, password);
      final input = InputFileStream(zip.path);
      try {
        await _stageArchive(
          ZipDecoder().decodeStream(input, verify: true),
          maxBytes: BackupCipher.maxFileBytes,
        );
      } finally {
        await input.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  }

  static Future<Uint8List> create(AppDatabase db, String password) async {
    final support = await _support();
    await support.create(recursive: true);
    final temp = await support.createTemp('backup-working-');
    try {
      final snapshot = File(p.join(temp.path, 'data.sqlite'));
      await db.customStatement('VACUUM INTO ?', [snapshot.path]);
      final attachments = await AttachmentStore.directory();
      final prefs = await SharedPreferences.getInstance();
      final temporaryFiles =
          (prefs.getStringList(TemporaryFiles.key) ?? <String>[]).toSet();
      final schedules = await ScheduleStore.list();
      final values = <String, Object?>{
        for (final key in _prefs)
          if (prefs.containsKey(key)) key: prefs.get(key),
        if (schedules.isNotEmpty)
          _schedules: jsonEncode([for (final s in schedules) s.toJson()]),
      };
      final archive = Archive();
      void add(String name, List<int> bytes) {
        archive.addFile(ArchiveFile.bytes(name, bytes));
      }

      if (await snapshot.length() > BackupCipher.maxPlainBytes) {
        throw const FormatException(
          'Database exceeds the backup safety limit.',
        );
      }
      add('data.sqlite', await snapshot.readAsBytes());
      add('preferences.json', utf8.encode(jsonEncode(values)));
      add(
        'manifest.json',
        utf8.encode(
          jsonEncode({
            'version': 1,
            'attachmentsRoot': attachments.path,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      );
      var total = await snapshot.length();
      await for (final entity in attachments.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!_safeName(name) || temporaryFiles.contains(name)) continue;
        total += await entity.length();
        if (total > BackupCipher.maxPlainBytes ||
            archive.files.length >= maxEntries) {
          throw const FormatException(
            'Backup exceeds the 96 MB or 10,000-file safety limit.',
          );
        }
        add('attachments/$name', await entity.readAsBytes());
      }
      final zip = ZipEncoder().encodeBytes(archive);
      return await BackupCipher.encrypt(zip, password);
    } finally {
      await temp.delete(recursive: true);
    }
  }

  static Future<void> stage(Uint8List encrypted, String password) async {
    final plain = await BackupCipher.decrypt(encrypted, password);
    final archive = ZipDecoder().decodeBytes(plain, verify: true);
    await _stageArchive(archive);
  }

  static Future<void> _stageArchive(
    Archive archive, {
    int maxBytes = BackupCipher.maxPlainBytes,
  }) async {
    if (archive.files.length > maxEntries) {
      throw const FormatException('Backup has too many files.');
    }
    var total = 0;
    final files = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (!file.isFile ||
          file.isSymbolicLink ||
          !(const {
                'data.sqlite',
                'preferences.json',
                'manifest.json',
              }.contains(file.name) ||
              (file.name.startsWith('attachments/') &&
                  _safeName(file.name.substring('attachments/'.length))) ||
              (file.name.startsWith('drafts/') &&
                  _safeName(file.name.substring('drafts/'.length)) &&
                  file.name.endsWith('.json')))) {
        throw const FormatException('Backup contains an invalid file path.');
      }
      total += file.size;
      if (file.size < 0 || total > maxBytes || files.containsKey(file.name)) {
        throw const FormatException(
          'Backup is oversized or has duplicate files.',
        );
      }
      files[file.name] = file;
    }
    if (!files.keys.toSet().containsAll([
      'data.sqlite',
      'preferences.json',
      'manifest.json',
    ])) {
      throw const FormatException('Backup is incomplete.');
    }
    if (files['manifest.json']!.size > 1024 * 1024 ||
        files['preferences.json']!.size > 4 * 1024 * 1024) {
      throw const FormatException('Backup metadata exceeds its safety limit.');
    }
    final manifest =
        jsonDecode(utf8.decode(files['manifest.json']!.content as List<int>))
            as Map<String, dynamic>;
    if (manifest['version'] != 1 || manifest['attachmentsRoot'] is! String) {
      throw const FormatException('Unsupported backup version.');
    }
    final settings = jsonDecode(
      utf8.decode(files['preferences.json']!.content as List<int>),
    );
    if (settings is! Map || settings.keys.any((key) => !_prefs.contains(key))) {
      throw const FormatException('Backup settings are invalid.');
    }
    final support = await _support();
    final pending = Directory(p.join(support.path, 'restore_pending'));
    if (await pending.exists()) {
      throw StateError('A restore is already waiting for an app restart.');
    }
    await pending.create(recursive: true);
    try {
      for (final entry in files.entries) {
        final path = p.join(pending.path, entry.key);
        final file = File(path);
        await file.parent.create(recursive: true);
        final output = OutputFileStream(file.path);
        try {
          entry.value.writeContent(output);
        } finally {
          await output.close();
        }
      }
      final staged = File(p.join(pending.path, 'data.sqlite'));
      _validateDatabase(staged, allowOlder: true);
      // Migrate and validate staging, before replacing any live user files.
      final migrated = AppDatabase.forTesting(NativeDatabase(staged));
      try {
        await migrated.customSelect('SELECT 1').get();
      } finally {
        await migrated.close();
      }
      _validateDatabase(staged);
    } catch (_) {
      await pending.delete(recursive: true);
      rethrow;
    }
  }

  static bool _safeName(String name) =>
      name.isNotEmpty &&
      RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name) &&
      name != '.' &&
      name != '..';

  static void _validateDatabase(File file, {bool allowOlder = false}) {
    final sqlite = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      final version =
          sqlite.select('PRAGMA user_version').first.values.first as int;
      if (sqlite.select('PRAGMA integrity_check').first.values.first != 'ok' ||
          version < 1 ||
          version > AppDatabase.currentSchemaVersion ||
          (!allowOlder && version != AppDatabase.currentSchemaVersion)) {
        throw const FormatException(
          'Backup database is invalid or incompatible.',
        );
      }
    } finally {
      sqlite.close();
    }
  }

  /// Called before the app opens its database on the next launch.
  static Future<void> applyPendingRestore() async {
    final support = await _support();
    final pending = Directory(p.join(support.path, 'restore_pending'));
    if (!await pending.exists()) return;
    // The files were already swapped; finishRestore will repair paths and
    // settings. This also makes a crash between swap and opening SQLite safe.
    if (await File(p.join(support.path, 'restore_rewrite.json')).exists()) {
      return;
    }
    final previous = Directory(p.join(support.path, 'restore_previous'));
    if (await previous.exists()) {
      throw StateError('A previous restore needs recovery before retrying.');
    }
    _validateDatabase(File(p.join(pending.path, 'data.sqlite')));
    final manifest =
        jsonDecode(
              await File(p.join(pending.path, 'manifest.json')).readAsString(),
            )
            as Map<String, dynamic>;
    final documents = await getApplicationDocumentsDirectory();
    final liveDb = File(p.join(documents.path, 'ondevice_llm.sqlite'));
    final liveAttachments = Directory(p.join(documents.path, 'attachments'));
    final liveDrafts = Directory(p.join(support.path, 'drafts'));
    await previous.create(recursive: true);
    final oldFiles = <String>[];
    var oldAttachments = false;
    var newDb = false;
    var newAttachments = false;
    var oldDrafts = false, newDrafts = false;
    try {
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('${liveDb.path}$suffix');
        if (await file.exists()) {
          await file.rename(p.join(previous.path, 'data.sqlite$suffix'));
          oldFiles.add(suffix);
        }
      }
      if (await liveAttachments.exists()) {
        await liveAttachments.rename(p.join(previous.path, 'attachments'));
        oldAttachments = true;
      }
      await File(p.join(pending.path, 'data.sqlite')).rename(liveDb.path);
      newDb = true;
      final stagedAttachments = Directory(p.join(pending.path, 'attachments'));
      if (await stagedAttachments.exists()) {
        await stagedAttachments.rename(liveAttachments.path);
      } else {
        await liveAttachments.create();
      }
      newAttachments = true;
      if (await liveDrafts.exists()) {
        await liveDrafts.rename(p.join(previous.path, 'drafts'));
        oldDrafts = true;
      }
      final stagedDrafts = Directory(p.join(pending.path, 'drafts'));
      if (await stagedDrafts.exists()) {
        await stagedDrafts.rename(liveDrafts.path);
      } else {
        await liveDrafts.create();
      }
      newDrafts = true;
      await File(p.join(support.path, 'restore_rewrite.json')).writeAsString(
        jsonEncode({'attachmentsRoot': manifest['attachmentsRoot']}),
        flush: true,
      );
    } catch (_) {
      if (newDb && await liveDb.exists()) await liveDb.delete();
      if (newAttachments && await liveAttachments.exists()) {
        await liveAttachments.delete(recursive: true);
      }
      if (newDrafts && await liveDrafts.exists()) {
        await liveDrafts.delete(recursive: true);
      }
      if (oldDrafts) {
        await Directory(
          p.join(previous.path, 'drafts'),
        ).rename(liveDrafts.path);
      }
      for (final suffix in oldFiles) {
        await File(
          p.join(previous.path, 'data.sqlite$suffix'),
        ).rename('${liveDb.path}$suffix');
      }
      if (oldAttachments) {
        await Directory(
          p.join(previous.path, 'attachments'),
        ).rename(liveAttachments.path);
      }
      await previous.delete(recursive: true);
      if (await pending.exists()) await pending.delete(recursive: true);
      rethrow;
    }
  }

  /// Rewrite absolute attachment paths for a different app sandbox and
  /// remove rollback files only after the restored database opens.
  static Future<void> finishRestore(AppDatabase db) async {
    final support = await _support();
    final marker = File(p.join(support.path, 'restore_rewrite.json'));
    if (!await marker.exists()) return;
    final manifest = jsonDecode(await marker.readAsString()) as Map;
    final oldRoot = manifest['attachmentsRoot'] as String;
    final documents = await getApplicationDocumentsDirectory();
    final newRoot = p.join(documents.path, 'attachments');
    if (oldRoot != newRoot) {
      String escaped(String value) {
        final encoded = jsonEncode(value);
        return encoded.substring(1, encoded.length - 1);
      }

      await db.customStatement(
        'UPDATE messages SET attachments_json = replace(attachments_json, ?, ?)',
        [escaped(oldRoot), escaped(newRoot)],
      );
      final drafts = Directory(p.join(support.path, 'drafts'));
      if (await drafts.exists()) {
        await for (final file in drafts.list(followLinks: false)) {
          if (file is! File || !file.path.endsWith('.json')) continue;
          final raw = await file.readAsString();
          // Same JSON path escaping as the message attachment records.
          await file.writeAsString(
            raw.replaceAll(escaped(oldRoot), escaped(newRoot)),
            flush: true,
          );
        }
      }
    }
    final pending = Directory(p.join(support.path, 'restore_pending'));
    final savedPrefs =
        jsonDecode(
              await File(
                p.join(pending.path, 'preferences.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    // A backup replaces the schedules too (none in it: none after).
    final saved = savedPrefs[_schedules];
    await ScheduleStore.save(
      saved is String ? ScheduledPrompt.decodeList(saved) : const [],
    );
    for (final key in _prefs) {
      if (key == _schedules) continue;
      final value = savedPrefs[key];
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else {
        await prefs.remove(key);
      }
    }
    await marker.delete();
    for (final name in ['restore_previous', 'restore_pending']) {
      final dir = Directory(p.join(support.path, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}
