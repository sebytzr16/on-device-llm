import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/settings/domain/entities/inference_settings.dart';
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
List<InferenceSettings> pcOptimizationSetups(
  InferenceSettings best, {
  bool mtpHead = false,
}) => [
  best,
  if (mtpHead) ...[
    best.copyWith(draftModelId: '$mtpHeadPrefix$mtpOff'),
    best.copyWith(draftMaxTokens: 3),
  ],
  if (best.effectiveMicroBatchSize <= 1024 && best.batchSize != 1024)
    best.copyWith(batchSize: 1024),
  if (best.effectiveThreads != 4) best.copyWith(cpuThreads: 4),
  best.copyWith(flashAttention: false),
];

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
