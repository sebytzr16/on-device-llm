import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/platform/device_info.dart';
import '../../domain/entities/model_catalog.dart';
import '../../domain/entities/model_info.dart';

/// How a model's memory needs compare with this phone.
enum ModelFit { fits, tight, tooLarge, unknown }

ModelFit modelFit(DeviceMemory? memory, ModelInfo model) {
  if (memory == null) return ModelFit.unknown;
  final minRam = catalogMeta[model.id]?.minRamGb ?? 0;
  if (memory.fits(model.sizeBytes, minRamGb: minRam)) return ModelFit.fits;
  // Borderline: the publisher's floor or the byte budget is missed by a small
  // margin. Loading may still work with a smaller context.
  final nearBytes = memory.fits((model.sizeBytes * 0.85).round());
  final nearRam = memory.totalGb >= minRam - 1;
  return nearBytes && nearRam ? ModelFit.tight : ModelFit.tooLarge;
}

String paramLabel(ModelInfo model) {
  final b =
      catalogMeta[model.id]?.parameterCountB ??
      model.parameterCountB?.toDouble();
  if (b == null) return '';
  if (b < 1) return '${(b * 1000).round()}M';
  return b == b.roundToDouble() ? '${b.round()}B' : '${b}B';
}

String quantLabel(ModelInfo model) => model.quantization.name.toUpperCase();

String speedLabel(double bytesPerSecond) =>
    '${(bytesPerSecond / 1048576).toStringAsFixed(1)} MB/s';

String percentLabel(double fraction) =>
    '${(fraction * 100).toStringAsFixed(1)}%';

/// Small mono pill used for model facts.
class ModelTag extends StatelessWidget {
  final String label;
  final Color? color;
  const ModelTag(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color == null ? c.surfaceRaised : tint.fade(0.12),
        borderRadius: AppDesign.radius(AppDesign.rSm),
        border: Border.all(color: color == null ? c.hairline : tint.fade(0.4)),
      ),
      child: Text(label, style: context.text.mono.copyWith(color: tint)),
    );
  }
}

class FitBadge extends StatelessWidget {
  final ModelFit fit;
  const FitBadge(this.fit, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return switch (fit) {
      ModelFit.fits => ModelTag(context.l10n.fitFits, color: c.success),
      ModelFit.tight => ModelTag(context.l10n.fitTight, color: c.warning),
      ModelFit.tooLarge => ModelTag(context.l10n.fitTooLarge, color: c.danger),
      ModelFit.unknown => const SizedBox.shrink(),
    };
  }
}

/// Parameter count · quantization · size · Reasoning · fit.
class ModelTagRow extends StatelessWidget {
  final ModelInfo model;
  final DeviceMemory? memory;
  final bool showFit;
  const ModelTagRow({
    super.key,
    required this.model,
    this.memory,
    this.showFit = true,
  });

  @override
  Widget build(BuildContext context) {
    final params = paramLabel(model);
    final meta = catalogMeta[model.id];
    return Wrap(
      spacing: AppDesign.sm - 2,
      runSpacing: AppDesign.sm - 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (params.isNotEmpty) ModelTag(params),
        ModelTag(quantLabel(model)),
        ModelTag(model.sizeLabel),
        if (meta?.reasoning == true)
          ModelTag('Reasoning', color: context.colors.reasoning),
        if (showFit) FitBadge(modelFit(memory, model)),
      ],
    );
  }
}
