import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/logging/quiet_failure.dart';
import '../../core/platform/device_info.dart';
import '../../core/providers/shared_providers.dart';
import '../../data/storage/model_storage.dart';
import '../adapters/adapter_store.dart';
import '../models/domain/entities/model_catalog.dart';
import '../models/domain/entities/model_info.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../settings/presentation/providers/model_profiles_provider.dart';
import '../settings/presentation/providers/settings_provider.dart';
import 'benchmark_receipt.dart';
import 'model_speed_engine_provider.dart';
import 'model_tuner.dart';
import 'optimize_setups.dart';
import 'optimized_models_provider.dart';
import 'tune_benchmark_run.dart';

final _log = Logger('optimize');

final optimizeIosProvider = Provider<bool>((ref) => Platform.isIOS);
final optimizeMobileProvider = Provider<bool>(
  (ref) => Platform.isAndroid || ref.watch(optimizeIosProvider),
);
final optimizeDeviceMemoryProvider = Provider<Future<DeviceMemory?> Function()>(
  (ref) => DeviceMemory.read,
);
final optimizeControllerProvider =
    NotifierProvider.family<OptimizeController, OptimizeState, String>(
      OptimizeController.new,
    );

enum OptimizeFailure { measurement, save, reload }

class _OptimizeSaveFailure implements Exception {
  const _OptimizeSaveFailure(this.cause);
  final Object cause;
}

class OptimizeState {
  final bool running;
  final double? progress;
  final (int, int)? step;
  final OptimizeFailure? failure;
  bool get failed => failure != null;
  final (double, double)? rates;
  final OptimizeKeepReason? kept;
  final bool saved;
  final String? changes;
  const OptimizeState({
    this.running = false,
    this.progress,
    this.step,
    this.failure,
    this.rates,
    this.kept,
    this.saved = false,
    this.changes,
  });

  OptimizeState copyWith({
    double? progress,
    (int, int)? step,
    OptimizeFailure? failure,
    (double, double)? rates,
    OptimizeKeepReason? kept,
    bool? saved,
    String? changes,
  }) => OptimizeState(
    running: running,
    progress: progress?.clamp(0.0, 1.0) ?? this.progress,
    step: step ?? this.step,
    failure: failure ?? this.failure,
    rates: rates ?? this.rates,
    kept: kept ?? this.kept,
    saved: saved ?? this.saved,
    changes: changes ?? this.changes,
  );
}

class OptimizeController extends Notifier<OptimizeState> {
  final String modelId;
  OptimizeController(this.modelId);
  TuneBenchmarkRun? _run;
  OptimizeState _value = const OptimizeState();
  @override
  OptimizeState build() {
    ref.onDispose(cancel);
    return const OptimizeState();
  }

  void _update(OptimizeState next) {
    _value = next;
    if (ref.mounted) state = next;
  }

  Future<void> start(
    ModelInfo model,
    InferenceSettings current, {
    void Function(Map<String, Object?>)? onTuned,
  }) async {
    if (_value.running ||
        model.id != modelId ||
        model.localPath == null ||
        ref.read(sessionBusyProvider) ||
        ref.read(modelManagerProvider).isLoadingModel) {
      return;
    }
    final busy = ref.read(sessionBusyProvider.notifier);
    final manager = ref.read(modelManagerProvider.notifier);
    final profiles = ref.read(modelProfilesProvider.notifier);
    final global = ref.read(settingsProvider.notifier);
    final receipts = ref.read(benchmarkReceiptsProvider.notifier);
    final estimator = ref.read(llamaEstimatorProvider);
    final mobile = ref.read(optimizeMobileProvider);
    final ios = mobile && ref.read(optimizeIosProvider);
    final readMemory = ref.read(optimizeDeviceMemoryProvider);
    final original = current;
    // A loaded model holds the memory the estimates read as free, so every
    // layer count looked over budget; the estimates below unload it and the
    // run loads the model again at the end.
    final runner = TuneBenchmarkRun(
      engine: ref.read(modelSpeedEngineProvider),
      model: model,
      load: (s) => manager.loadModel(model, forChat: true, settings: s),
      estimate: (s) async {
        // Each benchmark leaves the model loaded; its memory would read as
        // taken and every next setup as over budget. The next load reloads.
        if (ref.read(modelManagerProvider).loadedModelId != null) {
          await manager.unloadModel(ownsBusy: true);
        }
        final projector = model.projector ?? visionProjectors[model.id];
        final mmproj =
            projector != null &&
                ref.read(modelManagerProvider).vision.contains(model.id)
            ? (await ModelStorage.modelFile(projector.fileName)).path
            : null;
        final estimate = await estimator.estimate(
          modelPath: model.localPath!,
          // Native Auto can select Metal, while the phone model loader
          // resolves Auto to CPU.
          settings: ios && s.backend == GpuBackend.auto
              ? s.copyWith(backend: GpuBackend.cpu)
              : s,
          mmprojPath: mmproj,
          adapters: await ref
              .read(adaptersProvider.notifier)
              .resolved(model.id),
          draftModelPath: s.speculationMode == 'off'
              ? null
              : await manager.draftPathFor(model, s.draftModelId),
        );
        if (ios && (estimate['ramAvailableMb'] as num? ?? 0) <= 0) {
          // The bridge's /proc memory probe is unavailable on iOS. Query
          // the process budget after unloading, for each estimate.
          final memory = await readMemory();
          if (memory == null) {
            throw StateError('iOS process memory budget unavailable');
          }
          final available = memory.availableBytes >> 20;
          return {
            ...estimate,
            'ramAvailableMb': available,
            'ramTotalMb': memory.totalBytes >> 20,
            // Leave headroom for allocations outside the native estimate.
            'ramBudgetMb': (available - 256).clamp(0, available),
          };
        }
        return estimate;
      },
      save: (receipt) => _save(() => receipts.save(receipt)),
    );
    busy.state = true;
    _run = runner;
    _update(const OptimizeState(running: true, progress: 0));
    var finalSettings = original;
    try {
      await profiles.ready;
      await global.ready;
      await manager.ready;
      if (runner.cancelled) return;
      final defaults = await pcOptimizationDefaults(
        current: original,
        defaults: global.defaults,
        estimate: runner.estimate,
        mobile: mobile,
        ios: ios,
      );
      if (runner.cancelled) return;
      final setups = pcOptimizationSetups(
        defaults,
        mobile: mobile,
        ios: ios,
        mtpHead: !ios && await autoMtpHead(model.localPath!) != null,
        userDraft: mobile
            ? ''
            : original.draftModelId.isNotEmpty
            ? original.draftModelId
            : matchingDraftOnDisk(
                    model,
                    ref.read(modelManagerProvider).catalog,
                  )?.id ??
                  '',
        userSpeculationMode: original.draftModelId.isNotEmpty
            ? original.speculationMode
            : 'draft',
        cpuMoe: mobile
            ? const []
            : await moeExpertPlacements(defaults, estimate: runner.estimate),
      );
      // Screening gets half the bar; verified interleaved rounds get half.
      final stages = setups.length + 1;
      void progress(int stage, double part) {
        _update(_value.copyWith(progress: (stage + part) / stages / 2));
      }

      final before = await runner.fits(original.toJson())
          ? await runner.benchmark(
              original.toJson(),
              progress: (f) => progress(0, f),
              quick: true,
            )
          : null;
      if (runner.cancelled) return;
      final measured =
          <({InferenceSettings settings, TuneMeasurement measurement})>[];
      for (var i = 0; i < setups.length; i++) {
        if (runner.cancelled) return;
        _update(_value.copyWith(step: (i + 1, setups.length)));
        try {
          if (await runner.fits(setups[i].toJson())) {
            final m = await runner.benchmark(
              setups[i].toJson(),
              progress: (f) => progress(i + 1, f),
              quick: true,
            );
            measured.add((settings: setups[i], measurement: m));
          }
        } catch (e, st) {
          // Optional setups can be refused by the engine. A failed baseline
          // or receipt write ends the scan.
          if (i == 0 || e is _OptimizeSaveFailure) rethrow;
          quietFailure('optimize_setup_$i', e, st);
        }
        progress(i + 1, 1);
      }
      if (runner.cancelled) return;
      if (measured.isEmpty) throw StateError('No setup measured');
      // The original settings are the equivalence gate. When they do not
      // fit this PC any more (a bigger context, another model loaded on the
      // card), the safe setup (setups[0]: F16 cache, every layer that fits)
      // becomes the reference and is saved even if nothing beats it:
      // settings that cannot load are worse than any setup that ran.
      final unfit = before == null;
      final safe = measured.first;
      final base = unfit && identical(safe.settings, setups.first)
          ? safe.measurement
          : before;
      if (base == null || base.outputHash.isEmpty) {
        _keep(OptimizeKeepReason.baselineUnavailable);
        return;
      }
      final picked = pickOptimizeWinner(
        reference: base.outputHash,
        baseline: base,
        runs: measured,
      );
      if (picked == null) {
        _keep(OptimizeKeepReason.outputChanged);
        return;
      }
      final reference = base.outputHash;
      // Bound verification to the two best equivalent finalists. No single
      // screening sample, including the default setup, can authorize a save.
      final finalists =
          measured
              .where((r) => optimizeOutputAcceptable(base, r.measurement))
              .toList()
            ..sort(
              (a, b) => optimizeRate(
                b.measurement,
              ).compareTo(optimizeRate(a.measurement)),
            );
      final baseline = unfit ? safe.settings : original;
      final verified = OptimizeRunner(
        runner,
        [
          baseline,
          ...finalists
              .where((r) => !identical(r.settings, baseline))
              .take(2)
              .map((r) => r.settings),
        ],
        reference,
        (f) {
          _update(_value.copyWith(progress: 0.5 + f / 2));
        },
        baseline: base,
      );
      TuneReport report;
      try {
        report = await ModelTuner(verified, endToEnd: true, minimumGain: 0.03)
            .run(
              initial: {'setup': 0},
              candidates: {
                'setup': [for (var i = 1; i < verified.setups.length; i++) i],
              },
            );
      } on OptimizeBudgetExhausted {
        // Out of time before every setup was proven: nothing new is proven
        // faster, so it ends like a noisy run, not an error.
        report = const TuneReport(TuneStatus.drift, [], {});
      }
      if (runner.cancelled) return;
      final index = report.changes['setup'] as int? ?? 0;
      final best = verified.setups[index];
      final faster =
          (report.status == TuneStatus.complete && index != 0) || unfit;
      final kept = faster
          ? null
          : verified.mismatched
          ? OptimizeKeepReason.outputChanged
          : report.status == TuneStatus.drift
          ? OptimizeKeepReason.noisy
          : OptimizeKeepReason.slower;
      final winner = best, rate = verified.medianTokens(index);
      if (faster) {
        final changes = {
          for (final key in pcOptimizationKeys) key: winner.toJson()[key],
          // Null profile values are dropped by sanitization. Save the effective
          // V precision so a global override cannot undo the measured cache.
          'vCacheType': winner.effectiveVCacheType.name,
        };
        // The model's profile sits above the app-wide settings, so the
        // winner applies without touching other models (audit P1-13).
        await _save(
          () => profiles.set(model.id, {
            ...profiles.of(model.id),
            ...changes,
          }, requirePersistence: true),
        );
        finalSettings = winner;
        final changesText = [
          for (final key in pcOptimizationKeys)
            if (original.toJson()[key] != changes[key])
              '$key: ${original.toJson()[key]} -> ${changes[key]}',
        ].join(', ');
        _update(_value.copyWith(changes: changesText, saved: true));
        onTuned?.call(changes);
      }
      _update(
        _value.copyWith(
          rates: (unfit ? 0 : verified.medianTokens(0), rate),
          kept: kept,
        ),
      );
    } on _OptimizeSaveFailure catch (e, st) {
      _fail(OptimizeFailure.save, e.cause, st);
    } catch (e, st) {
      if (!runner.cancelled) _fail(OptimizeFailure.measurement, e, st);
    } finally {
      try {
        await manager.loadModel(model, forChat: true, settings: finalSettings);
      } catch (e, st) {
        _fail(OptimizeFailure.reload, e, st);
      }
      try {
        if (!runner.cancelled &&
            !_value.failed &&
            (_value.saved || _value.kept != null)) {
          await ref
              .read(optimizedModelsProvider.notifier)
              .markOptimized(model.id);
        }
      } catch (e, st) {
        _fail(OptimizeFailure.save, e, st);
      } finally {
        if (ref.mounted) busy.state = false;
        _run = null;
        _update(
          OptimizeState(
            failure: _value.failure,
            rates: _value.rates,
            kept: _value.kept,
            saved: _value.saved,
            changes: _value.changes,
          ),
        );
      }
    }
  }

  void _keep(OptimizeKeepReason reason) =>
      _update(_value.copyWith(kept: reason));

  Future<void> _save(Future<void> Function() write) async {
    try {
      await write();
    } catch (e, st) {
      Error.throwWithStackTrace(_OptimizeSaveFailure(e), st);
    }
  }

  void _fail(OptimizeFailure failure, Object error, StackTrace stack) {
    _log.warning('Optimize ${failure.name} failed for $modelId', error, stack);
    if (!_value.failed) _update(_value.copyWith(failure: failure));
  }

  void cancel() => _run?.cancel();
}
