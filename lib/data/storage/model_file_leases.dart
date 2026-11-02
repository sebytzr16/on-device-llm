import 'dart:io';

import 'package:path/path.dart' as p;

/// Process-wide ownership of model files. Acquire before starting a load and
/// retain the lease until the runtime has finished unloading.
class ModelFileLeases {
  static final instance = ModelFileLeases();
  final _holders = <String, Map<Object, String>>{};
  final _mutations = <String>{};
  final _directories = <String>{};

  bool _blocked(String key) =>
      _mutations.contains(key) ||
      _directories.any((dir) => dir == key || p.isWithin(dir, key));

  String _key(String path) {
    var key = p.normalize(p.absolute(path));
    if (FileSystemEntity.typeSync(key) != FileSystemEntityType.notFound) {
      key = File(key).resolveSymbolicLinksSync();
    }
    return Platform.isWindows ? key.toLowerCase() : key;
  }

  ModelFileLease acquire(Iterable<String> paths, {required String owner}) {
    final keys = paths.map(_key).toSet();
    if (keys.any(_blocked)) {
      throw StateError('Model files are being moved or deleted.');
    }
    final token = Object();
    for (final key in keys) {
      (_holders[key] ??= {})[token] = owner;
    }
    return ModelFileLease._(() {
      for (final key in keys) {
        _holders[key]?.remove(token);
        if (_holders[key]?.isEmpty == true) _holders.remove(key);
      }
    });
  }

  Set<String> holders(Iterable<String> paths) => {
    for (final key in paths.map(_key)) ...?_holders[key]?.values,
  };

  /// A folder operation also excludes leases for files created during the move.
  ModelFileLease beginDirectoryMutation(Iterable<String> paths) {
    final dirs = paths.map(_key).toSet();
    bool contains(String key) =>
        dirs.any((dir) => dir == key || p.isWithin(dir, key));
    if (_holders.keys.any(contains) ||
        _mutations.any(contains) ||
        dirs.any(_blocked) ||
        _directories.any(contains)) {
      throw StateError('Model files are in use.');
    }
    _directories.addAll(dirs);
    return ModelFileLease._(() => _directories.removeAll(dirs));
  }

  /// Holds an exclusive guard across the entire asynchronous delete or move.
  /// New runtime leases fail until the caller releases this guard.
  ModelFileLease beginMutation(Iterable<String> paths, {String? busyMessage}) {
    final keys = paths.map(_key).toSet();
    final owners = holders(keys);
    if (owners.isNotEmpty || keys.any(_blocked)) {
      throw StateError(
        busyMessage ?? 'Model files are in use: ${owners.join(', ')}',
      );
    }
    _mutations.addAll(keys);
    return ModelFileLease._(() => _mutations.removeAll(keys));
  }
}

class ModelFileLease {
  void Function()? _release;
  ModelFileLease._(this._release);
  void release() {
    _release?.call();
    _release = null;
  }
}
