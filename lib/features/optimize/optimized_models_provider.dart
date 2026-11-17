import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final optimizedModelsProvider =
    AsyncNotifierProvider<OptimizedModels, Set<String>>(OptimizedModels.new);

class OptimizedModels extends AsyncNotifier<Set<String>> {
  static const storageKey = 'optimized_models_v1';
  Future<void> _writes = Future.value();

  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return Set.unmodifiable(prefs.getStringList(storageKey) ?? <String>[]);
  }

  Future<void> markOptimized(String id) {
    final write = _writes.then((_) async {
      final models = await future;
      final updated = Set<String>.unmodifiable({...models, id});
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(storageKey, updated.toList()..sort())) {
        throw StateError('Could not save optimized models');
      }
      if (ref.mounted) state = AsyncData(updated);
    });
    _writes = write.catchError((Object _, StackTrace _) {});
    return write;
  }
}
