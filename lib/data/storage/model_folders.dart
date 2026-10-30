import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

enum ModelFolderFailure { notWritable, insufficientSpace, conflict, busy }

class ModelFolderException implements Exception {
  final ModelFolderFailure reason;
  const ModelFolderException(this.reason);
}

/// Absolute catalog paths remain valid when a folder is left in place.
/// Older roots also resolve companion files, which are stored by filename.
class ModelFolders {
  final Directory defaultDirectory;
  final SharedPreferences preferences;
  final Future<int> Function(String path) availableBytes;
  static const _folderKey = 'desktop.modelsFolder';
  static const _rootsKey = 'desktop.previousModelFolders';

  ModelFolders(this.defaultDirectory, this.preferences, this.availableBytes);

  Directory get current =>
      Directory(preferences.getString(_folderKey) ?? defaultDirectory.path);

  List<String> get roots =>
      {current.path, ...?preferences.getStringList(_rootsKey)}.toList();

  Future<File> resolve(String name) async => File(await resolvePath(name));

  Future<String> resolvePath(String name) async {
    for (final root in roots) {
      final path = p.join(root, name);
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        return path;
      }
    }
    return p.join(current.path, name);
  }

  Future<void> change(
    Directory target, {
    required bool move,
    required Future<void> Function(Map<String, String>) updatePaths,
    void Function(double)? onProgress,
  }) async {
    target = Directory(p.normalize(p.absolute(target.path)));
    if (p.equals(target.path, p.normalize(p.absolute(current.path)))) return;
    final oldRoots = roots;
    for (final root in oldRoots) {
      if (p.isWithin(root, target.path) || p.isWithin(target.path, root)) {
        throw const ModelFolderException(ModelFolderFailure.conflict);
      }
    }
    try {
      await target.create(recursive: true);
      final probe = File(
        p.join(
          target.path,
          '.ondevice-write-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await probe.writeAsBytes([0], flush: true);
      await probe.delete();
    } on FileSystemException {
      throw const ModelFolderException(ModelFolderFailure.notWritable);
    }
    if (!move) {
      if (!await preferences.setStringList(_rootsKey, oldRoots) ||
          !await preferences.setString(_folderKey, target.path)) {
        throw const ModelFolderException(ModelFolderFailure.notWritable);
      }
      return;
    }
    final files = <File>[];
    for (final root in oldRoots) {
      final dir = Directory(root);
      if (p.equals(p.normalize(p.absolute(root)), target.path)) continue;
      if (!await dir.exists()) continue;
      await for (final entry in dir.list(recursive: true, followLinks: false)) {
        if (entry is File) files.add(entry);
      }
    }
    final destinations = <String, String>{};
    var bytes = 0;
    for (final file in files) {
      final root = oldRoots.firstWhere((r) => p.isWithin(r, file.path));
      final destination = p.join(
        target.path,
        p.relative(file.path, from: root),
      );
      if (destinations.containsValue(destination) ||
          await FileSystemEntity.type(destination) !=
              FileSystemEntityType.notFound) {
        throw const ModelFolderException(ModelFolderFailure.conflict);
      }
      destinations[file.path] = destination;
      bytes += await file.length();
    }
    if (await availableBytes(target.path) < bytes + 16 * 1024 * 1024) {
      throw const ModelFolderException(ModelFolderFailure.insufficientSpace);
    }
    final copied = <File>[];
    var pathsUpdated = false;
    Directory? staging;
    try {
      staging = await target.createTemp('.ondevice-move-');
      var done = 0;
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final temporary = File(p.join(staging.path, '$index'));
        final sink = temporary.openWrite();
        try {
          await sink.addStream(
            file.openRead().map((chunk) {
              done += chunk.length;
              onProgress?.call(bytes == 0 ? 1 : done / bytes);
              return chunk;
            }),
          );
          await sink.flush();
        } finally {
          await sink.close();
        }
        final destination = File(destinations[file.path]!);
        await destination.parent.create(recursive: true);
        // Recheck after a long copy; never replace another model.
        if (await destination.exists()) {
          throw const ModelFolderException(ModelFolderFailure.conflict);
        }
        copied.add(await temporary.rename(destination.path));
      }
      await updatePaths(destinations);
      pathsUpdated = true;
      if (!await preferences.setString(_folderKey, target.path)) {
        await updatePaths({
          for (final e in destinations.entries) e.value: e.key,
        });
        pathsUpdated = false;
        throw const ModelFolderException(ModelFolderFailure.notWritable);
      }
      await preferences.setStringList(_rootsKey, const []);
    } catch (error) {
      // A failed preference write must not remove files the committed catalog
      // can already reference. Originals are retained on every failure.
      if (!pathsUpdated) {
        for (final file in copied) {
          if (await file.exists()) await file.delete();
        }
      }
      if (error is FileSystemException) {
        // Windows ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL.
        throw ModelFolderException(
          [39, 112].contains(error.osError?.errorCode)
              ? ModelFolderFailure.insufficientSpace
              : ModelFolderFailure.notWritable,
        );
      }
      rethrow;
    } finally {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
    // Catalog and preference now point at verified copies. A locked source
    // can stay behind without compromising the new library.
    for (final file in files) {
      try {
        await file.delete();
      } on FileSystemException {
        // Loaded files are blocked by the caller; antivirus can still lock one.
      }
    }
    onProgress?.call(1);
  }
}
