import 'package:flutter/material.dart';
import '../../../../core/design/app_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/platform/device_info.dart';
import '../../../../core/platform/desktop_host.dart';
import '../../../../core/providers/shared_providers.dart';
import '../../../../inference/ffi/llama_bindings.dart';
import '../../../settings/domain/entities/inference_settings.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../data/storage/gguf_metadata.dart';
import '../../domain/entities/model_catalog.dart';
import '../../domain/entities/model_info.dart';
import 'model_tags.dart';

final modelMetadataProvider = FutureProvider.family<GgufMetadata?, String>((
  ref,
  path,
) async {
  try {
    return await GgufMetadata.inspect(path);
  } catch (_) {
    return null;
  }
});

final modelDeviceMemoryProvider = FutureProvider<DeviceMemory?>((ref) async {
  if (!DesktopHost.active) return ref.watch(deviceMemoryProvider.future);
  try {
    final facts = await ref
        .read(llamaEstimatorProvider)
        .estimate(modelPath: '', settings: const InferenceSettings());
    // A PC runs a model across system RAM and the graphics card (experts
    // and layers that miss the card stay in RAM), so the budget is both,
    // installed rather than free right now (owner 2026-11-01: Gemma 4 26B
    // and Qwen 3.6 35B showed "too large" on 32 GB RAM + 8 GB VRAM).
    final (ram, vram) = desktopMemoryMb(facts);
    if (ram <= 0) return null;
    final free =
        ((facts['ramAvailableMb'] as num?)?.toDouble() ?? ram) +
        ((facts['vramFreeMb'] as num?)?.toDouble() ?? vram);
    return DeviceMemory(
      totalBytes: ((ram + vram) * 1048576).round(),
      availableBytes: (free * 1048576).round(),
      lowMemory: false,
    );
  } catch (_) {
    return null;
  }
});

/// Installed system RAM and the largest graphics card's memory, in MB, from
/// an empty-path estimate. Falls back to free amounts where totals are
/// missing.
(double, double) desktopMemoryMb(Map<String, dynamic>? facts) {
  final ram =
      (facts?['ramTotalMb'] as num?)?.toDouble() ??
      (facts?['ramAvailableMb'] as num?)?.toDouble() ??
      0;
  final card = (facts?['devices'] as List?)
      ?.whereType<Map>()
      .where((d) => d['type'] == 'gpu')
      .map((d) => ((d['totalMb'] ?? d['freeMb']) as num?)?.toDouble() ?? 0)
      .fold<double>(0, (a, b) => b > a ? b : a);
  final vram =
      (facts?['vramTotalMb'] as num?)?.toDouble() ??
      card ??
      (facts?['vramFreeMb'] as num?)?.toDouble() ??
      0;
  return (ram, vram);
}

class ModelCapabilities {
  final bool tools, vision, thinking, draft, embedding;
  final int? contextLength;
  const ModelCapabilities({
    this.tools = false,
    this.vision = false,
    this.thinking = false,
    this.draft = false,
    this.embedding = false,
    this.contextLength,
  });

  factory ModelCapabilities.derive({
    ModelInfo? model,
    GgufMetadata? metadata,
    Iterable<String> tags = const [],
    int? contextLength,
  }) {
    final hints = tags.map((s) => s.toLowerCase()).toSet();
    return ModelCapabilities(
      tools:
          metadata?.supportsTools == true ||
          hints.any(
            const {'tool-use', 'tool-calling', 'function-calling'}.contains,
          ),
      vision:
          metadata?.supportsVision == true ||
          model?.projector != null ||
          visionProjectors.containsKey(model?.id) ||
          hints.any(
            const {'vision', 'image-text-to-text', 'multimodal'}.contains,
          ),
      thinking:
          metadata?.supportsThinking == true ||
          catalogMeta[model?.id]?.reasoning == true ||
          hints.any(const {'reasoning', 'thinking'}.contains),
      draft:
          (metadata?.nextnPredictLayers ?? 0) > 0 ||
          metadata?.isMtpOnly == true ||
          hints.any(const {'mtp', 'draft', 'speculative-decoding'}.contains),
      embedding:
          metadata?.isEmbedding == true ||
          hints.contains('feature-extraction') ||
          hints.contains('sentence-similarity'),
      contextLength: metadata?.contextLength ?? contextLength,
    );
  }
}

class ModelCapabilityBadges extends ConsumerWidget {
  final ModelInfo? model;
  final List<String> tags;
  final int? contextLength;
  final bool showFit;
  final bool dense;
  const ModelCapabilityBadges({
    super.key,
    this.model,
    this.tags = const [],
    this.contextLength,
    this.showFit = true,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = model;
    final path = m?.localPath;
    final metadata = path == null
        ? null
        : ref.watch(modelMetadataProvider(path)).asData?.value;
    final facts = ModelCapabilities.derive(
      model: m,
      metadata: metadata,
      tags: tags,
      contextLength: contextLength,
    );
    final memory = m == null || !showFit
        ? null
        : ref.watch(modelDeviceMemoryProvider).asData?.value;
    final t = context.l10n;
    final fit = m == null || !showFit
        ? ModelFit.unknown
        : modelFit(
            memory,
            m,
            // The loaded bridge names the backend when there is one;
            // otherwise the selected backend does.
            backend:
                LlamaBindings.windowsGpuOf(
                  ref.watch(llamaEngineProvider).library,
                ) ??
                ref.watch(settingsProvider.select((s) => s.backend)).name,
            fileType: metadata?.fileType,
          );
    Widget tag(String label, IconData icon) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceRaised,
        borderRadius: AppDesign.radius(AppDesign.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.colors.textMuted),
          const SizedBox(width: AppSpace.xs),
          Text(label, style: context.text.caption),
        ],
      ),
    );
    final badges = <Widget>[
      if (facts.tools) tag(t.modelCapabilityTools, Icons.build_outlined),
      if (facts.vision) tag(t.modelCapabilityVision, Icons.visibility_outlined),
      if (facts.thinking)
        tag(t.modelCapabilityThinking, Icons.psychology_outlined),
      if (facts.draft) tag(t.modelCapabilityDraft, Icons.bolt_outlined),
      if (facts.embedding) tag(t.modelCapabilityEmbedding, Icons.data_array),
      if (fit != ModelFit.unknown) FitBadge(fit),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < badges.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.row),
            badges[i],
          ],
        ],
      ),
    );
  }
}
