import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'remote_provider.dart';
import '../../core/l10n/l10n.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

/// Why a request was refused before it was sent.
class RemoteLimitReached implements Exception {
  final String message;
  const RemoteLimitReached(this.message);
  @override
  String toString() => message;
}

/// Request counts per connection and model, so the caps in
/// [RemoteProfile.limits] hold across app restarts. Only counts and timestamps are
/// kept — never prompts.
class RemoteUsageLog {
  static const _kKey = 'remote_usage_v1';

  final DateTime Function() _now;
  final Future<SharedPreferences>? Function() _prefs;
  Map<String, _Usage>? _log;
  Future<void> _writes = Future.value();
  Future<void> _admissions = Future.value();
  Future<Map<String, _Usage>>? _loading;

  RemoteUsageLog({
    DateTime Function()? now,
    Future<SharedPreferences>? Function()? prefs,
  }) : _now = now ?? DateTime.now,
       _prefs = prefs ?? SharedPreferences.getInstance;

  static String keyFor(String profileId, String model) =>
      '$profileId|${model.trim()}';

  Future<Map<String, _Usage>> _load() => _loading ??= _read();

  Future<Map<String, _Usage>> _read() async {
    if (_log != null) return _log!;
    final log = <String, _Usage>{};
    try {
      final raw = (await _prefs())?.getString(_kKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final buckets = <int, int>{};
            if (e.value is Map && (e.value as Map)['minute'] is Map) {
              final entry = e.value as Map;
              log['${e.key}'] = _Usage(
                (entry['dayStart'] as num).toInt(),
                (entry['day'] as num).toInt(),
                {
                  for (final bucket in (entry['minute'] as Map).entries)
                    int.parse('${bucket.key}'): (bucket.value as num).toInt(),
                },
              );
              continue;
            }
            if (e.value is Map) {
              for (final bucket in (e.value as Map).entries) {
                final at = int.parse('${bucket.key}');
                final count = (bucket.value as num).toInt();
                if (count > 0) buckets[at] = count;
              }
            } else if (e.value is List) {
              for (final t in e.value as List) {
                if (t is num) {
                  buckets.update(t.toInt(), (n) => n + 1, ifAbsent: () => 1);
                }
              }
            }
            final now = _now();
            final start = DateTime(
              now.year,
              now.month,
              now.day,
            ).millisecondsSinceEpoch;
            log['${e.key}'] = _Usage(
              start,
              buckets.entries
                  .where((e) => e.key >= start)
                  .fold(0, (sum, e) => sum + e.value),
              buckets,
            );
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
    final entry = (await _load())[keyFor(profileId, model)];
    if (entry == null) return (minute: 0, day: 0);
    final now = _now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final cutoff = now
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    entry.minute.removeWhere((at, _) => at <= cutoff);
    return (
      minute: entry.minute.values.fold(0, (sum, n) => sum + n),
      day: entry.dayStart == start ? entry.day : 0,
    );
  }

  /// Throws [RemoteLimitReached] when [limit] would be exceeded by one more
  /// request; otherwise records the request and returns its time, which
  /// [refund] takes back.
  Future<int> charge(
    String profileId,
    String model,
    RemoteLimit limit, {
    String label = '',
  }) {
    final next = _admissions.then(
      (_) => _charge(profileId, model, limit, label),
    );
    _admissions = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Takes back the request charged at [at] that never reached the
  /// provider (a connection error or Stop before sending) (P3-25).
  Future<void> refund(String profileId, String model, int at) {
    final next = _admissions.then((_) async {
      final entry = (await _load())[keyFor(profileId, model)];
      final n = entry?.minute[at];
      if (entry == null || n == null) return;
      if (n > 1) {
        entry.minute[at] = n - 1;
      } else {
        entry.minute.remove(at);
      }
      final now = _now();
      final start = DateTime(now.year, now.month, now.day);
      if (entry.dayStart == start.millisecondsSinceEpoch && entry.day > 0) {
        entry.day--;
      }
      _persist();
    });
    _admissions = next.catchError((_) {});
    return next;
  }

  Future<int> _charge(
    String profileId,
    String model,
    RemoteLimit limit,
    String label,
  ) async {
    final log = await _load();
    final key = keyFor(profileId, model);
    final now = _now();
    if (!limit.isEmpty) {
      final c = await counts(profileId, model);
      final t = appStrings;
      final what = label.isEmpty ? t.remoteThisModel : label;
      if (limit.perMinute > 0 && c.minute >= limit.perMinute) {
        final oldest = (log[key]?.minute.keys ?? const <int>[])
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
          t.remoteMinuteLimit(
            '${limit.perMinute}',
            what,
            '${wait.clamp(1, 60)}',
          ),
        );
      }
      if (limit.perDay > 0 && c.day >= limit.perDay) {
        throw RemoteLimitReached(t.remoteDayLimit('${limit.perDay}', what));
      }
    }
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final entry = log.putIfAbsent(key, () => _Usage(start, 0, {}));
    if (entry.dayStart != start) {
      entry.dayStart = start;
      entry.day = 0;
    }
    final cutoff = now
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    entry.minute.removeWhere((at, _) => at <= cutoff);
    entry.minute.update(
      now.millisecondsSinceEpoch,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    entry.day++;
    _persist();
    return now.millisecondsSinceEpoch;
  }

  void _persist() {
    final snapshot = jsonEncode({
      for (final entry in _log!.entries)
        entry.key: {
          'dayStart': entry.value.dayStart,
          'day': entry.value.day,
          'minute': {
            for (final bucket in entry.value.minute.entries)
              '${bucket.key}': bucket.value,
          },
        },
    });
    _writes = _writes.then((_) async {
      try {
        await (await _prefs())?.setString(_kKey, snapshot);
      } catch (e, st) {
        quietFailure('remote_usage:223', e, st);
      }
    });
  }

  /// Forgets the counts of a deleted connection.
  Future<void> forget(String profileId) async {
    final log = await _load();
    log.removeWhere((k, _) => k.startsWith('$profileId|'));
    _persist();
  }
}

class _Usage {
  int dayStart, day;
  final Map<int, int> minute;
  _Usage(this.dayStart, this.day, this.minute);
}
