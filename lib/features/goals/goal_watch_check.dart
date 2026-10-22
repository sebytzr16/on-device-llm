import '../../data/network/web_search/search_models.dart';
import 'goal_watch.dart';

/// One bounded logical search; both foreground and headless callers use
/// the same baseline, change rule and failure semantics.
abstract final class GoalWatchCheck {
  static Future<GoalWatch> run(
    GoalWatch watch, {
    required bool webEnabled,
    required Future<List<SearchResult>> Function(String) search,
    DateTime Function()? now,
  }) async {
    final clock = now ?? DateTime.now;
    if (!webEnabled) return watch.failed('webOff', clock());
    try {
      final results = await search(
        watch.query,
      ).timeout(const Duration(seconds: 25));
      return results.isEmpty
          ? watch.failed('noResults', clock())
          : watch.checked(GoalWatches.snapshot(results, clock()));
    } catch (_) {
      return watch.failed('offline', clock());
    }
  }

  /// A baseline, error, unchanged result or retry emits no change alert.
  static bool shouldNotify(GoalWatch watch) =>
      watch.lastError == null &&
      watch.lastChange != null &&
      !watch.lastChange!.isEmpty;
}
