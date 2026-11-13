import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/storage/download_jobs.dart';
import '../../data/storage/download_history.dart';
import '../../core/l10n/l10n.dart';
import '../../data/storage/download_manager.dart';
import '../../data/storage/model_storage.dart';
import '../../data/storage/model_file_leases.dart';
import 'domain/entities/image_gen_model.dart';
import 'image_gen_imports.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

class _ImageDownloadPaused implements Exception {}

/// Injectable so pack lifecycle tests use the same notifier as production.
final imageGenDownloadManagerProvider = Provider<DownloadManager>(
  (ref) => DownloadManager(),
);

enum ImageGenModelStatus { missing, downloading, ready }

class ImageGenModelState {
  final ImageGenModelStatus status;

  /// Bytes received across the model's files while downloading.
  final int received;
  final String? error;
  final double? bytesPerSecond;
  final List<String> missingFiles;
  final int missingBytes;
  final bool paused;
  const ImageGenModelState(
    this.status, {
    this.received = 0,
    this.error,
    this.bytesPerSecond,
    this.missingFiles = const [],
    this.missingBytes = 0,
    this.paused = false,
  });
}

class ImageGenDownloadsState {
  final Map<String, ImageGenModelState> models;
  const ImageGenDownloadsState(this.models);
  ImageGenModelState of(ImageGenModel model) =>
      models[model.id] ?? const ImageGenModelState(ImageGenModelStatus.missing);
}

/// Downloads the files of the image and video models one after another,
/// like the voice packs: pinned, SHA-256 checked, resumed after a restart.
class ImageGenDownloadsNotifier extends Notifier<ImageGenDownloadsState> {
  DownloadManager? _downloader;
  final _active = <String>{};
  final _stopping = <String>{};
  final _finished = <String, Completer<void>>{};
  bool _alive = true;
  Future<void> _maintenance = Future.value();

  DownloadManager get _dl => _downloader ??= ref.read<DownloadManager>(
    imageGenDownloadManagerProvider,
  );

  @override
  ImageGenDownloadsState build() {
    ref.onDispose(() {
      _alive = false;
      _downloader?.dispose();
    });
    // Imported models are loaded from preferences after the first refresh:
    // refresh again when the list arrives or a user adds or removes one.
    ref.listen<List<ImageGenModel>>(imageGenImportsProvider, (previous, next) {
      if (_alive) unawaited(_refresh(resumePending: true));
    });
    unawaited(_refresh(resumePending: true));
    return const ImageGenDownloadsState({});
  }

  void _set(ImageGenModel model, ImageGenModelState s) {
    if (!_alive) return;
    state = ImageGenDownloadsState({...state.models, model.id: s});
  }

  /// Files already hashed, keyed by path, size and modification time:
  /// readiness re-checks stay cheap until a component is replaced. Matches
  /// are kept in preferences so ~20 GB of video components are not re-hashed
  /// on every launch.
  static final _verifiedHashes = <String, String>{};
  static Future<void>? _loaded;
  static const _prefsKey = 'imageGenVerifiedHashes';
  static const _maxRemembered = 200;

  static Future<void> _load() => _loaded ??= () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final row in prefs.getStringList(_prefsKey) ?? const <String>[]) {
        final at = row.lastIndexOf('=');
        if (at > 0) {
          _verifiedHashes[row.substring(0, at)] = row.substring(at + 1);
        }
      }
    } on Exception {
      // No stored marks: files are hashed again, which is only slower.
    }
  }();

  static Future<void> _remember(String key, String hash) async {
    _verifiedHashes.remove(key);
    _verifiedHashes[key] = hash;
    while (_verifiedHashes.length > _maxRemembered) {
      _verifiedHashes.remove(_verifiedHashes.keys.first);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, [
        for (final e in _verifiedHashes.entries) '${e.key}=${e.value}',
      ]);
    } on Exception {
      // Kept in memory for this session.
    }
  }

  static Future<bool> isReady(ImageGenModel model) async {
    model = resolveImageGenCompanions(model);
    if (imageGenNeedsCompanions(model)) return false;
    for (final f in model.files) {
      final file = await ModelStorage.modelFile(f.fileName);
      if (!await _verified(file: file, f: f)) return false;
    }
    return true;
  }

  /// Size is cheap; the SHA-256 is checked once per path/size/mtime so a
  /// truncated or replaced component is not reported as ready.
  static Future<bool> _verified({
    required File file,
    required ImageGenComponent f,
  }) async {
    if (!await file.exists()) return false;
    final stat = await file.stat();
    if (stat.size != f.sizeBytes) return false;
    if (f.sha256.isEmpty) return true;
    final mark =
        '${file.path}|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
    final expected = f.sha256.toLowerCase();
    await _load();
    final cached = _verifiedHashes[mark];
    if (cached != null) return cached == expected;
    String hash;
    try {
      hash = (await ModelStorage.validateAndHash(file.path)).toLowerCase();
    } on Exception {
      // Unreadable or not a valid GGUF: not ready, like a checksum mismatch.
      return false;
    }
    // Only matches are stored: a bad file is re-checked after a repair.
    if (hash == expected) await _remember(mark, hash);
    return hash == expected;
  }

  // Retention is independent of readiness: truncated components still belong
  // to a variant and must not lose their shared files during maintenance.
  static Future<bool> _hasFiles(ImageGenModel model) async {
    if (model.imported && await _hasPrimary(model)) return true;
    for (final f in model.files) {
      if (!await ModelStorage.exists(f.fileName)) return false;
    }
    return true;
  }

  static Future<bool> _hasPrimary(ImageGenModel model) async {
    final primary =
        model.file(ImageGenRole.diffusion) ?? model.file(ImageGenRole.upscaler);
    if (primary == null) return false;
    final file = await ModelStorage.modelFile(primary.fileName);
    return await file.exists() || await File('${file.path}.part').exists();
  }

  /// Each component's path, for loading.
  static Future<Map<ImageGenRole, String>> paths(ImageGenModel model) async {
    model = resolveImageGenCompanions(model);
    if (imageGenNeedsCompanions(model)) {
      throw StateError(appStrings.imageCompanionsUnknown);
    }
    final missing = <String>[];
    final paths = <ImageGenRole, String>{};
    // Presence only: readiness (size + hash) is the download badge's job, and
    // the engine reports a damaged file itself.
    for (final f in model.files) {
      final file = await ModelStorage.modelFile(f.fileName);
      if (!file.existsSync()) missing.add(f.fileName);
      paths[f.role] = file.path;
    }
    if (missing.isNotEmpty) {
      throw StateError(appStrings.imageMissingFiles(missing.join(', ')));
    }
    return paths;
  }

  Future<void> refresh() => _refresh();

  Future<ImageGenModelState> _missingState(
    ImageGenModel model, {
    bool paused = false,
    String? error,
  }) async {
    var received = 0, missingBytes = 0;
    final missing = <String>[];
    for (final f in model.files) {
      final file = await ModelStorage.modelFile(f.fileName);
      if (await _verified(file: file, f: f)) {
        received += f.sizeBytes;
      } else {
        missing.add(f.fileName);
        final part = File('${file.path}.part');
        final count = await part.exists()
            ? (await part.length()).clamp(0, f.sizeBytes)
            : 0;
        received += count;
        missingBytes += f.sizeBytes - count;
      }
    }
    return ImageGenModelState(
      ImageGenModelStatus.missing,
      received: received,
      missingFiles: missing,
      missingBytes: missingBytes,
      paused: paused,
      error: error,
    );
  }

  Future<void> _refresh({bool resumePending = false}) async {
    if (!_alive) return;
    Set<String> pending = const {};
    List<DownloadRecord> history = const [];
    try {
      pending = await DownloadJobs.active();
      history = await DownloadHistory.read();
    } catch (e, st) {
      quietFailure('image_gen_downloads:83', e, st);
    }
    if (!_alive) return;
    for (final model in imageGenManagedModels(
      ref.read(imageGenImportsProvider),
    )) {
      if (!_alive) return;
      if (_active.contains(model.id)) continue;
      bool ready;
      try {
        ready = await isReady(model);
      } catch (_) {
        ready = false; // no storage (tests)
      }
      if (!_alive) return;
      if (_active.contains(model.id)) continue;
      if (ready) {
        _set(model, const ImageGenModelState(ImageGenModelStatus.ready));
      } else if (resumePending && pending.contains(model.downloadKey)) {
        unawaited(download(model));
      } else {
        try {
          final missing = await _missingState(model);
          final latest = history
              .where((row) => row.modelId.startsWith('${model.downloadKey}:'))
              .firstOrNull;
          final resumable =
              latest?.result != 'cancelled' &&
              (state.of(model).paused ||
                  latest?.result == 'paused' ||
                  missing.received > 0 && await _hasPrimary(model));
          if (!_active.contains(model.id)) {
            _set(
              model,
              ImageGenModelState(
                ImageGenModelStatus.missing,
                received: missing.received,
                missingFiles: missing.missingFiles,
                missingBytes: missing.missingBytes,
                paused: resumable,
                error: imageGenNeedsCompanions(model)
                    ? appStrings.imageCompanionsUnknown
                    : null,
              ),
            );
          }
        } catch (_) {
          _set(model, const ImageGenModelState(ImageGenModelStatus.missing));
        }
      }
    }
  }

  Future<void> download(ImageGenModel model) async {
    model = resolveImageGenCompanions(model);
    if (imageGenNeedsCompanions(model)) {
      _set(
        model,
        ImageGenModelState(
          ImageGenModelStatus.missing,
          error: appStrings.imageCompanionsUnknown,
        ),
      );
      return;
    }
    await _maintenance;
    if (!_alive) return;
    if (!_active.add(model.id)) return;
    _stopping.remove(model.id);
    final finished = Completer<void>();
    _finished[model.id] = finished;
    var done = 0;
    _set(model, const ImageGenModelState(ImageGenModelStatus.downloading));
    try {
      await DownloadJobs.add(model.downloadKey);
      for (final f in model.files) {
        if (!_alive || _stopping.contains(model.id)) {
          throw _ImageDownloadPaused();
        }
        final file = await ModelStorage.modelFile(f.fileName);
        if (await _verified(file: file, f: f)) {
          done += f.sizeBytes;
          continue;
        }
        // A mismatched existing file is left for the downloader to refuse:
        // ready is only reported after its own size/SHA verification.
        if (!_alive || _stopping.contains(model.id)) {
          throw _ImageDownloadPaused();
        }
        final jobId = '${model.downloadKey}:${f.fileName}';
        final sub = _dl.progressStream(jobId).listen((p) {
          _set(
            model,
            ImageGenModelState(
              ImageGenModelStatus.downloading,
              received: done + p.received,
              bytesPerSecond: p.bytesPerSecond,
            ),
          );
        });
        try {
          await _dl.download(
            modelId: jobId,
            url: f.url,
            fileName: f.fileName,
            expectedSha256: f.sha256,
            expectedSize: f.sizeBytes,
          );
        } finally {
          await sub.cancel();
        }
        done += f.sizeBytes;
      }
      if (!_alive || _stopping.contains(model.id)) throw _ImageDownloadPaused();
      await DownloadJobs.remove(model.downloadKey);
      _set(model, const ImageGenModelState(ImageGenModelStatus.ready));
      unawaited(_refresh());
    } catch (e) {
      final paused =
          e is _ImageDownloadPaused ||
          e is DioException && CancelToken.isCancel(e);
      _set(
        model,
        await _missingState(model, paused: paused, error: paused ? null : '$e'),
      );
      if (paused) await DownloadJobs.remove(model.downloadKey);
    } finally {
      _active.remove(model.id);
      _stopping.remove(model.id);
      _finished.remove(model.id);
      finished.complete();
    }
  }

  Future<void> pause(ImageGenModel model) async {
    model = resolveImageGenCompanions(model);
    _stopping.add(model.id);
    final finished = _finished[model.id]?.future;
    for (final f in model.files) {
      await _dl.pause('${model.downloadKey}:${f.fileName}');
    }
    if (finished != null) await finished;
    _stopping.remove(model.id);
  }

  Future<void> cancel(ImageGenModel model) async {
    model = resolveImageGenCompanions(model);
    await pause(model);
    await DownloadJobs.remove(model.downloadKey);
    for (final f in model.files) {
      await ModelStorage.deletePartial(f.fileName);
      await DownloadHistory.cancelled('${model.downloadKey}:${f.fileName}');
    }
    _set(model, await _missingState(model));
  }

  /// Removes orphaned catalog components, keeping installed models and every
  /// active download. File leases still protect loaded runtimes.
  Future<void> _maintain(Future<void> Function() action) {
    final operation = _maintenance.then((_) => action());
    _maintenance = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> removeUnusedParts() => _maintain(_removeUnusedParts);

  Future<void> _removeUnusedParts() async {
    await ref.read(imageGenImportsProvider.notifier).ready;
    final catalog = imageGenManagedModels(ref.read(imageGenImportsProvider));
    final keep = <String>{};
    for (final model in catalog) {
      if (_active.contains(model.id) || await _hasFiles(model)) {
        keep.addAll(model.files.map((f) => f.fileName));
      }
    }
    final unused = {
      for (final model in catalog)
        for (final file in model.files)
          if (!keep.contains(file.fileName)) file.fileName,
    };
    final paths = [
      for (final name in unused) (await ModelStorage.modelFile(name)).path,
    ];
    final guard = ModelFileLeases.instance.beginMutation(paths);
    try {
      for (final name in unused) {
        await ModelStorage.delete(name);
        await ModelStorage.deletePartial(name);
      }
    } finally {
      guard.release();
    }
  }

  Future<void> delete(ImageGenModel model) => _maintain(() async {
    await _delete(model);
    // The files are gone: forget an imported model so it leaves Create too.
    if (model.imported) {
      await ref.read(imageGenImportsProvider.notifier).remove(model.id);
    }
  });

  Future<void> _delete(ImageGenModel model) async {
    model = resolveImageGenCompanions(model);
    await ref.read(imageGenImportsProvider.notifier).ready;
    await pause(model);
    await DownloadJobs.remove(model.downloadKey);
    // Quants of one model share the VAE and text encoder, and the picture
    // models share the upscaler with Upscale mode: keep a file another
    // installed model or active download still uses.
    final shared = {
      for (final other in imageGenManagedModels(
        ref.read(imageGenImportsProvider),
      ))
        if (other.id != model.id &&
            (_active.contains(other.id) || await _hasFiles(other)))
          ...other.files.map((f) => f.fileName),
    };
    final paths = [
      for (final f in model.files)
        (await ModelStorage.modelFile(f.fileName)).path,
    ];
    final guard = ModelFileLeases.instance.beginMutation(paths);
    try {
      for (final f in model.files) {
        if (shared.contains(f.fileName)) continue;
        await ModelStorage.delete(f.fileName);
        await ModelStorage.deletePartial(f.fileName);
      }
    } finally {
      guard.release();
    }
    _set(model, await _missingState(model));
  }
}

final imageGenDownloadsProvider =
    NotifierProvider<ImageGenDownloadsNotifier, ImageGenDownloadsState>(
      ImageGenDownloadsNotifier.new,
    );
