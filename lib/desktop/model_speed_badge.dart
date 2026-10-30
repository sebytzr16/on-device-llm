import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import 'model_speed_results_provider.dart';

class ModelSpeedBadge extends ConsumerWidget {
  final String modelId;
  const ModelSpeedBadge(this.modelId, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results =
        ref
            .watch(modelSpeedResultsProvider)
            .values
            .where((r) => r.modelId == modelId)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (results.isEmpty || results.first.samples.isEmpty) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: context.l10n.desktopBenchLast(
        results.first.timestamp.toLocal().toString(),
      ),
      child: Text(
        context.l10n.desktopBenchRate(
          results.first.samples.first.decodeTps.toStringAsFixed(0),
        ),
        style: context.text.caption.copyWith(color: context.colors.accent),
      ),
    );
  }
}
