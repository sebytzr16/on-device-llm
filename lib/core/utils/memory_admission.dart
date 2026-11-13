import 'dart:async';

/// Allocation transactions share one queue in the app isolate. Native engines
/// measure live free memory inside the transaction, after earlier allocations
/// have finished. Resident models stay warm and count against the next fit;
/// active work is never evicted to make a new load succeed.
class MemoryAdmission {
  static final shared = MemoryAdmission();
  Future<void>? _tail;
  int _queued = 0;

  Future<T> run<T>(Future<T> Function() allocate) {
    // An idle queue starts the allocation directly, so no completed future
    // from an earlier zone is chained (keeps fake-async tests and callers in
    // their own zone).
    final tail = _tail;
    final next = tail == null
        ? Future.sync(allocate)
        : tail.then((_) => allocate());
    _queued++;
    late final Future<void> done;
    done = next
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          if (--_queued == 0 && identical(_tail, done)) _tail = null;
        });
    _tail = done;
    return next;
  }
}
