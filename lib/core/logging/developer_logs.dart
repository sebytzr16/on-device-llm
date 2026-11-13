import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

class DeveloperLogEntry {
  final DateTime time;
  final Level level;
  final String tag, message;
  const DeveloperLogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });

  @override
  String toString() =>
      '${time.toIso8601String()} [${level.name}] $tag: $message';
}

/// Memory only; the startup logger feeds this even while the view is closed.
class DeveloperLogBuffer extends ChangeNotifier {
  static const capacity = 2000;
  final _entries = _LogRing(capacity);
  // A fresh, cheap view also gives Riverpod a new identity to publish.
  List<DeveloperLogEntry> get entries => UnmodifiableListView(_entries);

  void record(LogRecord record) {
    final message = StringBuffer(record.message);
    if (record.error != null) message.write('\n${record.error}');
    if (record.stackTrace != null) message.write('\n${record.stackTrace}');
    // A blank line (an empty stack trace) is no entry of its own; it showed
    // as a bare WARNING row (owner 2026-11-12).
    final lines = message
        .toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty);
    for (final line in lines) {
      _entries.append(
        DeveloperLogEntry(
          time: record.time,
          level: record.level,
          tag: record.loggerName,
          message: line,
        ),
      );
    }
    notifyListeners();
  }

  void clear() {
    _entries.reset();
    notifyListeners();
  }
}

class _LogRing extends ListBase<DeveloperLogEntry> {
  final List<DeveloperLogEntry?> _items;
  int _start = 0, _length = 0;
  _LogRing(int capacity) : _items = List.filled(capacity, null);

  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Read-only log entries');

  @override
  DeveloperLogEntry operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _items[(_start + index) % _items.length]!;
  }

  @override
  void operator []=(int index, DeveloperLogEntry value) =>
      throw UnsupportedError('Read-only log entries');

  void append(DeveloperLogEntry entry) {
    _items[(_start + _length) % _items.length] = entry;
    if (_length < _items.length) {
      _length++;
    } else {
      _start = (_start + 1) % _items.length;
    }
  }

  void reset() {
    _items.fillRange(0, _items.length, null);
    _start = _length = 0;
  }
}

final developerLogBuffer = DeveloperLogBuffer();
final developerLogsProvider =
    NotifierProvider<DeveloperLogsNotifier, List<DeveloperLogEntry>>(
      DeveloperLogsNotifier.new,
    );

class DeveloperLogsNotifier extends Notifier<List<DeveloperLogEntry>> {
  @override
  List<DeveloperLogEntry> build() {
    void update() => state = developerLogBuffer.entries;
    developerLogBuffer.addListener(update);
    ref.onDispose(() => developerLogBuffer.removeListener(update));
    return developerLogBuffer.entries;
  }

  void clear() => developerLogBuffer.clear();
}
