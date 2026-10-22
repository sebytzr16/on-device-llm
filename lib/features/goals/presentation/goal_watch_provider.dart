import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/shared_providers.dart';
import '../../../data/network/web_search/search_models.dart';
import '../../schedule/scheduled_prompt.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import '../goal_deliverables.dart';
import '../goal_watch.dart';
import '../goal_watch_check.dart';
import '../goal_watch_store.dart';

/// The watched goals ([GoalWatch]), kept on the device. A check is one web
/// search per watch. Android also checks due watches in a bounded headless
/// job; opening Goals reloads those results.
class GoalWatchNotifier extends Notifier<List<GoalWatch>> {
  late Future<void> ready;
  Future<void> _writes = Future.value();
  final _checking = <int>{};

  /// For tests: the search a check runs.
  Future<List<SearchResult>> Function(String query)? searchOverride;

  @override
  List<GoalWatch> build() {
    ready = _load();
    return const [];
  }

  Future<void> _load() async {
    final watches = await GoalWatchStore.list();
    if (ref.mounted) state = watches;
  }

  Future<void> _persist({GoalWatch? watch, GoalWatch? expected, int? remove}) {
    final write = _writes.then((_) async {
      if (watch != null) await GoalWatchStore.put(watch, expected: expected);
      if (remove != null) await GoalWatchStore.remove(remove);
      await _load();
    });
    _writes = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  bool isChecking(int id) => _checking.contains(id);

  /// Watches [objective] under the daily notification [prompt] (a new
  /// watch, or the same one at a new time), and takes its first results as
  /// the baseline.
  Future<void> watch(String objective, ScheduledPrompt prompt) async {
    await ready;
    await _load();
    final old = state.where((w) => w.id == prompt.id).firstOrNull;
    final w =
        old?.at(prompt.hour, prompt.minute) ??
        GoalWatch(
          id: prompt.id,
          objective: objective,
          query: GoalDeliverables.researchPart(objective),
          hour: prompt.hour,
          minute: prompt.minute,
          createdAt: DateTime.now(),
        );
    state = [w, ...state.where((x) => x.id != w.id)];
    await _persist(watch: w);
    if (w.last == null) unawaited(check(w.id));
  }

  Future<void> remove(int id) async {
    await ready;
    state = [...state.where((w) => w.id != id)];
    await _persist(remove: id);
  }

  /// Checks every due watch; a watch whose notification was removed in
  /// Schedule is removed too.
  Future<void> checkDue() async {
    await ready;
    await _load();
    if (Platform.isAndroid) {
      try {
        final ids = {
          for (final p in await ScheduleStore.list())
            if (p.isGoal && p.enabled) p.id,
        };
        final gone = state.where((w) => !ids.contains(w.id)).toList();
        if (gone.isNotEmpty) {
          for (final w in gone) {
            await _persist(remove: w.id);
          }
        }
      } catch (_) {
        // The schedule could not be read: keep the watches.
      }
    }
    final now = DateTime.now();
    for (final w in [...state]) {
      if (w.dueAt(now)) await check(w.id);
    }
  }

  /// One check: a web search for the watch's question, compared with the
  /// last check.
  Future<void> check(int id) async {
    if (!_checking.add(id)) return;
    try {
      await ready;
      await _load();
      state = [...state];
      final w = state.where((x) => x.id == id).firstOrNull;
      if (w == null) return;
      final settings = ref.read(settingsProvider);
      final next = await GoalWatchCheck.run(
        w,
        webEnabled: searchOverride != null || settings.webSearchEnabled,
        search: (query) =>
            searchOverride?.call(query) ??
            ref
                .read(duckDuckGoScraperProvider)
                .search(
                  query,
                  limit: GoalWatches.results + 2,
                  localeCode: settings.localeCode,
                ),
      );
      // Removed meanwhile (or Goals closed): not put back.
      if (!ref.mounted || !state.any((x) => x.id == id)) return;
      state = [for (final x in state) x.id == id ? next : x];
      await _persist(watch: next, expected: w);
    } finally {
      _checking.remove(id);
      if (ref.mounted) state = [...state];
    }
  }
}

final goalWatchProvider = NotifierProvider<GoalWatchNotifier, List<GoalWatch>>(
  GoalWatchNotifier.new,
);
