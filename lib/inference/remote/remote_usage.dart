import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'remote_provider.dart';

/// Why a request was refused before it was sent.
class RemoteLimitReached implements Exception {
  final String message;
  const RemoteLimitReached(this.message);
  @override
  String toString() => message;
}

/// Request counts per connection and model, so the caps in
/// [RemoteProfile.limits] hold across app restarts. Only timestamps are
/// kept — never prompts.
class RemoteUsageLog {
  static const _kKey = 'remote_usage_v1';
  static const _maxPerKey = 5000;

  final DateTime Function() _now;
  final Future<SharedPreferences>? Function() _prefs;
  Map<String, List<int>>? _log;
  Future<void> _writes = Future.value();

  RemoteUsageLog({
    DateTime Function()? now,
    Future<SharedPreferences>? Function()? prefs,
  }) : _now = now ?? DateTime.now,
       _prefs = prefs ?? SharedPreferences.getInstance;

  static String keyFor(String profileId, String model) =>
      '$profileId|${model.trim()}';

  Future<Map<String, List<int>>> _load() async {
    if (_log != null) return _log!;
    final log = <String, List<int>>{};
    try {
      final raw = (await _prefs())?.getString(_kKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            if (e.value is List) {
              log['${e.key}'] = [
                for (final t in e.value as List)
                  if (t is num) t.toInt(),
              ];
            }
          }
        }
      }
    } catch (_) {
      // A corrupt log only loses the counts.
    }
    return _log = log;
  }

  /// Requests made in the current minute (rolling) and today (local day).
  Future<({int minute, int day})> counts(String profileId, String model) async {
    final stamps = (await _load())[keyFor(profileId, model)] ?? const [];
    final now = _now();
    final minuteAgo = now.subtract(const Duration(minutes: 1));
    final dayStart = DateTime(now.year, now.month, now.day);
    var minute = 0, day = 0;
    for (final t in stamps) {
      final at = DateTime.fromMillisecondsSinceEpoch(t);
      if (at.isAfter(minuteAgo)) minute++;
      if (!at.isBefore(dayStart)) day++;
    }
    return (minute: minute, day: day);
  }

  /// Throws [RemoteLimitReached] when [limit] would be exceeded by one more
  /// request; otherwise records the request.
  Future<void> charge(
    String profileId,
    String model,
    RemoteLimit limit, {
    String label = '',
  }) async {
    final log = await _load();
    final key = keyFor(profileId, model);
    final now = _now();
    if (!limit.isEmpty) {
      final c = await counts(profileId, model);
      final what = label.isEmpty ? 'this model' : label;
      if (limit.perMinute > 0 && c.minute >= limit.perMinute) {
        final oldest = (log[key] ?? const [])
            .map(DateTime.fromMillisecondsSinceEpoch)
            .where((t) => t.isAfter(now.subtract(const Duration(minutes: 1))))
            .fold<DateTime?>(
              null,
              (a, b) => a == null || b.isBefore(a) ? b : a,
            );
        final wait = oldest == null
            ? 60
            : 60 - now.difference(oldest).inSeconds;
        throw RemoteLimitReached(
          'Request limit reached: ${limit.perMinute}/min for $what. Try again in ${wait.clamp(1, 60)} s or raise the cap in the connection settings.',
        );
      }
      if (limit.perDay > 0 && c.day >= limit.perDay) {
        throw RemoteLimitReached(
          'Daily request limit reached: ${limit.perDay}/day for $what. It resets at midnight; raise the cap in the connection settings if needed.',
        );
      }
    }
    final dayStart = DateTime(now.year, now.month, now.day);
    final kept = [
      for (final t in log[key] ?? const <int>[])
        if (!DateTime.fromMillisecondsSinceEpoch(t).isBefore(dayStart)) t,
      now.millisecondsSinceEpoch,
    ];
    log[key] = kept.length > _maxPerKey
        ? kept.sublist(kept.length - _maxPerKey)
        : kept;
    _persist();
  }

  void _persist() {
    final snapshot = jsonEncode(_log);
    _writes = _writes.then((_) async {
      try {
        await (await _prefs())?.setString(_kKey, snapshot);
      } catch (_) {}
    });
  }

  /// Forgets the counts of a deleted connection.
  Future<void> forget(String profileId) async {
    final log = await _load();
    log.removeWhere((k, _) => k.startsWith('$profileId|'));
    _persist();
  }
}
