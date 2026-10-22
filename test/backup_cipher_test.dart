import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:ondevice_llm/features/backup/local_backup_service.dart';
import 'package:ondevice_llm/features/backup/backup_cipher.dart';

void main() {
  test('encrypted backup round trips and detects tampering', () async {
    final clear = utf8.encode('chat and attachment data');
    final encrypted = await BackupCipher.encrypt(
      clear,
      'a sufficiently long password',
    );
    expect(encrypted, isNot(containsAll(clear)));
    expect(
      await BackupCipher.decrypt(encrypted, 'a sufficiently long password'),
      clear,
    );
    await expectLater(
      BackupCipher.decrypt(encrypted, 'a different long password'),
      throwsFormatException,
    );
    encrypted[encrypted.length - 1] ^= 1;
    await expectLater(
      BackupCipher.decrypt(encrypted, 'a sufficiently long password'),
      throwsFormatException,
    );
  });
  test('restore rejects archive path traversal', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('../outside.txt', utf8.encode('bad')));
    final encrypted = await BackupCipher.encrypt(
      ZipEncoder().encodeBytes(archive),
      'a sufficiently long password',
    );
    await expectLater(
      LocalBackupService.stage(encrypted, 'a sufficiently long password'),
      throwsFormatException,
    );
  });
}
