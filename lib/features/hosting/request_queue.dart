import 'dart:async';

import 'device_model_server.dart';

/// One active request per runtime, with a bounded FIFO of waiting requests.
class RequestQueue {
  final _waiting = <String, List<Completer<void>>>{};
  bool _closed = false;

  Future<void> acquire(String key) async {
    if (_closed) throw const RouteRefusal(503, 'The server stopped.');
    final queue = _waiting[key];
    if (queue == null) {
      _waiting[key] = [];
      return;
    }
    if (queue.length >= 8) {
      throw const RouteRefusal(
        429,
        'The model request queue is full (8 waiting).',
      );
    }
    final ready = Completer<void>();
    queue.add(ready);
    await ready.future;
  }

  void release(String key) {
    final queue = _waiting[key];
    if (queue == null) return;
    if (queue.isEmpty) {
      _waiting.remove(key);
    } else {
      queue.removeAt(0).complete();
    }
  }

  void close() {
    _closed = true;
    for (final queue in _waiting.values) {
      for (final ready in queue) {
        ready.completeError(const RouteRefusal(503, 'The server stopped.'));
      }
    }
    _waiting.clear();
  }
}
