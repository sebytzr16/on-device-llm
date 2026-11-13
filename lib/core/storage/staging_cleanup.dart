import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Removes the private staging directories an abrupt process kill leaves
/// behind (audit S16). Every swept name comes from one of the app's own
/// `createTemp` calls, so the sweep never follows a path a request supplied.
class StagingCleanup {
  StagingCleanup._();

  /// Plaintext backup working/verification directories.
  static const supportPrefixes = ['backup-working-', 'backup-verify-'];

  /// Upload, inline-image and paste staging under the system temp directory.
  static const temporaryPrefixes = [
    'ondevice-workspace-',
    'desktopServe-',
    'knowledge-import',
    'chat-paste-',
  ];

  /// Sweeps both staging roots; unreachable roots and failed removals are
  /// left for the next start instead of blocking it.
  static Future<void> sweep({
    Future<Directory> Function()? support,
    Directory? temporary,
  }) async {
    await _sweep(
      await (support ?? getApplicationSupportDirectory)(),
      supportPrefixes,
    );
    await _sweep(temporary ?? Directory.systemTemp, temporaryPrefixes);
  }

  static Future<void> _sweep(Directory root, List<String> prefixes) async {
    try {
      if (!await root.exists()) return;
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path);
        if (!prefixes.any(name.startsWith)) continue;
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          // Kept for the next start.
        }
      }
    } on FileSystemException {
      // An unreadable staging root has nothing this sweep can safely remove.
    }
  }
}
