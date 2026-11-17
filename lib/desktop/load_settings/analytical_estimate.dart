import '../../data/storage/gguf_metadata.dart';
import '../../features/settings/domain/entities/inference_settings.dart';

Map<String, dynamic> analyticalMemoryEstimate({
  GgufMetadata? metadata,
  required int weightsBytes,
  required InferenceSettings settings,
  Map<String, dynamic> hardware = const {},
  GgufMetadata? draft,
  int draftBytes = 0,
}) => _estimate(
  metadata: metadata,
  weightsBytes: weightsBytes,
  // Auto: the length the engine asks for before its fit shrinks it.
  settings: settings.contextAuto
      ? settings.copyWith(
          contextSize: InferenceSettings.autoContext(
            trained: metadata?.contextLength,
            ramTotalMb: (hardware['ramTotalMb'] as num?)?.toInt(),
            desktop: true,
          ),
        )
      : settings,
  hardware: hardware,
  draft: draft,
  draftBytes: draftBytes,
);

/// Pure arithmetic, independent of native model loading and GPU probing.
/// Missing architecture fields give a provisional catalog-weight estimate;
/// the cached GGUF header supplies the full KV calculation as soon as read.
Map<String, dynamic> _estimate({
  GgufMetadata? metadata,
  required int weightsBytes,
  required InferenceSettings settings,
  Map<String, dynamic> hardware = const {},
  GgufMetadata? draft,
  int draftBytes = 0,
}) {
  const mib = 1024 * 1024;
  final layers = metadata?.blockCount ?? 0;
  final heads = metadata?.headCount ?? 0;
  final embedding = metadata?.embeddingLength ?? 0;
  final ctx = settings.contextSize;
  // GGML quantized rows include one half-precision scale per 32 values.
  final kv = kvCacheBytes(metadata, settings);
  final batch = settings.effectiveMicroBatchSize.clamp(1, ctx);
  // Activation workspace plus attention scores (flash attention tiles scores
  // instead of materializing the batch-by-context matrix). Backend allocators
  // may refine this approximation later without delaying the UI.
  final compute =
      4.0 *
      batch *
      (embedding * 6 + heads * (settings.flashAttention ? 256 : ctx));
  final weights = (metadata?.weightsBytes ?? weightsBytes).clamp(0, 1 << 62);
  final devices = (hardware['devices'] as List?)?.whereType<Map>();
  bool usableGpu(Map device) {
    final backend = (device['backend'] as String? ?? '').toLowerCase();
    final type = device['type'];
    if ((type != 'gpu' && type != 'igpu') ||
        (device['totalMb'] as num? ?? 0) <= 0) {
      return false;
    }
    if (settings.backend == GpuBackend.cpu) return false;
    if (settings.backend != GpuBackend.auto) {
      return backend.isEmpty || backend.contains(settings.backend.name);
    }
    // Auto leaves integrated Vulkan/OpenCL devices on the CPU.
    return backend == 'metal' ||
        (type == 'gpu' &&
            (backend.isEmpty || backend == 'cuda' || backend == 'vulkan'));
  }

  final hasGpu =
      devices?.any(usableGpu) ?? ((hardware['vramTotalMb'] as num? ?? 0) > 0);
  final effectiveLayers = hasGpu ? settings.effectiveGpuLayers : 0;
  final gpu = effectiveLayers.clamp(0, layers);
  final fraction = layers > 0
      ? gpu / layers
      : (effectiveLayers > 0 ? 1.0 : 0.0);
  final gpuKv = settings.offloadKv ? kv * fraction : 0.0;
  // A draft (or DFlash) model follows the target onto the card (the bridge
  // offloads it whenever the target has GPU layers).
  final draftTotal = draft == null && draftBytes <= 0
      ? 0.0
      : (draft?.weightsBytes ?? draftBytes) + kvCacheBytes(draft, settings);
  final draftOnGpu = gpu > 0 || (layers == 0 && effectiveLayers > 0);
  final vram =
      weights * fraction +
      gpuKv +
      compute * fraction +
      (draftOnGpu ? settings.moeCacheSizeMb * mib : 0) +
      (draftOnGpu ? draftTotal : 0);
  final ram =
      weights * (1 - fraction) +
      kv -
      gpuKv +
      compute * (1 - fraction) +
      (draftOnGpu ? 0 : draftTotal);
  // Before the first measurement the card's size comes from the device list.
  final card = (hardware['devices'] as List?)
      ?.whereType<Map>()
      .where(usableGpu)
      .fold<Map?>(
        null,
        (best, d) =>
            best == null || (d['totalMb'] as num) > (best['totalMb'] as num)
            ? d
            : best,
      );
  return {
    if (card != null && hardware['vramTotalMb'] == null) ...{
      'vramTotalMb': card['totalMb'],
      if (card['freeMb'] is num) 'vramFreeMb': card['freeMb'],
    },
    for (final field in const [
      'devices',
      'vramTotalMb',
      'vramFreeMb',
      'ramTotalMb',
      'ramAvailableMb',
    ])
      if (hardware[field] != null) field: hardware[field],
    'analytical': true,
    if (hardware['supportsFp8Kv'] is bool)
      'supportsFp8Kv': hardware['supportsFp8Kv'],
    // The bridge counts the output layer too (n_layer + 1); match it so
    // the layer line does not jump when the measurement lands.
    'layers': layers > 0 ? layers + 1 : 0,
    'gpuLayers': layers > 0 && gpu >= layers ? layers + 1 : gpu,
    'contextSize': ctx,
    if (metadata?.contextLength != null)
      'contextTrain': metadata!.contextLength,
    'weightsMb': weights / mib,
    if (draftTotal > 0) 'draftMb': draftTotal / mib,
    'kvCacheMb': kv / mib,
    'computeBufferMb': compute / mib,
    'vramNeedMb': vram / mib,
    'ramNeedMb': ram / mib,
  };
}

/// Bytes of KV cache at the configured context. Windowed (SWA) layers keep
/// only the window plus one micro-batch unless swaFull requests full context.
/// Layers that reuse an earlier
/// layer's cache (Gemma 3n/4 `shared_kv_layers`) own none.
double kvCacheBytes(GgufMetadata? metadata, InferenceSettings settings) {
  if (metadata == null) return 0;
  final layers = metadata.blockCount ?? 0;
  final heads = metadata.headCount ?? 0;
  final kvHeads = metadata.kvHeadCount ?? heads;
  final embedding = metadata.embeddingLength ?? 0;
  final key = metadata.keyLength ?? (heads > 0 ? embedding ~/ heads : 0);
  final value = metadata.valueLength ?? key;
  final ctx = settings.contextSize;
  // GGML quantized rows include one half-precision scale per 32 values.
  double rowBytes(int width, KvCacheType type) => switch (type) {
    KvCacheType.fp16 => width * 2.0,
    KvCacheType.f8_e4m3 => width * 1.0,
    KvCacheType.q8_0 => ((width + 31) ~/ 32) * 34.0,
    KvCacheType.q4_0 => ((width + 31) ~/ 32) * 18.0,
  };
  final own = (layers - (metadata.sharedKvLayers ?? 0)).clamp(0, layers);
  final swa = metadata.swaLayers;
  final window = metadata.slidingWindow ?? 0;
  final batch = settings.effectiveMicroBatchSize.clamp(1, ctx);
  var total = 0.0;
  for (var i = 0; i < own; i++) {
    final windowed = window > 0 && swa != null && i < swa.length && swa[i];
    final cells = windowed && !settings.swaFull
        ? (window + batch).clamp(1, ctx)
        : ctx;
    final k = windowed ? (metadata.keyLengthSwa ?? key) : key;
    final v = windowed ? (metadata.valueLengthSwa ?? value) : value;
    total +=
        kvHeads *
        cells *
        (rowBytes(k, settings.kvCacheType) +
            rowBytes(v, settings.effectiveVCacheType));
  }
  return total;
}
