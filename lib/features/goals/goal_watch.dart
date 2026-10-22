import 'dart:convert';

import '../../data/network/web_search/search_models.dart';

/// A goal watched each day (audit G2, 2026-10-08). Each check is one web
/// search for the goal's question, with no model and no page reads; it is
/// compared with the last check, and only a meaningful change is reported:
/// a result never seen before in the top results, or a figure (a price, a
/// weight, a percentage) that changed on a page already seen. Checks run
/// in a bounded Android background job and when Goals opens. Alerts are
/// emitted only for a meaningful change. A full goal runs again only when asked.
class GoalWatch {
  /// The daily notification's id ([ScheduledPrompt.id]).
  final int id;
  final String objective;

  /// What is searched: the objective without its deliverable request.
  final String query;
  final int hour, minute;
  final DateTime createdAt;

  /// The last check's results, compared with the next one.
  final GoalWatchSnapshot? last;

  /// Every result page seen so far, so one seen before does not count as
  /// new again when it comes back into the top results.
  final List<String> seen;
  final DateTime? lastCheckedAt;

  /// What the last check found; null before the first comparison.
  final GoalWatchChange? lastChange;

  /// Why the last check could not run (web search off, no connection).
  final String? lastError;

  const GoalWatch({
    required this.id,
    required this.objective,
    required this.query,
    required this.hour,
    required this.minute,
    required this.createdAt,
    this.last,
    this.seen = const [],
    this.lastCheckedAt,
    this.lastChange,
    this.lastError,
  });

  static const maxSeen = 200;

  /// The most recent scheduled time at or before [now].
  DateTime lastSlot(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return today.isAfter(now)
        ? DateTime(now.year, now.month, now.day - 1, hour, minute)
        : today;
  }

  /// Due when it has never been checked or the scheduled time has passed
  /// since the last check.
  bool dueAt(DateTime now) =>
      lastCheckedAt == null || lastCheckedAt!.isBefore(lastSlot(now));

  /// This watch after a check that returned [now].
  GoalWatch checked(GoalWatchSnapshot now) {
    final change = last == null ? null : GoalWatches.diff(last!, now, seen);
    final allSeen = <String>{
      ...seen,
      ...?last?.items.map((i) => i.key),
      ...now.items.map((i) => i.key),
    }.toList();
    return GoalWatch(
      id: id,
      objective: objective,
      query: query,
      hour: hour,
      minute: minute,
      createdAt: createdAt,
      last: now,
      seen: allSeen.length > maxSeen
          ? allSeen.sublist(allSeen.length - maxSeen)
          : allSeen,
      lastCheckedAt: now.at,
      lastChange: change,
    );
  }

  GoalWatch failed(String error, DateTime at) => GoalWatch(
    id: id,
    objective: objective,
    query: query,
    hour: hour,
    minute: minute,
    createdAt: createdAt,
    last: last,
    seen: seen,
    lastCheckedAt: at,
    lastChange: lastChange,
    lastError: error,
  );

  GoalWatch at(int hour, int minute) => GoalWatch(
    id: id,
    objective: objective,
    query: query,
    hour: hour,
    minute: minute,
    createdAt: createdAt,
    last: last,
    seen: seen,
    lastCheckedAt: lastCheckedAt,
    lastChange: lastChange,
    lastError: lastError,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'objective': objective,
    'query': query,
    'hour': hour,
    'minute': minute,
    'createdAt': createdAt.toIso8601String(),
    if (last != null) 'last': last!.toJson(),
    'seen': seen,
    if (lastCheckedAt != null)
      'lastCheckedAt': lastCheckedAt!.toIso8601String(),
    if (lastChange != null) 'lastChange': lastChange!.toJson(),
    if (lastError != null) 'lastError': lastError,
  };

  static GoalWatch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], objective = raw['objective'];
    final hour = raw['hour'], minute = raw['minute'];
    if (id is! int || objective is! String || hour is! int || minute is! int) {
      return null;
    }
    return GoalWatch(
      id: id,
      objective: objective,
      query: raw['query'] is String ? raw['query'] as String : objective,
      hour: hour,
      minute: minute,
      createdAt:
          DateTime.tryParse('${raw['createdAt']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      last: GoalWatchSnapshot.fromJson(raw['last']),
      seen: [
        for (final s in (raw['seen'] as List?) ?? const [])
          if (s is String) s,
      ],
      lastCheckedAt: DateTime.tryParse('${raw['lastCheckedAt']}'),
      lastChange: GoalWatchChange.fromJson(raw['lastChange']),
      lastError: raw['lastError'] as String?,
    );
  }
}

/// One result of a check: its page and the figures its snippet gives.
class GoalWatchItem {
  final String title, url;
  final List<String> figures;
  const GoalWatchItem({
    required this.title,
    required this.url,
    this.figures = const [],
  });

  /// The page without its query, fragment and trailing slash.
  String get key => GoalWatches.pageKey(url);

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'figures': figures,
  };

  static GoalWatchItem? fromJson(Object? raw) {
    if (raw is! Map || raw['url'] is! String) return null;
    return GoalWatchItem(
      title: '${raw['title'] ?? ''}',
      url: raw['url'] as String,
      figures: [
        for (final f in (raw['figures'] as List?) ?? const [])
          if (f is String) f,
      ],
    );
  }
}

class GoalWatchSnapshot {
  final DateTime at;
  final List<GoalWatchItem> items;
  const GoalWatchSnapshot(this.at, this.items);

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'items': [for (final i in items) i.toJson()],
  };

  static GoalWatchSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}');
    if (at == null) return null;
    return GoalWatchSnapshot(at, [
      for (final i in (raw['items'] as List?) ?? const [])
        ?GoalWatchItem.fromJson(i),
    ]);
  }
}

/// A figure that changed on a page already seen.
class GoalWatchFigureChange {
  final GoalWatchItem item;
  final List<String> before, after;
  const GoalWatchFigureChange(this.item, this.before, this.after);
}

class GoalWatchChange {
  /// Results in the top results for the first time.
  final List<GoalWatchItem> fresh;
  final List<GoalWatchFigureChange> figures;
  const GoalWatchChange({this.fresh = const [], this.figures = const []});

  bool get isEmpty => fresh.isEmpty && figures.isEmpty;

  Map<String, dynamic> toJson() => {
    'fresh': [for (final i in fresh) i.toJson()],
    'figures': [
      for (final f in figures)
        {'item': f.item.toJson(), 'before': f.before, 'after': f.after},
    ],
  };

  static GoalWatchChange? fromJson(Object? raw) {
    if (raw is! Map) return null;
    List<String> strings(Object? v) => [
      for (final s in (v as List?) ?? const [])
        if (s is String) s,
    ];
    return GoalWatchChange(
      fresh: [
        for (final i in (raw['fresh'] as List?) ?? const [])
          ?GoalWatchItem.fromJson(i),
      ],
      figures: [
        for (final f in (raw['figures'] as List?) ?? const [])
          if (f is Map && GoalWatchItem.fromJson(f['item']) != null)
            GoalWatchFigureChange(
              GoalWatchItem.fromJson(f['item'])!,
              strings(f['before']),
              strings(f['after']),
            ),
      ],
    );
  }
}

abstract final class GoalWatches {
  /// Results a check keeps.
  static const results = 6;

  // A figure worth watching: an amount of money, a percentage, or a
  // number with a unit. Bare years and small counts change from snippet to
  // snippet without meaning anything.
  static final _figure = RegExp(
    r'(?<![\p{L}\p{N}.,])(?:US\$|CA\$|C\$|[$€£¥])?\s?\d+(?:[.,]\d+)*'
    r'(?:\s?(?:%|€|\$|£|USD|EUR|CAD|GBP|kg|g|lbs|lb|oz|km/h|km|mi|mm|cm|GB|TB|MB|mAh|kWh|Wh|kW|W|hp|mph|°C|°F|MP|fps|GHz|Hz|inches|inch|hours|min|days|euros?|dollars?))?(?![\p{L}\p{N}])',
    unicode: true,
  );

  static final _hasUnitOrMoney = RegExp(r'[$€£¥%]|[A-Za-z°]');

  /// The figures in [text], at most 12, in order of appearance.
  static List<String> figures(String text) {
    final out = <String>[];
    for (final m in _figure.allMatches(text)) {
      final f = m[0]!.trim().replaceAll(RegExp(r'\s+'), ' ');
      final digits = f.replaceAll(RegExp(r'[^\d]'), '');
      final decimal = RegExp(r'\d[.,]\d').hasMatch(f);
      if (!_hasUnitOrMoney.hasMatch(f) && !decimal) continue;
      if (digits.isEmpty) continue;
      if (!out.contains(f)) out.add(f);
      if (out.length >= 12) break;
    }
    return out;
  }

  static String pageKey(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.host.isEmpty) return url.trim().toLowerCase();
    var path = u.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return '${u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '')}$path';
  }

  static GoalWatchSnapshot snapshot(List<SearchResult> found, DateTime at) {
    final items = <GoalWatchItem>[];
    for (final r in found) {
      if (r.sponsored || r.url.trim().isEmpty) continue;
      final item = GoalWatchItem(
        title: r.title.trim(),
        url: r.url.trim(),
        figures: figures('${r.title} ${r.snippet}'),
      );
      if (items.any((i) => i.key == item.key)) continue;
      items.add(item);
      if (items.length >= results) break;
    }
    return GoalWatchSnapshot(at, items);
  }

  /// What changed from [before] to [now]: pages in the top results never
  /// seen before ([seen] holds every earlier page), and figures that
  /// changed on a page both checks saw.
  static GoalWatchChange diff(
    GoalWatchSnapshot before,
    GoalWatchSnapshot now, [
    List<String> seen = const [],
  ]) {
    final known = {...seen, ...before.items.map((i) => i.key)};
    final fresh = [
      for (final i in now.items)
        if (!known.contains(i.key)) i,
    ];
    final figures = <GoalWatchFigureChange>[];
    for (final i in now.items) {
      final old = before.items.where((b) => b.key == i.key).firstOrNull;
      if (old == null || old.figures.isEmpty || i.figures.isEmpty) continue;
      final a = old.figures.toSet(), b = i.figures.toSet();
      if (a.difference(b).isEmpty && b.difference(a).isEmpty) continue;
      figures.add(
        GoalWatchFigureChange(
          i,
          old.figures.where((f) => !b.contains(f)).toList(),
          i.figures.where((f) => !a.contains(f)).toList(),
        ),
      );
    }
    return GoalWatchChange(fresh: fresh, figures: figures);
  }

  static String encode(List<GoalWatch> watches) =>
      jsonEncode([for (final w in watches) w.toJson()]);

  static List<GoalWatch> decode(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final w in list) ?GoalWatch.fromJson(w)];
    } catch (_) {
      return const [];
    }
  }
}
