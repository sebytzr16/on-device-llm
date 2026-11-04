import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'device_model_server.dart';
import 'workspace_jobs.dart';
import 'workspace_uploads.dart';

/// Called only after DeviceModelServer's VPN/address and bearer-token checks.
class WorkspaceApi {
  static const root = '/v1/workspace';
  final WorkspaceJobs jobs;
  final Future<void> Function(WorkspaceJob, Map<String, dynamic>) run;
  final List<String> capabilities;
  final WorkspaceUploads uploads;
  WorkspaceApi({
    required this.run,
    required this.capabilities,
    WorkspaceJobs? jobs,
    WorkspaceUploads? uploads,
  }) : jobs = jobs ?? WorkspaceJobs(),
       uploads = uploads ?? WorkspaceUploads();

  Future<void> handle(HttpRequest request) async {
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
        final job = jobs.submit(
          requestId: input['requestId'] as String,
          fingerprint: sha256.convert(utf8.encode(raw)).toString(),
          run: (job) => run(job, input),
        );
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
      if (job == null) {
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
        final events = StreamIterator(job.events(after: cursor));
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
          await events.cancel();
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
    } finally {
      if (!detached) await response.close();
    }
  }

  Future<void> dispose() async {
    await jobs.dispose();
    await uploads.dispose();
  }
}
