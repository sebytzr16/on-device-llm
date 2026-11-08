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
  static const maxJournalBytes = 8 * 1024 * 1024;

  WorkspaceJob(this.id, this.requestId, this.fingerprint);

  int get sequence => _sequence;
  int get retainedBytes => _bytes;

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
    _bytes = _events.fold(
      0,
      (total, event) => total + utf8.encode(jsonEncode(event)).length,
    );
  }

  void emit(String type, [Map<String, dynamic> data = const {}]) {
    if (terminal) return;
    final event = <String, dynamic>{
      'jobId': id,
      'sequence': sequence + 1,
      'type': type,
      'data': data,
    };
    final size = utf8.encode(jsonEncode(event)).length;
    if (_bytes + size > maxJournalBytes) {
      // Include the replacement while compacting so its predecessor does not
      // count against the budget alongside the new snapshot.
      _events.add(event);
      _compactSnapshots();
      _events.removeLast();
      _bytes -= size;
    }
    if (_bytes + size > maxJournalBytes &&
        !const {'done', 'failed', 'cancelled'}.contains(type)) {
      stop('Job activity exceeded the retained event limit.');
      return;
    }
    _bytes += size;
    _events.add(event);
    _sequence++;
    terminal = const {'done', 'failed', 'cancelled'}.contains(type);
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
    if (terminal) {
      for (final approval in _approvals.values) {
        if (!approval.isCompleted) approval.complete(false);
      }
      _approvals.clear();
    }
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
  final int maxActive;
  final int maxRetained;
  WorkspaceJobs({this.maxActive = 8, this.maxRetained = 32});

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
      if (_jobs.length < maxRetained) break;
      _jobs.remove(old.id);
      _requests.remove(old.requestId);
      unawaited(old.dispose());
    }
    final job = WorkspaceJob(const Uuid().v4(), requestId, fingerprint);
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
    unawaited(job.execution);
    return job;
  }

  Future<void> dispose() async {
    for (final job in _jobs.values) {
      job.stop('The server stopped.');
    }
    await Future.wait(_jobs.values.map((job) => job.execution));
    await Future.wait(_jobs.values.map((job) => job.dispose()));
    _jobs.clear();
    _requests.clear();
  }
}
