import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../data/storage/download_manager.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/models/presentation/widgets/model_tags.dart';

enum DesktopLoadPhase {
  preparing,
  weights,
  context,
  projector,
  finishing,
  done,
}

DesktopLoadPhase desktopLoadPhase(
  double? progress, {
  bool hasProjector = false,
}) {
  if (progress == null || progress <= 0) return DesktopLoadPhase.preparing;
  if (progress >= 1) return DesktopLoadPhase.done;
  if (progress < 0.9) return DesktopLoadPhase.weights;
  if (progress < 0.97) return DesktopLoadPhase.context;
  return hasProjector ? DesktopLoadPhase.projector : DesktopLoadPhase.finishing;
}

String loadPhaseLabel(
  BuildContext context,
  double? progress, {
  bool hasProjector = false,
}) => switch (desktopLoadPhase(progress, hasProjector: hasProjector)) {
  DesktopLoadPhase.preparing => context.l10n.desktopLoadPhasePreparing,
  DesktopLoadPhase.weights => context.l10n.desktopLoadPhaseWeights(
    wholePercentLabel(progress!),
  ),
  DesktopLoadPhase.context => context.l10n.desktopLoadPhaseContext,
  DesktopLoadPhase.projector => context.l10n.desktopLoadPhaseProjector,
  DesktopLoadPhase.finishing => context.l10n.desktopLoadPhaseFinishing,
  DesktopLoadPhase.done => context.l10n.desktopLoadPhaseDone,
};

/// The model being loaded: name, phase, percent and a bar. [compact] drops
/// the name for rows that already show it.
class ModelLoadProgress extends ConsumerWidget {
  final bool compact;
  const ModelLoadProgress({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final (id, progress) = ref.watch(
      modelManagerProvider.select((s) => (s.loadingModelId, s.loadProgress)),
    );
    final model = ref
        .read(modelManagerProvider)
        .catalog
        .where((m) => m.id == id)
        .firstOrNull;
    final name = model?.displayName;
    final phase = loadPhaseLabel(
      context,
      progress,
      hasProjector: model?.projector != null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                compact || name == null ? phase : '$name · $phase',
                overflow: TextOverflow.ellipsis,
                style: context.text.small.copyWith(color: c.textMuted),
              ),
            ),
            // Any moment of a load can be stopped (owner request OR-02).
            IconButton(
              tooltip: context.l10n.stopLoading,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () =>
                  ref.read(modelManagerProvider.notifier).stopLoad(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppDesign.radius(AppDesign.rFull),
          child: TweenAnimationBuilder<double>(
            // Polls land every 100 ms; easing between them keeps the bar
            // from stepping.
            tween: Tween(end: progress ?? 0),
            duration: const Duration(milliseconds: 180),
            builder: (context, value, _) => LinearProgressIndicator(
              value: progress == null || progress <= 0 ? null : value,
              minHeight: 3,
              backgroundColor: c.hairline,
              color: c.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// A download in flight: percent, bytes done of total, speed and time left
/// over a bar. [dense] keeps the facts to percent and speed for narrow rows.
class DownloadProgressBar extends StatelessWidget {
  final DownloadProgress progress;
  final bool dense;
  const DownloadProgressBar(this.progress, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    // Hashing a finished file: the bytes are all in, the bar waits.
    final checking = p.status == DownloadStatus.verifying;
    final known = p.total > 0 && !checking;
    final speed = p.bytesPerSecond;
    final eta = etaLabel(p.received, p.total, speed);
    final facts = [
      if (checking) context.l10n.verifyingSha,
      if (!dense && !checking)
        known
            ? '${bytesLabel(p.received)} / ${bytesLabel(p.total)}'
            : bytesLabel(p.received),
      if (!checking && speed != null && speed > 0) speedLabel(speed),
      if (!dense && !checking && eta != null) context.l10n.timeLeft(eta),
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              known ? percentLabel(p.fraction) : '…',
              style: context.text.mono.copyWith(
                fontSize: 11.5,
                color: c.accent,
              ),
            ),
            const SizedBox(width: AppDesign.sm),
            Expanded(
              child: Text(
                facts,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: context.text.mono.copyWith(
                  fontSize: 11,
                  color: c.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppDesign.radius(AppDesign.rFull),
          child: LinearProgressIndicator(
            value: known ? p.fraction : null,
            minHeight: 3,
            backgroundColor: c.hairline,
            color: c.accent,
          ),
        ),
      ],
    );
  }
}
