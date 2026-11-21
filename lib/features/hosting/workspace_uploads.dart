import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:ondevice_llm/core/logging/quiet_failure.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../attachments/data/attachment_store.dart';

class WorkspaceUpload {
  final String id, name;
  final File file;
  final int size;
  final DateTime created;
  final _UploadBatch? _batch;
  WorkspaceUpload._(
    this.id,
    this.name,
    this.file,
    this.size,
    this.created, [
    this._batch,
  ]);
}

class _UploadBatch {
  final (String, String?) key;
  final DateTime created;
  DateTime lastActivity;
  int files = 0;
  int receiving = 0;

  _UploadBatch(this.key, this.created) : lastActivity = created;
}

/// Raw bytes are uploaded once; clients never supply a server file path.
class WorkspaceUploads {
  static const maxFileBytes = 64 * 1024 * 1024;
  static const maxTotalBytes = 256 * 1024 * 1024;
  static const idleTimeout = Duration(seconds: 60);

  /// 64 MiB fits at about 1 Mbit/s; a slower or stalled client must not keep
  /// its admission slot and reserved bytes for longer than this.
  static const receiveDeadline = Duration(minutes: 10);

  /// An upload nobody submitted is abandoned: expire it instead of holding
  /// its slot and bytes until hosting restarts.
  static const abandonedAfter = Duration(minutes: 15);
  static const maxBatchLifetime = Duration(hours: 1);
  final _files = <String, WorkspaceUpload>{};
  final _batches = <(String, String?), _UploadBatch>{};
  final _references = <String, int>{};
  final _pendingDeletes = <String>{};
  Timer? _expiration;
  void Function(String)? onExpired;
  final Duration _maxAge;
  final Duration _sweepInterval;
  final int _maxCacheBytes;
  int _bytes = 0;
  int _reserved = 0;

  final Future<Directory> Function() _createDirectory;
  final DateTime Function() _clock;
  final Duration _receiveDeadline;
  WorkspaceUploads({
    Future<Directory> Function()? createDirectory,
    this._receiveDeadline = WorkspaceUploads.receiveDeadline,
    this._maxAge = abandonedAfter,
    this._sweepInterval = const Duration(minutes: 1),
    this._maxCacheBytes = maxTotalBytes,
    DateTime Function()? clock,
  }) : _createDirectory =
           createDirectory ??
           (() => Directory.systemTemp.createTemp('ondevice-workspace-')),
       _clock = clock ?? DateTime.now;

  WorkspaceUpload? operator [](String id) =>
      _pendingDeletes.contains(id) ? null : _files[id];

  /// Adds the batch-less entry a failed receive keeps when its staged file
  /// cannot be removed, so the sweep stays covered for that shape.
  @visibleForTesting
  void debugAdoptBatchless(String id, File file) {
    final size = file.lengthSync();
    _files[id] = WorkspaceUpload._(
      id,
      p.basename(file.path),
      file,
      size,
      _clock(),
    );
    _bytes += size;
    _armExpiration();
  }

  /// Retain before accepted work can wait on another job or model.
  void acquire(String id) {
    if (this[id] != null) {
      _references[id] = (_references[id] ?? 0) + 1;
    }
  }

  Future<void> release(String id) async {
    final references = _references[id] ?? 0;
    if (references > 1) {
      _references[id] = references - 1;
      return;
    }
    _references.remove(id);
    _delete(id);
  }

  bool _delete(String id) {
    final upload = _files[id];
    if (upload == null) return false;
    _pendingDeletes.add(id);
    try {
      if (FileSystemEntity.typeSync(upload.file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        upload.file.deleteSync();
      }
      if (upload.file.parent.existsSync()) upload.file.parent.deleteSync();
    } on FileSystemException {
      return false;
    }
    _files.remove(id);
    final batch = upload._batch;
    if (batch != null && --batch.files == 0 && _batches[batch.key] == batch) {
      _batches.remove(batch.key);
    }
    _pendingDeletes.remove(id);
    _bytes -= upload.size;
    if (_files.isEmpty && _reserved == 0) {
      _expiration?.cancel();
      _expiration = null;
    }
    return true;
  }

  Future<WorkspaceUpload> receive(
    HttpRequest request, {
    String principal = 'legacy',
    Future<void>? cancelled,
  }) async {
    final size = request.contentLength;
    if (size < 1 || size > maxFileBytes) {
      throw const FormatException(
        'Uploads require a content length of 1 to 64 MiB.',
      );
    }
    final id = const Uuid().v4();
    final name = p.posix.basename(
      (request.uri.queryParameters['name'] ?? 'file').replaceAll('\\', '/'),
    );
    if (name.isEmpty || name.length > 240) {
      throw const FormatException(
        'The upload file name must contain 1 to 240 characters.',
      );
    }
    final batchId = request.uri.queryParameters['batch'];
    if (batchId != null && (batchId.isEmpty || batchId.length > 128)) {
      throw const FormatException('Invalid upload batch identifier.');
    }
    // A client that sends no batch gets a batch of its own: otherwise every
    // batch-less upload of a principal would refresh the others' expiry.
    final batchKey = (principal, batchId ?? id);
    await expireAbandoned(maxAge: _maxAge);
    if (_files.length + _reserved >= 64 || _bytes + size > _maxCacheBytes) {
      throw StateError(
        'The server upload cache is full. Restart hosting after active jobs finish.',
      );
    }
    final receivingBatch = _batches[batchKey];
    if (receivingBatch != null) receivingBatch.receiving++;
    _bytes += size;
    _reserved++;
    Directory? directory;
    File? stagedFile;
    IOSink? sink;
    Timer? deadline;
    var retained = false;
    try {
      directory = await _createDirectory();
      final file = stagedFile = File(
        p.join(directory.path, '$id${AttachmentStore.safeDiskSuffix(name)}'),
      );
      var received = 0;
      sink = file.openWrite();
      Object? stopped;
      final finished = Completer<void>();
      late final StreamSubscription<List<int>> body;
      void stop(Object reason) {
        if (finished.isCompleted) return;
        stopped = reason;
        finished.complete();
      }

      // The idle timeout alone restarts on every chunk, so a client trickling
      // bytes could hold the slot for hours: the total deadline also applies.
      final deadlineTimer = deadline = Timer(_receiveDeadline, () {
        stop(TimeoutException('Upload deadline reached.', _receiveDeadline));
      });
      body = request
          .timeout(idleTimeout)
          .listen(
            (chunk) {
              if (finished.isCompleted) return;
              received += chunk.length;
              if (received > size) {
                stop(
                  const FormatException('Upload exceeded its declared length.'),
                );
                return;
              }
              sink!.add(chunk);
            },
            onError: (Object error, StackTrace stack) => stop(error),
            onDone: () {
              if (!finished.isCompleted) finished.complete();
            },
            cancelOnError: true,
          );
      unawaited(
        cancelled?.then((_) => stop(StateError('The server stopped.'))),
      );
      await finished.future;
      deadlineTimer.cancel();
      await body.cancel();
      if (stopped != null) throw stopped!;
      await sink.close();
      sink = null;
      if (received != size) {
        throw const FormatException('Upload was incomplete.');
      }
      final now = _clock();
      var batch = _batches[batchKey];
      if (batch == null || now.difference(batch.created) >= maxBatchLifetime) {
        batch = _batches[batchKey] = _UploadBatch(batchKey, now);
      }
      batch.lastActivity = now;
      batch.files++;
      final upload = WorkspaceUpload._(id, name, file, size, now, batch);
      _files[id] = upload;
      _armExpiration();
      retained = true;
      return upload;
    } finally {
      deadline?.cancel();
      if (receivingBatch != null) receivingBatch.receiving--;
      _reserved--;
      if (!retained) {
        try {
          await sink?.close();
        } on Object catch (e, st) {
          // A cleanup failure must not hide the receive error.
          quietFailure('workspace_uploads sink close', e, st);
        } finally {
          if (stagedFile != null) {
            _files[id] = WorkspaceUpload._(
              id,
              name,
              stagedFile,
              size,
              _clock(),
            );
            if (!_delete(id)) _armExpiration();
          } else {
            _bytes -= size;
            try {
              final temp = directory;
              if (temp != null && await temp.exists()) {
                await temp.delete();
              }
            } on Object catch (e, st) {
              // Another attempt must not leave the temp directory behind.
              quietFailure('workspace_uploads cleanup', e, st);
            }
          }
        }
      }
    }
  }

  void _armExpiration() {
    _expiration ??= Timer.periodic(
      _sweepInterval,
      (_) => unawaited(expireAbandoned(maxAge: _maxAge)),
    );
  }

  /// Release uploads that were never submitted to a job. Their bytes and
  /// admission slots would otherwise stay reserved until hosting stops.
  Future<int> expireAbandoned({Duration maxAge = abandonedAfter}) async {
    for (final id in _pendingDeletes.toList()) {
      _delete(id);
    }
    final now = _clock();
    var expired = 0;
    for (final upload in _files.values.toList()) {
      if ((_references[upload.id] ?? 0) > 0 ||
          _pendingDeletes.contains(upload.id)) {
        continue;
      }
      final batch = upload._batch;
      // Never expire a batch that is still receiving: its hard lifetime would
      // delete files the in-flight upload of the same batch is about to use.
      if (batch != null && batch.receiving > 0) continue;
      // An upload re-inventoried without a batch expires on its own clock.
      final created = batch?.created ?? upload.created;
      final lastActivity = batch?.lastActivity ?? upload.created;
      final idle = now.difference(lastActivity) >= maxAge;
      if (!idle && now.difference(created) < maxBatchLifetime) continue;
      onExpired?.call(upload.id);
      _delete(upload.id);
      expired++;
    }
    return expired;
  }

  Future<void> dispose() async {
    _expiration?.cancel();
    _expiration = null;
    _references.clear();
    for (final id in _files.keys.toList()) {
      _delete(id);
    }
  }
}
