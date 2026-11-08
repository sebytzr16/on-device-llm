import '../schedule/scheduled_prompt.dart';
import '../goals/goal_watch_store.dart';
import '../goals/goal_watch.dart';
import '../attachments/data/bounded_zip.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../core/storage/app_directories.dart';
import '../../data/local/database/app_database.dart';
import '../attachments/data/attachment_store.dart';
import '../chat/domain/temporary_files.dart';
import 'backup_cipher.dart';

/// Encrypted, local-only snapshot of chats, knowledge, attachments and
/// user settings. Multi-gigabyte model weights and secure-store API keys are
/// deliberately excluded.
class LocalBackupService {
  static const maxEntries = 10000;
  static const backedUpPreferenceKeys = [
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
    'goal_history_v1',
    'goal_watches_v1',
    'model_sampling_variants_v1',
    'onboarding_done_v1',
    'prompt_shortcuts_v1',
    'chat_model_pins_v1',
    _schedules,
  ];

  /// Device-local state and caches deliberately do not travel to another app.
  static const excludedPreferenceKeys = {
    'workspace_jobs_v1':
        'Server-owned jobs belong to this installation and connection.',
    'workspace_capabilities_v1':
        'Connection capability cache, rebuilt from the server.',
    'active_model_downloads_v1': 'Transfers belong to this installation.',
    'model_download_history_v1': 'Transfers belong to this installation.',
    'temporary_attachment_cleanup_v1': 'Temporary attachments are excluded.',
    'desktop.modelsFolder': 'Device-local model paths.',
    'desktop.previousModelFolders': 'Device-local model paths.',
    'device_host_access_token': 'Secret; never included in a backup.',
    'remote_usage_v1': 'Device-local usage accounting.',
    'benchmarks_v1': 'Device-specific performance measurements.',
    'desktop_tune_receipts_v1': 'Device-specific performance measurements.',
    'desktop_speed_results_v1': 'Device-specific performance measurements.',
    'server_pool_v1': 'Device-local runtime configuration.',
    'hosting_port_v1': 'Device-local listener configuration.',
    'search_misses_v1': 'Retrieval cache.',
    'retired_model_names_v1': 'Device-local model inventory.',
    'hidden_library_models_v1': 'Device-local model inventory.',
    'model_recommendations_v1': 'Rebuilt from installed models.',
    'thinking_off_profiles_2026_09_28': 'One-time migration marker.',
    'thinking_off_2026_09_28': 'One-time migration marker.',
    'sampling_defaults_2026_10_04': 'One-time migration marker.',
    'desktop_advanced': 'Device-local presentation preference.',
    'desktop_lean_prompt': 'Device-local prompt preference.',
  };

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
      final watches = await GoalWatchStore.list();
      final metadata = <String, Object?>{
        for (final key in backedUpPreferenceKeys)
          if (prefs.containsKey(key)) key: prefs.get(key),
        GoalWatchStore.key: GoalWatches.encode(watches),
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
          readZipMetadata(input, maxEntries: maxEntries),
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
    final file = await createFile(db, password);
    try {
      // Byte callers still have the legacy envelope's in-memory limit.
      // File exports can use the larger streaming limit.
      if (await file.length() > BackupCipher.maxEncryptedBytes) {
        throw const FormatException(
          'Backup exceeds the 96 MB byte export limit.',
        );
      }
      return await file.readAsBytes();
    } finally {
      await file.delete();
    }
  }

  static Future<void> stage(Uint8List encrypted, String password) async {
    final plain = await BackupCipher.decrypt(encrypted, password);
    final archive = readZipMetadata(
      InputMemoryStream(plain),
      maxEntries: maxEntries,
    );
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
        jsonDecode(
              utf8.decode(_entryBytes(files['manifest.json']!, 1024 * 1024)),
            )
            as Map<String, dynamic>;
    if (manifest['version'] != 1 || manifest['attachmentsRoot'] is! String) {
      throw const FormatException('Unsupported backup version.');
    }
    final settings = jsonDecode(
      utf8.decode(_entryBytes(files['preferences.json']!, 4 * 1024 * 1024)),
    );
    if (settings is! Map ||
        settings.keys.any((key) => !backedUpPreferenceKeys.contains(key))) {
      throw const FormatException('Backup settings are invalid.');
    }
    final support = await _support();
    final pending = Directory(p.join(support.path, 'restore_pending'));
    if (await pending.exists()) {
      throw StateError('A restore is already waiting for an app restart.');
    }
    await pending.create(recursive: true);
    try {
      var actual = 0;
      for (final entry in files.entries) {
        final path = p.join(pending.path, entry.key);
        final file = File(path);
        await file.parent.create(recursive: true);
        final output = OutputFileStream(file.path);
        try {
          actual += inflateZipEntry(
            entry.value,
            maxBytes - actual,
            output.writeBytes,
          );
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
      await _rewritePaths(
        pending,
        manifest['attachmentsRoot'] as String,
        (await AttachmentStore.directory()).path,
        validateOnly: true,
      );
      await File(p.join(pending.path, 'ready')).writeAsString('1', flush: true);
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

  static List<int> _entryBytes(ArchiveFile file, int limit) {
    final out = BytesBuilder(copy: false);
    inflateZipEntry(file, limit, out.add);
    return out.takeBytes();
  }

  static Future<void> _rewritePaths(
    Directory pending,
    String oldRoot,
    String newRoot, {
    bool validateOnly = false,
    File? database,
    Directory? draftDirectory,
  }) async {
    String checkedPath(Object? raw) {
      if (raw is! String) {
        throw const FormatException('Invalid attachment path.');
      }
      String? name;
      for (final style in [p.Style.posix, p.Style.windows]) {
        final context = p.Context(style: style);
        for (final root in [oldRoot, newRoot]) {
          if (context.isAbsolute(raw) &&
              context.normalize(context.dirname(raw)) ==
                  context.normalize(root)) {
            name = context.basename(raw);
          }
        }
      }
      if (_safeName(raw)) name = raw;
      if (name == null || !_safeName(name)) {
        throw const FormatException('Attachment path is outside app storage.');
      }
      return p.join(newRoot, name);
    }

    Object? rewrite(Object? value) {
      if (value is List) return value.map(rewrite).toList();
      if (value is Map) {
        return <String, Object?>{
          for (final entry in value.entries)
            entry.key as String: entry.key == 'path'
                ? checkedPath(entry.value)
                : rewrite(entry.value),
        };
      }
      return value;
    }

    final sqlite = sqlite3.open(
      database?.path ?? p.join(pending.path, 'data.sqlite'),
    );
    try {
      sqlite.execute('BEGIN IMMEDIATE');
      for (final row in sqlite.select(
        'SELECT id, attachments_json FROM messages WHERE attachments_json IS NOT NULL',
      )) {
        final raw = row['attachments_json'] as String;
        if (raw.isEmpty) continue;
        final encoded = jsonEncode(rewrite(jsonDecode(raw)));
        if (!validateOnly) {
          sqlite.execute(
            'UPDATE messages SET attachments_json = ? WHERE id = ?',
            [encoded, row['id']],
          );
        }
      }
      for (final row in sqlite.select(
        'SELECT id, original_file FROM knowledge_docs WHERE original_file IS NOT NULL',
      )) {
        if (!_safeName(row['original_file'] as String) ||
            !_safeName(row['id'] as String)) {
          throw const FormatException('Invalid knowledge original path.');
        }
      }
      sqlite.execute('COMMIT');
    } finally {
      sqlite.close();
    }
    final drafts = draftDirectory ?? Directory(p.join(pending.path, 'drafts'));
    if (await drafts.exists()) {
      await for (final file in drafts.list(followLinks: false)) {
        if (file is! File) throw const FormatException('Invalid draft.');
        if (!file.path.endsWith('.json')) continue;
        final encoded = jsonEncode(
          rewrite(jsonDecode(await file.readAsString())),
        );
        if (!validateOnly) {
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(encoded, flush: true);
          await temp.rename(file.path);
        }
      }
    }
  }

  /// Called before the app opens its database on the next launch. Each rename
  /// is repeatable: its destination proves it completed even after a power cut.
  static Future<void> applyPendingRestore({
    void Function(String)? checkpoint,
  }) async {
    final support = await _support();
    final pending = Directory(p.join(support.path, 'restore_pending'));
    final marker = File(p.join(support.path, 'restore_rewrite.json'));
    if (!await pending.exists()) {
      if (await marker.exists()) {
        final journal = jsonDecode(await marker.readAsString()) as Map;
        if (journal['phase'] == 'complete') {
          await _cleanupRestore(support, marker);
        }
      }
      return;
    }
    final documents = await appDataDirectory();
    final previous = Directory(p.join(support.path, 'restore_previous'));
    Map<String, dynamic> journal;
    if (await marker.exists()) {
      journal = jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      if (journal['phase'] == null) {
        // Complete an already-swapped restore from an older app version.
        final liveDb = File(_livePath('data.sqlite', documents, support));
        _validateDatabase(liveDb);
        await _rewritePaths(
          pending,
          journal['attachmentsRoot'] as String,
          p.join(documents.path, 'attachments'),
          database: liveDb,
          draftDirectory: Directory(p.join(support.path, 'drafts')),
        );
        await _saveJournal(marker, {'phase': 'installed'});
        return;
      }
      if (journal['phase'] == 'installed' || journal['phase'] == 'complete') {
        return;
      }
    } else {
      // An interrupted staging copy has never touched live data.
      if (!await File(p.join(pending.path, 'ready')).exists()) {
        await pending.delete(recursive: true);
        return;
      }
      if (await previous.exists()) {
        throw StateError('A previous restore needs recovery before retrying.');
      }
      _validateDatabase(File(p.join(pending.path, 'data.sqlite')));
      final manifest =
          jsonDecode(
                await File(
                  p.join(pending.path, 'manifest.json'),
                ).readAsString(),
              )
              as Map;
      await _rewritePaths(
        pending,
        manifest['attachmentsRoot'] as String,
        p.join(documents.path, 'attachments'),
      );
      for (final name in ['attachments', 'drafts']) {
        await Directory(p.join(pending.path, name)).create(recursive: true);
      }
      final old = <String>[];
      for (final name in [
        'data.sqlite',
        'data.sqlite-wal',
        'data.sqlite-shm',
        'attachments',
        'drafts',
      ]) {
        final live = _livePath(name, documents, support);
        if (await FileSystemEntity.type(live, followLinks: false) !=
            FileSystemEntityType.notFound) {
          old.add(name);
        }
      }
      journal = {'phase': 'swapping', 'old': old};
      await _saveJournal(marker, journal);
      checkpoint?.call('journal');
    }
    await previous.create(recursive: true);
    for (final name in (journal['old'] as List).cast<String>()) {
      final saved = p.join(previous.path, name);
      if (await FileSystemEntity.type(saved, followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      final live = _livePath(name, documents, support);
      if (name == 'attachments' || name == 'drafts') {
        await Directory(live).rename(saved);
      } else {
        await File(live).rename(saved);
      }
      checkpoint?.call('save:$name');
    }
    for (final name in ['data.sqlite', 'attachments', 'drafts']) {
      final staged = p.join(pending.path, name);
      final live = _livePath(name, documents, support);
      if (await FileSystemEntity.type(staged, followLinks: false) ==
          FileSystemEntityType.notFound) {
        if (await FileSystemEntity.type(live, followLinks: false) ==
            FileSystemEntityType.notFound) {
          throw StateError('Restore destination is missing: $name');
        }
        continue;
      }
      if (name == 'data.sqlite') {
        await File(staged).rename(live);
      } else {
        await Directory(staged).rename(live);
      }
      checkpoint?.call('install:$name');
    }
    await _saveJournal(marker, {...journal, 'phase': 'installed'});
    checkpoint?.call('installed');
  }

  static String _livePath(
    String name,
    Directory documents,
    Directory support,
  ) => name == 'drafts'
      ? p.join(support.path, name)
      : p.join(
          documents.path,
          name.replaceFirst('data.sqlite', 'ondevice_llm.sqlite'),
        );

  static Future<void> _saveJournal(
    File marker,
    Map<String, dynamic> journal,
  ) async {
    final temp = File('${marker.path}.tmp');
    await temp.writeAsString(jsonEncode(journal), flush: true);
    await temp.rename(marker.path);
  }

  /// Rewrite absolute attachment paths for a different app sandbox and
  /// remove rollback files only after the restored database opens.
  static Future<void> finishRestore(
    AppDatabase db, {
    void Function(String)? checkpoint,
  }) async {
    final support = await _support();
    final marker = File(p.join(support.path, 'restore_rewrite.json'));
    if (!await marker.exists()) return;
    final journal =
        jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
    if (journal['phase'] == null || journal['phase'] == 'swapping') {
      throw StateError('Restore must finish before opening the database.');
    }
    if (journal['phase'] == 'complete') {
      await _cleanupRestore(support, marker);
      return;
    }
    await db.customSelect('SELECT 1').get();
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
    final watches = GoalWatches.decode(
      savedPrefs[GoalWatchStore.key] as String? ?? '[]',
    );
    for (final watch in await GoalWatchStore.list()) {
      await GoalWatchStore.remove(watch.id);
    }
    for (final watch in watches) {
      if (!await GoalWatchStore.put(watch)) {
        throw StateError('Could not restore watch.');
      }
    }
    final schedules = saved is String
        ? ScheduledPrompt.decodeList(saved)
        : <ScheduledPrompt>[];
    await ScheduleStore.save([
      for (final schedule in schedules)
        if (schedule.kind != 'goal' ||
            watches.any((watch) => watch.id == schedule.id))
          schedule,
    ]);
    for (final key in backedUpPreferenceKeys) {
      if (key == _schedules || key == GoalWatchStore.key) continue;
      final value = savedPrefs[key];
      final bool saved;
      if (value is String) {
        saved = await prefs.setString(key, value);
      } else if (value is bool) {
        saved = await prefs.setBool(key, value);
      } else if (value is List && value.every((item) => item is String)) {
        saved = await prefs.setStringList(key, value.cast<String>());
      } else {
        saved = await prefs.remove(key);
      }
      if (!saved) throw StateError('Could not restore preference $key.');
    }
    checkpoint?.call('settings');
    await _saveJournal(marker, {...journal, 'phase': 'complete'});
    checkpoint?.call('complete');
    await _cleanupRestore(support, marker);
  }

  static Future<void> _cleanupRestore(Directory support, File marker) async {
    for (final name in ['restore_previous', 'restore_pending']) {
      final dir = Directory(p.join(support.path, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    await marker.delete();
  }
}
