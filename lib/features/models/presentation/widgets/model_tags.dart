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

String quantLabel(ModelInfo model) => model.quantLabel;

String speedLabel(double bytesPerSecond) =>
    '${(bytesPerSecond / 1048576).toStringAsFixed(1)} MB/s';

String percentLabel(double fraction) =>
    '${(fraction * 100).toStringAsFixed(1)}%';

/// Load progress reads in whole steps; tenths flicker at 10 updates a second.
String wholePercentLabel(double fraction) => '${(fraction * 100).floor()}%';

String bytesLabel(int bytes) => bytes >= 1073741824
    ? '${(bytes / 1073741824).toStringAsFixed(2)} GB'
    : '${(bytes / 1048576).toStringAsFixed(0)} MB';

/// Time left at the current speed ("4m 12s"), or null when it can't be
/// told yet.
String? etaLabel(int received, int total, double? bytesPerSecond) {
  if (total <= 0 || bytesPerSecond == null || bytesPerSecond < 1) return null;
  final seconds = ((total - received) / bytesPerSecond).ceil();
  if (seconds < 0) return null;
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

/// Small mono pill used for model facts.
class ModelTag extends StatelessWidget {
  final String label;
  final Color? color;

  /// Smaller, for lists where the tags sit under a row.
  final bool dense;
  const ModelTag(this.label, {super.key, this.color, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.textMuted;
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 1)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color == null ? c.surfaceRaised : tint.fade(0.12),
        borderRadius: AppDesign.radius(AppDesign.rFull),
        border: Border.all(color: color == null ? c.hairline : tint.fade(0.4)),
      ),
      child: Text(
        label,
        style: context.text.mono.copyWith(
          color: tint,
          height: 1.2,
          fontSize: dense ? 10.5 : null,
        ),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      ),
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
    return Wrap(
      spacing: AppDesign.sm - 2,
      runSpacing: AppDesign.sm - 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (params.isNotEmpty) ModelTag(params),
        ModelTag(quantLabel(model)),
        ModelTag(model.sizeLabel),
        if (showFit) FitBadge(modelFit(memory, model)),
      ],
    );
  }
}
