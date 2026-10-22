import 'dart:convert';

import 'package:flutter/services.dart';

import '../../data/network/web_search/duckduckgo_scraper.dart';
import '../settings/domain/entities/inference_settings.dart';
import 'goal_watch.dart';
import 'goal_watch_check.dart';
import 'goal_watch_store.dart';

/// Runs without the app, database, models, microphone or phone actions.
/// Android owns job lifetime and destroys this engine on stop/timeout.
Future<void> runGoalWatchBackground() async {
  const channel = MethodChannel('ondevice_llm/goal_watch_background');
  DuckDuckGoScraper? search;
  var retry = false;
  try {
    final work = await channel.invokeMapMethod<String, dynamic>('work');
    if (work == null) return;
    final raw = work['settings'];
    final settings = raw is String
        ? InferenceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>)
        : const InferenceSettings();
    search = DuckDuckGoScraper();
    DuckDuckGoScraper.preferredRegion = settings.searchRegion;
    final watches = GoalWatches.decode('${work['watches'] ?? '[]'}');
    final start = DateTime.now();
    var checked = 0;
    for (final watch in watches) {
      if (!watch.dueAt(DateTime.now())) continue;
      // The OS also enforces 90 seconds. Reserve time to finish a 25s
      // request, and cap the number of searches per job.
      if (checked >= 8 || DateTime.now().difference(start).inSeconds >= 55) {
        retry = true;
        break;
      }
      checked++;
      final next = await GoalWatchCheck.run(
        watch,
        webEnabled: settings.webSearchEnabled,
        search: (query) => search!.search(
          query,
          limit: GoalWatches.results + 2,
          localeCode: settings.localeCode,
        ),
      );
      final stored = await GoalWatchStore.put(next, expected: watch);
      if (stored && GoalWatchCheck.shouldNotify(next)) {
        await channel.invokeMethod<void>('changed', {
          'id': next.id,
          'fresh': next.lastChange!.fresh.length,
          'figures': next.lastChange!.figures.length,
          'locale': settings.localeCode,
        });
      }
    }
  } finally {
    search?.dispose();
    await channel.invokeMethod<void>('finished', {'retry': retry});
  }
}
