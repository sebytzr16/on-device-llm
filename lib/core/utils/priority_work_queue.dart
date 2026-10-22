import 'dart:async';

/// Runs one operation at a time. Interactive requests go ahead of queued
/// indexing work; an active native call keeps ownership until it finishes.
class PriorityWorkQueue {
  final _pending = <({int priority, Future<void> Function() run})>[];
  bool _running = false;
  Future<T> submit<T>(
    Future<T> Function() action, {
    int priority = 0,
    bool Function()? cancelled,
  }) {
    final result = Completer<T>();
    _pending.add((
      priority: priority,
      run: () async {
        try {
          if (cancelled?.call() == true) {
            throw StateError('Queued work cancelled');
          }
          result.complete(await action());
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      },
    ));
    if (!_running) unawaited(_drain());
    return result.future;
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        var selected = 0;
        for (var i = 1; i < _pending.length; i++) {
          if (_pending[i].priority > _pending[selected].priority) selected = i;
        }
        await _pending.removeAt(selected).run();
      }
    } finally {
      _running = false;
    }
  }
}
