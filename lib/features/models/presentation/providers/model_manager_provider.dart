import '../../../../data/storage/download_history.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/errors/exceptions.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/platform/desktop_host.dart';
import '../../../../core/providers/shared_providers.dart';
import '../../../../data/local/database/app_database.dart';
import '../../../../data/storage/download_manager.dart';
import '../../../../data/storage/download_jobs.dart';
import '../../../../data/storage/model_storage.dart';
import '../../../../data/storage/model_file_leases.dart';
import '../../../../data/storage/model_folders.dart';
import '../../../../data/storage/gguf_metadata.dart';
import '../../../../data/storage/gguf_split.dart';
import '../../../../inference/engine/llama_engine.dart';
import '../../../../inference/engine/diffusiongemma_engine.dart';
import 'model_recommendations_provider.dart';
import '../../../adapters/adapter_store.dart';
import '../../../helper/helper_runner.dart';
import '../../../benchmark/benchmark.dart';
import '../../../chat/presentation/providers/chat_model_pins.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../settings/domain/entities/inference_settings.dart';
import '../../../presets/presentation/providers/presets_provider.dart';
import '../../../settings/presentation/providers/effective_settings_provider.dart';
import '../../../settings/presentation/providers/model_profiles_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/widgets/settings_labels.dart';
import '../../domain/entities/model_catalog.dart';
import '../../domain/entities/model_info.dart';
import 'retired_model_names.dart';

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
  final String? loadingModelId;
  final double? loadProgress;
  final bool isLoadingModel, isImporting;

  /// Catalog ids whose vision projector file is present on disk.
  final Set<String> vision;

  /// The knowledge library's embedding model is on disk (FX-02).
  final bool embeddingReady;

  /// Its projector for photos and voice notes is on disk too.
  final bool embeddingMediaReady;

  /// The optional source-check model is on disk.
  final bool supportCheckReady;

  /// Catalog ids whose file is being hashed, read for its settings or
  /// joined by its projector: no progress to show, not usable yet.
  final Set<String> preparing;
  const ModelManagerState({
    this.catalog = const [],
    this.downloads = const {},
    this.loadedModelId,
    this.loadingModelId,
    this.loadProgress,
    this.error,
    this.isLoadingModel = false,
    this.isImporting = false,
    this.vision = const {},
    this.embeddingReady = false,
    this.embeddingMediaReady = false,
    this.supportCheckReady = false,
    this.preparing = const {},
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
    String? loadingModelId,
    bool clearLoadingModel = false,
    double? loadProgress,
    bool clearLoadProgress = false,
    bool clearLoaded = false,
    bool? isLoadingModel,
    bool? isImporting,
    String? error,
    bool clearError = false,
    Set<String>? vision,
    bool? embeddingReady,
    bool? embeddingMediaReady,
    bool? supportCheckReady,
    Set<String>? preparing,
  }) => ModelManagerState(
    catalog: catalog ?? this.catalog,
    downloads: downloads ?? this.downloads,
    loadedModelId: clearLoaded ? null : loadedModelId ?? this.loadedModelId,
    loadingModelId: clearLoadingModel
        ? null
        : loadingModelId ?? this.loadingModelId,
    loadProgress: clearLoadProgress ? null : loadProgress ?? this.loadProgress,
    isLoadingModel: isLoadingModel ?? this.isLoadingModel,
    isImporting: isImporting ?? this.isImporting,
    error: clearError ? null : error ?? this.error,
    vision: vision ?? this.vision,
    embeddingReady: embeddingReady ?? this.embeddingReady,
    embeddingMediaReady: embeddingMediaReady ?? this.embeddingMediaReady,
    supportCheckReady: supportCheckReady ?? this.supportCheckReady,
    preparing: preparing ?? this.preparing,
  );
}

/// The files and settings a chat model was loaded with.
typedef ChatLoad = ({
  String modelId,
  String modelPath,
  InferenceSettings settings,
  String? mmprojPath,
  String? draftModelPath,
});

class ModelManagerNotifier extends Notifier<ModelManagerState> {
  final _downloader = DownloadManager();
  final _projectorDownloads = <String, Future<void>>{};
  final _subscriptions = <String, StreamSubscription<DownloadProgress>>{};
  StreamSubscription<double?>? _loadSubscription;
  Timer? _loadProgressTimer;
  bool _alive = true;
  Completer<void>? _fileOperation;
  late Future<void> ready;
  @override
  ModelManagerState build() {
    final sub = ref
        .read(appDatabaseProvider)
        .watchAllModels()
        .listen(
          (rows) {
            if (_alive) {
              // An MTP head is a sidecar the loader attaches by itself, not
              // a model to pick (a hub download of one showed up as "mtp
              // gemma 4 26B A4B it", 2026-10-28).
              state = state.copyWith(
                catalog: rows
                    .map(_fromRow)
                    .where((m) => !isMtpHeadFile(m.fileName))
                    .toList(),
              );
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
      _stopLoadProgress();
      unawaited(sub.cancel());
      _downloader.dispose();
      for (final s in _subscriptions.values) {
        unawaited(s.cancel());
      }
    });
    return const ModelManagerState();
  }

  ModelInfo _fromRow(Model r) => ModelInfo(
    parts: r.partsJson == null
        ? const []
        : [
            for (final part in jsonDecode(r.partsJson!) as List)
              ModelDownloadPart.fromJson(part as Map<String, dynamic>),
          ],
    projector: r.projectorJson == null
        ? null
        : VisionProjector.fromJson(
            jsonDecode(r.projectorJson!) as Map<String, dynamic>,
          ),
    id: r.id,
    // Hub rows saved before tidyName kept the raw file stem
    // ("Gemma-4-E4B-Q8_K_P"); a name the user changed is left alone.
    displayName:
        r.id.startsWith('hf-') && r.fileName.endsWith('-${r.displayName}.gguf')
        ? ModelQuantization.tidyName(r.displayName)
        : r.displayName,
    fileName: r.fileName,
    downloadUrl: r.downloadUrl,
    sha256: r.sha256,
    sizeBytes: r.sizeBytes,
    // A family saved by a newer or older build reads as other, not a throw.
    family: ModelFamily.values.asNameMap()[r.family] ?? ModelFamily.other,
    // Hub rows saved before ModelQuantization.of stored Q4_K_M for any
    // quant name outside the enum (Q8_K_P, Q5_K_S); the file name decides.
    quantization:
        r.id.startsWith('hf-') &&
            ModelQuantization.of(r.fileName) != ModelQuantization.unknown
        ? ModelQuantization.of(r.fileName)
        : ModelQuantization.values.asNameMap()[r.quantization] ??
              ModelQuantization.of(r.fileName),
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
            partsJson: drift.Value(
              m.parts.isEmpty
                  ? null
                  : jsonEncode(m.parts.map((f) => f.toJson()).toList()),
            ),
            projectorJson: drift.Value(
              m.projector == null ? null : jsonEncode(m.projector!.toJson()),
            ),
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

  Future<bool> _modelFilesExist(String path) async {
    try {
      await ModelStorage.ggufFilesBeside(path);
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<void> _seed() async {
    try {
      final db = ref.read(appDatabaseProvider);
      for (final m in catalogModels) {
        if (await db.getModel(m.id) == null) await save(m);
      }
      await refreshVision();
      final models = await db.allModels();
      for (final m in models) {
        if (m.isDownloaded &&
            (m.localPath == null || !await _modelFilesExist(m.localPath!))) {
          await (db.update(db.models)..where((t) => t.id.equals(m.id))).write(
            const ModelsCompanion(
              isDownloaded: drift.Value(false),
              localPath: drift.Value(null),
            ),
          );
        }
        // Entries the catalog no longer offers disappear unless the file
        // is still here (then Remove takes the row with the file).
        // The desktop offers its own list: phone entries seeded by earlier
        // builds (Qwen 2B, 1.7B…) go the same way.
        final phoneOnly =
            DesktopHost.active &&
            bundledCatalog.any((b) => b.id == m.id) &&
            !catalogModels.any((c) => c.id == m.id);
        if ((retiredCatalogIds.contains(m.id) || phoneOnly) &&
            !(m.isDownloaded && m.localPath != null)) {
          await ModelStorage.deletePartial(m.fileName);
          await db.deleteModel(m.id);
        }
      }
      await _adoptCatalogCopies(db);
      await _adoptOrphanFiles(db);
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
    for (final entry in catalogModels) {
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
          // A file a runtime holds leased is not moved out from under it
          // (audit N14, 2026-11-07); the guard refuses with the usual
          // in-use error and the row keeps the file where it is.
          final guard = _guardModelPaths([file.path]);
          try {
            path = (await file.rename(target.path)).path;
          } finally {
            guard.release();
          }
        }
      } catch (_) {
        // A file that cannot be renamed (or is in use) is used where it is.
      }
      await (db.update(db.models)..where((t) => t.id.equals(entry.id))).write(
        ModelsCompanion(
          isDownloaded: const drift.Value(true),
          localPath: drift.Value(path),
          downloadedAt: drift.Value(copy.downloadedAt ?? DateTime.now()),
          projectorJson: drift.Value(copy.projectorJson),
        ),
      );
      await db.deleteModel(copy.id);
      await _moveModelId(copy.id, entry.id);
    }
  }

  /// A finished GGUF in the models folder with no row (a Hub download whose
  /// row was lost, a file copied in by hand) is listed again rather than
  /// taking disk space unseen. Hub files keep their `hf-<hash>` id; a
  /// projector of the same stem is paired with it. Header only: no hashing.
  Future<void> _adoptOrphanFiles(AppDatabase db) async {
    if (!DesktopHost.active) return;
    final rows = await db.allModels();
    final known = <String>{
      for (final r in rows) r.fileName.toLowerCase(),
      for (final r in rows)
        if (r.localPath != null) p.basename(r.localPath!).toLowerCase(),
      for (final r in rows)
        if (_fromRow(r).projector != null)
          _fromRow(r).projector!.fileName.toLowerCase(),
      for (final v in visionProjectors.values) v.fileName.toLowerCase(),
      embeddingModel.fileName.toLowerCase(),
      if (embeddingModel.projector != null)
        embeddingModel.projector!.fileName.toLowerCase(),
      supportCheckModel.fileName.toLowerCase(),
      for (final m in catalogModels) m.fileName.toLowerCase(),
    };
    final List<File> files;
    try {
      files = (await ModelStorage.modelsDir())
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.gguf'))
          .where((f) => !known.contains(p.basename(f.path).toLowerCase()))
          .where((f) => !isMtpHeadFile(f.path))
          .where((f) => (GgufSplit.parse(p.basename(f.path))?.index ?? 1) == 1)
          .toList();
    } catch (_) {
      return;
    }
    final hubPrefix = _hubPrefix;
    final stem = _fileStem;
    final projectors = [
      for (final f in files)
        if (p.basename(f.path).toLowerCase().contains('mmproj')) f,
    ];
    for (final file in files) {
      final name = p.basename(file.path);
      if (name.toLowerCase().contains('mmproj')) continue;
      try {
        final parts = await ModelStorage.ggufFilesBeside(file.path);
        var size = 0;
        for (final part in parts) {
          size += await part.length();
        }
        final metadata = await GgufMetadata.inspect(file.path);
        final hub = hubPrefix.firstMatch(name);
        final projector = projectors
            .where((f) => stem(p.basename(f.path)) == stem(name))
            .firstOrNull;
        final info = ModelInfo(
          id: hub != null ? 'hf-${hub.group(1)}' : 'local-${stem(name)}',
          displayName: ModelQuantization.tidyName(
            GgufSplit.parse(hub?.group(2) ?? name)?.displayName ??
                hub?.group(2) ??
                name,
          ),
          fileName: name,
          sizeBytes: size,
          family:
              _familyFromArchitecture(metadata.architecture) ??
              ModelFamily.other,
          quantization: ModelQuantization.of(name),
          parameterCountB:
              metadata.parameterCount == null ||
                  metadata.parameterCount! < 500000000
              ? null
              : (metadata.parameterCount! / 1000000000).round(),
          license: 'Found in the models folder · check publisher license',
          projector: projector == null
              ? null
              : VisionProjector(
                  fileName: p.basename(projector.path),
                  downloadUrl: '',
                  sha256: '',
                  sizeBytes: await projector.length(),
                ),
        );
        if (await db.getModel(info.id) != null) continue;
        await save(info, localPath: file.path);
      } catch (_) {
        // Not a readable GGUF (still being copied, or another tool's file).
      }
    }
    await refreshVision();
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
      // The voice packs and image models resume through their own providers.
      if (id.startsWith('voice:') || id.startsWith('image-gen:')) continue;
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
            (model.projector ?? visionProjectors[modelId]) == null ||
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
          // A job left behind by a finished download can leave its
          // abandoned .part (gigabytes) beside the verified file.
          if (model?.localPath case final path? when model!.isDownloaded) {
            await DownloadManager.dropStalePart(File(path));
          }
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
    void Function()? onLoadStart,
    bool vision = false,
  }) async {
    if (state.isLoadingModel || (ref.read(sessionBusyProvider) && !forChat)) {
      throw StateError(
        stringsFor(ref.read(settingsProvider).localeCode).modelStopSwitch,
      );
    }
    if (!info.isDownloaded || info.localPath == null) {
      throw StateError(
        stringsFor(ref.read(settingsProvider).localeCode).modelDownloadFirst,
      );
    }
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
            if (ref.read(currentProjectProvider)?.collection.isNotEmpty == true)
              'knowledgeCollection': ref
                  .read(currentProjectProvider)!
                  .collection,
          },
          projectLabel: ref.read(currentProjectProvider)?.name ?? 'Project',
        ).effective;
    // Every local send asks for its model: when the engine already holds
    // it with the same settings, nothing is loaded and the chat never
    // shows "loading" (audit P1-18, owner report OR-01).
    ({String path, String config})? unchanged;
    if (info.id != diffusionGemmaModelId && state.loadedModelId == info.id) {
      try {
        final plan = await _plan(info, resolved, vision: vision);
        if (state.loadedModelId == info.id &&
            !state.isLoadingModel &&
            ref.read(llamaEngineProvider).holdsLoad(plan.path, plan.config)) {
          unchanged = (path: plan.path, config: plan.config);
        }
      } catch (_) {
        // The full load below reports it.
      }
    }
    if (unchanged != null) {
      // The server pool can borrow this runtime even when the primary
      // server has its own engine. Reuse must also await that handoff
      // (owner P2-05 re-trace, 2026-11-01).
      await ref.read(engineHandoffProvider)?.call(info.id);
      if (state.loadedModelId == info.id &&
          !state.isLoadingModel &&
          ref
              .read(llamaEngineProvider)
              .holdsLoad(unchanged.path, unchanged.config)) {
        return;
      }
    }
    if (state.isLoadingModel) {
      throw StateError(
        stringsFor(ref.read(settingsProvider).localeCode).modelStopSwitch,
      );
    }
    _loadStopped = false;
    onLoadStart?.call();
    state = state.copyWith(
      isLoadingModel: true,
      loadingModelId: info.id,
      clearLoadProgress: true,
      clearError: true,
    );
    try {
      _checkStopped();
      // A local server sharing this runtime keeps its model on its own.
      await ref.read(engineHandoffProvider)?.call(info.id);
      final engine = ref.read(llamaEngineProvider);
      if (info.id == diffusionGemmaModelId) {
        if (!DesktopHost.active || !Platform.isWindows) {
          throw UnsupportedError('DiffusionGemma requires Windows desktop.');
        }
        await engine.unload();
        await ref.read(diffusionGemmaEngineProvider).loadModel(info.localPath!);
        if (_alive) {
          state = state.copyWith(
            loadedModelId: info.id,
            isLoadingModel: false,
            clearLoadingModel: true,
            clearLoadProgress: true,
          );
        }
        return;
      }
      ref.read(diffusionGemmaEngineProvider).dispose();
      _checkStopped();
      final loads = engine.loadCount;
      double? pendingProgress;
      _loadSubscription = engine.loadProgressChanges.listen((value) {
        pendingProgress = value;
        _loadProgressTimer ??= Timer(const Duration(milliseconds: 100), () {
          _loadProgressTimer = null;
          if (_alive &&
              state.isLoadingModel &&
              state.loadProgress != pendingProgress) {
            state = state.copyWith(
              loadProgress: pendingProgress,
              clearLoadProgress: pendingProgress == null,
            );
          }
        });
      });
      engine.loadStop = () => _loadStopped;
      try {
        _chatLoad = await _loadOn(engine, info, resolved, vision: vision);
      } finally {
        engine.loadStop = null;
      }
      if (_alive) {
        state = state.copyWith(
          loadedModelId: info.id,
          isLoadingModel: false,
          clearLoadingModel: true,
          clearLoadProgress: true,
        );
        if (engine.loadCount != loads) {
          _noteContextCap(engine.metrics);
          if (DesktopHost.active) {
            unawaited(
              Future(() async {
                if (_alive && ref.mounted) {
                  await ref.read(chatProvider.notifier).primeLoadedModel(info);
                }
              }),
            );
          }
        }
      }
    } catch (e, st) {
      // A Stop is the user's choice, not an error to show.
      final stopped = _loadStopped || e is ModelLoadStopped;
      final memory = stopped ? null : _memoryError(e);
      if (_alive) {
        state = state.copyWith(
          isLoadingModel: false,
          clearLoadingModel: true,
          clearLoadProgress: true,
          clearLoaded: true,
          error: stopped ? null : '${memory ?? e}',
        );
      }
      if (stopped) Error.throwWithStackTrace(const ModelLoadStopped(), st);
      if (memory != null) Error.throwWithStackTrace(memory, st);
      rethrow;
    } finally {
      _loadStopped = false;
      _stopLoadProgress();
    }
  }

  bool _loadStopped = false;

  void _checkStopped() {
    if (_loadStopped) throw const ModelLoadStopped();
  }

  /// Stops the chat's model load at any step: before the file is read, while
  /// llama.cpp loads it (its progress callback cancels), or right after
  /// (audit P1-19, owner request OR-02). The chat is left with no model.
  void stopLoad() {
    if (!state.isLoadingModel) return;
    _loadStopped = true;
    ref.read(llamaEngineProvider).cancel();
  }

  ChatLoad? _chatLoad;

  /// What the chat's loaded model was loaded with, so a memory estimate can
  /// count what unloading it frees. Null while none is loaded.
  ChatLoad? get loadedConfig {
    final load = _chatLoad;
    return load != null &&
            !state.isLoadingModel &&
            state.loadedModelId == load.modelId
        ? load
        : null;
  }

  Future<ChatLoad> _loadOn(
    LlamaEngine engine,
    ModelInfo info,
    InferenceSettings resolved, {
    bool vision = false,
  }) async {
    final plan = await _plan(info, resolved, vision: vision);
    await engine.loadModel(
      modelPath: plan.path,
      settings: plan.load.settings,
      mmprojPath: plan.load.mmprojPath,
      adapters: plan.adapters,
      draftModelPath: plan.load.draftModelPath,
    );
    if (plan.missingDraft != null) {
      ref
          .read(islandProvider.notifier)
          .toast(
            'Selected draft "${plan.missingDraft}" is missing or unavailable. The model loaded without that draft.',
            tone: IslandTone.warning,
            icon: Icons.warning_amber_rounded,
            duration: const Duration(seconds: 8),
          );
    }
    return plan.load;
  }

  /// Everything a load of [info] needs, and the engine config it makes, so
  /// a send can tell an unchanged load without starting one. GGUF reads are
  /// cached by file, so this is cheap after the first load.
  Future<
    ({
      String path,
      ChatLoad load,
      List<({String path, double scale})> adapters,
      String config,
      String? missingDraft,
    })
  >
  _plan(
    ModelInfo info,
    InferenceSettings resolved, {
    bool vision = false,
  }) async {
    final projector = info.projector ?? visionProjectors[info.id];
    final draft = draftPathFor(info, resolved.draftModelId);
    final selected = resolved.draftModelId;
    final missingDraft =
        selected.isNotEmpty &&
        selected != '$mtpHeadPrefix$mtpOff' &&
        selected != info.id &&
        draft == null;
    if (draft != null) {
      final metadata = await GgufMetadata.inspect(draft);
      if (metadata.isMtpOnly) {
        final target = await GgufMetadata.inspect(info.localPath!);
        final issue = metadata.mtpHeadIssueFor(
          target,
          strings: stringsFor(ref.read(settingsProvider).localeCode),
        );
        if (issue != null) throw StateError(issue);
      }
    }
    // A head found on its own drafts 2 tokens a step: the best measured
    // with real sampling (2026-10-28, E4B Q8 on a 3070: 80-88 tok/s vs
    // 61 without the head; 3 or more drafts were slower).
    if (draft != null &&
        resolved.draftModelId.isEmpty &&
        resolved.draftMaxTokens == const InferenceSettings().draftMaxTokens) {
      resolved = resolved.copyWith(draftMaxTokens: 2);
    }
    final settings = await _resolveBackend(resolved);
    // The projector loads for a chat with a photo ([vision]) and then stays
    // while the model is loaded, so later turns do not reload; a model
    // whose vision is off never loads it (owner, 2026-11-01).
    final current = _chatLoad;
    final keep =
        current != null &&
        current.modelId == info.id &&
        current.mmprojPath != null &&
        state.loadedModelId == info.id;
    final mmproj =
        projector != null &&
            state.vision.contains(info.id) &&
            resolved.visionEnabled &&
            (vision || keep)
        ? (await ModelStorage.modelFile(projector.fileName)).path
        : null;
    final adapters = await ref
        .read(adaptersProvider.notifier)
        .resolved(info.id);
    return (
      path: info.localPath!,
      load: (
        modelId: info.id,
        modelPath: info.localPath!,
        settings: settings,
        mmprojPath: mmproj,
        draftModelPath: draft,
      ),
      adapters: adapters,
      config: LlamaEngine.loadConfig(
        settings: settings,
        mmprojPath: mmproj,
        adapters: adapters,
        draftModelPath: draft,
      ),
      missingDraft: missingDraft ? selected : null,
    );
  }

  /// What the local server answers [info]'s requests with: its model
  /// profile over the app's settings (no chat or project layers: the server
  /// has no chat).
  InferenceSettings servedSettings(ModelInfo info) => resolveSettings(
    global: ref.read(settingsProvider),
    defaults: ref.read(settingsProvider.notifier).defaults,
    profiles: ref.read(modelProfilesProvider),
    preset: ref.read(presetsProvider).active,
    chat: const {},
    recommendations: ref.read(modelRecommendationsProvider),
    model: info,
  ).effective;

  /// Loads [info] on the local server's own [engine] with its model
  /// profile (no chat or project layers: the server has no chat). The
  /// manager's own state stays about the chat's model.
  Future<void> loadServed(
    ModelInfo info,
    LlamaEngine engine, {
    bool vision = false,
  }) async {
    if (info.id == diffusionGemmaModelId) {
      throw UnsupportedError(
        'DiffusionGemma runs in desktop chat only; local server hosting is unavailable.',
      );
    }
    if (!info.isDownloaded || info.localPath == null) {
      throw StateError(
        stringsFor(ref.read(settingsProvider).localeCode).modelDownloadFirst,
      );
    }
    try {
      // A text-only server load leaves the projector out. The server's first
      // photo request calls this with vision:true under its model admission.
      await _loadOn(engine, info, servedSettings(info), vision: vision);
    } catch (e, st) {
      final memory = _memoryError(e);
      if (memory != null) Error.throwWithStackTrace(memory, st);
      rethrow;
    }
  }

  void _stopLoadProgress() {
    unawaited(_loadSubscription?.cancel());
    _loadSubscription = null;
    _loadProgressTimer?.cancel();
    _loadProgressTimer = null;
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
  /// catalog entry (never the model itself), or an MTP head file
  /// (`mtp:<path>`). Null turns speculation off.
  /// On the desktop an empty id is Auto: the matching MTP head, when one
  /// is on disk ([autoMtpHead]); `mtp:off` turns it off.
  String? draftPathFor(ModelInfo info, String draftModelId) {
    if (draftModelId.isEmpty) {
      final path = info.localPath;
      return DesktopHost.active && path != null ? autoMtpHead(path) : null;
    }
    if (draftModelId == info.id) return null;
    if (draftModelId.startsWith(mtpHeadPrefix)) {
      final path = draftModelId.substring(mtpHeadPrefix.length);
      return path != mtpOff && File(path).existsSync() ? path : null;
    }
    final draft = state.catalog.where((m) => m.id == draftModelId).firstOrNull;
    if (draft == null || !draft.isDownloaded || draft.localPath == null) {
      return null;
    }
    return File(draft.localPath!).existsSync() ? draft.localPath : null;
  }

  /// Auto is the compatibility/per-answer-speed policy: CPU. Accelerators
  /// remain explicit because changing backend reloads the model and OpenCL's
  /// faster prompt reading trades against slower answer decoding. On
  /// Windows a discrete GPU wins at both, so the bridge chooses there.
  bool _autoCpu = false;

  Future<InferenceSettings> _resolveBackend(InferenceSettings s) async {
    _autoCpu = s.backend == GpuBackend.auto && !DesktopHost.active;
    return _autoCpu ? s.copyWith(backend: GpuBackend.cpu) : s;
  }

  /// Why the running backend differs from the setting, for the panel.
  String? get backendChoice => _autoCpu
      ? 'Automatic resolved to CPU. OpenCL is explicit because it reads research prompts about 2x faster but decodes answers about 15% slower (measured).'
      : null;

  /// Releases the model's memory without leaving the chat. The next message
  /// loads it again.
  /// [ownsBusy]: the caller set the session busy itself (a tuning run) and
  /// unloads between its own loads.
  Future<void> unloadModel({bool ownsBusy = false}) async {
    if (state.isLoadingModel || (!ownsBusy && ref.read(sessionBusyProvider))) {
      throw StateError(
        stringsFor(ref.read(settingsProvider).localeCode).modelStopUnload,
      );
    }
    // The local server may share this runtime: its model moves to its own
    // first, so ejecting the chat's model does not stop the server's.
    await ref.read(engineHandoffProvider)?.call('');
    await ref.read(helperRunnerProvider).unload();
    await ref.read(llamaEngineProvider).unload();
    ref.read(diffusionGemmaEngineProvider).dispose();
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
    if (_subscriptions.containsKey(info.id)) return;
    if (info.isDownloaded) {
      if (info.projector != null) await downloadVision(info);
      return;
    }
    state = state.copyWith(
      clearError: true,
      preparing: {...state.preparing, info.id},
    );
    _subscriptions[info.id] = _downloader.progressStream(info.id).listen((p) {
      if (_alive) {
        state = state.copyWith(downloads: {...state.downloads, info.id: p});
      }
    });
    try {
      final existing = await ModelStorage.modelFile(info.fileName);
      final finished =
          info.parts.isEmpty &&
          await existing.exists() &&
          await existing.length() == info.sizeBytes;
      if (finished && _alive) {
        // Hashing a finished multi-GB file takes minutes: say so.
        state = state.copyWith(
          downloads: {
            ...state.downloads,
            info.id: DownloadProgress(
              modelId: info.id,
              status: DownloadStatus.verifying,
              received: info.sizeBytes,
              total: info.sizeBytes,
            ),
          },
        );
      }
      if (finished &&
          await ModelStorage.validateAndHash(existing.path) == info.sha256) {
        await DownloadManager.dropStalePart(existing);
        await _downloader.pause(info.id);
        await save(info, localPath: existing.path);
        await DownloadJobs.remove(info.id);
        if (_alive) {
          state = state.copyWith(
            downloads: {...state.downloads}..remove(info.id),
          );
        }
        await _learnSampling(info.copyWith(localPath: existing.path));
        if (info.projector != null) await downloadVision(info);
        return;
      }
      await DownloadJobs.add(info.id);
      if (info.parts.isNotEmpty) {
        await _downloader.downloadFiles(modelId: info.id, files: info.parts);
      } else {
        await _downloader.download(
          modelId: info.id,
          url: info.downloadUrl!,
          fileName: info.fileName,
          expectedSha256: info.sha256!,
          expectedSize: info.sizeBytes,
        );
      }
      final file = await ModelStorage.modelFile(info.fileName);
      await save(info, localPath: file.path);
      await DownloadJobs.remove(info.id);
      await _learnSampling(info.copyWith(localPath: file.path), hub: true);
      if (info.projector != null) await downloadVision(info);
    } catch (e) {
      if (_alive && !(e is DioException && CancelToken.isCancel(e))) {
        state = state.copyWith(error: '$e');
      }
    } finally {
      await _subscriptions.remove(info.id)?.cancel();
      if (_alive) {
        state = state.copyWith(
          preparing: {...state.preparing}..remove(info.id),
        );
      }
    }
  }

  Future<void> pauseDownload(String id) async {
    await DownloadJobs.remove(id);
    await _downloader.pause(id);
    if (!id.endsWith(':vision')) {
      await DownloadJobs.remove(ModelManagerState.visionKey(id));
      await _downloader.pause(ModelManagerState.visionKey(id));
    }
  }

  Future<void> cancelDownload(String id) async {
    await pauseDownload(id);
    final modelId = id.replaceFirst(RegExp(r':vision$'), '');
    final model = state.catalog.where((m) => m.id == modelId).firstOrNull;
    if (model != null) {
      if (!id.endsWith(':vision')) {
        for (final name
            in model.parts.isEmpty
                ? [model.fileName]
                : model.parts.map((p) => p.fileName)) {
          await ModelStorage.deletePartial(name);
        }
      }
      final projector = model.projector ?? visionProjectors[model.id];
      if (projector != null) {
        await ModelStorage.deletePartial(projector.fileName);
      }
    }
    await DownloadHistory.cancelled(id);
    if (_alive) {
      state = state.copyWith(downloads: {...state.downloads}..remove(id));
    }
  }

  /// Which catalog models can see photos right now (projector on disk),
  /// and whether the knowledge library's embedding model is present.
  Future<void> refreshVision() async {
    final ready = <String>{};
    final rows = await ref.read(appDatabaseProvider).allModels();
    final projectors = {
      ...visionProjectors,
      for (final row in rows)
        if (_fromRow(row).projector != null) row.id: _fromRow(row).projector!,
    };
    for (final e in projectors.entries) {
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
          final guard = _guardModelPaths([
            (await ModelStorage.modelFile(name)).path,
          ]);
          try {
            await ModelStorage.delete(name);
          } finally {
            guard.release();
          }
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
    await ref.read(embeddingEngineProvider).unload();
    final guard = _guardModelPaths([
      (await ModelStorage.modelFile(projector.fileName)).path,
    ]);
    try {
      await DownloadJobs.remove(ModelManagerState.embeddingMediaKey);
      await ModelStorage.delete(projector.fileName);
      await refreshVision();
    } finally {
      guard.release();
    }
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
    await ref.read(supportEngineProvider).unload();
    final guard = _guardModelPaths([
      (await ModelStorage.modelFile(supportCheckModel.fileName)).path,
    ]);
    try {
      await DownloadJobs.remove(ModelManagerState.supportCheckKey);
      await ModelStorage.delete(supportCheckModel.fileName);
      await refreshVision();
    } finally {
      guard.release();
    }
  }

  Future<void> deleteEmbedding() async {
    await ref.read(embeddingEngineProvider).unload();
    final guard = _guardModelPaths([
      (await ModelStorage.modelFile(embeddingModel.fileName)).path,
    ]);
    try {
      await DownloadJobs.remove(ModelManagerState.embeddingKey);
      await ModelStorage.delete(embeddingModel.fileName);
      await refreshVision();
    } finally {
      guard.release();
    }
  }

  /// Fetches the model's vision projector so photos can be attached.
  Future<void> downloadVision(ModelInfo info) async {
    final projector = info.projector ?? visionProjectors[info.id];
    if (projector == null) return;
    final pending = _projectorDownloads[projector.fileName];
    if (pending != null) {
      await pending;
      await refreshVision();
      return;
    }
    final work = _downloadVision(info);
    _projectorDownloads[projector.fileName] = work;
    try {
      await work;
    } finally {
      unawaited(_projectorDownloads.remove(projector.fileName));
    }
  }

  Future<void> _downloadVision(ModelInfo info) async {
    final projector = (info.projector ?? visionProjectors[info.id]);
    if (projector == null) return;
    final key = ModelManagerState.visionKey(info.id);
    if (_subscriptions.containsKey(key) || state.vision.contains(info.id)) {
      return;
    }
    final existing = await ModelStorage.modelFile(projector.fileName);
    if (await existing.exists() &&
        await existing.length() == projector.sizeBytes &&
        await ModelStorage.validateAndHash(existing.path) == projector.sha256) {
      await refreshVision();
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
    final projector = info.projector ?? visionProjectors[info.id];
    if (projector == null) return;
    if (state.loadedModelId == info.id) await unloadModel();
    final guard = _guardModelPaths([
      (await ModelStorage.modelFile(projector.fileName)).path,
    ]);
    try {
      await _deleteVisionFiles(info);
    } finally {
      guard.release();
    }
  }

  Future<void> _deleteVisionFiles(ModelInfo info) async {
    final projector = info.projector ?? visionProjectors[info.id];
    if (projector == null) return;
    await DownloadJobs.remove(ModelManagerState.visionKey(info.id));
    final others = await ref.read(appDatabaseProvider).allModels();
    if (!others.any(
      (row) =>
          row.id != info.id &&
          (_fromRow(row).projector ?? visionProjectors[row.id])?.fileName ==
              projector.fileName &&
          (row.isDownloaded || row.projectorJson != null),
    )) {
      await ModelStorage.delete(projector.fileName);
      await ModelStorage.deletePartial(projector.fileName);
    }
    await refreshVision();
  }

  static final _hubPrefix = RegExp(r'^([0-9a-f]{16})-(.+)\.gguf$');

  /// A model or projector file name without its hub prefix, `mmproj` marker
  /// and quantization tag, so a model and its projector compare equal.
  static String _fileStem(String name) {
    name = GgufSplit.parse(name)?.displayName ?? name;
    final base = (_hubPrefix.firstMatch(name)?.group(2) ?? name)
        .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^mmproj-', caseSensitive: false), '')
        .replaceFirst(RegExp(r'-mmproj', caseSensitive: false), '');
    final tag = ModelQuantization.tagOf(base);
    final upper = base.toUpperCase();
    return (tag == null ? upper : upper.substring(0, upper.lastIndexOf(tag)))
        .replaceAll(RegExp(r'[^A-Z0-9]+$'), '');
  }

  /// The vision projector beside an imported model: the one whose name
  /// matches the model's, else the only one in the folder (LM Studio and
  /// Hugging Face keep one model per folder).
  @visibleForTesting
  static File? projectorBeside(String path) {
    final List<File> projectors;
    try {
      projectors = File(path).parent.listSync().whereType<File>().where((f) {
        final name = p.basename(f.path).toLowerCase();
        return name.endsWith('.gguf') && name.contains('mmproj');
      }).toList();
    } catch (_) {
      return null;
    }
    final stem = _fileStem(p.basename(path));
    return projectors
            .where((f) => _fileStem(p.basename(f.path)) == stem)
            .firstOrNull ??
        (projectors.length == 1 ? projectors.single : null);
  }

  Future<void> importFile(String path, ModelFamily family) async {
    while (_fileOperation != null) {
      await _fileOperation!.future;
    }
    if (!_alive) return;
    _fileOperation = Completer<void>();
    state = state.copyWith(isImporting: true, clearError: true);
    File? partial;
    try {
      final sources = await ModelStorage.ggufFilesBeside(path);
      path = sources.first.path;
      final metadata = await GgufMetadata.inspect(path);
      final hashes = <String>[];
      var totalSize = 0;
      for (final source in sources) {
        hashes.add(await ModelStorage.validateAndHash(source.path));
        totalSize += await source.length();
      }
      final hash = hashes.first;
      final id = 'local-${hash.substring(0, 20)}';
      final split = GgufSplit.parse(p.basename(path));
      final names = split == null
          ? ['$id.gguf']
          : [
              for (var i = 1; i <= sources.length; i++)
                split.name(i, prefix: id),
            ];
      final name = names.first;
      final destination = await ModelStorage.modelFile(name);
      final destinations = [
        for (final name in names) File(p.join(destination.parent.path, name)),
      ];
      var requiredBytes = 0;
      for (var i = 0; i < sources.length; i++) {
        if (!await destinations[i].exists()) {
          requiredBytes += await sources[i].length();
        }
      }
      final capacity = await ModelStorage.availableStorage();
      if (capacity != null &&
          requiredBytes > 0 &&
          capacity.availableBytes < requiredBytes + 128 * 1024 * 1024) {
        throw const DownloadException(
          'Not enough free storage to import all model parts.',
        );
      }
      for (var i = 0; i < sources.length; i++) {
        final target = destinations[i];
        if (await target.exists()) {
          if (await ModelStorage.validateAndHash(target.path) != hashes[i]) {
            throw StateError(
              'A different model already exists at ${names[i]}.',
            );
          }
          continue;
        }
        partial = File('${target.path}.part');
        await sources[i].copy(partial.path);
        if (await ModelStorage.validateAndHash(partial.path) != hashes[i]) {
          throw StateError('Import changed while copying. Try again.');
        }
        await ModelStorage.excludeFromICloud(partial);
        await partial.rename(target.path);
        partial = null;
      }
      // A vision model's projector is copied along, so photos work.
      VisionProjector? projector;
      final source = projectorBeside(path);
      if (source != null) {
        final file = await ModelStorage.modelFile('$id-mmproj.gguf');
        if (!await file.exists()) {
          partial = File('${file.path}.part');
          await source.copy(partial.path);
          await partial.rename(file.path);
          partial = null;
        }
        projector = VisionProjector(
          fileName: p.basename(file.path),
          downloadUrl: '',
          sha256: '',
          sizeBytes: await file.length(),
        );
      }
      final info = ModelInfo(
        id: id,
        displayName: metadata.name?.trim().isNotEmpty == true
            ? metadata.name!.trim()
            : p.basenameWithoutExtension(split?.displayName ?? path),
        fileName: name,
        sizeBytes: totalSize,
        family: _familyFromArchitecture(metadata.architecture) ?? family,
        // The header's file type, else the source name (Q8_K_P, MXFP4).
        quantization:
            _quantizationFromFileType(metadata.fileType) !=
                ModelQuantization.unknown
            ? _quantizationFromFileType(metadata.fileType)
            : ModelQuantization.of(p.basename(path)),
        parameterCountB:
            metadata.parameterCount == null ||
                metadata.parameterCount! < 500000000
            ? null
            : (metadata.parameterCount! / 1000000000).round(),
        sha256: hash,
        license: 'Imported file · check publisher license',
        projector: projector,
      );
      await save(info, localPath: destination.path);
      await _learnSampling(info.copyWith(localPath: destination.path));
    } catch (e) {
      if (_alive) state = state.copyWith(error: '$e');
    } finally {
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } finally {
        if (_alive) state = state.copyWith(isImporting: false);
        _fileOperation?.complete();
        _fileOperation = null;
      }
    }
  }

  Future<void> changeModelsFolder(
    Directory target, {
    required bool move,
    void Function(double)? onProgress,
  }) async {
    await ready;
    final activeJobs = await DownloadJobs.active();
    if (state.loadedModelId != null ||
        state.isImporting ||
        state.isLoadingModel ||
        activeJobs.isNotEmpty ||
        _projectorDownloads.isNotEmpty) {
      throw const ModelFolderException(ModelFolderFailure.busy);
    }
    final folders = await ModelStorage.desktopFolders();
    final ModelFileLease guard;
    try {
      guard = ModelFileLeases.instance.beginDirectoryMutation([
        ...folders.roots,
        target.path,
      ]);
    } on StateError {
      throw const ModelFolderException(ModelFolderFailure.busy);
    }
    // Serialize imports and disable the import button while files move.
    state = state.copyWith(isImporting: true);
    _fileOperation = Completer<void>();
    try {
      final db = ref.read(appDatabaseProvider);
      await folders.change(
        target,
        move: move,
        onProgress: onProgress,
        updatePaths: (paths) async {
          await db.transaction(() async {
            for (final entry in paths.entries) {
              await (db.update(db.models)
                    ..where((m) => m.localPath.equals(entry.key)))
                  .write(ModelsCompanion(localPath: drift.Value(entry.value)));
            }
          });
          await _moveHeadChoices(paths);
        },
      );
      _autoMtpCache.clear();
      await refreshVision();
    } finally {
      if (_alive) state = state.copyWith(isImporting: false);
      _fileOperation?.complete();
      _fileOperation = null;
      guard.release();
    }
  }

  /// A hand-picked MTP head (`mtp:<path>`) in the app's settings or a
  /// model's profile follows its file to the new folder (audit P2-18).
  Future<void> _moveHeadChoices(Map<String, String> moved) async {
    String? follow(Object? id) {
      if (id is! String || !id.startsWith(mtpHeadPrefix)) return null;
      final to = moved[id.substring(mtpHeadPrefix.length)];
      return to == null ? null : '$mtpHeadPrefix$to';
    }

    final settings = ref.read(settingsProvider);
    final global = follow(settings.draftModelId);
    if (global != null) {
      await ref
          .read(settingsProvider.notifier)
          .update(settings.copyWith(draftModelId: global));
    }
    final profiles = ref.read(modelProfilesProvider.notifier);
    for (final entry in ref.read(modelProfilesProvider).entries) {
      final head = follow(entry.value['draftModelId']);
      if (head != null) {
        await profiles.set(entry.key, {...entry.value, 'draftModelId': head});
      }
    }
  }

  /// The family llama.cpp's architecture name implies (gemma3n, qwen3moe,
  /// qwen35moe, deepseek32 and the like included), else null: an unlisted
  /// architecture keeps the family the user picked rather than becoming
  /// "other". The embedded chat template decides prompts either way.
  static ModelFamily? _familyFromArchitecture(String? architecture) {
    final arch = architecture?.toLowerCase() ?? '';
    if (arch.contains('embed')) return null;
    for (final (prefix, family) in const [
      ('gemma', ModelFamily.gemma),
      ('qwen', ModelFamily.qwen),
      ('deepseek', ModelFamily.deepseek),
      ('phi', ModelFamily.phi),
      ('llama', ModelFamily.llama),
      ('mistral', ModelFamily.mistral),
      ('mixtral', ModelFamily.mistral),
    ]) {
      if (arch.startsWith(prefix)) return family;
    }
    return null;
  }

  static ModelQuantization _quantizationFromFileType(int? fileType) =>
      switch (fileType) {
        // llama_ftype values; the K and I variants map to the nearest bits.
        0 || 1 || 32 => ModelQuantization.fp16,
        2 => ModelQuantization.q4_0,
        7 => ModelQuantization.q8_0,
        10 || 19 || 20 || 21 || 24 || 28 || 29 || 31 => ModelQuantization.q2_k,
        11 || 12 || 13 || 22 || 23 || 26 || 27 => ModelQuantization.q3_k_m,
        3 || 14 || 15 || 38 => ModelQuantization.q4_k_m,
        8 || 9 || 16 || 17 => ModelQuantization.q5_k_m,
        18 => ModelQuantization.q6_k,
        25 || 30 => ModelQuantization.iq4_nl,
        _ => ModelQuantization.unknown,
      };

  ModelFileLease _guardModelPaths(Iterable<String> paths) =>
      ModelFileLeases.instance.beginMutation(
        [
          for (final path in paths)
            for (final name
                in GgufSplit.parse(p.basename(path))?.names ??
                    [p.basename(path)])
              p.join(p.dirname(path), name),
        ],
        busyMessage: stringsFor(
          ref.read(settingsProvider).localeCode,
        ).modelFilesInUse,
      );

  Future<void> deleteModel(ModelInfo info) async {
    if (ref.read(sessionBusyProvider) ||
        state.isLoadingModel ||
        _subscriptions.containsKey(info.id)) {
      throw StateError(
        stringsFor(ref.read(settingsProvider).localeCode).modelStopDelete,
      );
    }
    if (state.loadedModelId == info.id) await unloadModel();
    final projector = info.projector ?? visionProjectors[info.id];
    final paths = <String>[
      (await ModelStorage.modelFile(info.fileName)).path,
      if (info.localPath != null) info.localPath!,
      if (projector != null)
        (await ModelStorage.modelFile(projector.fileName)).path,
    ];
    final guard = _guardModelPaths(paths);
    try {
      await ref
          .read(retiredModelNamesProvider.notifier)
          .remember(info.id, info.displayName);
      await pauseDownload(info.id);
      await _deleteVisionFiles(info);
      await ModelStorage.deletePartial(info.fileName);
      await ModelStorage.delete(info.fileName);
      final db = ref.read(appDatabaseProvider);
      // Only the bundled catalog keeps an "available to download" row; a model
      // the user added by link, Hub search or import is gone for good.
      if (catalogModels.any((m) => m.id == info.id)) {
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
    } finally {
      guard.release();
    }
  }
}

final modelManagerProvider =
    NotifierProvider<ModelManagerNotifier, ModelManagerState>(
      ModelManagerNotifier.new,
    );

/// The `draftModelId` prefix for an MTP head: a small separate GGUF that
/// drafts from the target's hidden states (Unsloth's
/// `mtp-gemma-4-E4B-it-Q8_0.gguf`). It is a companion file, not a model
/// of its own, so it never joins the catalog.
const mtpHeadPrefix = 'mtp:';

/// The head path that turns Auto off: `mtp:off` names no file, so no head
/// is attached.
const mtpOff = 'off';

/// Whether [path] names an MTP head file: `mtp-*.gguf`, with or without the
/// Hub download's hash prefix.
bool isMtpHeadFile(String path) {
  final name = p.basename(path).toLowerCase();
  return name.endsWith('.gguf') &&
      RegExp(r'^(?:[0-9a-f]{16}-)?mtp-').hasMatch(name);
}

/// The Gemma 4 size an MTP head or model file is for (`e4b`, `12b`,
/// `26b-a4b`, ...), or null for other families. Heads exist only per base
/// size, and a head for another size is refused at load.
String? gemma4Size(String fileName) => RegExp(
  r'gemma-?4-((?:e\d+b)|(?:\d+b(?:-a\d+b)?))',
  caseSensitive: false,
).firstMatch(fileName)?.group(1)?.toLowerCase();

/// Folders searched for an MTP head besides the app's models folder:
/// LM Studio's model folder, where its MTP sidecars usually already are.
List<String> _mtpSearchRoots() {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  return [if (home != null) p.join(home, '.lmstudio', 'models')];
}

/// Found heads and misses by model size and folder. A miss expires after
/// a minute, so a head downloaded later is found, but a send no longer
/// re-lists LM Studio's folders each time (audit P2-34).
final Map<String, ({String? path, DateTime at})> _autoMtpCache = {};

/// The MTP head for the model at [modelPath] found on disk: an
/// `mtp-gemma-4-<size>*.gguf` beside the model, else in LM Studio's model
/// folder (three levels deep). Null when the model has no known head or
/// none is on disk.
String? autoMtpHead(String modelPath) {
  final size = gemma4Size(p.basename(modelPath));
  if (size == null || isMtpHeadFile(modelPath)) return null;
  final key = '$size|${File(modelPath).parent.path}';
  final cached = _autoMtpCache[key];
  if (cached != null) {
    final path = cached.path;
    if (path != null && File(path).existsSync()) return path;
    if (path == null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 1)) {
      return null;
    }
  }
  final found = <String>[];
  void scan(Directory dir, int depth) {
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is File) {
          if (isMtpHeadFile(e.path) && gemma4Size(p.basename(e.path)) == size) {
            found.add(e.path);
          }
        } else if (e is Directory && depth > 0) {
          scan(e, depth - 1);
        }
      }
    } on FileSystemException {
      // Unreadable folder: skip it.
    }
  }

  scan(File(modelPath).parent, 0);
  if (found.isEmpty) {
    for (final root in _mtpSearchRoots()) {
      scan(Directory(root), 3);
    }
  }
  // Prefer the Q8 head (what Unsloth and LM Studio ship), then the smallest.
  found.sort((a, b) {
    final q =
        (b.toLowerCase().contains('q8') ? 1 : 0) -
        (a.toLowerCase().contains('q8') ? 1 : 0);
    return q != 0 ? q : File(a).lengthSync().compareTo(File(b).lengthSync());
  });
  final head = found.firstOrNull;
  _autoMtpCache[key] = (path: head, at: DateTime.now());
  return head;
}

/// The MTP head files in the models folder, by path.
Future<List<String>> mtpHeadFiles() async {
  try {
    return [
      for (final f in (await ModelStorage.modelsDir()).listSync())
        if (f is File && isMtpHeadFile(f.path)) f.path,
    ]..sort();
  } catch (_) {
    return const [];
  }
}
