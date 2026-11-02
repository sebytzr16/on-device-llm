import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
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
        r'(^|[-_./ ])(mtp|draft)([-_./ ]|$)|gemma4-assistant',
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
        r'flux|stable-diffusion|sdxl|esrgan|vae|wan2|ltx|hunyuan',
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
  const ModelInventoryList({super.key, this.category});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(modelCategoryFilesProvider(category))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text('$error'),
        data: (files) => Column(
          children: [
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
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(file.uri.pathSegments.last),
      subtitle: SelectableText(file.path),
      trailing: Text(modelCategoryLabel(context.l10n, kind)),
    );
  }
}
