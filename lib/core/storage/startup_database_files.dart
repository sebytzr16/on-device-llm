import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'app_directories.dart';

/// Raw recovery works even when SQLite cannot open or migrate the database.
/// Call only after the failed connection has been closed.
class StartupDatabaseFiles {
  StartupDatabaseFiles({this.directory});
  final Directory? directory;
  static const names = [
    'ondevice_llm.sqlite',
    'ondevice_llm.sqlite-wal',
    'ondevice_llm.sqlite-shm',
    'ondevice_llm.sqlite-journal',
    'ondevice_llm.sqlite.dbenc-original',
    'ondevice_llm.sqlite.dbenc-pending',
  ];

  Future<Directory> preserve() async {
    final root = directory ?? await appDataDirectory();
    final backups = Directory(p.join(root.path, 'database-recovery'));
    await backups.create(recursive: true);
    final saved = await backups.createTemp('snapshot-');
    for (final name in names) {
      final source = File(p.join(root.path, name));
      if (await source.exists()) await source.copy(p.join(saved.path, name));
    }
    return saved;
  }

  Future<File> exportFiles() async {
    final saved = await preserve();
    final output = File(p.join(saved.path, 'database-recovery.zip'));
    final zip = ZipFileEncoder()..create(output.path);
    try {
      for (final name in names) {
        final file = File(p.join(saved.path, name));
        if (await file.exists()) await zip.addFile(file, name);
      }
    } finally {
      await zip.close();
    }
    return output;
  }

  Future<void> reset() async {
    // Complete the safety copy first. A failed copy must never delete data.
    await preserve();
    final root = directory ?? await appDataDirectory();
    for (final name in names) {
      final file = File(p.join(root.path, name));
      if (await file.exists()) await file.delete();
    }
  }
}
