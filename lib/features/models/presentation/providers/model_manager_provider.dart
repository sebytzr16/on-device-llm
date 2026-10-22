import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/errors/exceptions.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/providers/shared_providers.dart';
import '../../../../data/local/database/app_database.dart';
import '../../../../data/storage/download_manager.dart';
import '../../../../data/storage/download_jobs.dart';
import '../../../../data/storage/model_storage.dart';
import '../../../../data/storage/gguf_metadata.dart';
import 'model_recommendations_provider.dart';
import '../../../adapters/adapter_store.dart';
import '../../../benchmark/benchmark.dart';
import '../../../chat/presentation/providers/chat_model_pins.dart';
import '../../../settings/domain/entities/inference_settings.dart';
import '../../../presets/presentation/providers/presets_provider.dart';
import '../../../settings/presentation/providers/effective_settings_provider.dart';
import '../../../settings/presentation/providers/model_profiles_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/widgets/settings_labels.dart';
import '../../domain/entities/model_catalog.dart';
import '../../domain/entities/model_info.dart';

/// The note for a load whose context the bridge shortened, to the model's
/// trained length or to what fits in the memory free right now
/// (effectiveSettings.contextCap); null when it got what it asked for.
String? contextCapNote(AppLocalizations t, Map<String, dynamic> metrics) {
  final s = metrics['effectiveSettings'];
  if (s is! Map) return null;
  final size = (s['contextSize'] as num?)?.toInt() ?? 0;
  final asked = (s['contextRequested'] as num?)?.toInt() ?? 0;
  if (size <= 0 || size >= asked) return null;
  return switch (s['contextCap']) {
    'train' => t.contextCapTrain(tokenCount(size)),
    'memory' => t.contextCapMemory(tokenCount(size)),
    _ => null,
  };
}

/// The bridge's refusal when even a small context does not fit, in [t]'s
/// language; null for any other error.
NotEnoughMemoryException? memoryRefusal(AppLocalizations t, Object error) {
  final m = RegExp(
    r'Not enough free memory for this model: it needs about (\d+) MB.*?(\d+) MB is free',
  ).firstMatch('$error');
  if (m == null) return null;
  return NotEnoughMemoryException(
    t.notEnoughMemory(int.parse(m.group(1)!), int.parse(m.group(2)!)),
  );
}

class ModelManagerState {
  final List<ModelInfo> catalog;
  final Map<String, DownloadProgress> downloads;
  final String? loadedModelId, error;
  final bool isLoadingModel, isImporting;

  /// Catalog ids whose vision projector file is present on disk.
  final Set<String> vision;

  /// The knowledge library's embedding model is on disk (FX-02).
  final bool embeddingReady;

  /// Its projector for photos and voice notes is on disk too.
  final bool embeddingMediaReady;

  /// The optional source-check model is on disk.
  final bool supportCheckReady;
  const ModelManagerState({
    this.catalog = const [],
    this.downloads = const {},
    this.loadedModelId,
    this.error,
    this.isLoadingModel = false,
    this.isImporting = false,
    this.vision = const {},
    this.embeddingReady = false,
    this.embeddingMediaReady = false,
    this.supportCheckReady = false,
  });

  /// Progress key of a projector download.
  static String visionKey(String modelId) => '$modelId:vision';

  /// Progress key of the embedding model download.
  static const embeddingKey = 'embedding:embeddinggemma-2-q8';

  /// Progress key of the embedding projector (photos, voice notes).
  static const embeddingMediaKey = 'embedding:embeddinggemma-2-q8:media';

  /// Progress key of the source-check model download.
  static const supportCheckKey = 'support:qwen3-reranker-0.6b-q8';
  ModelInfo? get loadedModel =>
      catalog.where((m) => m.id == loadedModelId).firstOrNull;
  ModelManagerState copyWith({
    List<ModelInfo>? catalog,
    Map<String, DownloadProgress>? downloads,
    String? loadedModelId,
    bool clearLoaded = false,
    bool? isLoadingModel,
    bool? isImporting,
    String? error,
    bool clearError = false,
    Set<String>? vision,
    bool? embeddingReady,
    bool? embeddingMediaReady,
    bool? supportCheckReady,
  }) => ModelManagerState(
    catalog: catalog ?? this.catalog,
    downloads: downloads ?? this.downloads,
    loadedModelId: clearLoaded ? null : loadedModelId ?? this.loadedModelId,
    isLoadingModel: isLoadingModel ?? this.isLoadingModel,
    isImporting: isImporting ?? this.isImporting,
    error: clearError ? null : error ?? this.error,
    vision: vision ?? this.vision,
    embeddingReady: embeddingReady ?? this.embeddingReady,
    embeddingMediaReady: embeddingMediaReady ?? this.embeddingMediaReady,
    supportCheckReady: supportCheckReady ?? this.supportCheckReady,
  );
}

class ModelManagerNotifier extends Notifier<ModelManagerState> {
  final _downloader = DownloadManager();
  final _subscriptions = <String, StreamSubscription<DownloadProgress>>{};
  bool _alive = true;
  late Future<void> ready;
  @override
  ModelManagerState build() {
    final sub = ref
        .read(appDatabaseProvider)
        .watchAllModels()
        .listen(
          (rows) {
            if (_alive) {
              state = state.copyWith(catalog: rows.map(_fromRow).toList());
            }
          },
          onError: (Object e) {
            if (_alive) {
              state = state.copyWith(error: 'Cannot open model library: $e');
            }
          },
        );
    ready = Future.microtask(_seed);
    ref.onDispose(() {
      _alive = false;
      unawaited(sub.cancel());
      _downloader.dispose();
      for (final s in _subscriptions.values) {
        unawaited(s.cancel());
      }
    });
    return const ModelManagerState();
  }

  ModelInfo _fromRow(Model r) => ModelInfo(
    id: r.id,
    displayName: r.displayName,
    fileName: r.fileName,
    downloadUrl: r.downloadUrl,
    sha256: r.sha256,
    sizeBytes: r.sizeBytes,
    family: ModelFamily.values.byName(r.family),
    quantization: ModelQuantization.values.byName(r.quantization),
    isDownloaded: r.isDownloaded,
    localPath: r.localPath,
    downloadedAt: r.downloadedAt,
    license: r.license,
  );
  Future<void> save(ModelInfo m, {String? localPath}) async {
    final previous = await ref.read(appDatabaseProvider).getModel(m.id);
    localPath ??= previous?.isDownloaded == true ? previous!.localPath : null;
    await ref
        .read(appDatabaseProvider)
        .upsertModel(
          ModelsCompanion.insert(
            id: m.id,
            displayName: m.displayName,
            fileName: m.fileName,
            downloadUrl: drift.Value(m.downloadUrl),
            sha256: drift.Value(m.sha256),
            sizeBytes: m.sizeBytes,
            family: m.family.name,
            quantization: m.quantization.name,
            license: drift.Value(m.license),
            isDownloaded: drift.Value(localPath != null || m.isDownloaded),
            localPath: drift.Value(localPath ?? m.localPath),
            downloadedAt: drift.Value(
              localPath != null ? DateTime.now() : m.downloadedAt,
            ),
          ),
        );
  }

  Future<void> _seed() async {
    try {
      final db = ref.read(appDatabaseProvider);
      for (final m in bundledCatalog) {
        if (await db.getModel(m.id) == null) await save(m);
      }
      await refreshVision();
      final models = await db.allModels();
      for (final m in models) {
        if (m.isDownloaded &&
            (m.localPath == null || !await File(m.localPath!).exists())) {
          await (db.update(db.models)..where((t) => t.id.equals(m.id))).write(
            const ModelsCompanion(
              isDownloaded: drift.Value(false),
              localPath: drift.Value(null),
            ),
          );
        }
        // Entries the catalog no longer offers disappear unless the file
        // is still here (then Remove takes the row with the file).
        if (retiredCatalogIds.contains(m.id) &&
            !(m.isDownloaded && m.localPath != null)) {
          await ModelStorage.deletePartial(m.fileName);
          await db.deleteModel(m.id);
        }
      }
      await _adoptCatalogCopies(db);
      // Files already on the phone get their makers' sampling read once
      // (request 2026-10-04); local, header only.
      final recommendations = ref.read(modelRecommendationsProvider.notifier);
      for (final m in (await db.allModels()).map(_fromRow)) {
        if (m.isDownloaded) unawaited(recommendations.learnFromFile(m));
      }
      // A process can be killed mid-download. The .part file keeps bytes and
      // DownloadJobs distinguishes active work from a user-paused transfer.
      unawaited(
        _resumeInterruptedDownloads(
          (await db.allModels()).map(_fromRow).toList(),
        ),
      );
    } catch (e) {
      if (_alive) state = state.copyWith(error: '$e');
    }
  }

  /// A catalog model the user already added another way (Hugging Face
  /// search, a link, a file) is the same file when the publisher's SHA-256
  /// matches: the catalog row takes it over (renamed to the catalog's file
  /// name) and the duplicate row goes, its profile, chat pins and benchmark
  /// following it. The tester had the Q8_0 0.8B from a Hub search before it
  /// joined the catalog.
  Future<void> _adoptCatalogCopies(AppDatabase db) async {
    final rows = await db.allModels();
    for (final entry in bundledCatalog) {
      final own = rows.where((r) => r.id == entry.id).firstOrNull;
      final hash = entry.sha256?.toLowerCase();
      if (own == null || own.isDownloaded || hash == null) continue;
      final copy = rows
          .where(
            (r) =>
                r.id != entry.id &&
                r.isDownloaded &&
                r.localPath != null &&
                r.sha256?.toLowerCase() == hash,
          )
          .firstOrNull;
      if (copy == null) continue;
      final file = File(copy.localPath!);
      if (!await file.exists()) continue;
      var path = file.path;
      try {
        final target = await ModelStorage.modelFile(entry.fileName);
        if (!await target.exists()) {
          path = (await file.rename(target.path)).path;
        }
      } catch (_) {
        // A file that cannot be renamed is used where it is.
      }
      await (db.update(db.models)..where((t) => t.id.equals(entry.id))).write(
        ModelsCompanion(
          isDownloaded: const drift.Value(true),
          localPath: drift.Value(path),
          downloadedAt: drift.Value(copy.downloadedAt ?? DateTime.now()),
        ),
      );
      await db.deleteModel(copy.id);
      await _moveModelId(copy.id, entry.id);
    }
  }

  /// Keys that name a model (profile, pins, benchmark, draft model) move
  /// from [from] to [to].
  Future<void> _moveModelId(String from, String to) async {
    try {
      final profiles = ref.read(modelProfilesProvider.notifier);
      await profiles.ready;
      final profile = profiles.of(from);
      if (profile.isNotEmpty) {
        await profiles.set(to, profile);
        await profiles.clear(from);
      }
      final pins = ref.read(chatModelPinsProvider.notifier);
      await pins.ready;
      for (final e in {...ref.read(chatModelPinsProvider)}.entries) {
        if (e.value == from) await pins.set(e.key, to);
      }
      final bench = ref.read(benchmarkProvider.notifier);
      await bench.ready;
      await bench.rename(from, to);
      final settings = ref.read(settingsProvider.notifier);
      await settings.ready;
      final s = ref.read(settingsProvider);
      if (s.draftModelId == from) {
        await settings.update(s.copyWith(draftModelId: to));
      }
    } catch (_) {
      // Leftover keys only point at a model that no longer exists.
    }
  }

  Future<void> _resumeInterruptedDownloads(List<ModelInfo> models) async {
    Set<String> pending;
    try {
      pending = await DownloadJobs.active();
    } catch (error) {
      if (_alive) {
        state = state.copyWith(error: 'Download recovery failed: $error');
      }
      return;
    }
    for (final id in pending) {
      if (!_alive) return;
      if (!(await DownloadJobs.active()).contains(id)) continue;
      // The voice packs resume through their own provider.
      if (id.startsWith('voice:')) continue;
      if (id == ModelManagerState.embeddingMediaKey) {
        if (state.embeddingMediaReady) {
          await _downloader.pause(id);
          await DownloadJobs.remove(id);
        } else {
          unawaited(downloadEmbeddingMedia());
        }
      } else if (id == ModelManagerState.supportCheckKey) {
        if (state.supportCheckReady) {
          await _downloader.pause(id);
          await DownloadJobs.remove(id);
        } else {
          unawaited(downloadSupportCheck());
        }
      } else if (id == ModelManagerState.embeddingKey) {
        if (state.embeddingReady) {
          await _downloader.pause(id);
          await DownloadJobs.remove(id);
        } else {
          unawaited(downloadEmbedding());
        }
      } else if (id.endsWith(':vision')) {
        final modelId = id.substring(0, id.length - ':vision'.length);
        final model = models.where((m) => m.id == modelId).firstOrNull;
        if (model == null ||
            !visionProjectors.containsKey(modelId) ||
            state.vision.contains(modelId)) {
          await _downloader.pause(id);
          await DownloadJobs.remove(id);
        } else {
          unawaited(downloadVision(model));
        }
      } else {
        final model = models.where((m) => m.id == id).firstOrNull;
        if (model == null ||
            model.isDownloaded ||
            model.downloadUrl == null ||
            model.sha256 == null) {
          await _downloader.pause(id);
          await DownloadJobs.remove(id);
        } else {
          unawaited(downloadModel(model));
        }
      }
    }
  }

  /// [settings] are the resolved settings for the turn (model profile,
  /// preset and chat overrides applied); without them the cascade for the
  /// current chat is used. LoRA attachments and the draft model come from
  /// their own stores.
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
  }) async {
    if (state.isLoadingModel || (ref.read(sessionBusyProvider) && !forChat)) {
      throw StateError('Stop the current response before switching models.');
    }
    if (!info.isDownloaded || info.localPath == null) {
      throw StateError('Download or import this model first.');
    }
    state = state.copyWith(isLoadingModel: true, clearError: true);
    try {
      final projector = visionProjectors[info.id];
      final resolved =
          settings ??
          resolveSettings(
            global: ref.read(settingsProvider),
            defaults: ref.read(settingsProvider.notifier).defaults,
            profiles: ref.read(modelProfilesProvider),
            preset: ref.read(presetsProvider).active,
            chat: ref.read(chatOverridesProvider),
            recommendations: ref.read(modelRecommendationsProvider),
            model: info,
            project: {
              if (ref.read(currentProjectProvider)?.collection.isNotEmpty ==
                  true)
                'knowledgeCollection': ref
                    .read(currentProjectProvider)!
                    .collection,
            },
            projectLabel: ref.read(currentProjectProvider)?.name ?? 'Project',
          ).effective;
      final engine = ref.read(llamaEngineProvider);
      final loads = engine.loadCount;
      await engine.loadModel(
        modelPath: info.localPath!,
        settings: await _resolveBackend(resolved),
        mmprojPath: projector != null && state.vision.contains(info.id)
            ? (await ModelStorage.modelFile(projector.fileName)).path
            : null,
        adapters: await ref.read(adaptersProvider.notifier).resolved(info.id),
        draftModelPath: draftPathFor(info, resolved.draftModelId),
      );
      if (_alive) {
        state = state.copyWith(loadedModelId: info.id, isLoadingModel: false);
        if (engine.loadCount != loads) _noteContextCap(engine.metrics);
      }
    } catch (e, st) {
      final memory = _memoryError(e);
      if (_alive) {
        state = state.copyWith(
          isLoadingModel: false,
          clearLoaded: true,
          error: '${memory ?? e}',
        );
      }
      if (memory != null) Error.throwWithStackTrace(memory, st);
      rethrow;
    }
  }

  /// One line when the bridge shortened the context (report
  /// 2026-09-28: a 64K context made Android kill the app while it loaded).
  void _noteContextCap(Map<String, dynamic> metrics) {
    final text = contextCapNote(
      stringsFor(ref.read(settingsProvider).localeCode),
      metrics,
    );
    if (text == null) return;
    ref
        .read(islandProvider.notifier)
        .toast(
          text,
          tone: IslandTone.warning,
          icon: Icons.memory_rounded,
          duration: const Duration(seconds: 4),
        );
  }

  NotEnoughMemoryException? _memoryError(Object e) =>
      memoryRefusal(stringsFor(ref.read(settingsProvider).localeCode), e);

  /// The draft model's file for speculative decoding: another downloaded
  /// catalog entry (never the model itself). Null turns speculation off.
  String? draftPathFor(ModelInfo info, String draftModelId) {
    if (draftModelId.isEmpty || draftModelId == info.id) return null;
    final draft = state.catalog.where((m) => m.id == draftModelId).firstOrNull;
    if (draft == null || !draft.isDownloaded || draft.localPath == null) {
      return null;
    }
    return draft.localPath;
  }

  /// Auto is the compatibility/per-answer-speed policy: CPU. Accelerators
  /// remain explicit because changing backend reloads the model and OpenCL's
  /// faster prompt reading trades against slower answer decoding.
  bool _autoCpu = false;

  Future<InferenceSettings> _resolveBackend(InferenceSettings s) async {
    _autoCpu = s.backend == GpuBackend.auto;
    return _autoCpu ? s.copyWith(backend: GpuBackend.cpu) : s;
  }

  /// Why the running backend differs from the setting, for the panel.
  String? get backendChoice => _autoCpu
      ? 'Automatic resolved to CPU. OpenCL is explicit because it reads research prompts about 2x faster but decodes answers about 15% slower (measured).'
      : null;

  /// Releases the model's memory without leaving the chat. The next message
  /// loads it again.
  Future<void> unloadModel() async {
    if (state.isLoadingModel || ref.read(sessionBusyProvider)) {
      throw StateError('Stop the current response before unloading.');
    }
    await ref.read(llamaEngineProvider).unload();
    if (_alive) state = state.copyWith(clearLoaded: true);
  }

  /// The makers' sampling for a model just placed on the phone: its file's
  /// `general.sampling.*` keys and, for a Hugging Face download, the
  /// repository's `generation_config.json` (same host, same moment).
  Future<void> _learnSampling(ModelInfo m, {bool hub = false}) async {
    final r = ref.read(modelRecommendationsProvider.notifier);
    await r.learnFromFile(m, force: true);
    if (hub) unawaited(r.learnFromHub(m));
  }

  Future<void> downloadModel(ModelInfo info) async {
    if (_subscriptions.containsKey(info.id) || info.isDownloaded) return;
    state = state.copyWith(clearError: true);
    _subscriptions[info.id] = _downloader.progressStream(info.id).listen((p) {
      if (_alive) {
        state = state.copyWith(downloads: {...state.downloads, info.id: p});
      }
    });
    try {
      final existing = await ModelStorage.modelFile(info.fileName);
      if (await existing.exists() &&
          await existing.length() == info.sizeBytes &&
          await ModelStorage.validateAndHash(existing.path) == info.sha256) {
        await _downloader.pause(info.id);
        await save(info, localPath: existing.path);
        await DownloadJobs.remove(info.id);
        await _learnSampling(info.copyWith(localPath: existing.path));
        return;
      }
      await DownloadJobs.add(info.id);
      await _downloader.download(
        modelId: info.id,
        url: info.downloadUrl!,
        fileName: info.fileName,
        expectedSha256: info.sha256!,
        expectedSize: info.sizeBytes,
      );
      final file = await ModelStorage.modelFile(info.fileName);
      await save(info, localPath: file.path);
      await DownloadJobs.remove(info.id);
      await _learnSampling(info.copyWith(localPath: file.path), hub: true);
    } catch (e) {
      if (_alive && !(e is DioException && CancelToken.isCancel(e))) {
        state = state.copyWith(error: '$e');
      }
    } finally {
      await _subscriptions.remove(info.id)?.cancel();
    }
  }

  Future<void> pauseDownload(String id) async {
    await DownloadJobs.remove(id);
    await _downloader.pause(id);
  }

  /// Which catalog models can see photos right now (projector on disk),
  /// and whether the knowledge library's embedding model is present.
  Future<void> refreshVision() async {
    final ready = <String>{};
    for (final e in visionProjectors.entries) {
      final f = await ModelStorage.modelFile(e.value.fileName);
      if (await f.exists() && await f.length() == e.value.sizeBytes) {
        ready.add(e.key);
      }
    }
    Future<bool> present(String name, int size) async {
      final f = await ModelStorage.modelFile(name);
      return await f.exists() && await f.length() == size;
    }

    final embeddingReady = await present(
      embeddingModel.fileName,
      embeddingModel.sizeBytes,
    );
    final projector = embeddingModel.projector;
    final embeddingMediaReady =
        projector != null &&
        await present(projector.fileName, projector.sizeBytes);
    final supportCheckReady = await present(
      supportCheckModel.fileName,
      supportCheckModel.sizeBytes,
    );
    // An earlier embedding model's vectors cannot be compared with this
    // one's: passages re-index, so its file is only taking space.
    if (embeddingReady) {
      for (final name in embeddingModel.legacyFileNames) {
        try {
          await ModelStorage.delete(name);
        } catch (_) {}
      }
    }
    if (_alive) {
      state = state.copyWith(
        vision: ready,
        embeddingReady: embeddingReady,
        embeddingMediaReady: embeddingMediaReady,
        supportCheckReady: supportCheckReady,
      );
    }
  }

  /// Fetches the embedding model so knowledge collections can be searched
  /// by meaning (FX-02).
  Future<void> downloadEmbedding() async {
    if (state.embeddingReady) return;
    await _fetchEmbeddingFile(
      ModelManagerState.embeddingKey,
      url: embeddingModel.downloadUrl,
      fileName: embeddingModel.fileName,
      sha256: embeddingModel.sha256,
      size: embeddingModel.sizeBytes,
    );
  }

  /// Fetches the projector so photos and voice notes are searchable by
  /// meaning; passages of those already imported are indexed again.
  Future<void> downloadEmbeddingMedia() async {
    final projector = embeddingModel.projector;
    if (projector == null || state.embeddingMediaReady) return;
    await _fetchEmbeddingFile(
      ModelManagerState.embeddingMediaKey,
      url: projector.downloadUrl,
      fileName: projector.fileName,
      sha256: projector.sha256,
      size: projector.sizeBytes,
    );
    if (state.embeddingMediaReady) {
      await ref.read(appDatabaseProvider).clearKnowledgeMediaVectors();
    }
  }

  Future<void> deleteEmbeddingMedia() async {
    final projector = embeddingModel.projector;
    if (projector == null) return;
    ref.read(embeddingEngineProvider).dispose();
    await DownloadJobs.remove(ModelManagerState.embeddingMediaKey);
    await ModelStorage.delete(projector.fileName);
    await refreshVision();
  }

  Future<void> _fetchEmbeddingFile(
    String key, {
    required String url,
    required String fileName,
    required String sha256,
    required int size,
  }) async {
    if (_subscriptions.containsKey(key)) return;
    state = state.copyWith(clearError: true);
    _subscriptions[key] = _downloader.progressStream(key).listen((p) {
      if (_alive) {
        state = state.copyWith(downloads: {...state.downloads, key: p});
      }
    });
    try {
      await DownloadJobs.add(key);
      await _downloader.download(
        modelId: key,
        url: url,
        fileName: fileName,
        expectedSha256: sha256,
        expectedSize: size,
      );
      await refreshVision();
      await DownloadJobs.remove(key);
    } catch (e) {
      if (_alive && !(e is DioException && CancelToken.isCancel(e))) {
        state = state.copyWith(error: '$e');
      }
    } finally {
      await _subscriptions.remove(key)?.cancel();
    }
  }

  /// Fetches the source-check model; answers from sources are then also
  /// checked by meaning before a sentence is flagged.
  Future<void> downloadSupportCheck() async {
    if (state.supportCheckReady) return;
    await _fetchEmbeddingFile(
      ModelManagerState.supportCheckKey,
      url: supportCheckModel.downloadUrl,
      fileName: supportCheckModel.fileName,
      sha256: supportCheckModel.sha256,
      size: supportCheckModel.sizeBytes,
    );
  }

  Future<void> deleteSupportCheck() async {
    ref.read(supportEngineProvider).dispose();
    await DownloadJobs.remove(ModelManagerState.supportCheckKey);
    await ModelStorage.delete(supportCheckModel.fileName);
    await refreshVision();
  }

  Future<void> deleteEmbedding() async {
    ref.read(embeddingEngineProvider).dispose();
    await DownloadJobs.remove(ModelManagerState.embeddingKey);
    await ModelStorage.delete(embeddingModel.fileName);
    await refreshVision();
  }

  /// Fetches the model's vision projector so photos can be attached.
  Future<void> downloadVision(ModelInfo info) async {
    final projector = visionProjectors[info.id];
    if (projector == null) return;
    final key = ModelManagerState.visionKey(info.id);
    if (_subscriptions.containsKey(key) || state.vision.contains(info.id)) {
      return;
    }
    state = state.copyWith(clearError: true);
    _subscriptions[key] = _downloader.progressStream(key).listen((p) {
      if (_alive) {
        state = state.copyWith(downloads: {...state.downloads, key: p});
      }
    });
    try {
      await DownloadJobs.add(key);
      await _downloader.download(
        modelId: key,
        url: projector.downloadUrl,
        fileName: projector.fileName,
        expectedSha256: projector.sha256,
        expectedSize: projector.sizeBytes,
      );
      await refreshVision();
      await DownloadJobs.remove(key);
    } catch (e) {
      if (_alive && !(e is DioException && CancelToken.isCancel(e))) {
        state = state.copyWith(error: '$e');
      }
    } finally {
      await _subscriptions.remove(key)?.cancel();
    }
  }

  Future<void> deleteVision(ModelInfo info) async {
    final projector = visionProjectors[info.id];
    if (projector == null) return;
    if (state.loadedModelId == info.id) {
      // The projector is memory-mapped by the engine; drop it first.
      ref.read(llamaEngineProvider).dispose();
      state = state.copyWith(clearLoaded: true);
    }
    await DownloadJobs.remove(ModelManagerState.visionKey(info.id));
    await ModelStorage.delete(projector.fileName);
    await refreshVision();
  }

  Future<void> importFile(String path, ModelFamily family) async {
    if (state.isImporting) return;
    state = state.copyWith(isImporting: true, clearError: true);
    File? partial;
    try {
      final metadata = await GgufMetadata.inspect(path);
      final hash = await ModelStorage.validateAndHash(path);
      final id = 'local-${hash.substring(0, 20)}';
      final name = '$id.gguf';
      final destination = await ModelStorage.modelFile(name);
      if (!await destination.exists()) {
        partial = File('${destination.path}.part');
        await File(path).copy(partial.path);
        if (await ModelStorage.validateAndHash(partial.path) != hash) {
          throw StateError('Import changed while copying. Try again.');
        }
        await ModelStorage.excludeFromICloud(partial);
        await partial.rename(destination.path);
        partial = null;
      }
      final info = ModelInfo(
        id: id,
        displayName: metadata.name?.trim().isNotEmpty == true
            ? metadata.name!.trim()
            : p.basenameWithoutExtension(path),
        fileName: name,
        sizeBytes: await destination.length(),
        family: _familyFromArchitecture(metadata.architecture) ?? family,
        quantization: _quantizationFromFileType(metadata.fileType),
        parameterCountB:
            metadata.parameterCount == null ||
                metadata.parameterCount! < 500000000
            ? null
            : (metadata.parameterCount! / 1000000000).round(),
        sha256: hash,
        license: 'Imported file · check publisher license',
      );
      await save(info, localPath: destination.path);
      await _learnSampling(info.copyWith(localPath: destination.path));
    } catch (e) {
      if (_alive) state = state.copyWith(error: '$e');
    } finally {
      if (partial != null && await partial.exists()) await partial.delete();
      if (_alive) state = state.copyWith(isImporting: false);
    }
  }

  static ModelFamily? _familyFromArchitecture(String? architecture) =>
      switch (architecture?.toLowerCase()) {
        'gemma' || 'gemma2' || 'gemma3' || 'gemma4' => ModelFamily.gemma,
        'qwen' ||
        'qwen2' ||
        'qwen2moe' ||
        'qwen3' ||
        'qwen35' => ModelFamily.qwen,
        'deepseek' || 'deepseek2' => ModelFamily.deepseek,
        'phi2' || 'phi3' || 'phimoe' => ModelFamily.phi,
        'llama' => ModelFamily.llama,
        'mistral' || 'mixtral' => ModelFamily.mistral,
        null || '' => null,
        _ => ModelFamily.other,
      };

  static ModelQuantization _quantizationFromFileType(int? fileType) =>
      switch (fileType) {
        1 => ModelQuantization.fp16,
        2 => ModelQuantization.q4_0,
        7 => ModelQuantization.q8_0,
        10 => ModelQuantization.q2_k,
        12 => ModelQuantization.q3_k_m,
        15 => ModelQuantization.q4_k_m,
        17 => ModelQuantization.q5_k_m,
        18 => ModelQuantization.q6_k,
        25 => ModelQuantization.iq4_nl,
        _ => ModelQuantization.unknown,
      };

  Future<void> deleteModel(ModelInfo info) async {
    if (ref.read(sessionBusyProvider) ||
        state.isLoadingModel ||
        _subscriptions.containsKey(info.id)) {
      throw StateError('Stop generation and pause downloads before deleting.');
    }
    if (state.loadedModelId == info.id) {
      ref.read(llamaEngineProvider).dispose();
      state = state.copyWith(clearLoaded: true);
    }
    await _downloader.pause(info.id);
    await DownloadJobs.remove(info.id);
    await ModelStorage.delete(info.fileName);
    await ModelStorage.deletePartial(info.fileName);
    final db = ref.read(appDatabaseProvider);
    // Only the bundled catalog keeps an "available to download" row; a model
    // the user added by link, Hub search or import is gone for good.
    if (bundledCatalog.any((m) => m.id == info.id)) {
      await (db.update(db.models)..where((t) => t.id.equals(info.id))).write(
        const ModelsCompanion(
          isDownloaded: drift.Value(false),
          localPath: drift.Value(null),
          downloadedAt: drift.Value(null),
        ),
      );
    } else {
      await db.deleteModel(info.id);
    }
  }
}

final modelManagerProvider =
    NotifierProvider<ModelManagerNotifier, ModelManagerState>(
      ModelManagerNotifier.new,
    );
