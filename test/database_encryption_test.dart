import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/storage/database_encryption.dart';
import 'package:ondevice_llm/core/storage/device_encryption.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/backup/local_backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/hosting_secure_storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationSupportPath() async =>
      (Directory(p.join(root.path, 'support'))..createSync()).path;
  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File file;
  late MemoryHostSecrets vault;
  late SharedPreferences prefs;
  late DeviceEncryption encryption;
  late DatabaseEncryption codec;
  late DeviceEncryption oldInstance;
  late PathProviderPlatform oldPaths;

  Future<void> startup({void Function(String)? checkpoint}) async {
    await encryption.setEnabled(await encryption.enabled());
    await codec.prepare(file, checkpoint: checkpoint);
    await encryption.completeMigration();
  }

  Future<String> readTitle() async {
    final key = await codec.keyForFile(file);
    final db = sqlite3.open(file.path);
    try {
      DatabaseEncryption.setup(db, key);
      return db.select('SELECT title FROM chats').first['title'] as String;
    } finally {
      db.close();
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('database-encryption-');
    file = File(p.join(root.path, 'ondevice_llm.sqlite'));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    vault = MemoryHostSecrets();
    encryption = DeviceEncryption(
      storage: vault,
      preferences: () async => prefs,
      directories: () async => [],
    );
    codec = DatabaseEncryption(encryption);
    oldInstance = DeviceEncryption.instance;
    DeviceEncryption.instance = encryption;
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root);
    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await db.customStatement(
        "INSERT INTO chats(id,title,created_at,updated_at) VALUES('one','private chat',1,1)",
      );
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    DeviceEncryption.instance = oldInstance;
    PathProviderPlatform.instance = oldPaths;
    await root.delete(recursive: true);
  });

  test(
    'enable encrypts at restart; binary key opens it; disable decrypts',
    () async {
      expect(await DatabaseEncryption.isEncrypted(file), isFalse);
      await encryption.setEnabled(true);
      expect(await encryption.migrationPending(), isTrue);
      expect(await DatabaseEncryption.isEncrypted(file), isFalse);
      await startup();
      expect(await encryption.migrationPending(), isFalse);
      expect(await DatabaseEncryption.isEncrypted(file), isTrue);
      expect(await readTitle(), 'private chat');
      final unkeyed = sqlite3.open(file.path);
      try {
        expect(
          () => unkeyed.select('SELECT * FROM chats'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        unkeyed.close();
      }
      expect(
        base64Decode(vault.values[DeviceEncryption.databaseKeyName]!).length,
        32,
      );
      expect(
        vault.values[DeviceEncryption.databaseKeyName],
        isNot(vault.values[DeviceEncryption.keyName]),
      );
      expect(prefs.getKeys(), {DeviceEncryption.settingKey});
      await encryption.setEnabled(false);
      expect(await readTitle(), 'private chat');
      await startup();
      expect(await DatabaseEncryption.isEncrypted(file), isFalse);
      expect(await readTitle(), 'private chat');
    },
  );

  for (final encrypt in [true, false]) {
    for (final phase in ['copied', 'verified', 'saved', 'installed']) {
      test(
        'resume ${encrypt ? 'encryption' : 'decryption'} after $phase',
        () async {
          if (!encrypt) {
            await encryption.setEnabled(true);
            await startup();
          }
          await encryption.setEnabled(encrypt);
          await expectLater(
            startup(
              checkpoint: (step) {
                if (step == phase) throw StateError('simulated process exit');
              },
            ),
            throwsStateError,
          );
          expect(await encryption.migrationPending(), isTrue);
          await startup();
          expect(await readTitle(), 'private chat');
          expect(await DatabaseEncryption.isEncrypted(file), encrypt);
          expect(await File('${file.path}.dbenc-original').exists(), isFalse);
          expect(await File('${file.path}.dbenc-pending').exists(), isFalse);
        },
      );
    }
  }

  for (final missing in [true, false]) {
    test(
      '${missing ? 'missing' : 'wrong'} key preserves all database bytes',
      () async {
        await encryption.setEnabled(true);
        await startup();
        await encryption.setEnabled(false);
        final bytes = await file.readAsBytes();
        if (missing) {
          vault.values.remove(DeviceEncryption.databaseKeyName);
        } else {
          vault.values[DeviceEncryption.databaseKeyName] = base64Encode(
            Uint8List(32),
          );
        }
        await expectLater(
          codec.prepare(file),
          throwsA(isA<EncryptionRecovery>()),
        );
        expect(await file.readAsBytes(), bytes);
        expect(encryption.recovery.value, isTrue);
        expect(await file.exists(), isTrue);
      },
    );
  }

  test('encrypts a recovered WAL including uncheckpointed chats', () async {
    final live = sqlite3.open(file.path);
    late Uint8List mainBytes;
    late Uint8List walBytes;
    try {
      live.execute('PRAGMA journal_mode=WAL');
      live.execute('PRAGMA wal_autocheckpoint=0');
      live.execute(
        "INSERT INTO chats(id,title,created_at,updated_at) VALUES('two','WAL chat',2,2)",
      );
      mainBytes = await file.readAsBytes();
      walBytes = await File('${file.path}-wal').readAsBytes();
    } finally {
      live.close();
    }
    // Reconstruct the bytes a killed process leaves, without an open handle.
    await file.writeAsBytes(mainBytes, flush: true);
    await File('${file.path}-wal').writeAsBytes(walBytes, flush: true);
    await encryption.setEnabled(true);
    await startup();
    final db = AppDatabase();
    try {
      expect(
        (await db.allChats()).map((row) => row.title),
        containsAll(['private chat', 'WAL chat']),
      );
    } finally {
      await db.close();
    }
    expect(await DatabaseEncryption.isEncrypted(file), isTrue);
  });

  Future<void> plantUnreadableWal() async {
    await encryption.setEnabled(true);
    await startup();
    // A log whose frames are valid but don't decrypt with this device's key,
    // like one written by a broken process before it was killed.
    final other = File(p.join(root.path, 'other.sqlite'));
    await file.copy(other.path);
    final key = await codec.keyForFile(file);
    final db = sqlite3.open(other.path);
    try {
      DatabaseEncryption.setup(db, key);
      db.execute(
        DatabaseEncryption.keyPragma(
          'rekey',
          Uint8List(32)..fillRange(0, 32, 7),
        ),
      );
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA wal_autocheckpoint=0');
      db.execute('CREATE TABLE junk(a)');
      await File('${file.path}-wal').writeAsBytes(
        await File('${other.path}-wal').readAsBytes(),
        flush: true,
      );
    } finally {
      db.close();
    }
  }

  test('an unreadable WAL is set aside when the main file is intact', () async {
    await plantUnreadableWal();
    await codec.verifyExisting(file);
    expect(encryption.recovery.value, isFalse);
    expect(await File('${file.path}-wal').exists(), isFalse);
    final aside = root
        .listSync()
        .whereType<Directory>()
        .where((d) => p.basename(d.path).startsWith('recovered-wal-'))
        .single;
    expect(
      File(p.join(aside.path, 'ondevice_llm.sqlite-wal')).existsSync(),
      isTrue,
    );
    expect(await readTitle(), 'private chat');
  });

  test('a missing key never moves the WAL aside', () async {
    await plantUnreadableWal();
    final walBytes = await File('${file.path}-wal').readAsBytes();
    vault.values.remove(DeviceEncryption.databaseKeyName);
    await expectLater(
      codec.verifyExisting(file),
      throwsA(isA<EncryptionRecovery>()),
    );
    expect(encryption.recovery.value, isTrue);
    expect(await File('${file.path}-wal').readAsBytes(), walBytes);
  });

  test(
    'new databases are encrypted before Drift creates their schema',
    () async {
      await file.delete();
      await encryption.setEnabled(true);
      await startup();
      expect(await DatabaseEncryption.isEncrypted(file), isTrue);
      final db = AppDatabase();
      try {
        expect(await db.allChats(), isEmpty);
      } finally {
        await db.close();
      }
    },
  );

  test('a missing key retains an encrypted rollback original', () async {
    await encryption.setEnabled(true);
    await startup();
    await encryption.setEnabled(false);
    await expectLater(
      startup(
        checkpoint: (step) {
          if (step == 'installed') throw StateError('simulated process exit');
        },
      ),
      throwsStateError,
    );
    final original = File('${file.path}.dbenc-original');
    final savedBytes = await original.readAsBytes();
    final liveBytes = await file.readAsBytes();
    vault.values.remove(DeviceEncryption.databaseKeyName);
    await expectLater(codec.prepare(file), throwsA(isA<EncryptionRecovery>()));
    expect(await original.readAsBytes(), savedBytes);
    expect(await file.readAsBytes(), liveBytes);
  });

  test('an orphan copy never causes an empty database to be created', () async {
    final pending = await file.rename('${file.path}.dbenc-pending');
    final bytes = await pending.readAsBytes();
    await encryption.setEnabled(true);
    await expectLater(codec.prepare(file), throwsA(isA<EncryptionRecovery>()));
    expect(await file.exists(), isFalse);
    expect(await pending.readAsBytes(), bytes);
  });

  test(
    'password backup exports portable plaintext and restore re-encrypts',
    () async {
      await encryption.setEnabled(true);
      await startup();
      // Exercise the actual background setup callback with a binary key.
      final db = AppDatabase();
      late Uint8List backup;
      try {
        expect((await db.allChats()).single.title, 'private chat');
        backup = await LocalBackupService.create(db, 'a long backup password');
      } finally {
        await db.close();
      }

      await LocalBackupService.stage(backup, 'a long backup password');
      await LocalBackupService.applyPendingRestore();
      expect(await DatabaseEncryption.isEncrypted(file), isFalse);
      await startup();
      expect(await DatabaseEncryption.isEncrypted(file), isTrue);
      final restored = AppDatabase();
      try {
        await LocalBackupService.finishRestore(restored);
        expect((await restored.allChats()).single.title, 'private chat');
      } finally {
        await restored.close();
      }
      expect(
        (await Directory(p.join(root.path, 'support')).list().toList()).where(
          (entry) => p.basename(entry.path).startsWith('backup-working-'),
        ),
        isEmpty,
      );
    },
  );
}
