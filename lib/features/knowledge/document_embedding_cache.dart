import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Reusable attachment vectors, isolated by model and chunking revision.
/// Cache failures must never prevent reading a document (owner, 2026-11-01).
class DocumentEmbeddingCache {
  DocumentEmbeddingCache({
    Future<Directory> Function()? directory,
    this.memoryBytes = 8 * 1024 * 1024,
    this.diskBytes = 64 * 1024 * 1024,
  }) : directory = directory ?? _directory;

  final Future<Directory> Function() directory;
  final int memoryBytes, diskBytes;
  final _memory = <String, List<Float32List>>{};
  final _pending = <String, Future<List<Float32List>?>>{};
  Future<void> _writes = Future.value();

  static Future<Directory> _directory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/document_embeddings',
  );

  Future<List<Float32List>?> vectors(
    String modelId,
    List<String> chunks,
    Future<List<Float32List>?> Function() compute,
  ) async {
    final key = sha256
        .convert(
          utf8.encode(jsonEncode(['attachment-chunks-v1', modelId, chunks])),
        )
        .toString();
    final hit = _memory.remove(key);
    if (hit != null) return _memory[key] = hit;
    if (_pending[key] case final pending?) return pending;
    final work = _readOrCompute(key, chunks.length, compute);
    _pending[key] = work;
    try {
      return await work;
    } finally {
      unawaited(_pending.remove(key));
    }
  }

  bool _valid(List<Float32List> vectors, int count) =>
      vectors.length == count &&
      vectors.isNotEmpty &&
      vectors.first.isNotEmpty &&
      vectors.every(
        (v) => v.length == vectors.first.length && v.every((n) => n.isFinite),
      );

  Future<List<Float32List>?> _readOrCompute(
    String key,
    int count,
    Future<List<Float32List>?> Function() compute,
  ) async {
    File? file;
    try {
      file = File('${(await directory()).path}/$key.json');
      if (await file.exists() && await file.length() <= diskBytes) {
        final data = jsonDecode(await file.readAsString()) as List;
        final vectors = [
          for (final row in data)
            Float32List.fromList(
              (row as List).cast<num>().map((n) => n.toDouble()).toList(),
            ),
        ];
        if (_valid(vectors, count)) {
          await file.setLastModified(DateTime.now());
          _remember(key, vectors);
          return vectors;
        }
      }
    } catch (_) {}
    final vectors = await compute();
    if (vectors == null || !_valid(vectors, count)) return null;
    _remember(key, vectors);
    if (file != null) {
      final target = file;
      // Serialize eviction and writes so concurrent files respect the cap.
      _writes = _writes.then((_) async {
        try {
          final bytes = utf8.encode(jsonEncode(vectors));
          if (bytes.length > diskBytes) return;
          await target.parent.create(recursive: true);
          final entries = <({File file, FileStat stat})>[];
          await for (final entry in target.parent.list()) {
            if (entry is File && entry.path.endsWith('.json')) {
              entries.add((file: entry, stat: await entry.stat()));
            }
          }
          entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
          var size = entries.fold<int>(0, (n, e) => n + e.stat.size);
          for (final entry in entries) {
            if (size + bytes.length <= diskBytes) break;
            await entry.file.delete();
            size -= entry.stat.size;
          }
          final temporary = File('${target.path}.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          if (await target.exists()) await target.delete();
          await temporary.rename(target.path);
        } catch (_) {}
      });
      await _writes;
    }
    return vectors;
  }

  void _remember(String key, List<Float32List> vectors) {
    _memory[key] = vectors;
    int size() => _memory.values.fold(
      0,
      (n, rows) => n + rows.fold<int>(0, (n, row) => n + row.lengthInBytes),
    );
    while (_memory.isNotEmpty && size() > memoryBytes) {
      _memory.remove(_memory.keys.first);
    }
  }
}
