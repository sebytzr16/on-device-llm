import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// Server-owned work survives losing its event subscriber. Reattaching reads
/// the same ordered journal rather than starting another model/tool request.
class WorkspaceJob {
  final String id;
  final String requestId;
  final String fingerprint;
  final CancelToken cancel = CancelToken();
  final _events = <Map<String, dynamic>>[];
  var _changed = Completer<void>();
  final _approvals = <String, Completer<bool>>{};
  final DateTime created = DateTime.now();
  bool terminal = false;
  Future<void> execution = Future.value();
  List<String> get pendingApprovals => _approvals.keys.toList();
  int _bytes = 0;
  int _sequence = 0;
  int _terminalReserve = 0;
  static const maxJournalBytes = 8 * 1024 * 1024;
  static const _terminalTypes = {'done', 'failed', 'cancelled'};

  /// This job's share of the server's retained-event budget.
  final int journalLimit;

  /// Asks the server's shared budget for [bytes] before one event is
  /// retained; null keeps only [journalLimit].
  final bool Function(int bytes)? reserveBytes;

  /// Returns [bytes] to the shared budget when the journal shrinks.
  final void Function(int bytes)? releaseBytes;

  WorkspaceJob(
    this.id,
    this.requestId,
    this.fingerprint, {
    int? journalLimit,
    this.reserveBytes,
    this.releaseBytes,
  }) : journalLimit = journalLimit ?? maxJournalBytes {
    // A minimal terminal event must fit even at the largest sequence number.
    _terminalReserve = _eventSize(
      _event('cancelled', const {}, 9223372036854775807),
    );
    if (_terminalReserve > this.journalLimit ||
        !(reserveBytes?.call(_terminalReserve) ?? true)) {
      throw StateError('The server workspace journal is full.');
    }
  }

  int get sequence => _sequence;
  int get retainedBytes => _bytes;

  Map<String, dynamic> _event(
    String type,
    Map<String, dynamic> data,
    int sequence,
  ) => {'jobId': id, 'sequence': sequence, 'type': type, 'data': data};

  static int _eventSize(Map<String, dynamic> event) =>
      utf8.encode(jsonEncode(event)).length;

  void _compactSnapshots() {
    final seen = <String>{};
    final retained = <Map<String, dynamic>>[];
    for (final event in _events.reversed) {
      final data = event['data'] as Map;
      final key = switch (event['type']) {
        'agent' when data['id'] is String => 'agent:${data['id']}',
        'attachment_progress' when data['name'] is String =>
          'attachment:${data['name']}',
        'metrics' => 'metrics',
        _ => null,
      };
      if (key == null || seen.add(key)) retained.add(event);
    }
    _events
      ..clear()
      ..addAll(retained.reversed);
    _bytes = _events.fold(0, (total, event) => total + _eventSize(event));
  }

  void emit(String type, [Map<String, dynamic> data = const {}]) {
    if (terminal) return;
    var event = _event(type, data, sequence + 1);
    if (_terminalTypes.contains(type)) {
      // Preserve terminal details when possible, with a bounded fallback.
      int size;
      try {
        size = _eventSize(event);
      } on JsonUnsupportedObjectError {
        // The minimal event still tells subscribing clients how the job ended.
        event = _event(type, const {}, sequence + 1);
        size = _eventSize(event);
      }
      final extra = size - _terminalReserve;
      if (_bytes + size > journalLimit ||
          (extra > 0 && !(reserveBytes?.call(extra) ?? true))) {
        event = _event(type, const {}, sequence + 1);
        size = _eventSize(event);
      }
      if (size < _terminalReserve) releaseBytes?.call(_terminalReserve - size);
      _terminalReserve = 0;
      _bytes += size;
      _events.add(event);
      _sequence++;
      _finish();
      return;
    }
    final size = _eventSize(event);
    final activityLimit = journalLimit - _terminalReserve;
    if (_bytes + size > activityLimit) {
      // Include the replacement while compacting so its predecessor does not
      // count against the budget alongside the new snapshot.
      final before = _bytes;
      _events.add(event);
      _compactSnapshots();
      _events.removeLast();
      _bytes -= size;
      releaseBytes?.call(before - _bytes);
    }
    if (_bytes + size > activityLimit || !(reserveBytes?.call(size) ?? true)) {
      stop('Job activity exceeded the retained event limit.');
      return;
    }
    _bytes += size;
    _events.add(event);
    _sequence++;
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  /// Completes the journal, wakes subscribers and denies pending approvals.
  void _finish() {
    terminal = true;
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
    for (final approval in _approvals.values) {
      if (!approval.isCompleted) approval.complete(false);
    }
    _approvals.clear();
  }

  /// Capture the change signal before taking the snapshot so no event falls between replay
  /// and live subscription. Cursor advances only after yielding each event.
  Stream<Map<String, dynamic>> events({
    int after = 0,
    bool compact = false,
  }) async* {
    if (after < 0 || after > sequence) {
      throw ArgumentError.value(after, 'after', 'Invalid event cursor');
    }
    var cursor = after;
    while (true) {
      final changed = _changed.future;
      final pending = _events
          .where((event) => (event['sequence'] as int) > cursor)
          .toList();
      for (final event in pending) {
        final next = event['sequence'] as int;
        if (next > cursor + 1 && compact) {
          yield {
            'jobId': id,
            'sequence': cursor + 1,
            'type': 'checkpoint',
            'data': {'through': next - 1},
          };
          cursor = next - 1;
        }
        // Older clients require contiguous cursors. Empty historical updates
        // preserve that contract without retaining superseded output in memory.
        while (cursor + 1 < next) {
          yield {
            'jobId': id,
            'sequence': ++cursor,
            'type': 'compacted',
            'data': <String, dynamic>{},
          };
        }
        cursor = next;
        yield event;
      }
      if (cursor < sequence) continue;
      if (terminal) break;
      await changed;
    }
  }

  Future<bool> approve(String description) async {
    if (terminal || cancel.isCancelled) return false;
    final approvalId = const Uuid().v4();
    final answer = Completer<bool>();
    _approvals[approvalId] = answer;
    emit('approval', {'id': approvalId, 'description': description});
    try {
      return await answer.future;
    } finally {
      _approvals.remove(approvalId);
    }
  }

  bool decide(String approvalId, bool allow) {
    final answer = _approvals[approvalId];
    if (answer == null || answer.isCompleted || terminal) return false;
    answer.complete(allow);
    return true;
  }

  void stop([String reason = 'Stopped by the user.']) {
    if (terminal) return;
    cancel.cancel(reason);
    emit('cancelled', {'reason': reason});
  }

  Future<void> dispose() async {
    stop('The server stopped.');
  }
}

class WorkspaceJobs {
  final _jobs = <String, WorkspaceJob>{};
  final _requests = <String, String>{};
  final _executions = <Future<void>>{};
  final int maxActive;
  final int maxRetained;

  /// Event bytes kept across every retained job. [maxRetained] journals at the
  /// per-job cap would otherwise pin ~256 MiB on the host (audit 06a1-13).
  final int maxRetainedBytes;
  int _journalBytes = 0;

  WorkspaceJobs({
    this.maxActive = 8,
    this.maxRetained = 32,
    this.maxRetainedBytes = 32 * 1024 * 1024,
  });

  /// One job's share of [maxRetainedBytes], so active streams together stay
  /// inside the total instead of each claiming the per-job cap.
  int get journalLimit {
    final share = maxRetainedBytes ~/ (maxActive < 1 ? 1 : maxActive);
    return share < WorkspaceJob.maxJournalBytes
        ? share
        : WorkspaceJob.maxJournalBytes;
  }

  /// Event bytes retained across every job, never above [maxRetainedBytes].
  int get retainedBytes => _journalBytes;

  /// Reserves [bytes] of the shared budget for the job [jobId], dropping the
  /// oldest terminal journals when it is full. False means no room is left
  /// even for this one event.
  bool _reserveJournal(String jobId, int bytes) {
    while (_journalBytes + bytes > maxRetainedBytes) {
      WorkspaceJob? old;
      for (final candidate in _jobs.values) {
        if (candidate.terminal && candidate.id != jobId) {
          old = candidate;
          break;
        }
      }
      if (old == null) return false;
      _drop(old);
    }
    _journalBytes += bytes;
    return true;
  }

  void _releaseJournal(int bytes) => _journalBytes -= bytes;

  void _drop(WorkspaceJob job) {
    if (_jobs.remove(job.id) == null) return;
    _requests.remove(job.requestId);
    _journalBytes -= job.retainedBytes;
    unawaited(job.dispose());
  }

  WorkspaceJob? operator [](String id) => _jobs[id];

  WorkspaceJob submit({
    required String requestId,
    required String fingerprint,
    required Future<void> Function(WorkspaceJob job) run,
  }) {
    if (requestId.isEmpty || requestId.length > 128) {
      throw const FormatException('A bounded request ID is required.');
    }
    final existing = _jobs[_requests[requestId]];
    if (existing != null) {
      if (existing.fingerprint != fingerprint) {
        throw StateError('This request ID belongs to different input.');
      }
      return existing;
    }
    if (_jobs.values.where((j) => !j.terminal).length >= maxActive) {
      throw StateError('The server workspace queue is full.');
    }
    for (final old in _jobs.values.where((j) => j.terminal).toList()) {
      if (_jobs.length < maxRetained && _journalBytes <= maxRetainedBytes) {
        break;
      }
      _drop(old);
    }
    final id = const Uuid().v4();
    final job = WorkspaceJob(
      id,
      requestId,
      fingerprint,
      journalLimit: journalLimit,
      reserveBytes: (bytes) => _reserveJournal(id, bytes),
      releaseBytes: _releaseJournal,
    );
    _jobs[job.id] = job;
    _requests[requestId] = job.id;
    job.emit('queued');
    job.execution = () async {
      try {
        await run(job);
        if (!job.terminal) job.emit('done');
      } catch (error) {
        if (!job.terminal) job.emit('failed', {'message': '$error'});
      }
    }();
    final execution = job.execution;
    _executions.add(execution);
    unawaited(execution.whenComplete(() => _executions.remove(execution)));
    return job;
  }

  Future<void> dispose() async {
    for (final job in _jobs.values) {
      job.stop('The server stopped.');
    }
    await Future.wait(_executions.toList());
    await Future.wait(_jobs.values.map((job) => job.dispose()));
    _jobs.clear();
    _requests.clear();
    _journalBytes = 0;
  }
}
