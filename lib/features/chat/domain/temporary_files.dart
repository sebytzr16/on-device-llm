import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../attachments/data/attachment_store.dart';

/// Only attachment filenames are recorded for crash cleanup, never messages or
/// extracted text. The in-memory chat database and its drafts are not persisted.
class TemporaryFiles {
  static const key = 'temporary_attachment_cleanup_v1';
  static Future<void> _pending = Future.value();
  static Future<void> remember(Iterable<String> paths) => _serialize(() async {
    final prefs = await SharedPreferences.getInstance();
    final root = (await AttachmentStore.directory()).path;
    final names = {...(prefs.getStringList(key) ?? <String>[])};
    for (final path in paths) {
      if (p.isWithin(root, path)) names.add(p.basename(path));
    }
    await prefs.setStringList(key, names.toList());
  });
  static Future<void> clear() => _serialize(() async {
    final prefs = await SharedPreferences.getInstance();
    final root = (await AttachmentStore.directory()).path;
    final failed = <String>[];
    for (final name in prefs.getStringList(key) ?? <String>[]) {
      if (p.basename(name) != name || name == '.' || name == '..') continue;
      final file = File(p.join(root, name));
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        failed.add(name);
      }
    }
    await prefs.setStringList(key, failed);
  });
  static Future<void> _serialize(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }
}
