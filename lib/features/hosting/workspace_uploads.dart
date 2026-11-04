import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class WorkspaceUpload {
  final String id, name;
  final File file;
  WorkspaceUpload(this.id, this.name, this.file);
}

/// Raw bytes are uploaded once; clients never supply a server file path.
class WorkspaceUploads {
  static const maxFileBytes = 64 * 1024 * 1024;
  static const maxTotalBytes = 256 * 1024 * 1024;
  final _files = <String, WorkspaceUpload>{};
  int _bytes = 0;
  int _reserved = 0;

  WorkspaceUpload? operator [](String id) => _files[id];

  Future<void> release(String id) async {
    final upload = _files.remove(id);
    if (upload == null) return;
    if (await upload.file.exists()) {
      _bytes -= await upload.file.length();
      await upload.file.delete();
    }
    if (await upload.file.parent.exists()) await upload.file.parent.delete();
  }

  Future<WorkspaceUpload> receive(HttpRequest request) async {
    final size = request.contentLength;
    if (size < 1 || size > maxFileBytes) {
      throw const FormatException(
        'Uploads require a content length of 1 to 64 MiB.',
      );
    }
    if (_files.length + _reserved >= 64 || _bytes + size > maxTotalBytes) {
      throw StateError(
        'The server upload cache is full. Restart hosting after active jobs finish.',
      );
    }
    _bytes += size;
    _reserved++;
    final id = const Uuid().v4();
    final name = p.basename(request.uri.queryParameters['name'] ?? 'file');
    if (name.isEmpty || name.length > 240) {
      _bytes -= size;
      _reserved--;
      throw const FormatException(
        'The upload file name must contain 1 to 240 characters.',
      );
    }
    final directory = await Directory.systemTemp.createTemp(
      'ondevice-workspace-',
    );
    final file = File(p.join(directory.path, '$id${p.extension(name)}'));
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in request.timeout(const Duration(seconds: 60))) {
        received += chunk.length;
        if (received > size) {
          throw const FormatException('Upload exceeded its declared length.');
        }
        sink.add(chunk);
      }
      await sink.close();
      if (received != size) {
        throw const FormatException('Upload was incomplete.');
      }
      final upload = WorkspaceUpload(id, name, file);
      _files[id] = upload;
      return upload;
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      await directory.delete();
      _bytes -= size;
      rethrow;
    } finally {
      _reserved--;
    }
  }

  Future<void> dispose() async {
    for (final upload in _files.values) {
      if (await upload.file.exists()) await upload.file.delete();
      if (await upload.file.parent.exists()) await upload.file.parent.delete();
    }
    _files.clear();
    _bytes = 0;
  }
}
