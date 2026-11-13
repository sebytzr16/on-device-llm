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
  final WorkspaceUploads uploads;
  final _jobOwners = <String, String>{};
  final _uploadOwners = <String, String>{};

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
    WorkspaceJobs? jobs,
    WorkspaceUploads? uploads,
  }) : jobs = jobs ?? WorkspaceJobs(),
       uploads = uploads ?? WorkspaceUploads();

  Future<void> handle(
    HttpRequest request, {
    String principal = 'legacy',
  }) async {
    final response = request.response;
    var detached = false;
    void json(int code, Object body) {
      response.statusCode = code;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(body));
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
        final upload = await uploads.receive(request);
        _uploadOwners[upload.id] = principal;
        json(201, {'uploadId': upload.id});
        return;
      }
      if (request.method == 'GET' &&
          path.length == 1 &&
          path.first == 'capabilities') {
        json(200, {'version': 1, 'capabilities': capabilities});
        return;
      }
      if (request.method == 'POST' &&
          path.length == 1 &&
          path.first == 'jobs') {
        final raw = await DeviceModelServer.readBody(
          request,
          const Duration(seconds: 30),
        );
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
        if (input['uploads'] is List) {
          for (final upload in input['uploads'] as List) {
            if (upload is Map &&
                upload['uploadId'] is String &&
                _uploadOwners[upload['uploadId']] != principal) {
              json(404, {'error': 'Upload not found.'});
              return;
            }
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
            final acquired = <String>[];
            final credential = '$_completionSecret.${job.id}';
            _completionClients[credential] =
                request.connectionInfo?.remoteAddress.address ??
                'Unknown client';
            try {
              if (input['uploads'] is List) {
                for (final upload in input['uploads'] as List) {
                  if (upload is Map && upload['uploadId'] is String) {
                    final id = upload['uploadId'] as String;
                    uploads.acquire(id);
                    acquired.add(id);
                  }
                }
              }
              await run(job, input);
            } finally {
              _completionClients.remove(credential);
              try {
                await Future.wait(acquired.map(uploads.release));
              } finally {
                await _removeImageDirectory(job.id);
              }
            }
          },
        );
        _jobOwners[job.id] = principal;
        _jobUploads[job.id] = {
          if (input['uploads'] is List)
            for (final upload in input['uploads'] as List)
              if (upload is Map && upload['uploadId'] is String)
                upload['uploadId'] as String,
        };
        json(202, {
          'jobId': job.id,
          'sequence': job.sequence,
          'terminal': job.terminal,
        });
        return;
      }
      if (path.length < 2 || path.first != 'jobs') {
        json(404, {'error': 'Workspace endpoint not found.'});
        return;
      }
      final job = jobs[path[1]];
      if (job == null || _jobOwners[job.id] != principal) {
        json(404, {
          'error': 'Job expired or the server restarted. Submit a new request.',
        });
        return;
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
        response.persistentConnection = false;
        response.headers.chunkedTransferEncoding = false;
        final socket = await response.detachSocket(writeHeaders: false);
        detached = true;
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
          await socket.flush();
          while (await Future.any([
            events.moveNext(),
            disconnected.future.then((_) => false),
          ])) {
            final event = events.current;
            socket.write(
              'id: ${event['sequence']}\ndata: ${jsonEncode(event)}\n\n',
            );
            await socket.flush();
          }
        } on HttpException catch (_) {
          // Losing this subscriber never cancels server-owned execution.
        } on SocketException catch (_) {
          // The client can rejoin using its last received event sequence.
        } finally {
          // An idle async generator can be awaiting the next job update.
          // Request cancellation now, but release the socket and admission
          // immediately rather than waiting for server-owned work to progress.
          unawaited(events.cancel());
          await incoming.cancel();
          await socket.close();
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
          ),
        );
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
    } finally {
      if (!detached) await response.close();
    }
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

  Future<void> dispose() async {
    await jobs.dispose();
    for (final id in _imageDirectories.keys.toList()) {
      await _removeImageDirectory(id);
    }
    await uploads.dispose();
  }
}
