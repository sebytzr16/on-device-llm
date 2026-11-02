import 'dart:io';
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
      expect(
        await BackupCipher.decrypt(encrypted, 'a strong backup password'),
        isNotEmpty,
      );
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
