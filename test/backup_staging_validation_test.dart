import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/backup/backup_cipher.dart';
import 'package:ondevice_llm/features/backup/local_backup_service.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_backup_service_test.dart' show BackupPaths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const password = 'a strong backup password';
  late Directory root;
  late BackupPaths paths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup-staging-');
    paths = BackupPaths(
      p.join(root.path, 'support'),
      p.join(root.path, 'documents'),
    );
    Directory(paths.support).createSync(recursive: true);
    Directory(paths.documents).createSync(recursive: true);
    PathProviderPlatform.instance = paths;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  /// A real backup whose entries [edit] may replace, re-encrypted as-is.
  Future<Uint8List> backup(
    void Function(Map<String, List<int>> entries) edit,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    late Uint8List encrypted;
    try {
      encrypted = await LocalBackupService.create(db, password);
    } finally {
      await db.close();
    }
    final archive = ZipDecoder().decodeBytes(
      await BackupCipher.decrypt(encrypted, password),
    );
    final entries = <String, List<int>>{
      for (final file in archive.files)
        if (file.isFile) file.name: file.content,
    };
    edit(entries);
    final rebuilt = Archive();
    for (final entry in entries.entries) {
      rebuilt.add(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return BackupCipher.encrypt(
      Uint8List.fromList(ZipEncoder().encode(rebuilt)),
      password,
    );
  }

  Future<void> expectStagingRefuses(Uint8List bytes) async {
    await expectLater(
      LocalBackupService.stage(bytes, password),
      throwsA(isA<FormatException>()),
    );
    expect(
      await Directory(p.join(paths.support, 'restore_pending')).exists(),
      isFalse,
    );
  }

  test('staging refuses preference values the restore cannot write', () async {
    final bytes = await backup((entries) {
      entries['preferences.json'] = utf8.encode(
        jsonEncode({'inference_settings_v1': true}),
      );
    });
    await expectStagingRefuses(bytes);
  });

  test('staging refuses schedules the restore cannot decode', () async {
    final bytes = await backup((entries) {
      entries['preferences.json'] = utf8.encode(
        jsonEncode({'scheduled_prompts': 'not json'}),
      );
    });
    await expectStagingRefuses(bytes);
  });

  test(
    'staging refuses a table with matching columns but no primary key',
    () async {
      final bytes = await backup((entries) {
        final file = File(p.join(root.path, 'data.sqlite'));
        file.writeAsBytesSync(entries['data.sqlite']!);
        final database = sqlite3.open(file.path);
        try {
          final schema =
              database
                      .select(
                        "SELECT sql FROM sqlite_schema WHERE name = 'models'",
                      )
                      .single['sql']
                  as String;
          final withoutKey = schema.replaceFirst(
            RegExp(r',\s*PRIMARY KEY\s*\([^)]*\)', caseSensitive: false),
            '',
          );
          expect(withoutKey, isNot(schema));
          database.execute('DROP TABLE models');
          database.execute(withoutKey);
        } finally {
          database.close();
        }
        entries['data.sqlite'] = file.readAsBytesSync();
      });
      await expectStagingRefuses(bytes);
    },
  );

  test('staging refuses a database missing a required column', () async {
    final bytes = await backup((entries) {
      final file = File(p.join(root.path, 'data.sqlite'));
      file.writeAsBytesSync(entries['data.sqlite']!);
      final database = sqlite3.open(file.path);
      try {
        // Same user_version as this build: only the schema check can tell.
        database.execute('ALTER TABLE messages DROP COLUMN status');
      } finally {
        database.close();
      }
      entries['data.sqlite'] = file.readAsBytesSync();
    });
    await expectStagingRefuses(bytes);
  });

  test(
    'staging refuses a table row without a definition for its exact name',
    () async {
      final bytes = await backup((entries) {
        final file = File(p.join(root.path, 'data.sqlite'));
        file.writeAsBytesSync(entries['data.sqlite']!);
        final database = sqlite3.open(file.path);
        try {
          // A foreign archive can name the table differently in sqlite_schema
          // while its columns stay readable: PRAGMA resolves a table name
          // case-insensitively, so the version and integrity checks above pass
          // and only the exact-name definition lookup misses. `single` used
          // to surface that as a StateError ("No element") instead of the
          // incompatible-schema FormatException (review #5).
          database.execute('PRAGMA writable_schema = ON');
          database.execute(
            "UPDATE sqlite_schema SET name = 'Compare_History' "
            "WHERE type = 'table' AND name = 'compare_history'",
          );
          database.execute('PRAGMA writable_schema = OFF');
        } finally {
          database.close();
        }
        entries['data.sqlite'] = file.readAsBytesSync();
      });
      await expectStagingRefuses(bytes);
    },
  );
}
