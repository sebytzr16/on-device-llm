import 'dart:async';
import '../../core/storage/device_encryption.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

/// Reusable attachment vectors, isolated by model, chunking revision and
/// owner. Cache failures must never prevent reading a document (owner,
/// 2026-11-01).
class DocumentEmbeddingCache {
  DocumentEmbeddingCache({
    Future<Directory> Function()? directory,
    this.memoryBytes = 8 * 1024 * 1024,
    this.diskBytes = 64 * 1024 * 1024,
    this.persist = true,
    DeviceEncryption? encryption,
  }) : directory = directory ?? _directory,
       encryption = encryption ?? DeviceEncryption.instance;

  /// Vectors for work that must leave nothing on disk (temporary chats,
  /// hosted jobs): computed vectors live in memory until the process exits.
  DocumentEmbeddingCache.memoryOnly({this.memoryBytes = 8 * 1024 * 1024})
    : directory = _directory,
      diskBytes = 0,
      persist = false,
      encryption = DeviceEncryption.instance;

  final Future<Directory> Function() directory;
  final int memoryBytes, diskBytes;

  /// Whether vectors may be read from and written to the disk cache.
  final bool persist;
  final DeviceEncryption encryption;
  final _memory = <String, List<Float32List>>{};
  final _pending = <String, Future<List<Float32List>?>>{};
  Future<void> _writes = Future.value();
  static final _log = Logger('vectors');

  static Future<Directory> _directory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/document_embeddings',
  );

  /// Owner tag of a chat's attachment vectors, so deleting that chat removes
  /// exactly its own entries (audit S14/S15).
  static String chatOwner(String chatId) => 'chat:$chatId';

  static String _ownerTag(String owner) =>
      sha256.convert(utf8.encode(owner)).toString().substring(0, 16);

  static String _fileName(String key) => '${key.replaceAll(':', '-')}.json';

  Future<List<Float32List>?> vectors(
    String modelId,
    List<String> chunks,
    Future<List<Float32List>?> Function() compute, {
    String owner = '',
  }) async {
    final key =
        '${_ownerTag(owner)}:'
        '${sha256.convert(utf8.encode(jsonEncode(['attachment-chunks-v1', modelId, chunks]))).toString()}';
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
    if (!persist) {
      final vectors = await compute();
      if (vectors == null || !_valid(vectors, count)) return null;
      _remember(key, vectors);
      return vectors;
    }
    File? file;
    try {
      file = File(p.join((await directory()).path, _fileName(key)));
      if (await file.exists() && await file.length() <= diskBytes) {
        final data =
            jsonDecode(utf8.decode(await encryption.read(file))) as List;
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
    } on EncryptionRecovery {
      // A locked cache must never be recomputed over its original bytes.
      final vectors = await compute();
      return vectors != null && _valid(vectors, count) ? vectors : null;
    } catch (e, st) {
      quietFailure('document_embedding_cache:109', e, st);
    }
    final vectors = await compute();
    if (vectors == null || !_valid(vectors, count)) return null;
    _remember(key, vectors);
    if (file != null) {
      final target = file;
      // Serialize eviction and writes so concurrent files respect the cap.
      _writes = _writes.then((_) async {
        try {
          final bytes = utf8.encode(jsonEncode(vectors));
          final storedSize =
              bytes.length + (await encryption.enabled() ? 44 : 0);
          if (storedSize > diskBytes) return;
          await target.parent.create(recursive: true);
          final entries = <({File file, FileStat stat})>[];
          await for (final entry in target.parent.list()) {
            if (entry is File && entry.path.endsWith('.json')) {
              entries.add((file: entry, stat: await entry.stat()));
            }
          }
          await encryption.checkWritable();
          // Validate the entire eviction set before removing any entry.
          for (final entry in entries) {
            await encryption.read(entry.file);
          }
          entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
          // Commit the new envelope before eviction: a late vault/write
          // failure must not remove any existing cached data.
          await encryption.write(target, bytes);
          var size =
              storedSize +
              entries.fold<int>(
                0,
                (n, e) => n + (e.file.path == target.path ? 0 : e.stat.size),
              );
          for (final entry in entries) {
            if (size <= diskBytes) break;
            if (entry.file.path == target.path) continue;
            await entry.file.delete();
            size -= entry.stat.size;
          }
        } catch (e, st) {
          quietFailure('document_embedding_cache:138', e, st);
        }
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

  /// Removes every stored vector of [owner] from memory and, when this cache
  /// writes to disk, from its directory. Only that owner's entries go: another
  /// chat's vectors of the same text can still reuse its own copy (S14/S15).
  Future<void> deleteOwner(String owner) async {
    final tag = _ownerTag(owner);
    _memory.removeWhere((key, _) => key.startsWith('$tag:'));
    if (!persist) return;
    _writes = _writes.then((_) async {
      try {
        final dir = await directory();
        if (!await dir.exists()) return;
        await for (final entry in dir.list(followLinks: false)) {
          if (entry is! File) continue;
          if (!p.basename(entry.path).startsWith('$tag-')) continue;
          await entry.delete();
        }
      } on Exception catch (error, stack) {
        // Kept for the next deletion or budget eviction; never fatal here.
        _log.warning('Could not remove cached vectors', error, stack);
      }
    });
    await _writes;
  }
}
