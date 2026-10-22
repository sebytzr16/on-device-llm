import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/platform/device_info.dart';
import '../../../../data/storage/download_manager.dart';
import '../../../models/domain/entities/model_catalog.dart';
import '../../../models/domain/entities/model_info.dart';
import '../../../models/presentation/widgets/model_tags.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/motion/motion.dart';

/// Shared page frame: scrollable body above a pinned action row.
class StepFrame extends StatelessWidget {
  final String headline;
  final Widget body;
  final List<Widget> actions;
  const StepFrame({
    super.key,
    required this.headline,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppDesign.xl,
      0,
      AppDesign.xl,
      AppDesign.xl,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: AppDesign.xl),
            children: [
              Text(headline, style: context.text.display),
              const SizedBox(height: AppDesign.lg),
              body,
            ],
          ),
        ),
        const SizedBox(height: AppDesign.lg),
        ...actions,
      ],
    ),
  );
}

class PrivacyStep extends StatelessWidget {
  final VoidCallback onContinue;
  const PrivacyStep({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) => StepFrame(
    headline: context.l10n.obPrivateHeadline,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.obPrivateBody, style: context.text.bodyMuted),
        const SizedBox(height: AppDesign.xl),
        _Promise(
          Icons.person_off_outlined,
          context.l10n.obNoAccount,
          context.l10n.obNoAccountHint,
        ),
        _Promise(
          Icons.cloud_off_outlined,
          context.l10n.obNoCloud,
          context.l10n.obNoCloudHint,
        ),
        _Promise(
          Icons.lock_outline,
          context.l10n.obStaysHere,
          context.l10n.obStaysHereHint,
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: onContinue,
        child: Text(context.l10n.continueLabel),
      ),
    ],
  );
}

class _Promise extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  const _Promise(this.icon, this.title, this.detail);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppDesign.lg),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.colors.surfaceRaised,
            borderRadius: AppDesign.radius(AppDesign.rMd),
            border: Border.all(color: context.colors.hairline),
          ),
          child: Icon(icon, size: 18, color: context.colors.accent),
        ),
        const SizedBox(width: AppDesign.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.title),
              Text(detail, style: context.text.bodyMuted),
            ],
          ),
        ),
      ],
    ),
  );
}

class PickModelStep extends StatelessWidget {
  final ModelInfo selected, recommended;
  final List<ModelInfo> alternatives;
  final DeviceMemory? memory;
  final bool acknowledged;
  final ValueChanged<ModelInfo> onSelect;
  final ValueChanged<bool> onAcknowledge;
  final VoidCallback onDownload, onLater;
  const PickModelStep({
    super.key,
    required this.selected,
    required this.recommended,
    required this.alternatives,
    required this.memory,
    required this.acknowledged,
    required this.onSelect,
    required this.onAcknowledge,
    required this.onDownload,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = catalogMeta[selected.id];
    return StepFrame(
      headline: context.l10n.obPickModel,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            memory == null
                ? context.l10n.phoneRamUnknown
                : context.l10n.phoneRam(memory!.totalGb.toStringAsFixed(1)),
            style: context.text.mono,
          ),
          const SizedBox(height: AppDesign.lg),
          Container(
            padding: const EdgeInsets.all(AppDesign.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: AppDesign.radius(AppDesign.rLg),
              border: Border.all(color: c.accent.fade(0.55)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected.displayName,
                        style: context.text.title,
                      ),
                    ),
                    if (selected.id == recommended.id)
                      ModelTag(context.l10n.recommended, color: c.accent),
                  ],
                ),
                const SizedBox(height: AppDesign.sm + 2),
                ModelTagRow(model: selected, memory: memory),
                if (meta != null) ...[
                  const SizedBox(height: AppDesign.sm + 2),
                  Text(meta.blurb, style: context.text.bodyMuted),
                ],
              ],
            ),
          ),
          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: AppDesign.xl),
            Text(context.l10n.orChooseAnother, style: context.text.label),
            const SizedBox(height: AppDesign.md),
            for (final m in alternatives)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDesign.sm),
                child: Material(
                  color: c.surfaceRaised,
                  borderRadius: AppDesign.radius(AppDesign.rMd),
                  child: InkWell(
                    onTap: () => onSelect(m),
                    borderRadius: AppDesign.radius(AppDesign.rMd),
                    child: Container(
                      padding: const EdgeInsets.all(AppDesign.md),
                      decoration: BoxDecoration(
                        borderRadius: AppDesign.radius(AppDesign.rMd),
                        border: Border.all(color: c.hairline),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.displayName, style: context.text.title),
                                const SizedBox(height: AppDesign.sm - 2),
                                ModelTagRow(model: m, memory: memory),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: c.textFaint),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: AppDesign.lg),
          Text(
            '${selected.sizeLabel} from Hugging Face. License: ${selected.license}. The file is verified with SHA-256 before use.',
            style: context.text.small,
          ),
          CheckboxListTile(
            value: acknowledged,
            onChanged: (v) => onAcknowledge(v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              context.l10n.acknowledgeLicense,
              style: context.text.body,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: acknowledged ? onDownload : null,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(context.l10n.download),
        ),
        const SizedBox(height: AppDesign.sm),
        TextButton(onPressed: onLater, child: Text(context.l10n.later)),
      ],
    );
  }
}

class DownloadStep extends StatelessWidget {
  final ModelInfo model;
  final DownloadProgress? progress;
  final bool downloaded;
  final String? error;
  final VoidCallback onPause, onResume, onStart, onSkip;
  final VoidCallback? onReadiness;
  const DownloadStep({
    super.key,
    required this.model,
    required this.progress,
    required this.downloaded,
    required this.error,
    required this.onPause,
    required this.onResume,
    required this.onStart,
    required this.onSkip,
    this.onReadiness,
  });

  static final _big = AppText.monoStrong.copyWith(
    fontSize: 64,
    height: 1,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (downloaded) {
      return StepFrame(
        headline: context.l10n.obReady,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${model.displayName} is on this phone. From here on, nothing leaves it.',
              style: context.text.bodyMuted,
            ),
            const SizedBox(height: AppDesign.lg),
            ModelTagRow(model: model, showFit: false),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: onStart,
            child: Text(context.l10n.startChatting),
          ),
          if (onReadiness != null)
            TextButton.icon(
              onPressed: onReadiness,
              icon: const Icon(Icons.speed_outlined),
              label: Text(context.l10n.uiModelReadinessPageModelReadiness),
            ),
        ],
      );
    }
    final status = progress?.status;
    final downloading =
        status == DownloadStatus.downloading || status == DownloadStatus.queued;
    final verifying = status == DownloadStatus.verifying;
    final paused = status == DownloadStatus.paused;
    if (error != null && !downloading && !verifying) {
      return StepFrame(
        headline: context.l10n.downloadInterrupted,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error!,
              style: context.text.bodyMuted.copyWith(color: c.danger),
            ),
            const SizedBox(height: AppDesign.md),
            Text(
              context.l10n.downloadInterruptedHint,
              style: context.text.bodyMuted,
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(context.l10n.retry),
          ),
          const SizedBox(height: AppDesign.sm),
          TextButton(onPressed: onSkip, child: Text(context.l10n.skipForNow)),
        ],
      );
    }
    final fraction = progress?.fraction ?? 0;
    final received = (progress?.received ?? 0) / (1024 * 1024 * 1024);
    final detail = verifying
        ? context.l10n.verifyingSha
        : paused
        ? context.l10n.pausedOf(received.toStringAsFixed(2), model.sizeLabel)
        : progress == null
        ? context.l10n.starting
        : [
            if (progress!.bytesPerSecond != null)
              speedLabel(progress!.bytesPerSecond!),
            '${received.toStringAsFixed(2)} of ${model.sizeLabel}',
          ].join(' · ');
    return StepFrame(
      headline: context.l10n.downloading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(model.displayName, style: context.text.bodyMuted),
          const SizedBox(height: AppDesign.xxl),
          // The percentage rolls up digit by digit as the download runs.
          RollingText(
            verifying ? '100%' : '${(fraction * 100).toStringAsFixed(0)}%',
            style: _big.copyWith(color: c.text),
          ),
          const SizedBox(height: AppDesign.md),
          Text(detail, style: context.text.mono),
          const SizedBox(height: AppDesign.lg),
          ClipRRect(
            borderRadius: AppDesign.radius(AppDesign.rFull),
            child: LinearProgressIndicator(
              value: verifying || progress == null ? null : fraction,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: AppDesign.xl),
          Text(context.l10n.downloadingHint, style: context.text.bodyMuted),
        ],
      ),
      actions: [
        if (paused)
          FilledButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(context.l10n.resume),
          )
        else
          OutlinedButton.icon(
            onPressed: downloading ? onPause : null,
            icon: const Icon(Icons.pause, size: 18),
            label: Text(
              verifying ? context.l10n.verifying : context.l10n.pause,
            ),
          ),
      ],
    );
  }
}
