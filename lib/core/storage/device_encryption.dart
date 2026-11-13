import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_directories.dart';

/// A recoverable failure. Callers must preserve the original bytes.
class EncryptionRecovery implements Exception {
  const EncryptionRecovery();
  @override
  String toString() =>
      'Encrypted data could not be opened. Restore access to '
      'this device’s secure storage or restore a password-protected backup. '
      'Keep the original files; do not reset app data. No data was deleted.';
}

/// Device encryption policy and vault keys, independent of backup passwords.
/// All file access and transitions in this isolate share one ordered queue.
class DeviceEncryption {
  DeviceEncryption({
    FlutterSecureStorage? storage,
    Future<SharedPreferences> Function()? preferences,
    Future<List<Directory>> Function()? directories,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: false),
           ),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _directories = directories ?? _defaultDirectories,
       _nativeWatches = directories == null && Platform.isAndroid;

  // Replaceable for tests so backup/startup flows use an injected vault.
  static DeviceEncryption instance = DeviceEncryption();
  static const settingKey = 'device_file_encryption_v1';
  static const migrationKey = 'device_file_encryption_pending_v1';
  static const keyName = 'device_file_data_key_v1';
  static const databaseKeyName = 'device_database_key_v1';
  static const goalKeys = [
    'active_goal_v1',
    'active_goal_v2',
    'goal_draft_v1',
    'goal_history_v1',
    'goal_watches_v1',
  ];
  // Magic, format version, then 12-byte nonce, ciphertext and 16-byte tag.
  static const _magic = [0x4f, 0x44, 0x4c, 0x45, 0x4e, 0x43, 0];
  static const _header = [..._magic, 1];
  static const _textPrefix = 'ODLENC1:';
  static const watchChannel = MethodChannel('ondevice_llm/schedule');
  final bool _nativeWatches;
  final FlutterSecureStorage _storage;
  final Future<SharedPreferences> Function() _preferences;
  final Future<List<Directory>> Function() _directories;
  final _cipher = AesGcm.with256bits();
  final recovery = ValueNotifier<bool>(false);
  Future<void>? _tail;

  static Future<List<Directory>> _defaultDirectories() async {
    final support = await getApplicationSupportDirectory();
    final data = await appDataDirectory();
    return [
      Directory(p.join(support.path, 'drafts')),
      Directory(p.join(support.path, 'document_embeddings')),
      Directory(p.join(data.path, 'attachments')),
      Directory(p.join(data.path, 'made')),
    ];
  }

  Future<T> _ordered<T>(Future<T> Function() work) {
    // Do not retain a completed future: its zone may no longer be running
    // (for example after a widget test, or while runAsync performs file I/O).
    final previous = _tail;
    final result = previous == null
        ? Future<T>.microtask(work)
        : previous.then((_) => work());
    late final Future<void> tail;
    void release() {
      if (identical(_tail, tail)) _tail = null;
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    _tail = tail;
    return result;
  }

  Never _unavailable() {
    recovery.value = true;
    throw const EncryptionRecovery();
  }

  /// Separate from the file envelope key. Only create when the database and
  /// every retained migration original are known to be plaintext.
  Future<Uint8List> databaseKey({bool create = false}) async {
    try {
      var value = await _storage.read(key: databaseKeyName);
      if (value == null && create) {
        final key = await _cipher.newSecretKey();
        value = base64Encode(await key.extractBytes());
        await _storage.write(key: databaseKeyName, value: value);
      }
      if (value == null) return _unavailable();
      final bytes = base64Decode(value);
      if (bytes.length != 32) return _unavailable();
      return bytes;
    } catch (_) {
      return _unavailable();
    }
  }

  /// Called only after startup has verified the database's requested policy.
  Future<void> completeMigration() async {
    if (!await (await _preferences()).remove(migrationKey)) {
      throw const FileSystemException('Could not complete migration. Retry.');
    }
  }

  static bool isEncrypted(List<int> bytes) =>
      bytes.length >= _magic.length &&
      List.generate(
        _magic.length,
        (i) => bytes[i] == _magic[i],
      ).every((v) => v);

  Future<bool> migrationPending() async =>
      (await _preferences()).getBool(migrationKey) ?? false;

  Future<void> checkWritable() => _ordered(() async {
    if (await enabled()) await _key();
  });

  Future<bool> enabled() async {
    final prefs = await _preferences();
    await prefs.reload(); // The Android watch worker is a separate engine.
    return prefs.getBool(settingKey) ?? false;
  }

  Future<String> encodeText(String clear) => _ordered(() async {
    final encrypt = await enabled();
    return _encodeText(clear, encrypt);
  });

  Future<String> _encodeText(String clear, bool encrypt) async => encrypt
      ? '$_textPrefix${base64Encode(await _encode(utf8.encode(clear), true))}'
      : clear;

  Future<List<Map<String, dynamic>>> decodeWatches(String raw) =>
      _ordered(() => _decodeWatches(raw));

  Future<List<Map<String, dynamic>>> _decodeWatches(String raw) async {
    final rows = (jsonDecode(raw) as List).cast<Map>();
    return [
      for (final row in rows)
        if (row['encrypted'] is String)
          Map<String, dynamic>.from(
            jsonDecode(await _decodeText(row['encrypted'] as String)) as Map,
          )
        else
          Map<String, dynamic>.from(row),
    ];
  }

  Future<String> _encodeWatches(
    List<Map<String, dynamic>> rows,
    bool encrypt,
  ) async => jsonEncode([
    for (final row in rows)
      encrypt
          ? {
              'id': row['id'],
              'encrypted': await _encodeText(jsonEncode(row), true),
            }
          : row,
  ]);

  Future<SecretKey> _key() async {
    try {
      final value = await _storage.read(key: keyName);
      if (value == null) return _unavailable();
      final bytes = base64Decode(value);
      if (bytes.length != 32) return _unavailable();
      return SecretKey(bytes);
    } catch (_) {
      return _unavailable();
    }
  }

  Future<Uint8List> _decode(List<int> bytes) async {
    if (!isEncrypted(bytes)) return Uint8List.fromList(bytes);
    try {
      if (bytes.length < 8 + 12 + 16 || bytes[7] != 1) return _unavailable();
      final box = SecretBox.fromConcatenation(
        bytes.sublist(8),
        nonceLength: 12,
        macLength: 16,
      );
      return Uint8List.fromList(
        await _cipher.decrypt(box, secretKey: await _key(), aad: _header),
      );
    } catch (_) {
      return _unavailable();
    }
  }

  Future<Uint8List> _encode(List<int> bytes, bool encrypt) async {
    if (!encrypt) return Uint8List.fromList(bytes);
    final box = await _cipher.encrypt(
      bytes,
      secretKey: await _key(),
      aad: _header,
    );
    return Uint8List.fromList([..._header, ...box.concatenation()]);
  }

  Future<File> _source(File file) async {
    if (await file.exists()) return file;
    final original = File('${file.path}.enc-original');
    if (await original.exists()) return original;
    final pending = File('${file.path}.enc-pending');
    return await pending.exists() ? pending : file;
  }

  /// Null for a legacy/plain file, otherwise authenticated plaintext in memory.
  Future<Uint8List?> readEncrypted(File file) => _ordered(() async {
    final bytes = await (await _source(file)).readAsBytes();
    return isEncrypted(bytes) ? await _decode(bytes) : null;
  });

  Future<Uint8List> read(File file) =>
      _ordered(() async => _decode(await (await _source(file)).readAsBytes()));

  /// Validate an existing envelope before replacing it, even when switched off.
  Future<void> write(File file, List<int> bytes) => _ordered(() async {
    final source = await _source(file);
    if (await source.exists()) await _decode(await source.readAsBytes());
    for (final suffix in ['.enc-original', '.enc-pending']) {
      final artifact = File('${file.path}$suffix');
      if (await artifact.exists()) await _decode(await artifact.readAsBytes());
    }
    await _replace(file, await _encode(bytes, await enabled()));
  });

  /// Atomic replacement retains a recoverable original if interrupted.
  Future<void> _replace(File file, List<int> bytes) async {
    final temp = File('${file.path}.enc-pending');
    final backup = File('${file.path}.enc-original');
    // Never overwrite an original left by a failed rename.
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    }
    await temp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    try {
      await temp.rename(file.path);
    } catch (_) {
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
  }

  Future<String?> readGoal(
    String key, {
    bool allowUnavailable = true,
  }) => _ordered(() async {
    final raw = (await _preferences()).getString(key);
    try {
      return raw == null ? null : await _decodeText(raw);
    } on EncryptionRecovery {
      if (!allowUnavailable) rethrow;
      // The recovery banner explains why this value is temporarily unavailable.
      return null;
    }
  });

  Future<String> _decodeText(String raw) async {
    if (!raw.startsWith(_textPrefix)) return raw;
    try {
      final bytes = base64Decode(raw.substring(_textPrefix.length));
      if (!isEncrypted(bytes)) return _unavailable();
      return utf8.decode(await _decode(bytes));
    } catch (_) {
      return _unavailable();
    }
  }

  Future<bool> removeGoal(String key) => _ordered(() async {
    final prefs = await _preferences();
    final old = prefs.getString(key);
    if (old != null) await _decodeText(old);
    return prefs.remove(key);
  });

  Future<bool> writeGoal(String key, String value) => _ordered(() async {
    final prefs = await _preferences();
    final old = prefs.getString(key);
    if (old != null) await _decodeText(old);
    final encrypt = await enabled();
    final encoded = await _encode(utf8.encode(value), encrypt);
    return prefs.setString(
      key,
      encrypt ? '$_textPrefix${base64Encode(encoded)}' : value,
    );
  });

  /// Preflight every envelope before changing anything. Interrupted migrations
  /// can be retried: readers accept mixed versions and the key is never deleted.
  Future<void> setEnabled(bool encrypt) => _ordered(() async {
    final prefs = await _preferences();
    await prefs.reload();
    final targets = <String, File>{};
    final artifacts = <File>[];
    for (final dir in await _directories()) {
      if (!await dir.exists()) continue;
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        artifacts.add(entry);
        var path = entry.path;
        for (final suffix in ['.enc-original', '.enc-pending']) {
          if (path.endsWith(suffix))
            path = path.substring(0, path.length - suffix.length);
        }
        targets[path] = File(path);
      }
    }
    final files = targets.values.toList();
    var hasEncrypted = false;
    for (final file in artifacts) {
      final bytes = await file.readAsBytes();
      hasEncrypted |= isEncrypted(bytes);
      await _decode(bytes);
    }
    final goals = <String, String>{};
    for (final key in goalKeys) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      hasEncrypted |= raw.startsWith(_textPrefix);
      goals[key] = await _decodeText(raw);
    }
    String? nativeRaw;
    List<Map<String, dynamic>>? nativeRows;
    if (_nativeWatches) {
      nativeRaw = await watchChannel.invokeMethod<String>('watchList') ?? '[]';
      nativeRows = await _decodeWatches(nativeRaw);
    }
    if (encrypt) {
      try {
        final existing = await _storage.read(key: keyName);
        if (existing == null) {
          if (hasEncrypted || (prefs.getBool(settingKey) ?? false))
            _unavailable();
          final key = await _cipher.newSecretKey();
          await _storage.write(
            key: keyName,
            value: base64Encode(await key.extractBytes()),
          );
        }
        await _key(); // Reject malformed/unreadable vault entries.
      } catch (_) {
        _unavailable();
      }
    }
    // Publish the target policy before rewriting: failures retain a readable
    // mixed directory and future writes use the requested policy.
    if (!await prefs.setBool(migrationKey, true) ||
        !await prefs.setBool(settingKey, encrypt)) {
      throw const FileSystemException(
        'Could not save device encryption setting.',
      );
    }
    for (final file in files) {
      // A previously completed replacement may have consumed an orphan.
      final clear = await _decode(await (await _source(file)).readAsBytes());
      await _replace(file, await _encode(clear, encrypt));
    }
    for (final entry in goals.entries) {
      final bytes = await _encode(utf8.encode(entry.value), encrypt);
      if (!await prefs.setString(
        entry.key,
        encrypt ? '$_textPrefix${base64Encode(bytes)}' : entry.value,
      )) {
        throw const FileSystemException('Could not migrate Goals.');
      }
    }
    if (nativeRaw != null && nativeRows != null) {
      final migrated = await _encodeWatches(nativeRows, encrypt);
      if (await watchChannel.invokeMethod<bool>('watchReplace', {
            'expected': nativeRaw,
            'value': migrated,
          }) !=
          true) {
        throw const FileSystemException(
          'Goals changed during migration. Retry.',
        );
      }
    }
    // SQLite may have a live Drift connection. Startup applies its policy and
    // clears the shared marker only after both migrations have succeeded.
    recovery.value = false;
  });
}
