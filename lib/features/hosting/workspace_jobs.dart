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
  final _changes = StreamController<void>.broadcast();
  final _approvals = <String, Completer<bool>>{};
  final DateTime created = DateTime.now();
  bool terminal = false;
  Future<void> execution = Future.value();
  List<String> get pendingApprovals => _approvals.keys.toList();
  int _bytes = 0;
  static const maxJournalBytes = 8 * 1024 * 1024;

  WorkspaceJob(this.id, this.requestId, this.fingerprint);

  int get sequence => _events.length;

  void emit(String type, [Map<String, dynamic> data = const {}]) {
    if (terminal) return;
    final event = <String, dynamic>{
      'jobId': id,
      'sequence': sequence + 1,
      'type': type,
      'data': data,
    };
    final size = utf8.encode(jsonEncode(event)).length;
    if (_bytes + size > maxJournalBytes &&
        !const {'done', 'failed', 'cancelled'}.contains(type)) {
      stop('Job activity exceeded the retained event limit.');
      return;
    }
    _bytes += size;
    _events.add(event);
    terminal = const {'done', 'failed', 'cancelled'}.contains(type);
    _changes.add(null);
    if (terminal) {
      for (final approval in _approvals.values) {
        if (!approval.isCompleted) approval.complete(false);
      }
      _approvals.clear();
    }
  }

  /// Subscribe before taking the snapshot so no event can fall between replay
  /// and live subscription. Cursor advances only after yielding each event.
  Stream<Map<String, dynamic>> events({int after = 0}) async* {
    if (after < 0 || after > sequence) {
      throw ArgumentError.value(after, 'after', 'Invalid event cursor');
    }
    final changes = StreamIterator<void>(_changes.stream);
    var cursor = after;
    try {
      while (true) {
        while (cursor < _events.length) {
          yield _events[cursor++];
        }
        if (terminal) break;
        if (!await changes.moveNext()) break;
      }
    } finally {
      await changes.cancel();
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
    await _changes.close();
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
