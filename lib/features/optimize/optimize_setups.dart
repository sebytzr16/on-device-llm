import 'dart:io';
import 'dart:math' as math;

import '../../core/logging/quiet_failure.dart';
import '../../core/platform/cpu_cores.dart';
import '../models/domain/entities/model_info.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../settings/domain/settings_scope.dart';
import 'model_tuner.dart';
import 'tune_benchmark_run.dart';

export 'model_tuner.dart' show OptimizeBudgetExhausted;

const pcOptimizationKeys = {
  'nGpuLayers',
  'kvCacheType',
  'vCacheType',
  'flashAttention',
  'cpuThreads',
  'batchThreads',
  'batchSize',
  'microBatchSize',
  'mtp',
  'speculationMode',
  'draftModelId',
  'draftMaxTokens',
  'draftMinP',
  'draftGpuLayers',
  'offloadKv',
  'nCpuMoe',
  'expertsUsed',
};

Map<String, List<Object>> modelTuneCandidates(InferenceSettings s) => {
  'batchSize': [
    512,
    1024,
  ].where((v) => v >= s.effectiveMicroBatchSize).toList(),
  'cpuThreads': {s.effectiveThreads, 4}.toList(),
};

/// The setups Optimize measures, all with the KV cache of [best]: F16, or
/// q8_0 when only q8_0 puts every layer on the card or F16 cannot fit.
/// With an MTP head, drafting is tried off and at 3 tokens besides Auto's 2:
/// on Gemma 4 26B A4B with experts in RAM, 2 won (20 tok/s), 3 lost (18).
/// A draft model the user picked ([userDraft]) is measured too, against
/// [best] without it (owner 2026-11-12: with and without a draft model).
/// [cpuMoe] are expert placements to try on a mixture-of-experts model
/// whose experts do not all fit on the card ([moeExpertPlacements]).
List<InferenceSettings> pcOptimizationSetups(
  InferenceSettings best, {
  bool? mobile,
  bool? ios,
  int? bigCoreCount,
  bool mtpHead = false,
  String userDraft = '',
  String userSpeculationMode = 'auto',
  List<int> cpuMoe = const [],
}) {
  final iphone = ios ?? Platform.isIOS;
  if (mobile ?? (Platform.isAndroid || iphone)) {
    final big = iphone ? 4 : bigCoreCount ?? CpuCores.androidBig;
    final tryMtp = mtpHead && !iphone;
    // Never carry external drafts or expert placement into a phone sweep.
    final safe = best.copyWith(
      draftModelId: '',
      speculationMode: tryMtp ? 'auto' : 'off',
      mtp: false,
      nCpuMoe: -1,
      expertsUsed: -1,
    );
    return [
      safe,
      if (safe.effectiveThreads != 4) safe.copyWith(cpuThreads: 4),
      if (big != 4 && big != safe.effectiveThreads)
        safe.copyWith(cpuThreads: big),
      if (!iphone || safe.effectiveVCacheType == KvCacheType.fp16)
        safe.copyWith(flashAttention: false),
      for (final size in [256, 512])
        if (safe.batchSize != size)
          safe.copyWith(
            batchSize: size,
            microBatchSize: safe.effectiveMicroBatchSize.clamp(32, size),
          ),
      if (_phoneGpu(safe.backend, ios: iphone) && safe.nGpuLayers > 0)
        safe.copyWith(nGpuLayers: 0),
      if (tryMtp)
        safe.copyWith(
          speculationMode: 'off',
          draftModelId: '$mtpHeadPrefix$mtpOff',
        ),
    ];
  }
  return [
    best,
    if (userDraft.isNotEmpty && !userDraft.startsWith(mtpHeadPrefix))
      best.copyWith(
        draftModelId: userDraft,
        speculationMode: userSpeculationMode,
      ),
    for (final n in cpuMoe) best.copyWith(nCpuMoe: n),
    if (mtpHead) ...[
      best.copyWith(
        speculationMode: 'off',
        draftModelId: '$mtpHeadPrefix$mtpOff',
      ),
      best.copyWith(draftMaxTokens: 3),
    ],
    if (best.effectiveMicroBatchSize <= 1024 && best.batchSize != 1024)
      best.copyWith(batchSize: 1024),
    if (best.effectiveMicroBatchSize != 256 && best.batchSize >= 256)
      best.copyWith(microBatchSize: 256),
    if (best.effectiveBatchThreads != best.effectiveThreads)
      best.copyWith(batchThreads: best.effectiveThreads),
    if (best.effectiveThreads != 4) best.copyWith(cpuThreads: 4),
    best.copyWith(flashAttention: false),
  ];
}

bool _phoneGpu(GpuBackend backend, {required bool ios}) =>
    backend == (ios ? GpuBackend.metal : GpuBackend.opencl);

/// Why Optimize kept the user's current settings instead of saving a setup.
enum OptimizeKeepReason {
  slower,
  outputChanged,
  baselineUnavailable,
  noisy,

  /// The winning settings cannot be stored on this platform (desktop-only
  /// keys on a phone), so nothing was claimed as saved.
  unsupported,
}

/// Allow small greedy decoding differences across kernels and cache types.
/// Compare each prompt separately so a broken answer cannot hide in an average.
bool optimizeOutputAcceptable(TuneMeasurement reference, TuneMeasurement run) {
  if (reference.outputs.isEmpty || run.outputs.isEmpty) {
    return reference.outputHash.isNotEmpty &&
        reference.outputHash == run.outputHash;
  }
  if (reference.outputs.length != run.outputs.length) return false;
  for (var i = 0; i < reference.outputs.length; i++) {
    List<String> tokens(String text) => RegExp(
      r'\w+|[^\s]',
      unicode: true,
    ).allMatches(text.toLowerCase()).map((m) => m.group(0)!).take(96).toList();
    final a = tokens(reference.outputs[i]), b = tokens(run.outputs[i]);
    if (a.isEmpty || b.isEmpty) return false;
    // A common 32-token prefix is enough for the fixed short benchmark answers.
    if (a.length >= 32 &&
        b.length >= 32 &&
        List.generate(32, (j) => a[j] == b[j]).every((v) => v)) {
      continue;
    }
    var previous = List.filled(b.length + 1, 0);
    for (final token in a) {
      final row = List.filled(b.length + 1, 0);
      for (var j = 0; j < b.length; j++) {
        row[j + 1] = token == b[j]
            ? previous[j] + 1
            : (previous[j + 1] > row[j] ? previous[j + 1] : row[j]);
      }
      previous = row;
    }
    if (2 * previous.last / (a.length + b.length) < 0.8) return false;
  }
  return true;
}

/// Fastest acceptable screening result. Repeated verification authorizes saves.
({InferenceSettings settings, TuneMeasurement measurement})?
pickOptimizeWinner({
  required String? reference,
  TuneMeasurement? baseline,
  required List<({InferenceSettings settings, TuneMeasurement measurement})>
  runs,
}) {
  if (reference == null || reference.isEmpty) return null;
  final base = baseline ?? TuneMeasurement(0, reference);
  ({InferenceSettings settings, TuneMeasurement measurement})? best;
  for (final run in runs) {
    if (!optimizeOutputAcceptable(base, run.measurement)) continue;
    if (best == null ||
        optimizeRate(run.measurement) > optimizeRate(best.measurement)) {
      best = run;
    }
  }
  return best;
}

/// Prefer full workload throughput, including prompt processing.
double optimizeRate(TuneMeasurement m) =>
    m.workloadRate > 0 ? m.workloadRate : m.tokensPerSecond;

/// Treat a complete setup as one A/B candidate, retaining the tuner's A/A,
/// paired repeats and original-output gate. Screening never authorizes a save.
class OptimizeRunner implements TuneRunner {
  final TuneBenchmarkRun runner;
  final List<InferenceSettings> setups;
  final String reference;
  final TuneMeasurement? baseline;
  final void Function(double) progress;
  int _done = 0;
  bool mismatched = false;
  final int rounds;
  final measurements = <int, TuneMeasurement>{};
  final samples = <int, List<TuneMeasurement>>{};
  double medianTokens(int index) =>
      tuneMedian((samples[index] ?? []).map((m) => m.tokensPerSecond));
  OptimizeRunner(
    this.runner,
    this.setups,
    this.reference,
    this.progress, {
    this.baseline,
  }) : rounds = 6 + (setups.length - 1) * 6;

  @override
  Future<bool> fits(TuneSettings s) =>
      runner.fits(setups[s['setup'] as int].toJson());

  @override
  Future<TuneMeasurement> measure(TuneSettings s) async {
    if (runner.outOfTime) throw const OptimizeBudgetExhausted();
    if (runner.cancelled) return const TuneMeasurement(0, '');
    final index = s['setup'] as int;
    final base = baseline ?? TuneMeasurement(0, reference);
    TuneMeasurement? sample;
    var same = false;
    // A sample that differs from the reference is retried once before it
    // counts: one throttled round used to discard the whole run as noise.
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0 && (runner.cancelled || runner.outOfTime)) break;
      sample = await runner.benchmark(
        setups[index].toJson(),
        quick: true,
        progress: (f) => progress((_done + f) / rounds),
      );
      _done++;
      same = optimizeOutputAcceptable(base, sample);
      if (same || runner.cancelled) break;
    }
    if (sample == null || runner.cancelled) {
      return const TuneMeasurement(0, '');
    }
    if (!same) mismatched = true;
    measurements[index] = sample;
    samples.putIfAbsent(index, () => []).add(sample);
    // A run that does not reproduce the baseline fails even the A/A drift gate.
    return TuneMeasurement(
      sample.tokensPerSecond,
      same ? reference : '',
      workloadRate: sample.workloadRate,
      relativeNoise: sample.relativeNoise,
    );
  }

  @override
  void cancel() => runner.cancel();
}

/// Why no safe setup fitted the free memory. The run still measures the
/// smallest variant, and the section names what was short.
enum OptimizeUnfit { ram, vram }

/// What Optimize starts from: the setup to measure first, and, when no
/// estimate fitted, which memory was short.
class OptimizeDefaultsPlan {
  final InferenceSettings settings;
  final OptimizeUnfit? unfit;

  /// Whether the estimate answered with real numbers. False when the
  /// estimator is missing or failing: its silence is unknown, not a refusal,
  /// so the run may still measure and only a load that really fails is
  /// skipped. A refusal from a usable estimate is a fact and is respected.
  final bool estimateUsable;
  const OptimizeDefaultsPlan(
    this.settings, [
    this.unfit,
    this.estimateUsable = true,
  ]);
}

/// Only the explicit Optimize action chooses a new GPU layer count.
Future<InferenceSettings> pcOptimizationDefaults({
  bool? mobile,
  bool? ios,
  required InferenceSettings current,
  required InferenceSettings defaults,
  required Future<Map<String, dynamic>> Function(InferenceSettings) estimate,
}) async => (await pcOptimizationPlan(
  mobile: mobile,
  ios: ios,
  current: current,
  defaults: defaults,
  estimate: estimate,
)).settings;

/// The safe setup to measure first. This never throws for a missing layer
/// count or a refused estimate: it falls back to the current settings and to
/// safe variants (fewer GPU layers, a q8_0 KV cache, a smaller batch), and
/// leaves the decision to the measurement. An estimator that is missing or
/// failing is advice only, not a dead end. [outOfTime] shares the run's
/// deadline with these estimates; [OptimizeDefaultsPlan.estimateUsable] tells
/// a real refusal from an estimator that could not answer.
Future<OptimizeDefaultsPlan> pcOptimizationPlan({
  bool? mobile,
  bool? ios,
  required InferenceSettings current,
  required InferenceSettings defaults,
  required Future<Map<String, dynamic>> Function(InferenceSettings) estimate,
  bool Function()? outOfTime,
}) async {
  final json = current.toJson(), device = defaults.toJson();
  for (final key in pcOptimizationKeys) {
    json[key] = device[key];
  }
  json.addAll({
    'kvCacheType': 'fp16',
    'vCacheType': null,
    'flashAttention': true,
    'draftModelId': '',
    'mtp': false,
    'speculationMode': 'auto',
    'explicitOverrides': current.explicitOverrides
        .difference(pcOptimizationKeys)
        .toList(),
  });
  final iphone = ios ?? Platform.isIOS;
  final phone = mobile ?? (Platform.isAndroid || iphone);
  if (phone) {
    // The model loader resolves mobile Auto to CPU. Preserve explicit
    // phone GPU backends so estimates and loads use the same placement.
    json['backend'] = current.backend.name;
    json['nCpuMoe'] = -1;
    json['expertsUsed'] = -1;
    json['nGpuLayers'] = _phoneGpu(current.backend, ios: iphone) ? 999 : 0;
    if (iphone) {
      json['speculationMode'] = 'off';
      json['batchSize'] = defaults.effectiveBatchSize.clamp(32, 512);
      json['microBatchSize'] = defaults.effectiveMicroBatchSize.clamp(32, 256);
    }
  }
  var settings = InferenceSettings.fromJson(json);
  InferenceSettings keep(InferenceSettings s) => s.copyWith(
    explicitOverrides: current.explicitOverrides.difference(pcOptimizationKeys),
  );
  Future<Map<String, dynamic>?> probe(InferenceSettings s) async {
    // The run's deadline covers these estimates too: past it, stop asking
    // the bridge and fall through to the safe variant below.
    if (outOfTime?.call() ?? false) return null;
    try {
      return await estimate(s);
    } catch (e, st) {
      quietFailure('optimize_defaults_estimate', e, st);
      return null;
    }
  }

  final info = await probe(settings);
  final layers = (info?['layers'] as num?)?.toInt() ?? 0;
  // Every layer on the card first, with either cache: a q8_0 cache with all
  // of Gemma 4 E4B's 43 layers decoded at 101 tok/s on an 8 GB card, F16
  // with 33 layers at 16. Asking for every layer also lets the engine move
  // the vision projector (projectorDevice auto) or MoE experts to RAM, which
  // beats any partial layer count: Gemma 4 26B A4B decodes at 18-20 tok/s
  // that way, like LM Studio.
  final canOffload = phone
      ? _phoneGpu(settings.backend, ios: iphone)
      : settings.backend != GpuBackend.cpu;
  if (canOffload && layers > 0) {
    for (final kv in [KvCacheType.fp16, KvCacheType.q8_0]) {
      final all = settings.copyWith(kvCacheType: kv, nGpuLayers: 999);
      final fit = await probe(all);
      if (fit == null) continue;
      final placed = (fit['gpuLayers'] as num?)?.toInt() ?? 0;
      final whole = fit['gpuExpertsOnCpu'] == true || placed >= layers;
      if (whole && TuneBenchmarkRun.estimateFits(fit, all)) {
        return OptimizeDefaultsPlan(keep(all));
      }
    }
  }
  if (layers > 0) {
    for (final kv in [KvCacheType.fp16, KvCacheType.q8_0]) {
      var low = 0, high = canOffload ? layers : 0;
      settings = settings.copyWith(kvCacheType: kv);
      while (low < high) {
        final middle = (low + high + 1) ~/ 2;
        final candidate = settings.copyWith(nGpuLayers: middle);
        final fit = await probe(candidate);
        if (fit != null && TuneBenchmarkRun.estimateFits(fit, candidate)) {
          low = middle;
        } else {
          high = middle - 1;
        }
      }
      final candidate = settings.copyWith(nGpuLayers: low);
      final fit = await probe(candidate);
      if (fit != null && TuneBenchmarkRun.estimateFits(fit, candidate)) {
        // An empty draft id is MTP Auto: the matching sidecar is found at load.
        return OptimizeDefaultsPlan(keep(candidate));
      }
    }
  }
  // Safe variants, measured rather than refused: half the layers, a q8_0
  // cache, the CPU, smaller batches.
  final smallBatch = settings.effectiveBatchSize.clamp(32, 256);
  final smallMicro = settings.effectiveMicroBatchSize.clamp(32, 128);
  final variants = <InferenceSettings>[
    if (layers > 1)
      settings.copyWith(kvCacheType: KvCacheType.fp16, nGpuLayers: layers ~/ 2),
    if (layers > 0)
      settings.copyWith(kvCacheType: KvCacheType.q8_0, nGpuLayers: layers ~/ 2),
    settings.copyWith(
      kvCacheType: KvCacheType.fp16,
      nGpuLayers: 0,
      batchSize: smallBatch,
      microBatchSize: smallMicro,
    ),
    settings.copyWith(
      kvCacheType: KvCacheType.q8_0,
      nGpuLayers: 0,
      batchSize: smallBatch,
      microBatchSize: smallMicro,
    ),
  ];
  for (final candidate in variants) {
    final fit = await probe(candidate);
    if (fit != null && TuneBenchmarkRun.estimateFits(fit, candidate)) {
      return OptimizeDefaultsPlan(keep(candidate));
    }
  }
  // Nothing fits by the estimate: the smallest setup is returned with what
  // was short. When that estimate was usable the controller stops before
  // loading anything over budget; an estimate without numbers is unknown, so
  // the run may still measure (and the load decides).
  final smallest = variants.last;
  final short = await probe(smallest);
  final unfit = _unfitReason(short, smallest) ?? _unfitReason(info, settings);
  return OptimizeDefaultsPlan(
    keep(smallest),
    unfit,
    // A refusal only counts when the estimate gave numbers for this model.
    unfit != null || _estimateUsable(info),
  );
}

/// Whether the estimate answered with numbers at all. A bridge that is
/// missing or failing reports nothing, and that silence is not a refusal.
bool _estimateUsable(Map<String, dynamic>? e) =>
    e != null &&
    (e['ramNeedMb'] is num || e['vramNeedMb'] is num || e['layers'] is num);

/// Which memory the estimate says is short, for the message the user reads.
OptimizeUnfit? _unfitReason(Map<String, dynamic>? e, InferenceSettings s) {
  if (e == null) return null;
  final ram = e['ramNeedMb'] as num?, available = e['ramAvailableMb'] as num?;
  if (ram != null && available != null) {
    final budget =
        (e['ramBudgetMb'] as num?) ??
        available -
            math.max(1024, ((e['ramTotalMb'] as num?) ?? available) / 8);
    if (ram > budget) return OptimizeUnfit.ram;
  }
  final gpu = (e['gpuLayers'] as num?) ?? 0;
  final need = e['vramNeedMb'] as num?, free = e['vramFreeMb'] as num?;
  if (gpu > 0 &&
      need != null &&
      free != null &&
      need + s.vramReserveMb > free) {
    return OptimizeUnfit.vram;
  }
  return null;
}

/// The part of a measured winner the current platform stores in a profile.
/// Desktop-only keys (and values the registry cannot coerce) are dropped by
/// sanitization on phones, so Optimize never reports a save it did not make.
Map<String, dynamic> optimizeProfileChanges(InferenceSettings winner) {
  final json = winner.toJson();
  return SettingsResolver.sanitize({
    for (final key in pcOptimizationKeys) key: json[key],
    // Null profile values are dropped by sanitization. Save the effective
    // V precision so a global override cannot undo the measured cache.
    'vCacheType': winner.effectiveVCacheType.name,
  });
}

/// A downloaded model Optimize can try as [model]'s draft when the user has
/// not picked one (owner 2026-11-12: with and without a draft when a
/// matching draft is on disk): the smallest of the same family whose file is
/// a third of the size or less, so it shares the vocabulary and drafts
/// cheaply.
ModelInfo? matchingDraftOnDisk(ModelInfo model, Iterable<ModelInfo> library) {
  final size = model.sizeBytes;
  if (size <= 0) return null;
  ModelInfo? best;
  for (final m in library) {
    if (m.id == model.id ||
        !m.isDownloaded ||
        m.localPath == null ||
        m.family != model.family ||
        m.sizeBytes <= 0 ||
        m.sizeBytes * 3 > size) {
      continue;
    }
    if (best == null || m.sizeBytes < best.sizeBytes) best = m;
  }
  return best;
}

/// Expert placements Optimize measures on a mixture-of-experts model whose
/// experts do not all fit on the graphics card (owner 2026-11-12: MoE
/// models only). The engine's automatic fit leaves headroom; the fewest
/// layers' experts in RAM that still fit (by the same estimate a load
/// uses), and two and four more, are tried against it. Empty when every
/// expert already fits, the model has no experts, the run is CPU only, or the
/// estimate cannot run (unknown, so the run measures without MoE variants).
Future<List<int>> moeExpertPlacements(
  InferenceSettings best, {
  required Future<Map<String, dynamic>> Function(InferenceSettings) estimate,
}) async {
  if (best.backend == GpuBackend.cpu || best.nCpuMoe >= 0) return const [];
  final Map<String, dynamic> auto;
  try {
    auto = await estimate(best);
  } catch (e, st) {
    // An estimate that cannot run is unknown, not a placement: the run
    // measures without MoE variants instead of failing before a sample.
    quietFailure('optimize_moe_estimate', e, st);
    return const [];
  }
  if (auto['gpuExpertsOnCpu'] != true) return const [];
  final layers = (auto['layers'] as num?)?.toInt() ?? 0;
  if (layers <= 0) return const [];
  Future<bool> fits(int n) async {
    final s = best.copyWith(nCpuMoe: n);
    final e = await estimate(s);
    return (e['gpuLayers'] as num? ?? 0) > 0 &&
        TuneBenchmarkRun.estimateFits(e, s);
  }

  if (!await fits(layers)) return const [];
  var low = 0, high = layers;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (await fits(middle)) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return {low, low + 2, low + 4}.where((n) => n <= layers).toList();
}
