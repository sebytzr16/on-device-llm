import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/island/status_island.dart';
import '../../../../data/storage/model_file_leases.dart';
import '../../domain/entities/model_info.dart';
import 'model_tags.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/platform/desktop_host.dart';
import '../../../../data/storage/model_storage.dart';
import '../../../../data/storage/gguf_metadata.dart';
import '../providers/model_manager_provider.dart';
import 'model_capabilities.dart';

enum ModelCategory { llm, draft, embedding, reranker, projector, speech, image }

ModelCategory modelCategory(String name, {GgufMetadata? metadata}) {
  final n = name.toLowerCase();
  if (metadata?.isMtpOnly == true ||
      RegExp(
        r'(^|[-_./ ])(mtp|draft|dflash)([-_./ ]|$)|gemma4-assistant',
      ).hasMatch(n)) {
    return ModelCategory.draft;
  }
  if (RegExp(r'mmproj|projector').hasMatch(n) ||
      metadata?.supportsVision == true && metadata?.architecture == 'clip') {
    return ModelCategory.projector;
  }
  if (n.contains('rerank')) return ModelCategory.reranker;
  if (metadata?.isEmbedding == true ||
      RegExp(r'embedding|embed|bge-|e5-').hasMatch(n)) {
    return ModelCategory.embedding;
  }
  if (RegExp(
        r'whisper|parakeet|kokoro|sherpa|tts|stt|asr|vocoder|moonshine|piper|sensevoice',
      ).hasMatch(n) ||
      n.endsWith('.onnx') ||
      n.endsWith('.tar.bz2')) {
    return ModelCategory.speech;
  }
  if (RegExp(
        r'flux|stable-diffusion|sdxl|esrgan|vae|wan2|ltx|hunyuan|qwen[-_]?image|umt5|t5xxl',
      ).hasMatch(n) ||
      n.endsWith('.safetensors') ||
      n.endsWith('.pth')) {
    return ModelCategory.image;
  }
  return ModelCategory.llm;
}

String modelCategoryLabel(AppLocalizations t, ModelCategory? category) =>
    switch (category) {
      null => t.modelCategoryAll,
      ModelCategory.llm => t.modelCategoryLlm,
      ModelCategory.draft => t.modelCategoryDraft,
      ModelCategory.embedding => t.modelCategoryEmbedding,
      ModelCategory.reranker => t.modelCategoryReranker,
      ModelCategory.projector => t.modelCategoryProjector,
      ModelCategory.speech => t.modelCategorySpeech,
      ModelCategory.image => t.modelCategoryImage,
    };

/// The phone keeps the categories behind one drop-down pill; the PC shows
/// them as small chips (owner 2026-11-01: they took too much room).
class ModelCategoryFilters extends StatelessWidget {
  final ModelCategory? selected;
  final ValueChanged<ModelCategory?> onChanged;

  /// Chips instead of the drop-down; defaults to the PC.
  final bool? chips;
  const ModelCategoryFilters({
    super.key,
    this.selected,
    required this.onChanged,
    this.chips,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    const all = [null, ...ModelCategory.values];
    if (chips ?? DesktopHost.active) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final category in all)
            ChoiceChip(
              key: ValueKey('model-category-${category?.name ?? 'all'}'),
              label: Text(modelCategoryLabel(t, category)),
              labelStyle: context.text.small,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              showCheckmark: false,
              shape: const StadiumBorder(),
              selected: selected == category,
              onSelected: (_) => onChanged(category),
            ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: MenuAnchor(
        builder: (context, menu, _) => ActionChip(
          key: const ValueKey('model-category-menu'),
          shape: StadiumBorder(side: BorderSide(color: c.hairline)),
          backgroundColor: c.surfaceRaised,
          avatar: Icon(Icons.filter_list, size: 16, color: c.textMuted),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(modelCategoryLabel(t, selected)),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 18, color: c.textMuted),
            ],
          ),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
        menuChildren: [
          for (final category in all)
            MenuItemButton(
              key: ValueKey('model-category-${category?.name ?? 'all'}'),
              leadingIcon: Icon(
                selected == category ? Icons.check : null,
                size: 18,
                color: c.accent,
              ),
              onPressed: () => onChanged(category),
              child: Text(modelCategoryLabel(t, category)),
            ),
        ],
      ),
    );
  }
}

/// A model file's name for people: the 16-hex-digit hash a hub download
/// keeps in front, the extension and underscores go, the quant stays
/// ("30463452c5fe143f-mtp-Qwen_Qwen3.6-35B-A3B-Q8_0.gguf" →
/// "mtp-Qwen Qwen3.6-35B-A3B Q8_0").
String friendlyModelFileName(String fileName) {
  var name = fileName.split(RegExp(r'[\\/]')).last;
  name = name.replaceFirst(RegExp(r'^[0-9a-fA-F]{16}-'), '');
  name = name.replaceFirst(
    RegExp(
      r'\.(gguf|onnx|safetensors|pth|bin|tar\.bz2)$',
      caseSensitive: false,
    ),
    '',
  );
  final quant = RegExp(
    r'[-_.](I?Q\d\w*|F16|BF16|F32)$',
    caseSensitive: false,
  ).firstMatch(name);
  final stem = quant == null ? name : name.substring(0, quant.start);
  final pretty = stem.replaceAll('_', ' ').trim();
  return quant == null ? pretty : '$pretty ${quant.group(1)!.toUpperCase()}';
}

/// The phone's card for a model file that is not a chat model (draft,
/// embedding, projector, speech, picture): the chat model card's frame,
/// title and small meta line, with its actions in one row underneath.
class ModelFileCard extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Long text (full path, file list) shown on tap of the info icon.
  final String? details;
  final Widget? progress;
  final List<Widget> actions;
  const ModelFileCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.details,
    this.progress,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppDesign.radius(AppDesign.rLg),
        side: BorderSide(color: c.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: context.text.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (details != null)
                  Tooltip(
                    message: details!,
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 6),
                    child: Padding(
                      padding: const EdgeInsets.only(left: AppSpace.sm),
                      child: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: c.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(subtitle, style: context.text.small),
            if (progress != null) ...[
              const SizedBox(height: AppSpace.md),
              progress!,
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  for (final (i, a) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: AppSpace.sm),
                    Expanded(child: a),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A thin bar and "0.1 % · 16 MB / 12.49 GB", as on a chat download.
class ModelFileProgress extends StatelessWidget {
  final int received;
  final int total;
  final double? bytesPerSecond;
  const ModelFileProgress({
    super.key,
    required this.received,
    required this.total,
    this.bytesPerSecond,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (received / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppDesign.radius(AppDesign.rFull),
          child: LinearProgressIndicator(value: fraction, minHeight: 4),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          [
            '${(fraction * 100).toStringAsFixed(1)} %',
            '${bytesLabel(received)} / ${bytesLabel(total)}',
            if (bytesPerSecond != null)
              '${bytesLabel(bytesPerSecond!.round())}/s',
          ].join(' · '),
          style: context.text.monoStrong,
        ),
      ],
    );
  }
}

/// A model file's size on disk; 0 when it went away.
final modelFileSizeProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  path,
) async {
  try {
    return await File(path).length();
  } on FileSystemException {
    return 0;
  }
});

final modelInventoryFilesProvider = FutureProvider.autoDispose<List<File>>((
  ref,
) async {
  ref.watch(modelManagerProvider.select((s) => s.catalog));
  final roots = DesktopHost.active
      ? (await ModelStorage.desktopFolders()).roots
      : [(await ModelStorage.modelsDir()).path];
  final files = <File>[];
  for (final root in roots) {
    final dir = Directory(root);
    if (!await dir.exists()) continue;
    await for (final file in dir.list(recursive: true, followLinks: false)) {
      if (file is File &&
          ModelStorage.fileExtensions.any(file.path.toLowerCase().endsWith)) {
        files.add(file);
      }
    }
  }
  return files..sort((a, b) => a.path.compareTo(b.path));
});

final modelCategoryFilesProvider = FutureProvider.autoDispose
    .family<List<File>, ModelCategory?>((ref, category) async {
      final files = await ref.watch(modelInventoryFilesProvider.future);
      if (category == null) return files;
      final visible = <File>[];
      for (final file in files) {
        final facts = file.path.toLowerCase().endsWith('.gguf')
            ? await ref.watch(modelMetadataProvider(file.path).future)
            : null;
        if (modelCategory(file.path, metadata: facts) == category) {
          visible.add(file);
        }
      }
      return visible;
    });

class ModelInventoryList extends ConsumerWidget {
  final ModelCategory? category;

  /// Shows nothing at all when the category has no files (the All view
  /// stacks every category).
  final bool hideEmpty;

  /// Shown above the files when there are any.
  final Widget? header;
  const ModelInventoryList({
    super.key,
    this.category,
    this.hideEmpty = false,
    this.header,
  });
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
                  ?header,
                  if (files.isEmpty) Text(context.l10n.modelCategoryEmpty),
                  for (final file in files)
                    _InventoryRow(file: file, category: category),
                ],
              ),
      );
}

class _InventoryRow extends ConsumerWidget {
  final File file;
  final ModelCategory? category;
  const _InventoryRow({required this.file, this.category});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = file.path.toLowerCase().endsWith('.gguf')
        ? ref.watch(modelMetadataProvider(file.path)).asData?.value
        : null;
    final kind = modelCategory(file.path, metadata: metadata);
    if (category != null && category != kind) return const SizedBox.shrink();
    final size = ref.watch(modelFileSizeProvider(file.path)).asData?.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: ModelFileCard(
        title: friendlyModelFileName(file.path),
        subtitle: [
          if (metadata?.architecture != null) metadata!.architecture!,
          if (size != null) bytesLabel(size),
          // The chosen category already names the kind.
          if (category == null) modelCategoryLabel(context.l10n, kind),
        ].join(' · '),
        details: file.path,
        actions: [
          OutlinedButton.icon(
            key: ValueKey('inventory-delete-${file.path}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.textMuted,
            ),
            onPressed: () => deleteModelFile(context, ref, file),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(context.l10n.delete, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Deletes one model file after asking (owner 2026-11-12: every Models
/// category can delete). A chat model the app manages is deleted through
/// the model manager, so its profile and projector go with it; any other
/// file (draft, MTP head, embedding, reranker, projector, speech) is
/// removed while no loaded model holds it.
Future<void> deleteModelFile(
  BuildContext context,
  WidgetRef ref,
  File file,
) async {
  final t = context.l10n;
  final name = file.uri.pathSegments.last;
  var size = 0;
  try {
    size = await file.length();
  } catch (_) {}
  if (!context.mounted) return;
  final ok = await confirmAction(
    context,
    title: t.deleteModelQuestion,
    message: t.deleteModelHint(name, bytesLabel(size)),
    confirmLabel: t.delete,
    destructive: true,
    confirmKey: const Key('inventory-delete-confirm'),
  );
  if (!ok || !context.mounted) return;
  try {
    final key = file.absolute.path.toLowerCase();
    ModelInfo? owner;
    for (final m in ref.read(modelManagerProvider).catalog) {
      if (m.isDownloaded &&
          m.localPath != null &&
          File(m.localPath!).absolute.path.toLowerCase() == key) {
        owner = m;
      }
    }
    if (owner != null) {
      await ref.read(modelManagerProvider.notifier).deleteModel(owner);
    } else {
      final guard = ModelFileLeases.instance.beginMutation([file.path]);
      try {
        if (await file.exists()) await file.delete();
      } finally {
        guard.release();
      }
    }
    ref.invalidate(modelInventoryFilesProvider);
  } catch (e) {
    if (context.mounted) {
      showIslandToast(context, '$e', tone: IslandTone.error);
    }
  }
}
