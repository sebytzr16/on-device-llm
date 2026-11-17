import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/shared_providers.dart';
import '../../core/logging/quiet_failure.dart';
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

final optimizeMobileProvider = Provider<bool>((ref) => Platform.isAndroid);
final optimizeControllerProvider =
    NotifierProvider.family<OptimizeController, OptimizeState, String>(
      OptimizeController.new,
    );

class OptimizeState {
  final bool running;
  final double? progress;
  final (int, int)? step;
  final bool failed;
  final (double, double)? rates;
  final OptimizeKeepReason? kept;
  final bool saved;
  final String? changes;
  const OptimizeState({
    this.running = false,
    this.progress,
    this.step,
    this.failed = false,
    this.rates,
    this.kept,
    this.saved = false,
    this.changes,
  });

  OptimizeState copyWith({
    double? progress,
    (int, int)? step,
    bool? failed,
    (double, double)? rates,
    OptimizeKeepReason? kept,
    bool? saved,
    String? changes,
  }) => OptimizeState(
    running: running,
    progress: progress?.clamp(0.0, 1.0) ?? this.progress,
    step: step ?? this.step,
    failed: failed ?? this.failed,
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
        return estimator.estimate(
          modelPath: model.localPath!,
          settings: s,
          mmprojPath: mmproj,
          adapters: await ref
              .read(adaptersProvider.notifier)
              .resolved(model.id),
          draftModelPath: await manager.draftPathFor(model, s.draftModelId),
        );
      },
      save: receipts.save,
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
        mobile: ref.read(optimizeMobileProvider),
      );
      if (runner.cancelled) return;
      final mobile = ref.read(optimizeMobileProvider);
      final setups = pcOptimizationSetups(
        defaults,
        mobile: mobile,
        mtpHead: await autoMtpHead(model.localPath!) != null,
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
        if (await runner.fits(setups[i].toJson())) {
          try {
            final m = await runner.benchmark(
              setups[i].toJson(),
              progress: (f) => progress(i + 1, f),
              quick: true,
            );
            measured.add((settings: setups[i], measurement: m));
          } catch (e, st) {
            // A setup the engine refuses (a draft whose vocabulary does not
            // match, say) is skipped; the first is the baseline and must run.
            if (i == 0) rethrow;
            quietFailure('optimize_setup_$i', e, st);
          }
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
        await profiles.set(model.id, {...profiles.of(model.id), ...changes});
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
    } catch (_) {
      if (!runner.cancelled) _update(_value.copyWith(failed: true));
    } finally {
      try {
        await manager.loadModel(model, forChat: true, settings: finalSettings);
      } catch (_) {
        _update(_value.copyWith(failed: true));
      }
      try {
        if (!runner.cancelled &&
            !_value.failed &&
            (_value.saved || _value.kept != null)) {
          await ref
              .read(optimizedModelsProvider.notifier)
              .markOptimized(model.id);
        }
      } catch (_) {
        _update(_value.copyWith(failed: true));
      } finally {
        if (ref.mounted) busy.state = false;
        _run = null;
        _update(
          OptimizeState(
            failed: _value.failed,
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

  void cancel() => _run?.cancel();
}
