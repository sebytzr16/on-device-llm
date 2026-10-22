import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/platform/device_info.dart';
import '../../../../data/storage/download_manager.dart';
import '../../domain/entities/model_catalog.dart';
import '../../domain/entities/model_info.dart';
import 'model_tags.dart';
import '../../../../core/l10n/l10n.dart';

/// One model in the library, in any of its lifecycle states: idle,
/// downloading, verifying, paused/failed, downloaded (optionally active).
class ModelCard extends StatelessWidget {
  final ModelInfo model;
  final DownloadProgress? progress;
  final DeviceMemory? memory;
  final bool active, busy;
  final VoidCallback? onDownload, onPause, onLoad, onDelete;

  /// Frees the memory of the active (loaded) model.
  final VoidCallback? onUnload;

  /// Vision projector state: null when the model has none in the catalog.
  final bool? visionReady;
  final DownloadProgress? visionProgress;
  final VoidCallback? onDownloadVision, onDeleteVision, onPauseVision;
  final VoidCallback? onBenchmark;

  /// Last benchmark line ("31 tok/s · 3.2 s prefill"), if any.
  final String? benchmarkSummary;

  /// Per-model setting overrides (roadmap P1.4); the count is shown.
  final VoidCallback? onProfile;
  final int profileOverrides;

  /// Drops a not-yet-downloaded, non-bundled entry from the library.
  final VoidCallback? onRemoveEntry;
  const ModelCard({
    super.key,
    required this.model,
    this.progress,
    this.memory,
    this.active = false,
    this.busy = false,
    this.onDownload,
    this.onPause,
    this.onLoad,
    this.onDelete,
    this.onUnload,
    this.visionReady,
    this.visionProgress,
    this.onDownloadVision,
    this.onDeleteVision,
    this.onPauseVision,
    this.onBenchmark,
    this.benchmarkSummary,
    this.onProfile,
    this.profileOverrides = 0,
    this.onRemoveEntry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = progress?.status;
    final downloading =
        status == DownloadStatus.downloading || status == DownloadStatus.queued;
    final verifying = status == DownloadStatus.verifying;
    final interrupted =
        status == DownloadStatus.paused || status == DownloadStatus.failed;
    final meta = catalogMeta[model.id];
    final error = progress?.error;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppDesign.radius(AppDesign.rLg),
        side: BorderSide(color: active ? c.accent.fade(0.55) : c.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(model.displayName, style: context.text.title),
                ),
                if (active) ...[
                  const SizedBox(width: AppDesign.sm),
                  ModelTag(context.l10n.active, color: c.accent),
                ],
              ],
            ),
            const SizedBox(height: AppDesign.sm + 2),
            ModelTagRow(model: model, memory: memory),
            if (meta != null) ...[
              const SizedBox(height: AppDesign.sm + 2),
              Text(meta.blurb, style: context.text.bodyMuted),
            ],
            const SizedBox(height: AppDesign.sm),
            Text(
              context.l10n.licenseLabel(model.license),
              style: context.text.mono.copyWith(color: c.textFaint),
            ),
            if (downloading || verifying) ...[
              const SizedBox(height: AppDesign.lg),
              ClipRRect(
                borderRadius: AppDesign.radius(AppDesign.rFull),
                child: LinearProgressIndicator(
                  value: verifying ? null : progress!.fraction,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: AppDesign.sm),
              Text(
                verifying
                    ? context.l10n.verifyingSha
                    : [
                        percentLabel(progress!.fraction),
                        if (progress!.bytesPerSecond != null)
                          speedLabel(progress!.bytesPerSecond!),
                      ].join('  ·  '),
                style: context.text.monoStrong,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: AppDesign.md),
              Text(
                error,
                style: context.text.bodyMuted.copyWith(color: c.danger),
              ),
            ],
            const SizedBox(height: AppDesign.lg),
            // One clear main action per state; secondary actions sit in a
            // quiet row below it, all the same width.
            if (downloading)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onPause,
                  icon: const Icon(Icons.pause, size: 18),
                  label: Text(
                    status == DownloadStatus.queued
                        ? context.l10n.downloadQueued
                        : context.l10n.pause,
                  ),
                ),
              )
            else if (verifying)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: null,
                  child: Text(context.l10n.verifying),
                ),
              )
            else if (!model.isDownloaded && model.downloadUrl != null)
              Row(
                children: [
                  // Tonal: in a list of downloads, the installed model's
                  // Use model stays the loudest button on the page.
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onDownload,
                      icon: Icon(
                        interrupted ? Icons.refresh : Icons.download_outlined,
                        size: 18,
                      ),
                      label: Text(
                        interrupted
                            ? context.l10n.resumeRetry
                            : context.l10n.download,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // A link- or Hub-added entry that was never downloaded can
                  // leave the list; bundled catalog rows always stay.
                  if (onRemoveEntry != null) ...[
                    const SizedBox(width: AppDesign.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: Key('remove-entry-${model.id}'),
                        onPressed: busy ? null : onRemoveEntry,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.textMuted,
                        ),
                        icon: const Icon(Icons.playlist_remove, size: 18),
                        label: Text(
                          context.l10n.uiModelCardRemoveFromList,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else if (model.isDownloaded) ...[
              Row(
                children: [
                  // The loaded model's main action frees its memory; any
                  // other downloaded model's loads it.
                  Expanded(
                    child: active
                        ? OutlinedButton.icon(
                            key: Key('unload-${model.id}'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.danger,
                              side: BorderSide(
                                color: busy ? c.hairline : c.danger,
                              ),
                            ),
                            onPressed: busy ? null : onUnload,
                            icon: const Icon(Icons.eject_outlined, size: 18),
                            label: Text(
                              context.l10n.unloadShort,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: busy ? null : onLoad,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text(
                              context.l10n.useModel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
                  if (visionReady != null) ...[
                    const SizedBox(width: AppDesign.sm),
                    Expanded(child: _visionAction(context)),
                  ],
                ],
              ),
              const SizedBox(height: AppDesign.xs),
              Row(
                children: [
                  Expanded(
                    child: _QuietAction(
                      key: Key('benchmark-${model.id}'),
                      icon: Icons.speed_outlined,
                      label: benchmarkSummary ?? context.l10n.benchmark,
                      onPressed: busy ? null : onBenchmark,
                    ),
                  ),
                  if (onProfile != null)
                    Expanded(
                      child: _QuietAction(
                        key: Key('profile-${model.id}'),
                        icon: Icons.layers_outlined,
                        label: profileOverrides > 0
                            ? context.l10n.modelProfileCount(profileOverrides)
                            : context.l10n.modelProfile,
                        color: profileOverrides > 0 ? c.accent : null,
                        onPressed: onProfile,
                      ),
                    ),
                  Expanded(
                    child: _QuietAction(
                      icon: Icons.delete_outline,
                      label: context.l10n.remove,
                      onPressed: busy ? null : onDelete,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Photos need the model's projector file: offer it, show its download,
  /// or say it is ready and let the user remove it.
  Widget _visionAction(BuildContext context) {
    final c = context.colors;
    final projector = visionProjectors[model.id]!;
    final status = visionProgress?.status;
    if (status == DownloadStatus.downloading ||
        status == DownloadStatus.queued) {
      return OutlinedButton.icon(
        key: Key('vision-pause-${model.id}'),
        onPressed: onPauseVision,
        icon: const Icon(Icons.pause, size: 18),
        label: Text(
          context.l10n.visionPercent((visionProgress!.fraction * 100).round()),
        ),
      );
    }
    if (status == DownloadStatus.verifying) {
      return OutlinedButton(
        onPressed: null,
        child: Text(context.l10n.verifyingVision),
      );
    }
    if (visionReady == true) {
      return OutlinedButton.icon(
        key: Key('vision-remove-${model.id}'),
        onPressed: busy ? null : onDeleteVision,
        style: OutlinedButton.styleFrom(foregroundColor: c.success),
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: Text(context.l10n.visionReady),
      );
    }
    return OutlinedButton.icon(
      key: Key('vision-add-${model.id}'),
      onPressed: onDownloadVision,
      icon: Icon(
        status == DownloadStatus.paused || status == DownloadStatus.failed
            ? Icons.refresh
            : Icons.add_photo_alternate_outlined,
        size: 18,
      ),
      label: Text(
        context.l10n.addVisionMb((projector.sizeBytes / (1024 * 1024)).round()),
      ),
    );
  }
}

/// A secondary card action: icon over a short label, no border, so the
/// main action stays the obvious one.
class _QuietAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  const _QuietAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tone = color ?? context.colors.textMuted;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: tone,
        padding: const EdgeInsets.symmetric(vertical: AppDesign.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.label.copyWith(
              color: onPressed == null ? null : tone,
            ),
          ),
        ],
      ),
    );
  }
}
