import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/app_design.dart';
import '../../../../core/platform/device_info.dart';
import '../../../../core/providers/shared_providers.dart';
import '../../../../core/utils/external_links.dart';
import '../../../benchmark/benchmark.dart';
import '../../../benchmark/benchmark_dialog.dart';
import '../../../../data/network/hugging_face.dart';
import '../../domain/entities/model_catalog.dart';
import '../../domain/entities/model_info.dart';
import '../../../settings/presentation/providers/model_profiles_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/screens/overrides_page.dart';
import '../providers/model_manager_provider.dart';
import '../widgets/config_card_flow.dart';
import '../widgets/model_card.dart';
import 'hf_search_page.dart';
import 'model_readiness_page.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/motion/motion.dart';
import '../../../../core/design/app_dialog.dart';

class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});
  Future<void> _attempt(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        showIslandToast(context, '$e');
      }
    }
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref, {
    required bool fromLink,
  }) async {
    final url = TextEditingController();
    var family = ModelFamily.other;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            fromLink ? context.l10n.addFromHf : context.l10n.importGguf,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppDesign.md,
              children: [
                Text(
                  fromLink
                      ? context.l10n.addFromHfHint
                      : context.l10n.importGgufHint,
                  style: context.text.bodyMuted,
                ),
                if (fromLink) ...[
                  const SizedBox(height: AppDesign.lg),
                  TextField(
                    controller: url,
                    autofocus: true,
                    style: context.text.mono.copyWith(
                      color: context.colors.text,
                    ),
                    decoration: InputDecoration(
                      labelText: context.l10n.ggufLink,
                      hintText: context.l10n.uiModelsScreenHttpsHuggingfaceCo,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ],
                DropdownButtonFormField<ModelFamily>(
                  initialValue: family,
                  decoration: InputDecoration(
                    labelText: context.l10n.templateFallback,
                  ),
                  items: ModelFamily.values
                      .map(
                        (f) => DropdownMenuItem(
                          value: f,
                          child: Text(
                            f == ModelFamily.other
                                ? context.l10n.automaticMetadata
                                : f.name,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => family = v!),
                ),
                Text(
                  context.l10n.ggufWarning,
                  style: context.text.small.copyWith(
                    color: context.colors.textFaint,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                fromLink ? context.l10n.checkModel : context.l10n.chooseFile,
              ),
            ),
          ],
        ),
      ),
    );
    final link = url.text;
    url.dispose();
    if (confirmed != true || !context.mounted) return;
    final manager = ref.read(modelManagerProvider.notifier);
    await _attempt(context, () async {
      if (fromLink) {
        showIslandToast(context, context.l10n.checkingMetadata);
        final model = await HuggingFace.resolve(link, family);
        await manager.save(model);
      } else {
        final file = await FilePicker.pickFile(type: FileType.any);
        final path = file?.path;
        if (path != null) await manager.importFile(path, family);
      }
    });
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    ModelInfo model,
  ) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.downloadQuestion(model.displayName)),
        content: Text(
          '${model.sizeLabel} from Hugging Face.\n\nLicense: ${model.license}\n\nBy continuing, you acknowledge the publisher’s model license. The file is verified with SHA-256 before use.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              final uri = Uri.parse(model.downloadUrl!);
              unawaited(
                openExternalLink(
                  'https://huggingface.co/${uri.pathSegments.take(2).join('/')}',
                ),
              );
            },
            child: Text(context.l10n.modelCard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.download),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(modelManagerProvider.notifier).downloadModel(model);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ModelInfo model,
  ) async {
    final ok = await confirmAction(
      context,
      title: context.l10n.removeModelQuestion,
      message: context.l10n.removeModelHint(model.displayName, model.sizeLabel),
      confirmLabel: context.l10n.remove,
      cancelLabel: context.l10n.keep,
      destructive: true,
    );
    if (ok == true && context.mounted) {
      await _attempt(
        context,
        () => ref.read(modelManagerProvider.notifier).deleteModel(model),
      );
    }
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    ModelInfo model, {
    required ModelManagerState state,
    required DeviceMemory? memory,
    required bool busy,
  }) {
    final manager = ref.read(modelManagerProvider.notifier);
    // Cards rise in when the page opens or a model is added.
    return SpringEntrance(
      key: ValueKey('card-${model.id}'),
      child: ModelCard(
        model: model,
        progress: state.downloads[model.id],
        memory: memory,
        active: state.loadedModelId == model.id,
        busy: busy,
        onDownload: () => _download(context, ref, model),
        onPause: () => manager.pauseDownload(model.id),
        onLoad: () => _attempt(context, () => manager.loadModel(model)),
        onUnload: () => _attempt(context, manager.unloadModel),
        onDelete: () => _delete(context, ref, model),
        visionReady:
            visionProjectors.containsKey(model.id) && model.isDownloaded
            ? state.vision.contains(model.id)
            : null,
        visionProgress: state.downloads[ModelManagerState.visionKey(model.id)],
        onDownloadVision: () => manager.downloadVision(model),
        onPauseVision: () =>
            manager.pauseDownload(ModelManagerState.visionKey(model.id)),
        onDeleteVision: () =>
            _attempt(context, () => manager.deleteVision(model)),
        onBenchmark: () => showBenchmarkDialog(context, ref, model),
        onRemoveEntry:
            !model.isDownloaded && !bundledCatalog.any((m) => m.id == model.id)
            ? () => _attempt(context, () => manager.deleteModel(model))
            : null,
        onProfile: model.isDownloaded
            ? () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _ModelProfilePage(model: model),
                ),
              )
            : null,
        profileOverrides:
            ref.watch(modelProfilesProvider)[model.id]?.length ?? 0,
        benchmarkSummary: switch (ref
            .watch(benchmarkProvider)
            .results[model.id]) {
          null => null,
          final r =>
            '${r.decodeTps.toStringAsFixed(0)} tok/s · ${(r.prefillMs / 1000).toStringAsFixed(1)} s prefill',
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final state = ref.watch(modelManagerProvider);
    final memory = ref.watch(deviceMemoryProvider).value;
    final busy = ref.watch(sessionBusyProvider) || state.isLoadingModel;
    final onDevice = state.catalog.where((m) => m.isDownloaded).toList();
    final available = state.catalog.where((m) => !m.isDownloaded).toList();
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: context.l10n.uiModelsScreenModelReadiness,
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ModelReadinessPage(),
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.browseHf,
            onPressed: () => _attempt(
              context,
              () => openExternalLink(
                'https://huggingface.co/models?library=gguf',
              ),
            ),
            icon: const Icon(Icons.open_in_new, size: 20),
          ),
          PopupMenuButton<bool>(
            key: const Key('config-import'),
            tooltip: context.l10n.uiModelsScreenImportConfiguration,
            icon: const Icon(Icons.file_download_outlined),
            onSelected: (fromFile) =>
                importConfigCard(context, ref, fromFile: fromFile),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: false,
                child: Text(
                  context.l10n.uiModelsScreenImportConfigurationFromClipboard,
                ),
              ),
              PopupMenuItem(
                value: true,
                child: Text(
                  context.l10n.uiModelsScreenImportConfigurationFromAFile,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.lg,
                AppDesign.sm,
                AppDesign.lg,
                AppDesign.xxxl,
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverList.list(
                    children: [
                      Text(
                        context.l10n.yourModelLibrary,
                        style: context.text.display,
                      ),
                      const SizedBox(height: AppDesign.md),
                      Text(
                        context.l10n.libraryHint,
                        style: context.text.bodyMuted,
                      ),
                      const SizedBox(height: AppDesign.lg),
                      Row(
                        children: [
                          Icon(
                            Icons.smartphone_outlined,
                            size: 16,
                            color: c.textFaint,
                          ),
                          const SizedBox(width: AppDesign.sm),
                          Text(
                            memory == null
                                ? context.l10n.phoneRamUnknown
                                : context.l10n.phoneRam(
                                    memory.totalGb.toStringAsFixed(1),
                                  ),
                            style: context.text.mono,
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: AppDesign.xl,
                      ), // Search is the main way in; a link or a file are the two others.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            key: const Key('hf-search'),
                            onPressed: state.isImporting
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => const HfSearchPage(),
                                    ),
                                  ),
                            icon: const Icon(Icons.search, size: 18),
                            label: Text(context.l10n.searchHf),
                          ),
                          const SizedBox(height: AppDesign.sm),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: state.isImporting
                                      ? null
                                      : () =>
                                            _add(context, ref, fromLink: true),
                                  icon: const Icon(Icons.add_link, size: 18),
                                  label: Text(
                                    context.l10n.pasteLink,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppDesign.sm),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: state.isImporting
                                      ? null
                                      : () =>
                                            _add(context, ref, fromLink: false),
                                  icon: const Icon(
                                    Icons.file_open_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    context.l10n.importGgufButton,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (state.isImporting)
                        _StatusLine(context.l10n.checkingCopying),
                      if (state.isLoadingModel)
                        _StatusLine(context.l10n.loadingModel),
                      if (state.error != null) _ErrorCard(state.error!),
                      const SizedBox(height: AppDesign.xxl),
                    ],
                  ),
                  if (state.catalog.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDesign.xl,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: AppDesign.md),
                            Text(
                              context.l10n.preparingLibrary,
                              style: context.text.bodyMuted,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverMainAxisGroup(
                      slivers: [
                        SliverList.list(
                          children: [
                            _SectionLabel(context.l10n.onThisDevice),
                            if (onDevice.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppDesign.md,
                                ),
                                child: Text(
                                  context.l10n.nothingDownloaded,
                                  style: context.text.bodyMuted.copyWith(
                                    color: c.textFaint,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SliverList.separated(
                          itemCount: onDevice.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: AppDesign.md),
                          itemBuilder: (context, index) {
                            final m = onDevice[index];
                            return _card(
                              context,
                              ref,
                              m,
                              state: state,
                              memory: memory,
                              busy: busy,
                            );
                          },
                        ),
                        SliverList.list(
                          children: [
                            const SizedBox(height: AppDesign.xl),
                            _SectionLabel(context.l10n.availableToDownload),
                            if (available.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppDesign.md,
                                ),
                                child: Text(
                                  context.l10n.everythingOnPhone,
                                  style: context.text.bodyMuted.copyWith(
                                    color: c.textFaint,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SliverList.separated(
                          itemCount: available.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: AppDesign.md),
                          itemBuilder: (context, index) {
                            final m = available[index];
                            return _card(
                              context,
                              ref,
                              m,
                              state: state,
                              memory: memory,
                              busy: busy,
                            );
                          },
                        ),
                      ],
                    ),
                  SliverList.list(
                    children: [
                      const SizedBox(height: AppDesign.sm),
                      Text(
                        context.l10n.modelsFootnote,
                        style: context.text.small.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.md),
      child: Row(
        children: [
          Container(width: 3, height: 18, color: context.colors.accent),
          const SizedBox(width: AppDesign.sm + 2),
          Expanded(
            child: Text(
              text,
              style: context.text.title.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.text,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StatusLine extends StatelessWidget {
  final String text;
  const _StatusLine(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppDesign.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppDesign.radius(AppDesign.rFull),
          child: const LinearProgressIndicator(minHeight: 3),
        ),
        const SizedBox(height: AppDesign.sm),
        Text(text, style: context.text.mono),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard(this.message);
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: AppDesign.lg),
      padding: const EdgeInsets.all(AppDesign.md),
      decoration: BoxDecoration(
        color: c.danger.fade(0.08),
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: c.danger.fade(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: c.danger),
          const SizedBox(width: AppDesign.sm + 2),
          Expanded(
            child: Text(
              message,
              style: context.text.bodyMuted.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// The override editor for one model, inheriting from the user's settings
/// (the layers below a model profile).
class _ModelProfilePage extends ConsumerWidget {
  final ModelInfo model;
  const _ModelProfilePage({required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(modelProfilesProvider);
    return OverridesPage(
      title: context.l10n.modelProfileTitle(model.displayName),
      scopeLabel: context.l10n.modelProfileScope,
      overrides: profiles[model.id] ?? const {},
      inherited: ref.watch(settingsProvider),
      onChanged: (o) =>
          ref.read(modelProfilesProvider.notifier).set(model.id, o),
      actions: [
        PopupMenuButton<String>(
          key: const Key('config-menu'),
          tooltip: context.l10n.uiModelsScreenShareOrImportAConfiguration,
          icon: const Icon(Icons.ios_share),
          onSelected: (v) => switch (v) {
            'share' => shareConfigCard(context, ref, model),
            'copy' => copyConfigCard(context, ref, model),
            'paste' => importConfigCard(
              context,
              ref,
              fromFile: false,
              into: model,
            ),
            _ => importConfigCard(context, ref, fromFile: true, into: model),
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'share',
              child: Text(context.l10n.uiModelsScreenShareConfiguration),
            ),
            PopupMenuItem(
              value: 'copy',
              child: Text(context.l10n.uiModelsScreenCopyAsText),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'paste',
              child: Text(context.l10n.uiModelsScreenImportFromClipboard),
            ),
            PopupMenuItem(
              value: 'file',
              child: Text(context.l10n.uiModelsScreenImportFromAFile),
            ),
          ],
        ),
      ],
    );
  }
}
