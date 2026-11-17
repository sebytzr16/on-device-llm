import 'model_row_shell.dart';
import 'model_library_rows.dart';
import '../features/models/domain/entities/model_suggestions.dart';
import '../features/models/presentation/widgets/download_center.dart';
import '../features/models/presentation/widgets/model_categories.dart';
import '../features/models/presentation/screens/model_details_page.dart';
import '../features/models/presentation/widgets/model_capabilities.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/blur_switcher.dart';
import '../core/motion/pressable.dart';
import '../data/storage/download_manager.dart';
import '../data/storage/gguf_metadata.dart';
import '../data/storage/model_storage.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import '../features/helper/helper_runner.dart';
import '../features/hosting/presentation/device_hosting_provider.dart';
import '../features/models/domain/entities/model_catalog.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/hidden_library_models.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/models/presentation/recommended_models.dart';
import '../features/models/presentation/providers/fresh_downloads_provider.dart';
import '../core/tips/tip_anchor.dart';
import '../core/tips/tips_store.dart';
import '../features/models/presentation/widgets/best_fit_badge.dart';
import '../features/models/presentation/widgets/model_tags.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../core/platform/desktop_preferences.dart';
import 'model_visibility.dart';
import 'hf_discover.dart';
import 'load_progress.dart';
import 'load_settings_dialog.dart';
import 'model_speed_results_provider.dart';

/// The model library as a page: what is on this PC (load, eject, delete)
/// and the catalog to download from, in table-like rows.
class DesktopModelsPage extends StatefulWidget {
  const DesktopModelsPage({super.key});

  @override
  State<DesktopModelsPage> createState() => _DesktopModelsPageState();
}

class _DesktopModelsPageState extends State<DesktopModelsPage> {
  bool _discover = false;
  bool _allFiles = false;
  ModelCategory? _category;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.desktopPage,
      AppSpace.desktopPage,
      AppSpace.desktopPage,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(
          title: context.l10n.models,
          subtitle: context.l10n.desktopModelsExplanation,
          actions: [
            const DownloadsButton(labelled: true),
            if (!_discover) const _ImportButton(),
          ],
          bottom: Align(
            alignment: Alignment.centerLeft,
            child: TipAnchor(
              id: TipIds.modelsDiscover,
              title: context.l10n.tipDiscoverTitle,
              body: context.l10n.tipDiscoverBody,
              active: !_discover,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                    label: Text(context.l10n.desktopHfLocal),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.travel_explore_rounded, size: 16),
                    label: Text(context.l10n.desktopHfDiscover),
                  ),
                ],
                selected: {_discover},
                onSelectionChanged: (value) =>
                    setState(() => _discover = value.single),
              ),
            ),
          ),
        ),
        if (!_discover) ...[
          const SizedBox(height: 12),
          ModelCategoryFilters(
            selected: _category,
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: AppSpace.row),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(context.l10n.desktopModelsAllFiles),
                selected: _allFiles,
                onSelected: (value) => setState(() => _allFiles = value),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final folder = await ModelStorage.modelsDir();
                    await Process.start('explorer.exe', [folder.path]);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.desktopModelsFolderOpenError,
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(context.l10n.desktopModelsFolderOpen),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
        const SizedBox(height: AppSpace.section),
        Expanded(
          child: IndexedStack(
            index: _discover ? 1 : 0,
            children: [
              _category == ModelCategory.image
                  ? const DesktopImageGenLibrary()
                  : _allFiles ||
                        _category != null && _category != ModelCategory.llm
                  ? _AllModelFiles(category: _category)
                  : const _LocalModelsPage(),
              DesktopHfDiscover(active: _discover),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ImportButton extends ConsumerWidget {
  const _ImportButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importing = ref.watch(
      modelManagerProvider.select((m) => m.isImporting),
    );
    return Pressable(
      enabled: !importing,
      child: OutlinedButton.icon(
        onPressed: importing
            ? null
            : () => _LocalModelsPage._import(context, ref),
        icon: BlurSwitcher(
          child: importing
              ? const SizedBox.square(
                  key: ValueKey('importing'),
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              : const Icon(
                  Icons.file_open_outlined,
                  key: ValueKey('import'),
                  size: 16,
                ),
        ),
        label: Text(context.l10n.importGgufButton),
      ),
    );
  }
}

String? _lastRecommendedLog;

/// One line per change of the Recommended counts, so an empty list can be
/// told apart from an empty catalog or hidden rows in a release build.
void _logRecommended(int catalog, int available, int hidden) {
  final line =
      'Recommended: $available of $catalog library rows '
      '($hidden hidden)';
  if (line == _lastRecommendedLog) return;
  _lastRecommendedLog = line;
  Logger('models').info(line);
}

class _LocalModelsPage extends ConsumerWidget {
  const _LocalModelsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final models = ref.watch(modelManagerProvider);
    final advanced = ref.watch(desktopPreferencesProvider).advanced;
    final visible = models.catalog.where(
      (m) => desktopModelVisible(m, advanced: advanced),
    );
    final local = visible.where((m) => m.isDownloaded).toList();
    final hidden = ref.watch(hiddenLibraryModelsProvider);
    final memory = ref.watch(modelDeviceMemoryProvider).value;
    // Only chat models that can be downloaded: a file the user imported
    // and later moved has no URL, and image or draft files have their own
    // pages (owner 2026-11-12).
    Iterable<ModelInfo> offered(Set<String> hide) =>
        availableLibraryModels(
          models.catalog,
          desktop: true,
          hidden: hide,
        ).where(
          (m) =>
              m.downloadUrl != null &&
              modelCategory(m.fileName) == ModelCategory.llm,
        );
    final available = rankRecommended(
      offered(hidden),
      fit: (m) => modelFit(memory, m),
      desktop: true,
    );
    // Rows removed with the row's close button. Every suggestion had been
    // removed on a tester's PC and phone (17 ids, 2026-11-16), which left
    // an empty Recommended section with no way back.
    final removed = hidden.isEmpty
        ? 0
        : offered(const {}).length - offered(hidden).length;
    _logRecommended(models.catalog.length, available.length, hidden.length);
    final best =
        available.isNotEmpty &&
            modelFit(memory, available.first) == ModelFit.fits
        ? available.first.id
        : null;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (models.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              models.error!,
              style: context.text.small.copyWith(color: context.colors.danger),
            ),
          ),
        ModelSectionLabel(l10n.desktopLocalModels),
        if (local.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l10n.desktopNoModels, style: context.text.small),
          )
        else
          ModelRowTable(
            children: [
              for (final (i, m) in local.indexed)
                ModelRowCascade(
                  index: i,
                  child: _ModelRow(
                    key: ValueKey('model-row-${m.id}'),
                    model: m,
                  ),
                ),
            ],
          ),
        const SizedBox(height: 28),
        ModelSectionLabel(l10n.desktopCatalog),
        if (available.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              removed > 0 ? l10n.recommendedAllRemoved : l10n.recommendedEmpty,
              style: context.text.small,
            ),
          )
        else
          ModelRowTable(
            children: [
              for (final (i, m) in available.indexed)
                ModelRowCascade(
                  index: local.length + i,
                  child: _ModelRow(
                    key: ValueKey('model-row-${m.id}'),
                    model: m,
                    bestFit: m.id == best,
                    firstRun: local.isEmpty,
                  ),
                ),
            ],
          ),
        if (removed > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('recommended-show-removed'),
              onPressed: () =>
                  ref.read(hiddenLibraryModelsProvider.notifier).restoreAll(),
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: Text(l10n.recommendedShowRemoved(removed)),
            ),
          ),
        // All means all (owner 2026-11-12): image and video models and every
        // other kind of model file follow the chat models.
        const SizedBox(height: 28),
        ModelSectionLabel(l10n.modelCategoryImage),
        const DesktopImageGenRows(),
        for (final category in const [
          ModelCategory.draft,
          ModelCategory.embedding,
          ModelCategory.reranker,
          ModelCategory.projector,
          ModelCategory.speech,
        ])
          DesktopModelInventoryList(
            category: category,
            hideEmpty: true,
            header: Padding(
              padding: const EdgeInsets.only(top: 28),
              child: ModelSectionLabel(modelCategoryLabel(l10n, category)),
            ),
          ),
      ],
    );
  }

  /// A GGUF from anywhere on the PC. The family only picks a fallback chat
  /// template for files that ship none, so it is guessed from the name.
  static Future<void> _import(BuildContext context, WidgetRef ref) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
    );
    final path = file?.path;
    if (path == null || !context.mounted) return;
    await importDesktopModel(context, ref, path);
  }
}

Future<void> importDesktopModel(
  BuildContext context,
  WidgetRef ref,
  String path,
) async {
  final manager = ref.read(modelManagerProvider.notifier);
  await manager.ready;
  final name = path.toLowerCase();
  final family = ModelFamily.values.firstWhere(
    (f) => f != ModelFamily.other && name.contains(f.name),
    orElse: () => ModelFamily.other,
  );
  try {
    await manager.importFile(path, family);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// Architecture, parameter count and trained context from the GGUF header,
/// read once per file.
final _ggufFactsProvider = FutureProvider.family<GgufMetadata?, String>((
  ref,
  path,
) async {
  try {
    return await GgufMetadata.inspect(path);
  } catch (_) {
    return null;
  }
});

String _params(int count) {
  final b = count / 1e9;
  if (b < 1) return '${(count / 1e6).round()}M';
  return '${b >= 10 ? b.round() : b.toStringAsFixed(1)}B';
}

String _context(int tokens, AppLocalizations l10n) => l10n.modelContextBadge(
  tokens >= 1024 ? '${(tokens / 1024).round()}K' : '$tokens',
);

class _ModelRow extends ConsumerStatefulWidget {
  final ModelInfo model;

  /// The top Recommended row when it fits this device (first-run guide).
  final bool bestFit;

  /// Nothing is on this device yet: the best-fit row gets its tip.
  final bool firstRun;
  const _ModelRow({
    super.key,
    required this.model,
    this.bestFit = false,
    this.firstRun = false,
  });

  @override
  ConsumerState<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends ConsumerState<_ModelRow> {
  ModelInfo get m => widget.model;

  Future<void> _load() async {
    final settings = ref.read(settingsProvider);
    if (settings.remoteEnabled) {
      await ref
          .read(settingsProvider.notifier)
          .update(settings.copyWith(remoteEnabled: false));
    }
    await _attempt(() => ref.read(modelManagerProvider.notifier).loadModel(m));
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await confirmAction(
      context,
      title: l10n.removeModelQuestion,
      message: l10n.removeModelHint(m.displayName, m.sizeLabel),
      confirmLabel: l10n.remove,
      cancelLabel: l10n.keep,
      destructive: true,
    );
    if (ok) {
      await _attempt(
        () => ref.read(modelManagerProvider.notifier).deleteModel(m),
      );
    }
  }

  Future<void> _attempt(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final models = ref.watch(modelManagerProvider);
    final busy = ref.watch(chatProvider.select((s) => s.isGenerating));
    final loaded = models.loadedModelId == m.id;
    final helperStreams = ref.watch(helperStreamsProvider(m.id));
    final helperLoaded =
        ref.watch(helperLoadedModelsProvider).value?.contains(m.id) ?? false;
    final serving = ref.watch(
      deviceHostingProvider.select(
        (h) =>
            h.running &&
            (h.modelId == m.id || h.pooled.any((pooled) => pooled.id == m.id)),
      ),
    );
    final download = models.downloads[m.id];
    // Queued, streaming or hashing all show the bar (it says "Verifying
    // SHA-256" while hashing); after that the file is read for its
    // settings, which has no bytes to count.
    final downloading =
        !m.isDownloaded &&
        download != null &&
        const {
          DownloadStatus.queued,
          DownloadStatus.downloading,
          DownloadStatus.verifying,
        }.contains(download.status);
    final analyzing = !downloading && models.preparing.contains(m.id);
    final failed =
        !m.isDownloaded &&
        !downloading &&
        !analyzing &&
        download?.status == DownloadStatus.failed;
    final loadingThis = models.isLoadingModel && models.loadingModelId == m.id;
    final tips = ref.watch(tipsProvider);
    // Just downloaded and nothing loaded yet: Load is the next step.
    final fresh =
        ref.watch(freshDownloadsProvider).contains(m.id) &&
        models.loadedModelId == null &&
        !models.isLoadingModel;
    final quant = m.quantLabel;
    final facts = m.isDownloaded && m.localPath != null
        ? ref.watch(_ggufFactsProvider(m.localPath!)).asData?.value
        : null;
    final vision =
        models.vision.contains(m.id) ||
        (!m.isDownloaded && (m.projector ?? visionProjectors[m.id]) != null);
    final params = facts?.parameterCount != null
        ? _params(facts!.parameterCount!)
        : paramLabel(m);
    final speedResults =
        ref
            .watch(modelSpeedResultsProvider)
            .values
            .where((r) => r.modelId == m.id && r.samples.isNotEmpty)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final line = [
      facts?.architecture ?? m.family.name,
      if (params.isNotEmpty) params,
      if (facts?.contextLength case final ctx? when ctx > 0)
        _context(ctx, context.l10n),
      quant,
      m.sizeLabel,
      if (speedResults.isNotEmpty)
        l10n.desktopBenchRate(
          speedResults.first.samples.first.decodeTps.toStringAsFixed(0),
        ),
    ].join(' \u00b7 ');
    final partial =
        !m.isDownloaded &&
        !downloading &&
        !analyzing &&
        (download?.received ?? 0) > 0 &&
        (download?.status == DownloadStatus.paused ||
            download!.received < download.total);
    return ModelRowShell(
      name: m.displayName,
      subtitle: line,
      active: loaded,
      tooltip: m.fileName,
      onTap: m.isDownloaded ? () => openModelDetails(context, m) : null,
      nameBadges: [
        if (vision) ...[
          const SizedBox(width: 8),
          Icon(Icons.visibility_outlined, size: 14, color: c.textMuted),
        ],
        if (widget.bestFit && !m.isDownloaded) ...[
          const SizedBox(width: 8),
          const BestFitBadge(),
        ],
        if (serving) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: l10n.desktopModelServingHint,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: c.accent.fade(0.12),
                borderRadius: AppDesign.radius(4),
              ),
              child: Text(
                l10n.desktopModelServing,
                style: context.text.mono.copyWith(
                  fontSize: 10.5,
                  color: c.accent,
                ),
              ),
            ),
          ),
        ],
      ],
      details: ModelCapabilityBadges(model: m),
      progress: downloading || partial ? ModelRowProgress(download!) : null,
      actions: Row(
        key: ValueKey((
          downloading,
          analyzing,
          m.isDownloaded,
          loaded,
          loadingThis,
        )),
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (downloading)
            ModelRowButton(
              label: l10n.cancel,
              onPressed: () => _attempt(
                () => ref
                    .read(modelManagerProvider.notifier)
                    .cancelDownload(m.id),
              ),
            )
          else if (analyzing) ...[
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.modelAnalyzing,
              style: context.text.small.copyWith(color: c.accent),
            ),
          ] else if (loadingThis)
            const Expanded(child: ModelLoadProgress(compact: true))
          else if (!m.isDownloaded) ...[
            if (failed) ...[
              Tooltip(
                message: download?.error ?? '',
                child: Icon(Icons.error_outline, size: 16, color: c.danger),
              ),
              const SizedBox(width: 8),
            ],
            TipAnchor(
              id: TipIds.modelsBestFit,
              title: l10n.tipBestFitTitle,
              body: l10n.tipBestFitBody,
              // After the Discover tip, on a device with no model.
              active:
                  widget.bestFit &&
                  widget.firstRun &&
                  tips.seen.contains(TipIds.modelsDiscover),
              child: Pressable(
                child: _accentIf(
                  widget.bestFit,
                  onPressed: m.downloadUrl == null || models.isImporting
                      ? null
                      : () => _attempt(
                          () => ref
                              .read(modelManagerProvider.notifier)
                              .downloadModel(m),
                        ),
                  child: Text(
                    partial
                        ? l10n.resume
                        : failed
                        ? l10n.retry
                        : l10n.download,
                  ),
                ),
              ),
            ),
            if (partial)
              ModelRowDeleteButton(
                tooltip: l10n.delete,
                onPressed: () => _attempt(
                  () => ref
                      .read(modelManagerProvider.notifier)
                      .cancelDownload(m.id),
                ),
              ),
            const SizedBox(width: 4),
            IconButton(
              key: ValueKey('remove-available-${m.id}'),
              tooltip: l10n.uiModelCardRemoveFromList,
              onPressed: () => removeLibraryEntry(
                ref,
                ref.read(modelManagerProvider.notifier),
                m,
              ),
              icon: const Icon(Icons.close_rounded, size: 17),
            ),
          ] else if (loaded || helperLoaded) ...[
            Text(
              loaded
                  ? '${l10n.desktopLoaded}${helperStreams > 0 ? ' \u00b7 ${l10n.helperStreams(helperStreams)}' : ''}'
                  : l10n.helperLoadedBadge,
              style: context.text.small.copyWith(color: c.accent),
            ),
            const SizedBox(width: 10),
            Pressable(
              child: FilledButton(
                onPressed: () async {
                  try {
                    if (loaded) {
                      await ref
                          .read(modelManagerProvider.notifier)
                          .unloadModel();
                    } else {
                      await ref.read(helperRunnerProvider).unloadModel(m.id);
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
                child: Text(l10n.desktopEject),
              ),
            ),
          ] else
            TipAnchor(
              id: TipIds.downloadReady,
              title: l10n.tipDownloadReadyTitle(m.displayName),
              body: l10n.tipDownloadReadyBody,
              active: fresh,
              actionLabel: l10n.tipLoadAction,
              onAction: _load,
              child: Pressable(
                child: fresh
                    ? _accentIf(
                        true,
                        onPressed: busy || models.isImporting ? null : _load,
                        child: Text(l10n.desktopLoad),
                      )
                    : ModelRowAction(
                        tonal: true,
                        onPressed:
                            busy || models.isLoadingModel || models.isImporting
                            ? null
                            : _load,
                        child: Text(l10n.desktopLoad),
                      ),
              ),
            ),
          if (m.isDownloaded) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: l10n.desktopLoadSettingsTitle,
              onPressed: () => showDesktopLoadSettings(context, m),
              icon: const Icon(Icons.tune_rounded, size: 17),
            ),
            ModelRowDeleteButton(
              tooltip: l10n.delete,
              onPressed: loaded || helperLoaded || busy || models.isImporting
                  ? null
                  : _delete,
            ),
          ],
        ],
      ),
    );
  }
}

/// The accent button for the next first-run step, else the plain outline.
Widget _accentIf(
  bool accent, {
  required VoidCallback? onPressed,
  required Widget child,
}) => ModelRowAction(accent: accent, onPressed: onPressed, child: child);

/// Disk inventory includes sidecars and draft files excluded from the catalog.
final desktopModelFilesProvider = modelInventoryFilesProvider;

class _AllModelFiles extends StatelessWidget {
  final ModelCategory? category;
  const _AllModelFiles({this.category});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: DesktopModelInventoryList(category: category),
  );
}
