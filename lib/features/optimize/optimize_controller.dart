import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../inference/engine/engine_registry_provider.dart';
import '../../core/logging/quiet_failure.dart';
import '../../core/platform/device_info.dart';
import '../../core/providers/shared_providers.dart';
import '../../data/storage/model_storage.dart';
import '../adapters/adapter_store.dart';
import '../chat/presentation/providers/chat_provider.dart';
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

/// The whole run's time budget: screening and verification share one
/// deadline, so a slow model cannot screen for longer than it verifies.
final optimizeRunBudgetProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 10),
);

/// The run's clock. Tests advance it to exercise the deadline.
final optimizeClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Whether a chat answer is being written. Optimize must not unload the
/// model under a running turn.
final optimizeGeneratingProvider = Provider<bool Function()>(
  (ref) =>
      () => ref.read(chatProvider).isGenerating,
);

final optimizeControllerProvider =
    NotifierProvider.family<OptimizeController, OptimizeState, String>(
      OptimizeController.new,
    );

enum OptimizeFailure { measurement, save, reload }

/// Why Optimize could not start: the section says so instead of doing
/// nothing, and its button stays disabled meanwhile.
enum OptimizeBusyReason {
  /// This model's run is still going.
  running,

  /// A reply is being written in the chat.
  generating,

  /// The model manager is loading (or stopping) a model.
  loadingModel,

  /// Another model task holds the session (benchmark, goal, comparison).
  otherRun,

  /// The model has no local file to measure.
  notLoaded,
}

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
  final OptimizeBusyReason? busy;
  final OptimizeUnfit? unfit;
  final (double, double)? rates;
  final OptimizeKeepReason? kept;
  final bool saved;
  final String? changes;
  const OptimizeState({
    this.running = false,
    this.progress,
    this.step,
    this.failure,
    this.busy,
    this.unfit,
    this.rates,
    this.kept,
    this.saved = false,
    this.changes,
  });

  OptimizeState copyWith({
    double? progress,
    (int, int)? step,
    OptimizeFailure? failure,
    OptimizeBusyReason? busy,
    OptimizeUnfit? unfit,
    (double, double)? rates,
    OptimizeKeepReason? kept,
    bool? saved,
    String? changes,
  }) => OptimizeState(
    running: running,
    progress: progress?.clamp(0.0, 1.0) ?? this.progress,
    step: step ?? this.step,
    failure: failure ?? this.failure,
    busy: busy ?? this.busy,
    unfit: unfit ?? this.unfit,
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

  /// Whether this controller took the global session lock, so a dispose only
  /// releases a lock it owns.
  bool _holdsBusy = false;

  /// Set with the lock; a dispose releases it without touching `ref` inside
  /// the life-cycle callback (Riverpod forbids using a Ref there).
  void Function()? _releaseBusy;

  @override
  OptimizeState build() {
    ref.onDispose(() {
      final release = _holdsBusy ? _releaseBusy : null;
      final running = _run != null;
      _holdsBusy = false;
      _releaseBusy = null;
      if (!running && release == null) return;
      // Cancelling touches other providers (stopLoad, the session lock) and a
      // life-cycle callback may not use them: do both right after it. A
      // container that is gone makes the calls throw, which is tolerated.
      scheduleMicrotask(() {
        try {
          cancel();
        } catch (e, st) {
          quietFailure('optimize.dispose_cancel', e, st);
        }
        try {
          release?.call();
        } catch (e, st) {
          quietFailure('optimize.dispose_busy', e, st);
        }
      });
    });
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
    final engineDescriptor = ref
        .read(engineRegistryProvider)
        .descriptorFor(model);
    if (!engineDescriptor.capabilities.optimize) return;
    if (_value.running) {
      // The section already shows this run; keep it and its progress.
      _update(_value.copyWith(busy: OptimizeBusyReason.running));
      return;
    }
    final blocked = _blockedReason(model);
    if (blocked != null) {
      // Never return silently: the user pressed Optimize and gets the reason.
      _update(OptimizeState(busy: blocked));
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
    final clock = ref.read(optimizeClockProvider);
    final budget = ref.read(optimizeRunBudgetProvider);
    final original = current;
    final wasLoaded = ref.read(modelManagerProvider).loadedModelId == model.id;
    // A loaded model holds the memory the estimates read as free, so every
    // layer count looked over budget; the estimates below unload it and the
    // run loads the model again at the end with the chat's own settings (or
    // the saved winner).
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
              .resolvedNow(model.id),
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
      // Screening and verification share this one deadline.
      deadline: clock().add(budget),
      now: clock,
      // A cancel must not wait for a multi-gigabyte load to finish.
      stopLoad: manager.stopLoad,
    );
    busy.state = true;
    _holdsBusy = true;
    _releaseBusy = () => busy.state = false;
    _run = runner;
    var finalSettings = original;
    var changed = false;
    // A fresh run shows a fresh state: an old error, rates or result from the
    // previous run must not speak for this one.
    _update(const OptimizeState(running: true, progress: 0));
    try {
      await profiles.ready;
      await global.ready;
      await manager.ready;
      if (runner.cancelled) return;
      final plan = await pcOptimizationPlan(
        current: original,
        defaults: global.defaults,
        estimate: runner.estimate,
        mobile: mobile,
        ios: ios,
        // Planning estimates unload the model per probe: they share the
        // run's deadline instead of spending it before the first sample.
        outOfTime: () => runner.outOfTime,
      );
      if (runner.cancelled) return;
      if (plan.unfit != null) _update(_value.copyWith(unfit: plan.unfit));
      // An estimate that is missing or failing is unknown, not a refusal:
      // measure anyway and skip only what really fails to load, so the run
      // names the real reason.
      final untrusted = !plan.estimateUsable;
      // A usable estimate that places even the safe variants over budget is
      // a fact: loading it anyway can end the process on a phone (no Dart
      // exception to catch), so the run stops and names the short memory.
      if (plan.unfit != null && !untrusted) return;
      final defaults = plan.settings;
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
      final started = clock();
      // Progress also follows the clock, so a slow load or prompt visibly
      // moves the bar instead of leaving it at 0 %.
      void progress(int stage, double part) {
        final measured = (stage + part) / stages / 2;
        final elapsed = budget.inMicroseconds <= 0
            ? 0.0
            : clock().difference(started).inMicroseconds /
                  budget.inMicroseconds;
        _update(
          _value.copyWith(
            progress: math.max(
              _value.progress ?? 0.0,
              math.max(measured, elapsed * 0.9),
            ),
          ),
        );
      }

      progress(0, 0);

      TuneMeasurement? before;
      try {
        // The user's own settings are the reference; when the estimate says
        // they no longer fit, the safe setup becomes it (below).
        if (untrusted || await runner.fits(original.toJson())) {
          before = await runner.benchmark(
            original.toJson(),
            progress: (f) => progress(0, f),
            quick: true,
          );
        }
      } on OptimizeBudgetExhausted {
        // Out of time on the baseline: the current settings cannot be the
        // reference, but the setups below may still be measured.
        before = null;
      } on _OptimizeSaveFailure {
        rethrow;
      } catch (e, st) {
        if (runner.cancelled) return;
        quietFailure('optimize_baseline', e, st);
      }
      if (runner.cancelled) return;
      final measured =
          <({InferenceSettings settings, TuneMeasurement measurement})>[];
      for (var i = 0; i < setups.length; i++) {
        if (runner.cancelled) return;
        _update(_value.copyWith(step: (i + 1, setups.length)));
        try {
          // Only a setup the estimate really places over budget is skipped;
          // an estimate without numbers no longer refuses one.
          if (untrusted || await runner.fits(setups[i].toJson())) {
            final m = await runner.benchmark(
              setups[i].toJson(),
              progress: (f) => progress(i + 1, f),
              quick: true,
            );
            measured.add((settings: setups[i], measurement: m));
          }
        } on OptimizeBudgetExhausted {
          // One deadline for the whole run: stop screening but keep what ran.
          if (measured.isEmpty && before == null) rethrow;
          break;
        } catch (e, st) {
          // Optional setups can be refused by the engine. A failed receipt
          // write ends the scan.
          if (e is _OptimizeSaveFailure) rethrow;
          quietFailure('optimize_setup_$i', e, st);
        }
        progress(i + 1, 1);
      }
      if (runner.cancelled) return;
      if (measured.isEmpty && before == null) {
        throw StateError('No setup measured');
      }
      // The original settings are the equivalence gate. When they do not
      // fit this PC any more (a bigger context, another model loaded on the
      // card), the safe setup (setups[0]: F16 cache, every layer that fits)
      // becomes the reference and is saved even if nothing beats it:
      // settings that cannot load are worse than any setup that ran.
      final unfit = before == null;
      final safe = measured.isEmpty ? null : measured.first;
      final base =
          unfit && safe != null && identical(safe.settings, setups.first)
          ? safe.measurement
          : before;
      if (base == null || base.outputHash.isEmpty) {
        _keep(OptimizeKeepReason.baselineUnavailable);
        return;
      }
      if (measured.isEmpty) {
        // The current settings were measured and nothing else could be: the
        // run compared nothing, so it keeps what is there.
        _keep(OptimizeKeepReason.slower);
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
      final baseline = unfit && safe != null ? safe.settings : original;
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
          _update(
            _value.copyWith(
              progress: math.max(_value.progress ?? 0.0, 0.5 + f / 2),
            ),
          );
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
      // A save needs its own verified samples: one screening sample (or
      // none) never writes a profile.
      final proven = (verified.samples[index] ?? const []).isNotEmpty;
      final faster =
          proven &&
          ((report.status == TuneStatus.complete && index != 0) || unfit);
      final kept = faster
          ? null
          : verified.mismatched
          ? OptimizeKeepReason.outputChanged
          : report.status == TuneStatus.drift
          ? OptimizeKeepReason.noisy
          : OptimizeKeepReason.slower;
      final winner = best, rate = verified.medianTokens(index);
      if (faster) {
        // Only the keys this platform keeps are saved, so a phone never
        // reports a save that sanitization would drop.
        final changes = optimizeProfileChanges(winner);
        if (changes.isEmpty) {
          _keep(OptimizeKeepReason.unsupported);
          return;
        }
        // The model's profile sits above the app-wide settings, so the
        // winner applies without touching other models (audit P1-13).
        await _save(
          () => profiles.set(model.id, {
            ...profiles.of(model.id),
            ...changes,
          }, requirePersistence: true),
        );
        finalSettings = winner;
        changed = true;
        final changesText = [
          for (final entry in changes.entries)
            if (original.toJson()[entry.key] != entry.value)
              '${entry.key}: ${original.toJson()[entry.key]} -> ${entry.value}',
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
      // The benchmark loads the model with each measured setup, so a run that
      // saved nothing (or was cancelled) must put the chat's own settings
      // back before the loaded model is trusted again. Only a load-time
      // setting can linger: the benchmark's sampling is per request. A saved
      // run restores the winner, otherwise the user's settings, in one load.
      final restore = changed ? finalSettings : original;
      if (wasLoaded && !runner.sameLoadAs(restore)) {
        try {
          await manager.loadModel(model, forChat: true, settings: restore);
        } catch (e, st) {
          // Reported, not thrown: the result of the run stands.
          _fail(OptimizeFailure.reload, e, st);
        }
      }
      try {
        // Any completed run marks the model, kept or saved, so its first-run
        // offer and auto-start do not run it again and again.
        if (!runner.cancelled && !_value.failed) {
          await ref
              .read(optimizedModelsProvider.notifier)
              .markOptimized(model.id);
        }
      } catch (e, st) {
        _fail(OptimizeFailure.save, e, st);
      } finally {
        if (ref.mounted) busy.state = false;
        _holdsBusy = false;
        _releaseBusy = null;
        _run = null;
        _update(
          OptimizeState(
            failure: _value.failure,
            unfit: _value.unfit,
            rates: _value.rates,
            kept: _value.kept,
            saved: _value.saved,
            changes: _value.changes,
          ),
        );
      }
    }
  }

  /// Why a run may not start now; null when it may.
  OptimizeBusyReason? _blockedReason(ModelInfo model) {
    if (model.id != modelId || model.localPath == null) {
      return OptimizeBusyReason.notLoaded;
    }
    if (ref.read(modelManagerProvider).isLoadingModel) {
      return OptimizeBusyReason.loadingModel;
    }
    // A turn (or a goal, benchmark or comparison) holds the session. Only
    // then is the chat consulted, so an idle Optimize never touches it.
    if (!ref.read(sessionBusyProvider)) return null;
    return ref.read(optimizeGeneratingProvider)()
        ? OptimizeBusyReason.generating
        : OptimizeBusyReason.otherRun;
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
