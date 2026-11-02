import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadRecord {
  final String attempt, modelId, name, result;
  final int size;
  final DateTime date;
  const DownloadRecord({
    required this.attempt,
    required this.modelId,
    required this.name,
    required this.result,
    required this.size,
    required this.date,
  });
  Map<String, dynamic> toJson() => {
    'attempt': attempt,
    'modelId': modelId,
    'name': name,
    'result': result,
    'size': size,
    'date': date.toIso8601String(),
  };
  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
    attempt: j['attempt'] as String,
    modelId: j['modelId'] as String,
    name: j['name'] as String,
    result: j['result'] as String,
    size: j['size'] as int,
    date: DateTime.parse(j['date'] as String),
  );
}

/// Written at start too: a killed process leaves an interrupted attempt.
class DownloadHistory {
  static const key = 'model_download_history_v1';
  static final changes = StreamController<void>.broadcast();
  static Future<void> _pending = Future.value();
  static Future<List<DownloadRecord>> read() async {
    await _pending;
    return _read(await SharedPreferences.getInstance());
  }

  static List<DownloadRecord> _read(SharedPreferences prefs) {
    try {
      return (jsonDecode(prefs.getString(key) ?? '[]') as List)
          .map(
            (j) => DownloadRecord.fromJson(Map<String, dynamic>.from(j as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> put(DownloadRecord record) => _write(
    (rows) => [
      record,
      ...rows.where((r) => r.attempt != record.attempt),
    ].take(250).toList(),
  );
  static Future<void> cancelled(String id) => _write((rows) {
    final index = rows.indexWhere((r) => r.modelId == id);
    if (index < 0) return rows;
    final old = rows[index];
    rows[index] = DownloadRecord(
      attempt: old.attempt,
      modelId: old.modelId,
      name: old.name,
      result: 'cancelled',
      size: old.size,
      date: old.date,
    );
    return rows;
  });
  static Future<void> _write(
    List<DownloadRecord> Function(List<DownloadRecord>) update,
  ) {
    final next = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final rows = update(_read(prefs));
      await prefs.setString(
        key,
        jsonEncode(rows.map((r) => r.toJson()).toList()),
      );
      changes.add(null);
    });
    // History must never change the outcome or cleanup of a file transfer.
    _pending = next.catchError((Object _) {});
    return _pending;
  }
}
