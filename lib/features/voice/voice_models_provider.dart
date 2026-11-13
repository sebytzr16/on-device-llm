import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage/download_jobs.dart';
import '../../data/storage/download_manager.dart';
import '../../data/storage/model_storage.dart';
import 'voice_models.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

/// Install state of one voice pack.
enum VoicePackStatus { missing, downloading, unpacking, ready }

class VoicePackState {
  final VoicePackStatus status;

  /// Bytes received across the pack's files while downloading.
  final int received;
  final String? error;

  /// Ready from the older Supertonic 2 folder: speaking works, but the
  /// current Supertonic 3 pack can still be downloaded.
  final bool legacy;
  const VoicePackState(
    this.status, {
    this.received = 0,
    this.error,
    this.legacy = false,
  });
}

class VoiceModelsState {
  final Map<String, VoicePackState> packs;
  const VoiceModelsState(this.packs);
  VoicePackState of(VoicePack pack) =>
      packs[pack.id] ?? const VoicePackState(VoicePackStatus.missing);
  bool get canListen =>
      of(VoiceModels.listening).status == VoicePackStatus.ready ||
      of(VoiceModels.parakeetUltra).status == VoicePackStatus.ready ||
      of(VoiceModels.parakeet).status == VoicePackStatus.ready;
  bool get canSpeak => canSpeakWith('kokoro');
  bool canSpeakWith(String preferred) =>
      of(VoiceModels.speakingPack(preferred)).status == VoicePackStatus.ready;
}

/// Downloads, unpacks and removes the on-device voice (Whisper + VAD,
/// Kokoro). Files are pinned and SHA-256 checked like models; an interrupted
/// download resumes when the app starts again.
class VoiceModelsNotifier extends Notifier<VoiceModelsState> {
  DownloadManager? _downloader;
  final _active = <String>{};
  bool _alive = true;
  int _batchEpoch = 0;
  final _packEpochs = <String, int>{};

  /// Download a selection until the user pauses any pack in the batch.
  Future<void> downloadAll(Iterable<VoicePack> packs) async {
    final epoch = ++_batchEpoch;
    for (final pack in packs) {
      if (!_alive || epoch != _batchEpoch) return;
      await download(pack);
    }
  }

  DownloadManager get _dl => _downloader ??= DownloadManager();

  @override
  VoiceModelsState build() {
    ref.onDispose(() {
      _alive = false;
      _downloader?.dispose();
    });
    unawaited(_refresh(resume: true));
    return const VoiceModelsState({});
  }

  void _set(VoicePack pack, VoicePackState s) {
    if (!_alive) return;
    state = VoiceModelsState({...state.packs, pack.id: s});
  }

  Future<void> _refresh({bool resume = false}) async {
    Set<String> pending = const {};
    if (resume) {
      try {
        pending = await DownloadJobs.active();
      } catch (e, st) {
        quietFailure('voice_models_provider:77', e, st);
      }
    }
    for (final pack in VoiceModels.all) {
      // Re-check after the await: a download may have started for this pack.
      if (_active.contains(pack.id)) continue;
      bool ready;
      try {
        ready = await VoiceModels.isReady(pack);
      } catch (_) {
        ready = false; // no storage (tests, web)
      }
      if (!_alive) return;
      if (_active.contains(pack.id)) continue;
      // Supertonic 2's folder still speaks until Supertonic 3 is
      // downloaded, but the download row keeps offering the new pack.
      var legacy = false;
      if (!ready) {
        try {
          legacy = await VoiceModels.isLegacyReady(pack);
        } catch (_) {
          legacy = false; // no storage (tests, web)
        }
        if (!_alive) return;
        if (_active.contains(pack.id)) continue;
      }
      if (ready || legacy) {
        _set(pack, VoicePackState(VoicePackStatus.ready, legacy: legacy));
        // An interrupted Supertonic 3 download still resumes: the older
        // folder only stands in until it is in.
        if (!ready && pending.contains(pack.downloadKey)) {
          unawaited(download(pack));
        }
      } else if (pending.contains(pack.downloadKey)) {
        unawaited(download(pack));
      } else {
        _set(pack, const VoicePackState(VoicePackStatus.missing));
      }
    }
  }

  Future<void> download(VoicePack pack) async {
    if (!_active.add(pack.id)) return;
    final epoch = _packEpochs[pack.id] ?? 0;
    void check() {
      if (!_alive || epoch != (_packEpochs[pack.id] ?? 0)) {
        throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.cancel,
        );
      }
    }

    var done = 0;
    _set(pack, const VoicePackState(VoicePackStatus.downloading));
    try {
      await DownloadJobs.add(pack.downloadKey);
      for (final f in pack.files) {
        check();
        final exists = await ModelStorage.exists(f.fileName);
        check();
        if (exists) {
          done += f.sizeBytes;
          continue;
        }
        final key = '${pack.downloadKey}:${f.fileName}';
        final sub = _dl.progressStream(key).listen((p) {
          _set(
            pack,
            VoicePackState(
              VoicePackStatus.downloading,
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
      check();
      if (pack.unpackTo != null) {
        _set(pack, const VoicePackState(VoicePackStatus.unpacking));
        await VoiceModels.unpack(pack);
        // Re-check epoch after unpack completes.
        check();
      }
      await DownloadJobs.remove(pack.downloadKey);
      check();
      _set(pack, const VoicePackState(VoicePackStatus.ready));
    } catch (e) {
      final paused = e is DioException && CancelToken.isCancel(e);
      // The older Supertonic 2 folder still speaks while the new pack is
      // not in.
      var legacy = false;
      try {
        legacy = await VoiceModels.isLegacyReady(pack);
      } catch (_) {
        legacy = false; // no storage (tests, web)
      }
      _set(
        pack,
        VoicePackState(
          legacy ? VoicePackStatus.ready : VoicePackStatus.missing,
          received: done,
          error: paused ? null : '$e',
          legacy: legacy,
        ),
      );
      if (paused) await DownloadJobs.remove(pack.downloadKey);
    } finally {
      _active.remove(pack.id);
    }
  }

  Future<void> pause(VoicePack pack) async {
    _batchEpoch++;
    _packEpochs[pack.id] = (_packEpochs[pack.id] ?? 0) + 1;
    for (final f in pack.files) {
      await _dl.pause('${pack.downloadKey}:${f.fileName}');
    }
  }

  Future<void> delete(VoicePack pack) async {
    // Increment epoch first to cancel any in-flight download/unpack.
    _packEpochs[pack.id] = (_packEpochs[pack.id] ?? 0) + 1;
    // Wait for any active operation to notice the epoch change and exit.
    // Give it a brief moment to unwind; the operation checks epoch at each await.
    await Future.delayed(const Duration(milliseconds: 50));
    await pause(pack);
    await DownloadJobs.remove(pack.downloadKey);
    await VoiceModels.delete(pack);
    _set(pack, const VoicePackState(VoicePackStatus.missing));
  }
}

final voiceModelsProvider =
    NotifierProvider<VoiceModelsNotifier, VoiceModelsState>(
      VoiceModelsNotifier.new,
    );
