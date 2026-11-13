import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import 'model_tuner.dart';
import 'tune_benchmark_run.dart';

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
  bool mtpHead = false,
  String userDraft = '',
  String userSpeculationMode = 'auto',
  List<int> cpuMoe = const [],
}) => [
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

/// Why Optimize kept the user's current settings instead of saving a setup.
enum OptimizeKeepReason { slower, outputChanged, baselineUnavailable, noisy }

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
  final Stopwatch elapsed = Stopwatch()..start();
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
    if (elapsed.elapsed > const Duration(minutes: 15)) {
      throw StateError('Optimization verification budget exhausted');
    }
    if (runner.cancelled) return const TuneMeasurement(0, '');
    final index = s['setup'] as int;
    final m = await runner.benchmark(
      setups[index].toJson(),
      quick: true,
      progress: (f) => progress((_done + f) / rounds),
    );
    _done++;
    measurements[index] = m;
    samples.putIfAbsent(index, () => []).add(m);
    final same = optimizeOutputAcceptable(
      baseline ?? TuneMeasurement(0, reference),
      m,
    );
    if (!same) mismatched = true;
    // A run that does not reproduce the baseline fails even the A/A drift gate.
    return TuneMeasurement(
      m.tokensPerSecond,
      same ? reference : '',
      workloadRate: m.workloadRate,
      relativeNoise: m.relativeNoise,
    );
  }

  @override
  void cancel() => runner.cancel();
}

/// Only the explicit Optimize action chooses a new GPU layer count.
Future<InferenceSettings> pcOptimizationDefaults({
  required InferenceSettings current,
  required InferenceSettings defaults,
  required Future<Map<String, dynamic>> Function(InferenceSettings) estimate,
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
  var settings = InferenceSettings.fromJson(json);
  final info = await estimate(settings);
  final layers = (info['layers'] as num?)?.toInt();
  if (layers == null || layers <= 0) throw StateError('Missing layer estimate');
  InferenceSettings keep(InferenceSettings s) => s.copyWith(
    explicitOverrides: current.explicitOverrides.difference(pcOptimizationKeys),
  );
  // Every layer on the card first, with either cache: a q8_0 cache with all
  // of Gemma 4 E4B's 43 layers decoded at 101 tok/s on an 8 GB card, F16
  // with 33 layers at 16. Asking for every layer also lets the engine move
  // the vision projector (projectorDevice auto) or MoE experts to RAM, which
  // beats any partial layer count: Gemma 4 26B A4B decodes at 18-20 tok/s
  // that way, like LM Studio.
  if (settings.backend != GpuBackend.cpu) {
    for (final kv in [KvCacheType.fp16, KvCacheType.q8_0]) {
      final all = settings.copyWith(kvCacheType: kv, nGpuLayers: 999);
      final fit = await estimate(all);
      final placed = (fit['gpuLayers'] as num?)?.toInt() ?? 0;
      final whole = fit['gpuExpertsOnCpu'] == true || placed >= layers;
      if (whole && TuneBenchmarkRun.estimateFits(fit, all)) return keep(all);
    }
  }
  for (final kv in [KvCacheType.fp16, KvCacheType.q8_0]) {
    var low = 0, high = settings.backend == GpuBackend.cpu ? 0 : layers;
    settings = settings.copyWith(kvCacheType: kv);
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      final candidate = settings.copyWith(nGpuLayers: middle);
      if (TuneBenchmarkRun.estimateFits(await estimate(candidate), candidate)) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    final candidate = settings.copyWith(nGpuLayers: low);
    if (TuneBenchmarkRun.estimateFits(await estimate(candidate), candidate)) {
      // An empty draft id is MTP Auto: the matching sidecar is found at load.
      return keep(candidate);
    }
  }
  throw StateError('No safe load settings');
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
/// expert already fits, the model has no experts, or the run is CPU only.
Future<List<int>> moeExpertPlacements(
  InferenceSettings best, {
  required Future<Map<String, dynamic>> Function(InferenceSettings) estimate,
}) async {
  if (best.backend == GpuBackend.cpu || best.nCpuMoe >= 0) return const [];
  final auto = await estimate(best);
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
