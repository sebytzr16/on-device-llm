import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_dialog.dart';
import '../../core/island/status_island.dart';
import '../../core/l10n/l10n.dart';
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
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                model.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (recommended) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.star_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 2),
              Text(
                context.l10n.recommended,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
        Row(
          children: [
            Icon(
              ready ? Icons.check_circle_outline : Icons.download_outlined,
              size: 14,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                ready
                    ? context.l10n.imageModelReady
                    : state.status == ImageGenModelStatus.downloading
                    ? '${(100 * state.received / model.sizeBytes).clamp(0, 100).toStringAsFixed(0)}%'
                    : context.l10n.imageDownload(
                        bytesLabel(
                          state.missingBytes > 0
                              ? state.missingBytes
                              : model.sizeBytes,
                        ),
                      ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        if (state.status == ImageGenModelStatus.downloading)
          LinearProgressIndicator(
            value: (state.received / model.sizeBytes).clamp(0, 1),
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

/// Shared by the model library and download center, with resumable pack controls.
class ImageGenDownloadRow extends ConsumerWidget {
  final ImageGenModel model;
  const ImageGenDownloadRow({super.key, required this.model});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageGenDownloadsProvider).of(model);
    final notifier = ref.read(imageGenDownloadsProvider.notifier);
    final t = context.l10n;
    final downloading = state.status == ImageGenModelStatus.downloading;
    final ready = state.status == ImageGenModelStatus.ready;
    final fraction = (state.received / model.sizeBytes).clamp(0.0, 1.0);
    return ListTile(
      key: ValueKey(model.downloadKey),
      title: Text(model.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${bytesLabel(model.sizeBytes)} \u00b7 ${ready
                ? t.imageModelDownloaded
                : state.received > 0
                ? t.imageModelPartial
                : t.imageModelNotDownloaded}',
          ),
          if (downloading || state.received > 0 && !ready) ...[
            LinearProgressIndicator(value: fraction),
            Text(
              '${(fraction * 100).toStringAsFixed(1)}% \u00b7 ${bytesLabel(state.received)} / ${bytesLabel(model.sizeBytes)}'
              '${state.bytesPerSecond == null ? '' : ' \u00b7 ${bytesLabel(state.bytesPerSecond!.round())}/s'}',
            ),
          ],
          if (!ready && state.missingFiles.isNotEmpty)
            Text(t.imageMissingFiles(state.missingFiles.join(', '))),
          if (state.error != null) Text(state.error!),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!ready)
            IconButton(
              tooltip: downloading
                  ? t.imagePause
                  : state.received > 0 || state.paused
                  ? t.imageResumeDownload
                  : t.imageDownload(bytesLabel(model.sizeBytes)),
              icon: Icon(
                downloading
                    ? Icons.pause
                    : state.received > 0 || state.paused
                    ? Icons.play_arrow
                    : Icons.download_outlined,
              ),
              onPressed: () => downloading
                  ? notifier.pause(model)
                  : notifier.download(model),
            ),
          if (downloading || state.received > 0 && !ready)
            IconButton(
              tooltip: t.cancel,
              icon: const Icon(Icons.cancel_outlined),
              onPressed: () => notifier.cancel(model),
            ),
          if (ready || state.received > 0 && !downloading)
            IconButton(
              key: ValueKey('image-gen-delete-${model.id}'),
              tooltip: t.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => deleteImageGenModel(context, ref, model),
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
