import '../features/models/presentation/widgets/model_capabilities.dart';
import '../features/models/presentation/widgets/hf_model_card.dart';
import '../features/models/presentation/widgets/model_brand.dart';
import 'dart:async';
import 'focus_ring.dart';
import 'load_progress.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/shared_providers.dart';
import '../features/settings/domain/entities/inference_settings.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/pressable.dart';
import '../core/motion/spring_entrance.dart';
import '../data/network/hugging_face.dart';
import '../data/storage/download_manager.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/hf_repository_provider.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';

/// Local bridge query: no model file or network is needed.
final desktopHfMemoryProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  try {
    return await ref
        .read(llamaEstimatorProvider)
        .estimate(modelPath: '', settings: const InferenceSettings());
  } catch (_) {
    return null;
  }
});

enum _Sort { downloads, likes, updated }

/// Desktop discovery uses the phone's repository and download manager.
class DesktopHfDiscover extends ConsumerStatefulWidget {
  /// Whether Discover is the visible view; the field takes focus when it
  /// becomes so.
  final bool active;
  const DesktopHfDiscover({super.key, this.active = true});

  @override
  ConsumerState<DesktopHfDiscover> createState() => _DesktopHfDiscoverState();
}

class _DesktopHfDiscoverState extends ConsumerState<DesktopHfDiscover> {
  bool _includeProjector = true;
  int _cursor = -1;
  final _resultsScroll = ScrollController();
  final _query = TextEditingController();
  Timer? _debounce;
  List<HfRepo>? _results;
  HfRepo? _selected;
  HfRepoFiles? _files;
  _Sort _sort = _Sort.downloads;
  bool _searching = false, _reading = false;
  String? _searchError, _filesError, _actionError;
  int _searchVersion = 0, _filesVersion = 0;
  final _starting = <String>{};
  final _queryFocus = FocusNode(debugLabel: 'hf query');

  @override
  void initState() {
    super.initState();
    if (widget.active) _focusQuery();
  }

  @override
  void didUpdateWidget(DesktopHfDiscover old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _focusQuery();
  }

  // The Local/Discover switch keeps focus after the click, so autofocus
  // alone does not reach the field.
  void _focusQuery() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _queryFocus.requestFocus();
  });

  @override
  void dispose() {
    _debounce?.cancel();
    _queryFocus.dispose();
    _query.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    // Invalidate in-flight responses as soon as the query changes.
    _searchVersion++;
    setState(() => _searching = false);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String value) async {
    _debounce?.cancel();
    final version = ++_searchVersion;
    _filesVersion++;
    setState(() {
      _searching = value.trim().length >= 2;
      _searchError = null;
      _cursor = -1;
      _results = null;
      _selected = null;
      _files = null;
      _filesError = null;
      _reading = false;
    });
    if (!_searching) return;
    try {
      final results = await ref.read(hfRepositoryProvider).search(value.trim());
      if (!mounted || version != _searchVersion) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || version != _searchVersion) return;
      setState(() => _searchError = context.l10n.desktopHfSearchError);
    } finally {
      if (mounted && version == _searchVersion) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _open(HfRepo repo) async {
    final version = ++_filesVersion;
    setState(() {
      _includeProjector = true;
      _selected = repo;
      _files = null;
      _reading = true;
      _filesError = null;
    });
    try {
      final files = await ref.read(hfRepositoryProvider).files(repo.id);
      if (!mounted || version != _filesVersion) return;
      setState(() => _files = files);
    } catch (_) {
      if (!mounted || version != _filesVersion) return;
      setState(() => _filesError = context.l10n.desktopHfFilesError);
    } finally {
      if (mounted && version == _filesVersion) {
        setState(() => _reading = false);
      }
    }
  }

  Future<void> _download(ModelInfo model) async {
    if (!_starting.add(model.id)) return;
    setState(() => _actionError = null);
    try {
      final manager = ref.read(modelManagerProvider.notifier);
      await manager.save(model);
      await manager.downloadModel(model);
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = context.l10n.desktopHfDownloadError);
      }
    } finally {
      _starting.remove(model.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _cancel(String id) async {
    try {
      await ref.read(modelManagerProvider.notifier).pauseDownload(id);
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = context.l10n.desktopHfDownloadError);
      }
    }
  }

  void _moveCursor(int delta, int length) {
    if (length == 0) return;
    setState(() => _cursor = (_cursor + delta).clamp(0, length - 1));
    if (_resultsScroll.hasClients) {
      _resultsScroll.animateTo(
        (_cursor * 95.0).clamp(0, _resultsScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final results = [...?_results]
      ..sort(
        (a, b) => switch (_sort) {
          _Sort.downloads => b.downloads.compareTo(a.downloads),
          _Sort.likes => b.likes.compareTo(a.likes),
          _Sort.updated => (b.lastModified ?? DateTime(0)).compareTo(
            a.lastModified ?? DateTime(0),
          ),
        },
      );
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || results.isEmpty) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) {
          _moveCursor(
            key == LogicalKeyboardKey.arrowDown ? 1 : -1,
            results.length,
          );
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter && _cursor >= 0) {
          _open(results[_cursor]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _moveCursor(1, results.length),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _moveCursor(-1, results.length),
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (_cursor >= 0 && _cursor < results.length) {
                        _open(results[_cursor]);
                      } else {
                        _search(_query.text);
                      }
                    },
                  },
                  child: TextField(
                    key: const Key('desktop-hf-query'),
                    controller: _query,
                    focusNode: _queryFocus,
                    autofocus: true,
                    onEditingComplete: () {},
                    onChanged: _changed,
                    onSubmitted: (value) {
                      if (_cursor >= 0 && _cursor < results.length) {
                        _open(results[_cursor]);
                      } else {
                        _search(value);
                      }
                    },
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: t.desktopHfSearch,
                      hintText: t.desktopHfHint,
                      prefixIcon: const Icon(Icons.search, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              PopupMenuButton<_Sort>(
                key: const Key('desktop-hf-sort'),
                onSelected: (value) => setState(() {
                  _sort = value;
                  _cursor = -1;
                }),
                itemBuilder: (_) => [
                  for (final value in _Sort.values)
                    PopupMenuItem(
                      value: value,
                      child: Text(switch (value) {
                        _Sort.downloads => t.desktopHfDownloads,
                        _Sort.likes => t.desktopHfLikes,
                        _Sort.updated => t.desktopHfUpdated,
                      }, style: const TextStyle(fontSize: 13.5)),
                    ),
                ],
                child: Chip(
                  label: Text(
                    t.desktopHfSortLabel(switch (_sort) {
                      _Sort.downloads => t.desktopHfDownloads,
                      _Sort.likes => t.desktopHfLikes,
                      _Sort.updated => t.desktopHfUpdated,
                    }),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  avatar: const Icon(Icons.sort, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_searchError != null) _message(_searchError!, error: true),
          if (_actionError != null) _message(_actionError!, error: true),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _panel(
                    child: _searching
                        ? const Center(child: CircularProgressIndicator())
                        : _results == null
                        ? _message(t.desktopHfIntro)
                        : results.isEmpty
                        ? _message(t.desktopHfEmpty)
                        : ListView.separated(
                            controller: _resultsScroll,
                            itemCount: results.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) =>
                                _repoRow(results[i], i),
                          ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(flex: 3, child: _panel(child: _detail())),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) => Material(
    clipBehavior: Clip.antiAlias,
    color: context.colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: AppDesign.radius(AppDesign.rLg),
      side: BorderSide(color: context.colors.hairline),
    ),
    child: child,
  );

  Widget _message(String value, {bool error = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.search,
            size: 24,
            color: context.colors.textMuted,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: context.text.small.copyWith(
              color: error ? context.colors.danger : context.colors.textMuted,
            ),
          ),
        ],
      ),
    ),
  );

  String _updated(HfRepo repo) {
    final date = repo.lastModified;
    if (date == null) return '';
    final days = DateTime.now().difference(date).inDays;
    return days >= 0 && days < 7
        ? context.l10n.desktopHfUpdatedDays(days)
        : context.l10n.desktopHfUpdatedDate(
            DateFormat.yMMMd(
              Localizations.localeOf(context).toLanguageTag(),
            ).format(date.toLocal()),
          );
  }

  Widget _stats(HfRepo repo) {
    final format = NumberFormat.compact(
      locale: Localizations.localeOf(context).toLanguageTag(),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.download_outlined,
          size: 14,
          color: context.colors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(format.format(repo.downloads), style: context.text.small),
        const SizedBox(width: 8),
        Icon(Icons.favorite_border, size: 14, color: context.colors.textMuted),
        const SizedBox(width: 4),
        Text(format.format(repo.likes), style: context.text.small),
      ],
    );
  }

  Widget _repoRow(HfRepo repo, int index) {
    final parts = repo.id.split('/');
    return SpringEntrance(
      key: ValueKey(repo.id),
      delay: SpringEntrance.cascade(index),
      from: const Offset(0, 10),
      child: Material(
        color: _selected?.id == repo.id || _cursor == index
            ? context.colors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        child: DesktopFocusRing(
          label: repo.id,
          child: InkWell(
            key: Key('desktop-hf-repo-${repo.id}'),
            onTap: () {
              setState(() => _cursor = index);
              _open(repo);
            },
            child: SizedBox(
              height: 94,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    ModelBrandIcon(repo.id),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            parts.last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.label,
                          ),
                          ModelCapabilityBadges(
                            tags: repo.tags,
                            showFit: false,
                          ),
                          Text(
                            parts.length > 1 ? parts.first : repo.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.small.copyWith(
                              color: context.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _stats(repo),
                        if (repo.lastModified != null)
                          Text(
                            _updated(repo),
                            style: context.text.caption.copyWith(
                              color: context.colors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail() {
    final t = context.l10n;
    if (_reading) return const Center(child: CircularProgressIndicator());
    if (_filesError != null) return _message(_filesError!, error: true);
    final files = _files;
    if (files == null) return _message(t.desktopHfSelect);
    final projector = HuggingFace.selectProjector(files.files);
    final groups = <String, List<HfFile>>{};
    for (final file in files.models) {
      // Keeps quant names beyond the enum (Q8_K_P, Q4_K_S, IQ3_XS).
      final quant =
          ModelQuantization.tagOf(file.name) ??
          file.quantization.name.toUpperCase();
      (groups[quant] ??= []).add(file);
    }
    return ListView(
      key: ValueKey(files.repo),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            ModelBrandIcon(files.repo),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                files.repo,
                style: context.text.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: t.desktopHfCopyRepo,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: files.repo)),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
          ],
        ),
        Text(
          '${files.repo.split('/').first} · ${files.license}',
          style: context.text.small.copyWith(color: context.colors.textMuted),
        ),
        if (_selected != null) ...[
          const SizedBox(height: 8),
          _stats(_selected!),
          if (_selected!.lastModified != null)
            Text(_updated(_selected!), style: context.text.small),
        ],
        const SizedBox(height: 12),
        ModelCapabilityBadges(
          tags: files.tags,
          contextLength: files.contextLength,
          showFit: false,
        ),
        const SizedBox(height: 8),
        if (projector != null)
          Row(
            children: [
              Checkbox(
                value: _includeProjector,
                onChanged: (value) =>
                    setState(() => _includeProjector = value!),
              ),
              Expanded(
                child: Text(
                  t.desktopHfIncludesProjector(
                    projector.name.toUpperCase().contains('BF16')
                        ? 'BF16'
                        : projector.name.toUpperCase().contains('F16')
                        ? 'F16'
                        : projector.name.toUpperCase().contains('F32')
                        ? 'F32'
                        : projector.quantization.name.toUpperCase(),
                    '${(projector.size / 1073741824).toStringAsFixed(1)} GB',
                  ),
                  style: context.text.small,
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (groups.isEmpty) _message(t.desktopHfNoFiles),
        for (final entry in groups.entries) ...[
          for (final file in entry.value) _fileRow(files, file, entry.key),
        ],
        // The card can be long: the files come first so nobody scrolls
        // past the whole readme to download (owner 2026-11-01).
        const SizedBox(height: 16),
        HfModelCard(files: files),
      ],
    );
  }

  Widget _fileRow(HfRepoFiles files, HfFile file, String quant) {
    final t = context.l10n;
    final models = ref.watch(modelManagerProvider);
    final model = HuggingFace.modelFor(
      files,
      file,
      HuggingFace.guessFamily(files.repo),
      includeProjector: _includeProjector,
    );
    final saved = models.catalog
        .where(
          (m) =>
              m.id == model.id ||
              (m.sizeBytes == model.sizeBytes &&
                  m.sha256?.toLowerCase() == file.sha256.toLowerCase()),
        )
        .firstOrNull;
    final id = saved?.id ?? model.id;
    final visionProgress = models.downloads[ModelManagerState.visionKey(id)];
    final progress =
        visionProgress != null &&
            const {
              DownloadStatus.queued,
              DownloadStatus.downloading,
              DownloadStatus.verifying,
              DownloadStatus.failed,
            }.contains(visionProgress.status)
        ? visionProgress
        : models.downloads[id];
    final active =
        progress != null &&
        const {
          DownloadStatus.queued,
          DownloadStatus.downloading,
          DownloadStatus.verifying,
        }.contains(progress.status);
    final memory = ref.watch(desktopHfMemoryProvider).asData?.value;
    // Installed RAM and the card's total (owner 2026-11-01): free RAM at
    // this moment made 26B/35B MoE models read "too large" on 32 GB + 8 GB.
    final (ramTotal, vramTotal) = desktopMemoryMb(memory);
    final vram = memory == null ? null : vramTotal;
    final ram = memory == null ? null : ramTotal;
    final sizeMb =
        (model.sizeBytes + (model.projector?.sizeBytes ?? 0)) / 1048576;
    final fit = vram != null && vram > 0 && sizeMb <= vram
        ? t.desktopHfFitsGpu
        : ram != null &&
              ram > 0 &&
              vram != null &&
              vram > 0 &&
              sizeMb <= ram + vram
        ? t.desktopHfPartialGpu
        : ram != null && ram > 0 && sizeMb > ram + (vram ?? 0)
        ? t.desktopHfTooLarge
        : null;
    final color = fit == t.desktopHfFitsGpu
        ? context.colors.success
        : fit == t.desktopHfPartialGpu
        ? context.colors.warning
        : context.colors.danger;
    return Column(
      key: Key('desktop-hf-file-${file.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  quant,
                  style: context.text.mono.copyWith(
                    fontSize: 12,
                    color: context.colors.warning,
                  ),
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: file.displayName,
                  child: Text(
                    // Files of one repo share a long stem; the end is what
                    // tells two files of the same quant apart.
                    file.displayName.length > 40
                        ? '${file.displayName.substring(0, 14)}…'
                              '${file.displayName.substring(file.displayName.length - 25)}'
                        : file.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.small.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(model.sizeLabel, style: context.text.small),
              if (fit != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: AppDesign.radius(AppDesign.rMd),
                  ),
                  child: Text(
                    fit,
                    style: context.text.caption.copyWith(color: color),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              if (saved?.isDownloaded == true &&
                  (model.projector == null || models.vision.contains(id)) &&
                  !active)
                Text(
                  t.desktopHfDownloaded,
                  style: context.text.small.copyWith(
                    color: context.colors.accent,
                  ),
                )
              else if (active)
                Pressable(
                  child: TextButton(
                    onPressed: () => _cancel(id),
                    child: Text(t.desktopHfCancel),
                  ),
                )
              else if (models.preparing.contains(id) || _starting.contains(id))
                // Hashed, read for its settings, its projector checked:
                // seconds to a minute with no bytes to count.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.modelAnalyzing,
                      style: context.text.small.copyWith(
                        color: context.colors.accent,
                      ),
                    ),
                  ],
                )
              else
                Pressable(
                  // Outlined like the local list: a column of filled pills
                  // shouts.
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 13.5),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: _starting.contains(id)
                        ? null
                        : () => _download(
                            saved?.copyWith(
                                  projector: model.projector,
                                  clearProjector: !_includeProjector,
                                ) ??
                                model,
                          ),
                    child: Text(t.desktopHfDownload),
                  ),
                ),
            ],
          ),
        ),
        // Small and under the file name, left-aligned (owner 2026-11-01:
        // centred above the row they read as noise).
        Padding(
          padding: const EdgeInsets.only(left: 80, bottom: 8),
          child: ModelCapabilityBadges(
            model: model,
            tags: files.tags,
            contextLength: files.contextLength,
            showFit: false,
            dense: true,
          ),
        ),
        if (active)
          Padding(
            padding: const EdgeInsets.only(left: 80, bottom: 10),
            child: DownloadProgressBar(progress),
          )
        else if (models.preparing.contains(id))
          Padding(
            padding: const EdgeInsets.only(left: 80, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t.modelAnalyzingDetail,
                style: context.text.small.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
            ),
          ),
        if (progress?.status == DownloadStatus.failed)
          _message(t.desktopHfDownloadError, error: true),
      ],
    );
  }
}
