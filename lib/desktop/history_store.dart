import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/local/database/app_database.dart';

/// Immutable snapshot; ids and file names are generated locally, never prompts.
class HistoryEntry {
  final String id;
  final DateTime createdAt;
  final Map<String, dynamic> data;
  HistoryEntry({
    String? id,
    DateTime? createdAt,
    required Map<String, dynamic> data,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       data = Map.unmodifiable(data);

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'data': data,
  };
  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    data: Map<String, dynamic>.from(json['data'] as Map),
  );
}

class CreationHistoryStore {
  final Directory directory;
  final int cap;
  Future<void> _pending = Future.value();
  CreationHistoryStore(this.directory, {this.cap = 300}) : assert(cap > 0);

  File media(HistoryEntry entry) => File(
    p.join(
      directory.path,
      '${entry.id}.${entry.data['kind'] == 'video' ? 'avi' : 'png'}',
    ),
  );
  File thumbnail(HistoryEntry entry) =>
      File(p.join(directory.path, '${entry.id}.thumb.png'));
  File _sidecar(HistoryEntry entry) =>
      File(p.join(directory.path, '${entry.id}.json'));

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<List<HistoryEntry>> _list() async {
    if (!await directory.exists()) return [];
    final entries = <HistoryEntry>[];
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        final entry = HistoryEntry.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
        // Sidecars cannot redirect access outside the private directory.
        if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(entry.id)) continue;
        if (await media(entry).exists()) entries.add(entry);
      } on FormatException {
        // An interrupted or damaged sidecar must not hide other creations.
      } on TypeError {
        // Ignore invalid metadata from an older/corrupt file.
      }
    }
    entries.sort((a, b) {
      final order = b.createdAt.compareTo(a.createdAt);
      return order != 0 ? order : b.id.compareTo(a.id);
    });
    return entries;
  }

  Future<List<HistoryEntry>> list() => _serial(_list);

  /// The writer saves video directly from the worker before it can be released.
  Future<void> save(
    HistoryEntry entry, {
    required Future<void> Function(String path) writeMedia,
    required List<int> thumbnailPng,
  }) => _serial(() async {
    await directory.create(recursive: true);
    try {
      await writeMedia(media(entry).path);
      await thumbnail(entry).writeAsBytes(thumbnailPng, flush: true);
      final temporary = File('${_sidecar(entry).path}.tmp');
      await temporary.writeAsString(jsonEncode(entry.toJson()), flush: true);
      await temporary.rename(_sidecar(entry).path);
    } catch (_) {
      await _delete(entry);
      rethrow;
    }
    final entries = await _list();
    for (final old in entries.skip(cap)) {
      await _delete(old);
    }
  });

  Future<void> _delete(HistoryEntry entry) async {
    for (final file in [
      media(entry),
      thumbnail(entry),
      _sidecar(entry),
      File('${_sidecar(entry).path}.tmp'),
    ]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> delete(HistoryEntry entry) => _serial(() => _delete(entry));
  Future<int> sizeBytes() => _serial(() async {
    var bytes = 0;
    if (await directory.exists()) {
      await for (final file in directory.list()) {
        if (file is File) bytes += await file.length();
      }
    }
    return bytes;
  });
}

class CompareHistoryStore {
  final AppDatabase database;
  final int cap;
  CompareHistoryStore(this.database, {this.cap = 200}) : assert(cap > 0);

  Future<void> save(HistoryEntry entry) => database.transaction(() async {
    await database.customStatement(
      'INSERT OR REPLACE INTO compare_history (id, created_at, payload) VALUES (?, ?, ?)',
      [
        entry.id,
        entry.createdAt.microsecondsSinceEpoch,
        jsonEncode(entry.toJson()),
      ],
    );
    await database.customStatement(
      'DELETE FROM compare_history WHERE id NOT IN '
      '(SELECT id FROM compare_history ORDER BY created_at DESC, id DESC LIMIT ?)',
      [cap],
    );
  });
  Future<List<HistoryEntry>> list() async {
    final out = <HistoryEntry>[];
    for (final row in await _rows()) {
      try {
        out.add(_decode(row));
      } on FormatException {
        // An interrupted or damaged payload must not hide the other results.
      } on TypeError {
        // Ignore invalid metadata from an older/corrupt row.
      }
    }
    return out;
  }

  /// Payload rows that cannot be decoded, newest first: an interrupted
  /// write or a damaged database. [list] skips them, so one bad row no
  /// longer hides every valid comparison; the page offers to remove them.
  Future<List<String>> damagedIds() async {
    final out = <String>[];
    for (final row in await _rows()) {
      try {
        _decode(row);
      } on FormatException {
        out.add(row.read<String>('id'));
      } on TypeError {
        out.add(row.read<String>('id'));
      }
    }
    return out;
  }

  /// Removes the rows whose payload cannot be decoded and says how many
  /// went, leaving every readable comparison in place.
  Future<int> repair() async {
    final ids = await damagedIds();
    for (final id in ids) {
      await database.customStatement(
        'DELETE FROM compare_history WHERE id = ?',
        [id],
      );
    }
    return ids.length;
  }

  Future<List<QueryRow>> _rows() => database
      .customSelect(
        'SELECT id, payload FROM compare_history '
        'ORDER BY created_at DESC, id DESC',
      )
      .get();

  static HistoryEntry _decode(QueryRow row) => HistoryEntry.fromJson(
    jsonDecode(row.read<String>('payload')) as Map<String, dynamic>,
  );

  Future<void> delete(String id) => database.customStatement(
    'DELETE FROM compare_history WHERE id = ?',
    [id],
  );
  Future<void> clear() =>
      database.customStatement('DELETE FROM compare_history');
}

final creationHistoryStoreProvider = FutureProvider<CreationHistoryStore>((
  ref,
) async {
  final support = await getApplicationSupportDirectory();
  return CreationHistoryStore(Directory(p.join(support.path, 'creations')));
});
final creationHistoryProvider = FutureProvider<List<HistoryEntry>>(
  (ref) async => (await ref.watch(creationHistoryStoreProvider.future)).list(),
);
final creationHistorySizeProvider = FutureProvider<int>((ref) async {
  await ref.watch(creationHistoryProvider.future);
  return (await ref.watch(creationHistoryStoreProvider.future)).sizeBytes();
});
final compareHistoryStoreProvider = Provider<CompareHistoryStore>(
  (ref) => CompareHistoryStore(ref.watch(appDatabaseProvider)),
);
final compareHistoryProvider = FutureProvider<List<HistoryEntry>>(
  (ref) => ref.watch(compareHistoryStoreProvider).list(),
);

/// Saved comparisons whose payload cannot be read. [CompareHistoryStore.list]
/// hides them, so the count only exists to offer the user a remove action.
final compareHistoryDamagedProvider = FutureProvider<int>(
  (ref) async => (await ref.watch(
    compareHistoryStoreProvider,
  )).damagedIds().then((ids) => ids.length),
);
