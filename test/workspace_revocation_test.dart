import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/hosting/workspace_uploads.dart';

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response implements HttpResponse {
  @override
  int statusCode = 0;
  final body = StringBuffer();
  @override
  Duration? deadline;
  @override
  final HttpHeaders headers = _Headers();
  @override
  void write(Object? object) => body.write(object);
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Captures the reply the API writes on a detached socket, so the tests can
/// read the status and body the way the attached response used to carry them.
class _DetachedSocket implements Socket {
  _DetachedSocket(this.response);
  final _Response response;
  final _reply = StringBuffer();

  @override
  void write(Object? object) => _reply.write(object);

  @override
  void add(List<int> data) => _reply.write(utf8.decode(data));

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    final text = _reply.toString();
    final split = text.indexOf('\r\n\r\n');
    final head = split < 0 ? text : text.substring(0, split);
    final status = RegExp(r'^HTTP/1\.1 (\d{3})').firstMatch(head);
    if (status != null) response.statusCode = int.parse(status.group(1)!);
    if (split >= 0) response.body.write(text.substring(split + 4));
  }

  @override
  void destroy() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection implements HttpConnectionInfo {
  @override
  final InternetAddress remoteAddress;
  _Connection(String address) : remoteAddress = InternetAddress(address);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A request whose body arrives only when the test writes to it.
class _Request extends Stream<Uint8List> implements HttpRequest {
  final Stream<Uint8List> _body;
  @override
  final int contentLength;
  @override
  final Uri uri;
  @override
  final HttpHeaders headers = _Headers();
  @override
  final HttpConnectionInfo connectionInfo = _Connection('127.0.0.1');
  @override
  String get method => 'POST';
  @override
  final _Response response = _Response();
  _Request(this._body, this.contentLength, String path)
    : uri = Uri.parse('${WorkspaceApi.root}$path');

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  _Request request(String path, Object payload) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    return _Request(Stream.value(bytes), bytes.length, path);
  }

  /// Answers like the server does: the reply is written on a detached socket.
  Future<int?> handle(
    WorkspaceApi api,
    _Request request, {
    String principal = 'legacy',
  }) {
    final socket = _DetachedSocket(request.response);
    return api.handle(
      request,
      principal: principal,
      detach: () async => socket,
      releaseSocket: (_) {},
    );
  }

  test(
    'closing workspace admission cancels and drains an in-flight upload and job body',
    () async {
      final receiving = Completer<void>();
      final uploads = WorkspaceUploads(
        createDirectory: () async {
          final directory = await Directory.systemTemp.createTemp(
            'workspace-shutdown-',
          );
          receiving.complete();
          return directory;
        },
      );
      final api = WorkspaceApi(
        uploads: uploads,
        capabilities: const [],
        run: (_, _) async => fail('The job must be refused'),
      );
      final upload = StreamController<Uint8List>();
      final job = StreamController<Uint8List>();
      final sendingUpload = handle(
        api,
        _Request(upload.stream, 10, '/uploads'),
      );
      final sendingJob = handle(api, _Request(job.stream, 100, '/jobs'));
      await receiving.future;
      await api.dispose();
      await Future.wait([
        sendingUpload,
        sendingJob,
        upload.close(),
        job.close(),
      ]);
      final lateRequest = request('/jobs', {'requestId': 'late'});
      await handle(api, lateRequest);
      expect(lateRequest.response.statusCode, HttpStatus.serviceUnavailable);
    },
  );

  test(
    'oversized and malformed attachment lists are refused before lookup',
    () async {
      final api = WorkspaceApi(
        capabilities: const [],
        run: (_, _) async => fail('The job must be refused'),
      );
      addTearDown(api.dispose);
      for (final references in [
        null,
        List.filled(33, {'uploadId': 'absent', 'message': 0}),
        [
          {'uploadId': 'absent', 'message': 0},
          false,
        ],
        [
          {'uploadId': 'absent', 'message': '0'},
        ],
      ]) {
        final req = request('/jobs', {
          'requestId': 'bad',
          'uploads': references,
        });
        await handle(api, req);
        expect(req.response.statusCode, HttpStatus.badRequest);
      }
    },
  );

  test(
    'periodic expiration releases abandoned files and their ownership',
    () async {
      late Directory directory;
      final uploads = WorkspaceUploads(
        createDirectory: () async => directory = await Directory.systemTemp
            .createTemp('workspace-expire-'),
        maxAge: Duration.zero,
        sweepInterval: const Duration(milliseconds: 5),
      );
      final api = WorkspaceApi(
        uploads: uploads,
        capabilities: const [],
        run: (_, _) async => fail('The expired upload must be refused'),
      );
      addTearDown(api.dispose);
      final upload = request('/uploads', 'document');
      await handle(api, upload, principal: 'phone');
      final id =
          jsonDecode(upload.response.body.toString())['uploadId'] as String;
      final limit = DateTime.now().add(const Duration(seconds: 3));
      while (await directory.exists() && DateTime.now().isBefore(limit)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(await directory.exists(), isFalse);
      final job = request('/jobs', {
        'requestId': 'expired',
        'uploads': [
          {'uploadId': id, 'message': 0},
        ],
      });
      await handle(api, job, principal: 'phone');
      expect(job.response.statusCode, HttpStatus.notFound);
    },
  );

  test('a job body that arrives after revocation is refused', () async {
    final api = WorkspaceApi(
      capabilities: const [],
      run: (job, input) async {},
    );
    addTearDown(api.dispose);
    final payload = utf8.encode('{"requestId":"after-revoke"}');
    final body = StreamController<Uint8List>();
    final request = _Request(body.stream, payload.length, '/jobs');
    final handling = handle(api, request, principal: 'phone');
    // The device is unpaired while its body is still in flight.
    await api.revokePrincipal('phone');
    body.add(Uint8List.fromList(payload));
    await body.close();
    await handling;
    expect(request.response.statusCode, 409);
    expect(request.response.body.toString(), contains('disconnected'));
  });
}
