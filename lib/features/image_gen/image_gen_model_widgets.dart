import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_dialog.dart';
import '../../core/island/status_island.dart';
import '../../core/l10n/l10n.dart';
import '../../core/design/app_design.dart';
import '../models/presentation/widgets/model_categories.dart';
import '../models/presentation/widgets/model_tags.dart';
import 'domain/entities/image_gen_model.dart';
import 'image_gen_downloads.dart';
import 'image_gen_imports.dart';

/// Every catalog entry stays visible, including models not installed yet.
class ImageGenModelOption extends ConsumerWidget {
  final ImageGenModel model;

  /// The one picture or video model suggested for this graphics card.
  final bool recommended;

  /// Shown in Create's drop-down list: a downloaded model gets a delete
  /// button, called with the list's own context so it can close first.
  final void Function(BuildContext menuContext)? onDelete;
  const ImageGenModelOption({
    super.key,
    required this.model,
    this.recommended = false,
    this.onDelete,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageGenDownloadsProvider).of(model);
    final ready = state.status == ImageGenModelStatus.ready;
    final c = context.colors;
    final status = ready
        ? context.l10n.imageModelReady
        : state.status == ImageGenModelStatus.downloading || state.received > 0
        ? '${(100 * state.received / model.sizeBytes).clamp(0, 100).toStringAsFixed(state.received * 100 < model.sizeBytes ? 1 : 0)} %'
        : context.l10n.imageDownload(
            bytesLabel(
              state.missingBytes > 0 ? state.missingBytes : model.sizeBytes,
            ),
          );
    // Name alone on the first line so it never shares room with a chip;
    // status and "Recommended" go underneath (owner 2026-11-16: the
    // closed field was cut to "Qwen-Image ...").
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          model.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.body,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(
              ready ? Icons.check_circle_outline : Icons.download_outlined,
              size: 13,
              color: c.textMuted,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.small,
              ),
            ),
            if (recommended) ...[
              const SizedBox(width: 8),
              Icon(Icons.star_rounded, size: 13, color: c.accent),
              const SizedBox(width: 2),
              Text(
                context.l10n.recommended,
                maxLines: 1,
                style: context.text.small.copyWith(color: c.accent),
              ),
            ],
          ],
        ),
      ],
    );
    final delete = onDelete;
    if (delete == null ||
        !(ready || state.received > 0) ||
        state.status == ImageGenModelStatus.downloading) {
      return column;
    }
    return Row(
      children: [
        Expanded(child: column),
        IconButton(
          key: ValueKey('image-gen-menu-delete-${model.id}'),
          tooltip: context.l10n.delete,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => delete(context),
        ),
      ],
    );
  }
}

class ImageGenLibrary extends ConsumerWidget {
  const ImageGenLibrary({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = imageGenManagedModels(ref.watch(imageGenImportsProvider));
    return ListView(
      children: [for (final model in models) ImageGenDownloadRow(model: model)],
    );
  }
}

/// The phone's Models screen, Image / Video category.
class ImageGenLibraryCards extends ConsumerWidget {
  const ImageGenLibraryCards({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = imageGenManagedModels(ref.watch(imageGenImportsProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final model in models) ImageGenDownloadRow(model: model)],
    );
  }
}

/// Shared by the phone's model library and the download center: the chat
/// model card's frame, one meta line, a thin bar while part of the pack is
/// here, and the file list behind the info icon (owner 2026-11-16).
class ImageGenDownloadRow extends ConsumerWidget {
  final ImageGenModel model;
  const ImageGenDownloadRow({super.key, required this.model});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageGenDownloadsProvider).of(model);
    final notifier = ref.read(imageGenDownloadsProvider.notifier);
    final t = context.l10n;
    final c = context.colors;
    final downloading = state.status == ImageGenModelStatus.downloading;
    final ready = state.status == ImageGenModelStatus.ready;
    final partial = !ready && (state.received > 0 || state.paused);
    return Padding(
      key: ValueKey(model.downloadKey),
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: ModelFileCard(
        title: model.displayName,
        subtitle: [
          model.kind == ImageGenKind.video ? t.imageVideo : t.imagePicture,
          bytesLabel(model.sizeBytes),
          ready
              ? t.imageModelDownloaded
              : partial
              ? t.imageModelPartial
              : t.imageModelNotDownloaded,
        ].join(' · '),
        details: [
          if (!ready && state.missingFiles.isNotEmpty)
            t.imageMissingFiles(state.missingFiles.join(', '))
          else
            model.files.map((f) => f.fileName).join('\n'),
        ].join('\n'),
        progress: !ready && (downloading || partial || state.error != null)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (downloading || partial)
                    ModelFileProgress(
                      received: state.received,
                      total: model.sizeBytes,
                      bytesPerSecond: downloading ? state.bytesPerSecond : null,
                    ),
                  if (state.error != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      state.error!,
                      style: context.text.small.copyWith(color: c.danger),
                    ),
                  ],
                ],
              )
            : null,
        actions: [
          if (!ready)
            FilledButton.tonalIcon(
              onPressed: () => downloading
                  ? notifier.pause(model)
                  : notifier.download(model),
              icon: Icon(
                downloading
                    ? Icons.pause
                    : partial
                    ? Icons.play_arrow
                    : Icons.download_outlined,
                size: 18,
              ),
              label: Text(
                downloading
                    ? t.imagePause
                    : partial
                    ? t.resume
                    : t.download,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (downloading || partial)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: c.textMuted),
              onPressed: () => notifier.cancel(model),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: Text(t.cancel, overflow: TextOverflow.ellipsis),
            ),
          if (ready || partial && !downloading)
            OutlinedButton.icon(
              key: ValueKey('image-gen-delete-${model.id}'),
              style: OutlinedButton.styleFrom(foregroundColor: c.textMuted),
              onPressed: () => deleteImageGenModel(context, ref, model),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(t.delete, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

/// Deletes an image or video model's files after asking; files another
/// installed model shares (text encoder, VAE, upscaler) are kept.
Future<void> deleteImageGenModel(
  BuildContext context,
  WidgetRef ref,
  ImageGenModel model,
) async {
  final t = context.l10n;
  final ok = await confirmAction(
    context,
    title: t.deleteModelQuestion,
    message: t.deleteModelHint(model.displayName, bytesLabel(model.sizeBytes)),
    confirmLabel: t.delete,
    destructive: true,
    confirmKey: const Key('image-gen-delete-confirm'),
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(imageGenDownloadsProvider.notifier).delete(model);
  } catch (e) {
    if (context.mounted) {
      showIslandToast(context, '$e', tone: IslandTone.error);
    }
  }
}
