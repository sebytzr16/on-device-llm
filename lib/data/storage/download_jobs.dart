import 'package:shared_preferences/shared_preferences.dart';

/// Records downloads that should resume after an app process is restarted.
/// The bytes themselves remain in each model's verified .part file.
class DownloadJobs {
  static const key = 'active_model_downloads_v1';
  static Future<void> _pending = Future<void>.value();

  static Future<Set<String>> active() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? const <String>[]).toSet();
  }

  static Future<void> add(String id) => _update((ids) => ids.add(id));

  static Future<void> remove(String id) => _update((ids) => ids.remove(id));

  static Future<void> _update(void Function(Set<String>) change) {
    final next = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
      change(ids);
      await prefs.setStringList(key, ids.toList()..sort());
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}
