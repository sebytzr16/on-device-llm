import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/backup/local_backup_service.dart';
import 'package:ondevice_llm/features/backup/backup_cipher.dart';
import 'local_backup_service_test.dart' show BackupPaths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'byte exports use streaming files and clean their intermediate output',
    () async {
      final dir = await Directory.systemTemp.createTemp('backup-bytes-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = BackupPaths(dir.path, dir.path);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'hosting_tls.test': 'HOST-PRIVATE-KEY-SENTINEL',
        'host_paired_devices': 'HOST-DEVICE-SECRET-SENTINEL',
      });
      await File(
        '${dir.path}/hosting-tls.json',
      ).writeAsString('{"key":"LEGACY-HOST-PRIVATE-KEY-SENTINEL"}');
      await File(
        '${dir.path}/hosting-tls.fingerprint',
      ).writeAsString('public-pin');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        PathProviderPlatform.instance = previous;
        await dir.delete(recursive: true);
      });
      final encrypted = await LocalBackupService.create(
        db,
        'a strong backup password',
      );
      final plain = await BackupCipher.decrypt(
        encrypted,
        'a strong backup password',
      );
      expect(plain, isNotEmpty);
      final archive = ZipDecoder().decodeBytes(plain);
      expect(archive.files.any((f) => f.name.contains('hosting-tls')), isFalse);
      for (final file in archive.files.where((f) => f.isFile)) {
        final text = utf8.decode(file.content, allowMalformed: true);
        expect(text, isNot(contains('HOST-PRIVATE-KEY-SENTINEL')));
        expect(text, isNot(contains('HOST-DEVICE-SECRET-SENTINEL')));
      }
      expect(
        await dir
            .list()
            .where(
              (f) =>
                  f.path.endsWith('.odllm') ||
                  f.path.contains('backup-working-'),
            )
            .toList(),
        isEmpty,
      );
    },
  );
}
