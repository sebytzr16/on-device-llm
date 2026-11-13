import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'device_encryption.dart';

final _log = Logger('DatabaseEncryption');

/// Startup-only migration. No Drift connection may be open while [prepare]
/// runs. A failed copy never replaces the original database.
class DatabaseEncryption {
  DatabaseEncryption(this.encryption);
  final DeviceEncryption encryption;

  static Future<bool> isEncrypted(File file) async {
    if (!await file.exists() || await file.length() == 0) return false;
    final input = await file.open();
    try {
      return !const ListEquality().equals(
        await input.read(16),
        ascii.encode('SQLite format 3\u0000'),
      );
    } finally {
      await input.close();
    }
  }

  /// This must be the first SQL on every encrypted connection. Keep the key
  /// binary across the Drift isolate boundary and construct SQL only there.
  static void setup(Database db, Uint8List? key) {
    try {
      if (key != null) db.execute(keyPragma('key', key));
      db.select('SELECT count(*) FROM sqlite_master');
    } catch (_) {
      // SQLite exceptions can include SQL text. Never propagate key SQL.
      throw const EncryptionRecovery();
    }
  }

  static String keyPragma(String pragma, Uint8List key) =>
      'PRAGMA $pragma="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"';

  Future<Uint8List?> keyForFile(File file) async =>
      await isEncrypted(file) ? encryption.databaseKey() : null;

  static Map<String, int> _verify(Database db) {
    if (db
        .select('PRAGMA quick_check')
        .any((row) => row.values.first != 'ok')) {
      throw const EncryptionRecovery();
    }
    return {
      // Rekey may VACUUM, compacting FTS shadow tables. Compare logical user
      // tables (including virtual tables), whose row counts must not change.
      for (final row in db.select('PRAGMA table_list'))
        if (row['schema'] == 'main' &&
            (row['type'] == 'table' || row['type'] == 'virtual') &&
            !(row['name'] as String).startsWith('sqlite_'))
          row['name'] as String:
              db
                      .select(
                        'SELECT count(*) FROM "${(row['name'] as String).replaceAll('"', '""')}"',
                      )
                      .first
                      .values
                      .first
                  as int,
    };
  }

  Future<Map<String, int>> _check(File file, {bool full = true}) async {
    final key = await keyForFile(file);
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      setup(db, key);
      return full ? _verify(db) : const {};
    } catch (_) {
      encryption.recovery.value = true;
      throw const EncryptionRecovery();
    } finally {
      db.close();
      key?.fillRange(0, key.length, 0);
    }
  }

  /// Preflight before a pending restore can replace the live database. Missing
  /// files are valid during the restore's own rename journal; don't create one.
  Future<void> verifyExisting(File file) async {
    if (await file.exists() && await file.length() > 0) {
      try {
        await _check(file, full: false);
      } on EncryptionRecovery {
        if (!await _setAsideBrokenWal(file)) rethrow;
        encryption.recovery.value = false;
        await _check(file, full: false);
      }
    }
  }

  /// A write-ahead log that no longer decrypts (left by a process killed
  /// mid-write) must not lock the user out of an intact database. When the
  /// main file alone opens and passes quick_check, move the log and its
  /// index into a dated folder beside it. Nothing is deleted.
  Future<bool> _setAsideBrokenWal(File file) async {
    final wal = File('${file.path}-wal');
    if (!await wal.exists()) return false;
    final probeDir = await Directory.systemTemp.createTemp('odl-walcheck-');
    try {
      final probe = await file.copy(p.join(probeDir.path, 'main.sqlite'));
      await _check(probe);
    } on EncryptionRecovery {
      return false;
    } finally {
      await probeDir.delete(recursive: true);
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final aside = Directory(
      p.join(file.parent.path, 'recovered-wal-${stamp.split('.').first}'),
    );
    await aside.create(recursive: true);
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('${file.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.rename(
          p.join(aside.path, '${p.basename(file.path)}$suffix'),
        );
      }
    }
    _log.warning('Set aside an unreadable write-ahead log in ${aside.path}');
    return true;
  }

  Future<void> prepare(File file, {void Function(String)? checkpoint}) async {
    final original = File('${file.path}.dbenc-original');
    final pending = File('${file.path}.dbenc-pending');
    // If killed between the two renames, restore the known-good original.
    if (!await file.exists() && await original.exists()) {
      await _check(original);
      await original.rename(file.path);
    }
    if (await original.exists()) {
      await _check(original); // A missing old key must never cause deletion.
      await _check(file);
      await original.delete();
    }
    if (!await file.exists() && await pending.exists()) {
      encryption.recovery.value = true;
      throw const EncryptionRecovery();
    }
    final encrypt = await encryption.enabled();
    final wasEncrypted = await isEncrypted(file);
    Uint8List? targetKey;
    if (encrypt) {
      targetKey = await encryption.databaseKey(create: !wasEncrypted);
    }
    try {
      if (!await file.exists() || await file.length() == 0) {
        if (encrypt) {
          final db = sqlite3.open(file.path);
          try {
            setup(db, targetKey);
            db.execute('VACUUM');
          } finally {
            db.close();
          }
          if (!await isEncrypted(file)) throw const EncryptionRecovery();
        }
        return;
      }
      final counts = await _check(
        file,
        full: encrypt != wasEncrypted || await pending.exists(),
      );
      // An abandoned copy may be incomplete. Discard it only after the live
      // original verifies, then recreate it from that original.
      if (await pending.exists()) await pending.delete();
      for (final suffix in ['-journal', '-wal', '-shm']) {
        final sidecar = File('${pending.path}$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      if (encrypt == wasEncrypted) return;
      final oldKey = await keyForFile(file);
      final source = sqlite3.open(file.path);
      try {
        setup(source, oldKey);
        source.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        if (source.select('PRAGMA journal_mode=DELETE').first.values.first !=
            'delete') {
          throw const EncryptionRecovery();
        }
      } finally {
        source.close();
      }
      await file.copy(pending.path);
      checkpoint?.call('copied');
      final copy = sqlite3.open(pending.path);
      try {
        setup(copy, oldKey);
        copy.execute(
          encrypt ? keyPragma('rekey', targetKey!) : "PRAGMA rekey=''",
        );
      } catch (_) {
        throw const EncryptionRecovery();
      } finally {
        copy.close();
        oldKey?.fillRange(0, oldKey.length, 0);
      }
      if (await isEncrypted(pending) != encrypt) {
        throw const EncryptionRecovery(); // Fail closed if codec is absent.
      }
      final copiedCounts = await _check(pending);
      if (!const MapEquality<String, int>().equals(counts, copiedCounts)) {
        throw const EncryptionRecovery();
      }
      // Force the completed database bytes to disk before publishing the copy.
      final output = await pending.open(mode: FileMode.append);
      await output.flush();
      await output.close();
      checkpoint?.call('verified');
      await file.rename(original.path);
      checkpoint?.call('saved');
      await pending.rename(file.path);
      checkpoint?.call('installed');
      await _check(file);
      await original.delete();
    } on EncryptionRecovery {
      encryption.recovery.value = true;
      rethrow;
    } finally {
      targetKey?.fillRange(0, targetKey.length, 0);
    }
  }
}
