import 'dart:io';

import '../../domain/entities/inference_settings.dart';
import '../../../../core/l10n/l10n.dart';

/// Human-readable enum names (North Star 6.6: no raw identifiers in the UI).
String backendLabel(GpuBackend b) => switch (b) {
  GpuBackend.auto => 'Automatic',
  GpuBackend.cpu => 'CPU only',
  GpuBackend.vulkan => 'Vulkan (GPU)',
  GpuBackend.opencl => 'OpenCL (GPU)',
  GpuBackend.metal => 'Metal (GPU)',
  GpuBackend.qnn => 'QNN (NPU)',
};

/// Short form for one-line summaries.
String backendShort(GpuBackend b) => switch (b) {
  GpuBackend.auto => 'auto',
  GpuBackend.cpu => 'cpu',
  GpuBackend.vulkan => 'vulkan',
  GpuBackend.opencl => 'opencl',
  GpuBackend.metal => 'metal',
  GpuBackend.qnn => 'qnn',
};

String webModeLabel(WebMode m, [AppLocalizations? l10n]) => switch (m) {
  WebMode.off => l10n?.webModeOff ?? 'Off · stays local',
  WebMode.auto =>
    l10n?.webModeAuto ?? 'Auto · links, search requests and timely questions',
  WebMode.always => l10n?.webModeAlways ?? 'Always · research every message',
};

String thinkingLevelLabel(ThinkingLevel level, AppLocalizations l10n) =>
    switch (level) {
      ThinkingLevel.off => l10n.thinkOff,
      ThinkingLevel.low => l10n.thinkLow,
      ThinkingLevel.medium => l10n.thinkMedium,
      ThinkingLevel.high => l10n.thinkHigh,
    };

String thinkingLevelHint(ThinkingLevel level, AppLocalizations l10n) =>
    switch (level) {
      ThinkingLevel.off => l10n.thinkOffHint,
      ThinkingLevel.low => l10n.thinkLowHint,
      ThinkingLevel.medium => l10n.thinkMediumHint,
      ThinkingLevel.high => l10n.thinkHighHint,
    };

String webModeShort(WebMode m) => switch (m) {
  WebMode.off => 'Local',
  WebMode.auto => 'Web · auto',
  WebMode.always => 'Web · always',
};

String kvCacheLabel(KvCacheType t) => switch (t) {
  KvCacheType.fp16 => 'FP16 (default)',
  KvCacheType.q8_0 => 'Q8_0 (saves RAM)',
  KvCacheType.q4_0 => 'Q4_0 (saves more RAM)',
};

/// Backends the user may pick on this platform. QNN is never offered here:
/// QNN is not integrated into this runtime.
List<GpuBackend> availableBackends() => [
  GpuBackend.auto,
  GpuBackend.cpu,
  if (Platform.isAndroid) GpuBackend.opencl,
  if (Platform.isAndroid) GpuBackend.vulkan,
  if (Platform.isIOS || Platform.isMacOS) GpuBackend.metal,
];

String gpuLayersLabel(int n) => n == 999 ? 'All' : '$n';

String threadsLabel(InferenceSettings s) =>
    s.cpuThreads == 0 ? 'Auto (${s.effectiveThreads})' : '${s.cpuThreads}';

String microBatchLabel(InferenceSettings s) => s.microBatchSize == 0
    ? 'Auto (${s.effectiveMicroBatchSize})'
    : '${s.effectiveMicroBatchSize}';

String batchLabel(InferenceSettings s) =>
    s.batchSize == 0 ? 'Auto (${s.effectiveBatchSize})' : '${s.batchSize}';

/// "2k", "32k", "1M": token counts as people say them.
String tokenCount(int n) {
  if (n >= 1 << 20 && n % (1 << 20) == 0) return '${n ~/ (1 << 20)}M';
  if (n >= 1024 && n % 1024 == 0) return '${n ~/ 1024}k';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

/// Powers of two from 2k to 1M (roadmap SET-01: the user chooses the bound).
const contextPresets = [
  2048,
  4096,
  8192,
  16384,
  32768,
  65536,
  131072,
  262144,
  524288,
  1048576,
];

const responsePresets = [256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536];

/// 0 = unlimited.
const thinkingBudgetPresets = [0, 256, 512, 1024, 2048, 4096, 8192, 16384];

/// 0 = auto (512).
const batchPresets = [0, 128, 256, 512, 1024, 2048, 4096];

String batchThreadsLabel(InferenceSettings s) => s.batchThreads == 0
    ? 'Auto (${s.effectiveBatchThreads})'
    : '${s.batchThreads}';
