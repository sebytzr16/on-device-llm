import 'package:shared_preferences/shared_preferences.dart';

/// A preference store that cannot be read is copied aside before anything
/// can overwrite it: the loaders fall back to defaults, and the next save
/// would otherwise replace the user's shortcuts, presets, profiles or pins
/// with those defaults. The copy lives at `<key>.unreadable` (the first
/// one is kept) so it can be recovered by hand or by a later fix.
class PrefsRescue {
  static String rescueKey(String key) => '$key.unreadable';

  static Future<void> keepUnreadable(
    SharedPreferences? prefs,
    String key,
  ) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final raw = p.get(key);
      if (raw == null || p.containsKey(rescueKey(key))) return;
      await p.setString(rescueKey(key), '$raw');
    } catch (_) {
      // Nothing more can be done without storage.
    }
  }
}
