import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../data/storage/download_manager.dart';
import '../features/image_gen/domain/entities/image_gen_model.dart';
import '../features/image_gen/image_gen_downloads.dart';
import '../features/image_gen/image_gen_imports.dart';
import '../features/image_gen/image_gen_model_widgets.dart';
import '../features/models/presentation/widgets/model_capabilities.dart';
import '../features/models/presentation/widgets/model_categories.dart';
import '../features/models/presentation/widgets/model_tags.dart';
import 'model_row_shell.dart';

/// Desktop adapters keep the phone/download-center widgets unchanged.
class DesktopImageGenLibrary extends StatelessWidget {
  const DesktopImageGenLibrary({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      ModelSectionLabel(context.l10n.modelCategoryImage),
      const DesktopImageGenRows(),
    ],
  );
}

class DesktopImageGenRows extends ConsumerWidget {
  const DesktopImageGenRows({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ModelRowTable(
    children: [
      for (final (i, model) in imageGenManagedModels(
        ref.watch(imageGenImportsProvider),
      ).indexed)
        ModelRowCascade(
          index: i,
          child: DesktopImageGenRow(model: model),
        ),
    ],
  );
}

class DesktopImageGenRow extends ConsumerWidget {
  const DesktopImageGenRow({super.key, required this.model});
  final ImageGenModel model;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageGenDownloadsProvider).of(model);
    final notifier = ref.read(imageGenDownloadsProvider.notifier);
    final t = context.l10n;
    final downloading = state.status == ImageGenModelStatus.downloading;
    final ready = state.status == ImageGenModelStatus.ready;
    final partial = !ready && (state.received > 0 || state.paused);
    return ModelRowShell(
      key: ValueKey(model.downloadKey),
      name: model.displayName,
      tooltip: !ready && state.missingFiles.isNotEmpty
          ? t.imageMissingFiles(state.missingFiles.join(', '))
          : model.files.map((f) => f.fileName).join('\n'),
      subtitle: [
        model.kind == ImageGenKind.video ? t.imageVideo : t.imagePicture,
        bytesLabel(model.sizeBytes),
        ready
            ? t.imageModelDownloaded
            : partial
            ? t.imageModelPartial
            : t.imageModelNotDownloaded,
      ].join(' · '),
      // The missing-file list sits in the name's tooltip (owner 2026-11-16).
      details: state.error != null
          ? Text(
              state.error!,
              style: context.text.small.copyWith(color: context.colors.danger),
            )
          : null,
      progress: !ready && (downloading || partial)
          ? ModelRowProgress(
              DownloadProgress(
                modelId: model.downloadKey,
                status: downloading && state.received >= model.sizeBytes
                    ? DownloadStatus.verifying
                    : downloading
                    ? DownloadStatus.downloading
                    : DownloadStatus.paused,
                received: state.received,
                total: model.sizeBytes,
                bytesPerSecond: state.bytesPerSecond,
              ),
            )
          : null,
      actions: Row(
        key: ValueKey((state.status, partial)),
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!ready)
            ModelRowButton(
              label: downloading
                  ? t.imagePause
                  : partial
                  ? t.resume
                  : t.download,
              onPressed: () => downloading
                  ? notifier.pause(model)
                  : notifier.download(model),
            ),
          if (downloading) ...[
            const SizedBox(width: AppSpace.xs),
            ModelRowButton(
              label: t.cancel,
              onPressed: () => notifier.cancel(model),
            ),
          ],
          if (partial && !downloading)
            IconButton(
              tooltip: t.cancel,
              onPressed: () => notifier.cancel(model),
              icon: const Icon(Icons.cancel_outlined, size: 17),
            ),
          if (ready || partial && !downloading) ...[
            const SizedBox(width: AppSpace.xs),
            ModelRowDeleteButton(
              key: ValueKey('image-gen-delete-${model.id}'),
              tooltip: t.delete,
              onPressed: () => deleteImageGenModel(context, ref, model),
            ),
          ],
        ],
      ),
    );
  }
}

final _inventorySizeProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  path,
) async {
  try {
    return await File(path).length();
  } on FileSystemException {
    return 0;
  }
});

class DesktopModelInventoryList extends ConsumerWidget {
  const DesktopModelInventoryList({
    super.key,
    this.category,
    this.hideEmpty = false,
    this.header,
  });
  final ModelCategory? category;
  final bool hideEmpty;
  final Widget? header;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(modelCategoryFilesProvider(category))
      .when(
        loading: () => hideEmpty
            ? const SizedBox.shrink()
            : const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text('$error'),
        data: (files) => hideEmpty && files.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header ??
                      ModelSectionLabel(
                        modelCategoryLabel(context.l10n, category),
                      ),
                  if (files.isEmpty)
                    Text(context.l10n.modelCategoryEmpty)
                  else
                    ModelRowTable(
                      children: [
                        for (final (i, file) in files.indexed)
                          ModelRowCascade(
                            index: i,
                            child: DesktopInventoryRow(
                              file: file,
                              underHeading: category != null,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
      );
}

class DesktopInventoryRow extends ConsumerWidget {
  const DesktopInventoryRow({
    super.key,
    required this.file,
    this.underHeading = true,
  });
  final File file;

  /// False in a list without a category heading, where the kind is shown.
  final bool underHeading;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = file.path.toLowerCase().endsWith('.gguf')
        ? ref.watch(modelMetadataProvider(file.path)).asData?.value
        : null;
    final size = ref.watch(_inventorySizeProvider(file.path)).asData?.value;
    final kind = modelCategory(file.path, metadata: metadata);
    return ModelRowShell(
      name: friendlyModelFileName(file.path),
      tooltip: file.path,
      subtitle: [
        if (metadata?.architecture != null) metadata!.architecture!,
        if (size != null) bytesLabel(size),
        // Each section's heading already names the kind.
        if (!underHeading) modelCategoryLabel(context.l10n, kind),
      ].join(' · '),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ModelRowDeleteButton(
            key: ValueKey('inventory-delete-${file.path}'),
            tooltip: context.l10n.delete,
            onPressed: () => deleteModelFile(context, ref, file),
          ),
        ],
      ),
    );
  }
}
