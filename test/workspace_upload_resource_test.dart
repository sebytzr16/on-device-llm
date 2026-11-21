import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ondevice_llm/features/hosting/workspace_uploads.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';

/// An HttpRequest whose body is a plain stream, so a test can stall it.
class _UploadRequest extends Stream<Uint8List> implements HttpRequest {
  final Stream<Uint8List> _body;
  @override
  final int contentLength;
  @override
  final Uri uri;
  _UploadRequest(
    this._body,
    this.contentLength, {
    String name = 'file.bin',
    String? batch,
  }) : uri = Uri(queryParameters: {'name': name, 'batch': ?batch});

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
  test('a trickling upload is cut off at the total deadline', () async {
    final root = await Directory.systemTemp.createTemp('upload-deadline-');
    addTearDown(() => root.delete(recursive: true));
    var created = 0;
    final uploads = WorkspaceUploads(
      createDirectory: () async =>
          Directory(p.join(root.path, '${created++}'))..createSync(),
      receiveDeadline: const Duration(milliseconds: 100),
    );
    addTearDown(uploads.dispose);

    // Each stalled upload reserves a full 64 MiB of the 256 MiB cache; the
    // fifth is only accepted if every expired reservation was released.
    for (var attempt = 0; attempt < 5; attempt++) {
      final body = StreamController<Uint8List>();
      addTearDown(body.close);
      final upload = uploads.receive(
        _UploadRequest(body.stream, WorkspaceUploads.maxFileBytes),
      );
      body.add(Uint8List.fromList([1, 2]));
      await expectLater(upload, throwsA(isA<TimeoutException>()));
    }
    final done = await uploads.receive(
      _UploadRequest(Stream.value(Uint8List.fromList([1])), 1),
    );
    expect(await done.file.readAsBytes(), [1]);
  });

  test(
    'missing files release quota and failed removals keep it for retry',
    () async {
      final uploads = WorkspaceUploads(maxCacheBytes: 1);
      addTearDown(uploads.dispose);
      Future<WorkspaceUpload> receive() => uploads.receive(
        _UploadRequest(Stream.value(Uint8List.fromList([1])), 1),
      );
      final missing = await receive();
      await missing.file.delete();
      await uploads.release(missing.id);
      final blocked = await receive();
      await blocked.file.delete();
      final obstruction = await Directory(blocked.file.path).create();
      addTearDown(() async {
        if (await obstruction.exists()) await obstruction.delete();
      });
      await uploads.release(blocked.id);
      expect(uploads[blocked.id], isNull);
      await expectLater(receive(), throwsStateError);
      await obstruction.delete();
      await uploads.expireAbandoned();
      expect(await receive(), isA<WorkspaceUpload>());
    },
  );

  test('disk suffixes are selected independently of upload metadata', () async {
    final uploads = WorkspaceUploads();
    addTearDown(uploads.dispose);
    const name = 'notes.txt:metadata';
    final upload = await uploads.receive(
      _UploadRequest(Stream.value(Uint8List.fromList([1])), 1, name: name),
    );
    expect(upload.name, name);
    expect(p.basename(upload.file.path), '${upload.id}.bin');
    expect(AttachmentStore.safeDiskSuffix(name), '.bin');
    expect(AttachmentStore.safeDiskSuffix('notes.TXT'), '.txt');
  });

  test('uploads abandoned before submission expire with their quota', () async {
    final root = await Directory.systemTemp.createTemp('upload-expiry-');
    addTearDown(() => root.delete(recursive: true));
    var created = 0;
    final uploads = WorkspaceUploads(
      createDirectory: () async =>
          Directory(p.join(root.path, '${created++}'))..createSync(),
    );
    addTearDown(uploads.dispose);

    final abandoned = await uploads.receive(
      _UploadRequest(Stream.value(Uint8List.fromList([1])), 1),
    );
    final retained = await uploads.receive(
      _UploadRequest(Stream.value(Uint8List.fromList([1])), 1),
    );
    final file = abandoned.file;
    uploads.acquire(retained.id);

    expect(await uploads.expireAbandoned(maxAge: Duration.zero), 1);
    expect(uploads[abandoned.id], isNull);
    expect(await file.exists(), isFalse);
    // A job is still using the other upload: it must survive the sweep.
    expect(uploads[retained.id], isNotNull);
    await uploads.release(retained.id);
    expect(uploads[retained.id], isNull);
  });

  test(
    'only successful uploads in the same authenticated batch refresh expiry',
    () async {
      var now = DateTime.utc(2026);
      final uploads = WorkspaceUploads(clock: () => now, maxCacheBytes: 5);
      addTearDown(uploads.dispose);
      _UploadRequest file(String batch, [int size = 1]) => _UploadRequest(
        Stream.value(Uint8List.fromList([1])),
        size,
        batch: batch,
      );
      final active = await uploads.receive(file('active'), principal: 'alice');
      final idle = await uploads.receive(file('idle'), principal: 'alice');
      final other = await uploads.receive(file('active'), principal: 'bob');
      now = now.add(const Duration(minutes: 10));
      await uploads.receive(file('active'), principal: 'alice');
      await expectLater(
        uploads.receive(file('idle', 2), principal: 'alice'),
        throwsStateError,
      );
      await expectLater(
        uploads.receive(
          _UploadRequest(const Stream.empty(), 1, batch: 'idle'),
          principal: 'alice',
        ),
        throwsFormatException,
      );
      now = now.add(const Duration(minutes: 6));
      expect(await uploads.expireAbandoned(), 2);
      expect(uploads[active.id], isNotNull);
      expect(uploads[idle.id], isNull);
      expect(uploads[other.id], isNull);
    },
  );

  test('a batch that is still receiving survives its hard lifetime', () async {
    var now = DateTime.utc(2026);
    final root = await Directory.systemTemp.createTemp('upload-receiving-');
    addTearDown(() => root.delete(recursive: true));
    var created = 0;
    final uploads = WorkspaceUploads(
      clock: () => now,
      createDirectory: () async =>
          Directory(p.join(root.path, '${created++}'))..createSync(),
    );
    addTearDown(uploads.dispose);
    final first = await uploads.receive(
      _UploadRequest(Stream.value(Uint8List.fromList([1])), 1, batch: 'batch'),
      principal: 'alice',
    );
    final body = StreamController<Uint8List>();
    addTearDown(body.close);
    final pending = uploads.receive(
      _UploadRequest(body.stream, 1, batch: 'batch'),
      principal: 'alice',
    );
    // Wait until the transfer of that batch is counted as receiving.
    for (var i = 0; i < 100 && !body.hasListener; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(body.hasListener, isTrue);
    // The batch is now older than its hard lifetime but still receiving.
    now = now.add(const Duration(minutes: 61));
    expect(await uploads.expireAbandoned(), 0);
    expect(uploads[first.id], isNotNull);
    expect(await first.file.exists(), isTrue);
    body.add(Uint8List.fromList([1]));
    await body.close();
    await pending;
  });

  test('a batch-less upload expires on its own clock', () async {
    var now = DateTime.utc(2026);
    final uploads = WorkspaceUploads(clock: () => now);
    addTearDown(uploads.dispose);
    Future<WorkspaceUpload> receive() => uploads.receive(
      _UploadRequest(Stream.value(Uint8List.fromList([1])), 1),
      principal: 'alice',
    );
    final first = await receive();
    final second = await receive();
    now = now.add(const Duration(minutes: 10));
    final fresh = await receive();
    now = now.add(const Duration(minutes: 6));
    expect(await uploads.expireAbandoned(), 2);
    expect(uploads[first.id], isNull);
    expect(uploads[second.id], isNull);
    expect(uploads[fresh.id], isNotNull);
  });

  test('a batch-less re-inventoried upload expires cleanly', () async {
    final root = await Directory.systemTemp.createTemp('upload-orphan-');
    addTearDown(() => root.delete(recursive: true));
    final directory = await Directory(p.join(root.path, 'staged')).create();
    final file = File(p.join(directory.path, 'orphan.bin'))
      ..writeAsBytesSync([1]);
    final uploads = WorkspaceUploads();
    addTearDown(uploads.dispose);
    uploads.debugAdoptBatchless('orphan', file);
    expect(await uploads.expireAbandoned(maxAge: Duration.zero), 1);
    expect(uploads['orphan'], isNull);
    expect(file.existsSync(), isFalse);
  });

  test(
    'continuous activity cannot extend a batch past its hard lifetime',
    () async {
      var now = DateTime.utc(2026);
      final uploads = WorkspaceUploads(clock: () => now);
      addTearDown(uploads.dispose);
      Future<WorkspaceUpload> receive() => uploads.receive(
        _UploadRequest(
          Stream.value(Uint8List.fromList([1])),
          1,
          batch: 'active',
        ),
        principal: 'alice',
      );
      final first = await receive();
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(minutes: 10));
        await receive();
      }
      expect(uploads[first.id], isNotNull);
      now = now.add(const Duration(minutes: 10));
      expect(await uploads.expireAbandoned(), 6);
      expect(uploads[first.id], isNull);
    },
  );
}
