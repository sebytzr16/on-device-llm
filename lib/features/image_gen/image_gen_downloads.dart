import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage/download_jobs.dart';
import '../../data/storage/download_manager.dart';
import '../../data/storage/model_storage.dart';
import '../../data/storage/model_file_leases.dart';
import 'domain/entities/image_gen_model.dart';

enum ImageGenModelStatus { missing, downloading, ready }

class ImageGenModelState {
  final ImageGenModelStatus status;

  /// Bytes received across the model's files while downloading.
  final int received;
  final String? error;
  const ImageGenModelState(this.status, {this.received = 0, this.error});
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
  bool _alive = true;
  Future<void> _maintenance = Future.value();

  DownloadManager get _dl => _downloader ??= DownloadManager();

  @override
  ImageGenDownloadsState build() {
    ref.onDispose(() {
      _alive = false;
      _downloader?.dispose();
    });
    unawaited(_refresh());
    return const ImageGenDownloadsState({});
  }

  void _set(ImageGenModel model, ImageGenModelState s) {
    if (!_alive) return;
    state = ImageGenDownloadsState({...state.models, model.id: s});
  }

  static Future<bool> isReady(ImageGenModel model) async {
    for (final f in model.files) {
      if (!await ModelStorage.exists(f.fileName)) return false;
    }
    return true;
  }

  /// Each component's path, for loading.
  static Future<Map<ImageGenRole, String>> paths(ImageGenModel model) async => {
    for (final f in model.files)
      f.role: (await ModelStorage.modelFile(f.fileName)).path,
  };

  Future<void> _refresh() async {
    Set<String> pending = const {};
    try {
      pending = await DownloadJobs.active();
    } catch (_) {}
    for (final model in [...imageGenCatalog, ...upscalerTools]) {
      if (_active.contains(model.id)) continue;
      bool ready;
      try {
        ready = await isReady(model);
      } catch (_) {
        ready = false; // no storage (tests)
      }
      if (ready) {
        _set(model, const ImageGenModelState(ImageGenModelStatus.ready));
      } else if (pending.contains(model.downloadKey)) {
        unawaited(download(model));
      } else {
        _set(model, const ImageGenModelState(ImageGenModelStatus.missing));
      }
    }
  }

  Future<void> download(ImageGenModel model) async {
    await _maintenance;
    if (!_alive) return;
    if (!_active.add(model.id)) return;
    var done = 0;
    _set(model, const ImageGenModelState(ImageGenModelStatus.downloading));
    try {
      await DownloadJobs.add(model.downloadKey);
      for (final f in model.files) {
        if (await ModelStorage.exists(f.fileName)) {
          done += f.sizeBytes;
          continue;
        }
        final key = '${model.downloadKey}:${f.fileName}';
        final sub = _dl.progressStream(key).listen((p) {
          _set(
            model,
            ImageGenModelState(
              ImageGenModelStatus.downloading,
              received: done + p.received,
            ),
          );
        });
        try {
          await _dl.download(
            modelId: key,
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
      await DownloadJobs.remove(model.downloadKey);
      _set(model, const ImageGenModelState(ImageGenModelStatus.ready));
    } catch (e) {
      final paused = e is DioException && CancelToken.isCancel(e);
      _set(
        model,
        ImageGenModelState(
          ImageGenModelStatus.missing,
          received: done,
          error: paused ? null : '$e',
        ),
      );
      if (paused) await DownloadJobs.remove(model.downloadKey);
    } finally {
      _active.remove(model.id);
    }
  }

  Future<void> pause(ImageGenModel model) async {
    for (final f in model.files) {
      await _dl.pause('${model.downloadKey}:${f.fileName}');
    }
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
    final catalog = [...imageGenCatalog, ...upscalerTools];
    final keep = <String>{};
    for (final model in catalog) {
      if (_active.contains(model.id) || await isReady(model)) {
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

  Future<void> delete(ImageGenModel model) => _maintain(() => _delete(model));

  Future<void> _delete(ImageGenModel model) async {
    await pause(model);
    await DownloadJobs.remove(model.downloadKey);
    // Quants of one model share the VAE and text encoder, and the picture
    // models share the upscaler with Upscale mode: keep a file another
    // installed model or active download still uses.
    final shared = {
      for (final other in [...imageGenCatalog, ...upscalerTools])
        if (other.id != model.id &&
            (_active.contains(other.id) || await isReady(other)))
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
    _set(model, const ImageGenModelState(ImageGenModelStatus.missing));
  }
}

final imageGenDownloadsProvider =
    NotifierProvider<ImageGenDownloadsNotifier, ImageGenDownloadsState>(
      ImageGenDownloadsNotifier.new,
    );
