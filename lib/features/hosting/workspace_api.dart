import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'device_model_server.dart';
import 'pairing_code.dart';
import 'workspace_jobs.dart';
import 'workspace_uploads.dart';

/// Called only after DeviceModelServer's VPN/address and bearer-token checks.
class WorkspaceApi {
  static const root = '/v1/workspace';
  final WorkspaceJobs jobs;
  final Future<void> Function(WorkspaceJob, Map<String, dynamic>) run;
  final List<String> capabilities;

  /// Added to [capabilities] for the loopback principal, and to every
  /// principal while [shareDocuments] returns true (the host owner's
  /// explicit opt-in to share documents with paired devices).
  final List<String> localCapabilities;

  /// Whether the host owner lets paired devices use [localCapabilities].
  /// Read on every capabilities request; null keeps them loopback-only.
  final bool Function()? shareDocuments;
  final WorkspaceUploads uploads;
  final _jobOwners = <String, String>{};
  String? principalFor(WorkspaceJob job) => _jobOwners[job.id];

  /// The opt-in is for paired devices only: the legacy shared token is an
  /// old client that never agreed to the guaranteed hosting policies.
  List<String> capabilitiesFor(String principal) => [
    ...capabilities,
    if (principal == 'local' ||
        (principal != 'legacy' && (shareDocuments?.call() ?? false)))
      ...localCapabilities,
  ];

  bool _closing = false;
  final _requests = <Completer<void>, Future<void>>{};
  final _eventSockets = <Socket>{};
  Future<void>? _disposal;
  final _uploadOwners = <String, String>{};

  /// Bumped when a device is revoked: a request that was already reading its
  /// body must not register an upload or start a job afterwards.
  final _revocations = <String, int>{};

  /// Lets a test own a job it submitted directly to [jobs] (jobs submitted
  /// through the API are owned by the calling principal).
  @visibleForTesting
  void debugAssignOwner(String jobId, String principal) =>
      _jobOwners[jobId] = principal;
  final _jobUploads = <String, Set<String>>{};
  final _imageDirectories = <String, Future<Directory>>{};
  static const _completionHeader = 'x-workspace-completion';
  final _completionSecret = PairingCode.secret();
  final _completionClients = <String, String>{};

  /// In-memory credentials for this job's calls back to this server. Never
  /// included in workspace responses or taken from the submitted JSON.
  Map<String, String> completionHeaders(WorkspaceJob job) => {
    _completionHeader: '$_completionSecret.${job.id}',
  };

  /// Only a loopback caller holding this API instance's private credential
  /// can attribute a completion to an active job's original socket address.
  String? completionClient(HttpRequest request) {
    if (request.connectionInfo?.remoteAddress.isLoopback != true ||
        request.method != 'POST' ||
        request.uri.path != DeviceModelServer.completionsPath) {
      return null;
    }
    final credentials = request.headers[_completionHeader];
    if (credentials == null || credentials.length != 1) return null;
    return _completionClients[credentials.single];
  }

  WorkspaceApi({
    required this.run,
    required this.capabilities,
    this.localCapabilities = const [],
    this.shareDocuments,
    WorkspaceJobs? jobs,
    WorkspaceUploads? uploads,
  }) : jobs = jobs ?? WorkspaceJobs(),
       uploads = uploads ?? WorkspaceUploads() {
    this.uploads.onExpired = (id) => _uploadOwners.remove(id);
  }

  /// Answers the request on a detached socket and returns the status code it
  /// wrote, for the serving log; null means the peer went away first.
  Future<int?> handle(
    HttpRequest request, {
    String principal = 'legacy',
    required Future<Socket> Function() detach,
    required void Function(Socket) releaseSocket,
  }) async {
    if (_closing) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return HttpStatus.serviceUnavailable;
    }
    final cancel = Completer<void>();
    final done = _handle(
      request,
      principal,
      cancel.future,
      detach,
      releaseSocket,
    );
    _requests[cancel] = done;
    try {
      return await done;
    } finally {
      unawaited(_requests.remove(cancel));
    }
  }

  Future<int?> _handle(
    HttpRequest request,
    String principal,
    Future<void> cancelled,
    Future<Socket> Function() detach,
    void Function(Socket) releaseSocket,
  ) async {
    // A body can take seconds to arrive; check the principal again before
    // this request is allowed to change server state.
    final revocation = _revocations[principal] ?? 0;
    void stillAuthenticated() {
      if (_closing) throw StateError('The server stopped.');
      if ((_revocations[principal] ?? 0) != revocation) {
        throw StateError('This device was disconnected.');
      }
    }

    Socket? detached;
    int? status;
    Object? payload;
    void json(int code, Object body) {
      status = code;
      payload = body;
    }

    try {
      final path = request.uri.path
          .substring(root.length)
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      if (request.method == 'POST' &&
          path.length == 1 &&
          path.first == 'uploads') {
        final upload = await uploads.receive(
          request,
          principal: principal,
          cancelled: cancelled,
        );
        try {
          stillAuthenticated();
        } catch (_) {
          // The revocation sweep already ran, so this upload has no owner to
          // release it: do it here.
          await uploads.release(upload.id);
          rethrow;
        }
        _uploadOwners[upload.id] = principal;
        json(201, {'uploadId': upload.id});
        return status;
      }
      if (request.method == 'GET' &&
          path.length == 1 &&
          path.first == 'capabilities') {
        json(200, {'version': 1, 'capabilities': capabilitiesFor(principal)});
        return status;
      }
      if (request.method == 'POST' &&
          path.length == 1 &&
          path.first == 'jobs') {
        final raw = await DeviceModelServer.readBody(
          request,
          const Duration(seconds: 30),
          cancelled: cancelled,
        );
        stillAuthenticated();
        final input = jsonDecode(raw);
        if (input is! Map<String, dynamic> || input['requestId'] is! String) {
          throw const FormatException(
            'A JSON request with requestId is required.',
          );
        }
        final requestId = input['requestId'] as String;
        if (requestId.isEmpty || requestId.length > 128) {
          throw const FormatException('A bounded request ID is required.');
        }
        final references = input['uploads'];
        if (input.containsKey('uploads') &&
            (references is! List || references.length > 32)) {
          throw const FormatException(
            'Expected at most 32 attachment references.',
          );
        }
        final ids = <String>{};
        for (final reference in (references as List? ?? const [])) {
          if (reference is! Map ||
              reference['uploadId'] is! String ||
              reference['message'] is! int ||
              (reference['message'] as int) < 0) {
            throw const FormatException('Invalid attachment reference.');
          }
          ids.add(reference['uploadId'] as String);
        }
        for (final id in ids) {
          if (_uploadOwners[id] != principal) {
            json(404, {'error': 'Upload not found.'});
            return status;
          }
        }
        _jobOwners.removeWhere((id, _) => jobs[id] == null);
        _jobUploads.removeWhere((id, _) => jobs[id] == null);
        // Retain upload ownership while a retained job can be retried, even
        // after its bytes have been released by completed execution.
        _uploadOwners.removeWhere(
          (id, _) =>
              uploads[id] == null &&
              !_jobUploads.values.any((ids) => ids.contains(id)),
        );
        final job = jobs.submit(
          requestId: sha256
              .convert(utf8.encode(jsonEncode([principal, requestId])))
              .toString(),
          fingerprint: sha256.convert(utf8.encode(raw)).toString(),
          run: (job) async {
            // submit calls this synchronously only for newly accepted jobs;
            // retries and rejected submissions must not retain extra references.
            _jobOwners[job.id] = principal;
            final credential = '$_completionSecret.${job.id}';
            _completionClients[credential] =
                request.connectionInfo?.remoteAddress.address ??
                'Unknown client';
            try {
              for (final id in ids) {
                uploads.acquire(id);
              }
              await run(job, input);
            } finally {
              _completionClients.remove(credential);
              try {
                await Future.wait(ids.map(uploads.release));
              } finally {
                await _removeImageDirectory(job.id);
              }
            }
          },
        );
        _jobOwners[job.id] = principal;
        _jobUploads[job.id] = ids;
        json(202, {
          'jobId': job.id,
          'sequence': job.sequence,
          'terminal': job.terminal,
        });
        return status;
      }
      if (path.length < 2 || path.first != 'jobs') {
        json(404, {'error': 'Workspace endpoint not found.'});
        return status;
      }
      final job = jobs[path[1]];
      if (job == null || _jobOwners[job.id] != principal) {
        json(404, {
          'error': 'Job expired or the server restarted. Submit a new request.',
        });
        return status;
      }
      if (request.method == 'GET' && path.length == 2) {
        json(200, {
          'jobId': job.id,
          'sequence': job.sequence,
          'terminal': job.terminal,
          'pendingApprovals': job.pendingApprovals,
        });
      } else if (request.method == 'GET' &&
          path.length == 3 &&
          path[2] == 'events') {
        final cursor = int.tryParse(
          request.uri.queryParameters['after'] ?? '0',
        );
        if (cursor == null || cursor < 0 || cursor > job.sequence) {
          throw const FormatException('Invalid event cursor.');
        }
        final socket = detached = await detach();
        if (_closing) {
          json(HttpStatus.serviceUnavailable, {'error': 'The server stopped.'});
          return status;
        }
        _eventSockets.add(socket);
        final disconnected = Completer<void>();
        void lost() {
          if (!disconnected.isCompleted) disconnected.complete();
        }

        final incoming = socket.listen(
          (_) {},
          onDone: lost,
          onError: (_) => lost(),
        );
        final events = StreamIterator(
          job.events(
            after: cursor,
            compact: request.uri.queryParameters['compact'] == '1',
          ),
        );
        try {
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\n'
            'Connection: close\r\nCache-Control: no-cache\r\nAccess-Control-Allow-Origin: *\r\n\r\n',
          );
          await DeviceModelServer.flushWithin(
            socket,
            socket,
            DeviceModelServer.writeTimeout,
          );
          while (await Future.any([
            events.moveNext(),
            disconnected.future.then((_) => false),
          ])) {
            final event = events.current;
            socket.write(
              'id: ${event['sequence']}\ndata: ${jsonEncode(event)}\n\n',
            );
            await DeviceModelServer.flushWithin(
              socket,
              socket,
              DeviceModelServer.writeTimeout,
            );
          }
        } on HttpException catch (_) {
          // Losing this subscriber never cancels server-owned execution.
        } on SocketException catch (_) {
          // The client can rejoin using its last received event sequence.
        } on TimeoutException catch (_) {
          // The write deadline closed this subscription.
        } finally {
          // An idle async generator can be awaiting the next job update.
          // Request cancellation now, but release the socket and admission
          // immediately rather than waiting for server-owned work to progress.
          unawaited(events.cancel());
          _eventSockets.remove(socket);
          unawaited(incoming.cancel());
        }
      } else if (request.method == 'POST' &&
          path.length == 3 &&
          path[2] == 'cancel') {
        job.stop();
        json(200, {'cancelled': true});
      } else if (request.method == 'POST' &&
          path.length == 3 &&
          path[2] == 'approval') {
        final body = jsonDecode(
          await DeviceModelServer.readBody(
            request,
            const Duration(seconds: 15),
            cancelled: cancelled,
          ),
        );
        stillAuthenticated();
        if (body is! Map || body['id'] is! String || body['allow'] is! bool) {
          throw const FormatException('Approval requires id and allow.');
        }
        final accepted = job.decide(
          body['id'] as String,
          body['allow'] as bool,
        );
        json(accepted ? 200 : 409, {'accepted': accepted});
      } else {
        json(404, {'error': 'Workspace endpoint not found.'});
      }
    } on FormatException catch (error) {
      json(400, {'error': error.message});
    } on StateError catch (error) {
      json(409, {'error': error.message});
    } on TimeoutException catch (_) {
      json(408, {'error': 'Request body deadline reached.'});
    } on HttpException catch (_) {
      // The peer abandoned its body. Do not write to its closed response.
    } on SocketException catch (_) {
      // A disconnected upload does not affect server-owned jobs.
    } on Object catch (_) {
      // Anything else still owes the client a reply. Answering here keeps the
      // 500 on the detached socket instead of a 200 with an empty body while
      // the server's own catch can no longer write (audit 06a1-10).
      json(HttpStatus.internalServerError, {'error': 'Request failed.'});
    } finally {
      try {
        final code = status;
        if (code != null && detached == null) {
          final socket = detached = await detach();
          await DeviceModelServer.writeDetachedJson(
            socket,
            request.method,
            code,
            payload,
          );
        }
      } catch (_) {
        // The peer disconnected or could not receive the response in time.
      } finally {
        final socket = detached;
        if (socket != null) {
          await DeviceModelServer.closeDetached(socket);
          releaseSocket(socket);
        } else if (status == null) {
          await DeviceModelServer.closeAttached(request.response);
        }
      }
    }
    return status;
  }

  /// Decode inline images into a private directory owned by this job's run.
  Future<List<Map<String, Object>>> decodeMessages(
    WorkspaceJob job,
    Object? source, {
    required bool vision,
    required List<File> images,
  }) async {
    // The map holds the creation future so concurrent calls for one job share
    // the same directory instead of racing to create two.
    final directory = await _imageDirectories.putIfAbsent(
      job.id,
      () => Directory.systemTemp.createTemp('desktopServe-'),
    );
    return DeviceModelServer.decodeWorkspaceMessages(
      source,
      vision: vision,
      images: images,
      imageDirectory: directory,
    );
  }

  Future<void> _removeImageDirectory(String jobId) async {
    final directory = _imageDirectories[jobId];
    if (directory == null) return;
    try {
      final resolved = await directory;
      if (await resolved.exists()) await resolved.delete(recursive: true);
      unawaited(_imageDirectories.remove(jobId));
    } on FileSystemException {
      // Keep failed cleanup for another attempt when the server stops.
    }
  }

  Future<void> revokePrincipal(String principal) async {
    _revocations[principal] = (_revocations[principal] ?? 0) + 1;
    final stopped = <Future<void>>[];
    for (final entry in _jobOwners.entries) {
      final job = jobs[entry.key];
      if (entry.value == principal && job != null) {
        job.stop();
        stopped.add(job.execution);
      }
    }
    await Future.wait(stopped);
    for (final entry in _uploadOwners.entries.toList()) {
      if (entry.value == principal) {
        _uploadOwners.remove(entry.key);
        await uploads.release(entry.key);
      }
    }
  }

  void closeAdmission() {
    if (_closing) return;
    _closing = true;
    for (final cancel in _requests.keys) {
      cancel.complete();
    }
    for (final socket in _eventSockets) {
      socket.destroy();
    }
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    closeAdmission();
    final stopped = jobs.dispose();
    await Future.wait(_requests.values.map((done) => done.catchError((_) {})));
    await stopped;
    for (final id in _imageDirectories.keys.toList()) {
      await _removeImageDirectory(id);
    }
    await uploads.dispose();
  }
}
