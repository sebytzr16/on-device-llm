import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('models');

/// The model that loaded last, so the app can load it again at start.
class LastModelStore {
  static const _key = 'last_loaded_model_id';

  static Future<void> remember(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, id);
    } catch (e) {
      _log.fine('Could not remember the last model', e);
    }
  }

  static Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (e) {
      _log.fine('Could not read the last model', e);
      return null;
    }
  }
}
