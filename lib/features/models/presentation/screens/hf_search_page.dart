import '../widgets/model_capabilities.dart';
import '../widgets/hf_model_card.dart';
import '../widgets/model_brand.dart';
import '../../../../core/l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../data/network/hugging_face.dart';
import '../../domain/entities/model_info.dart';
import '../providers/model_manager_provider.dart';
import '../providers/hf_repository_provider.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/motion/motion.dart';

/// A diffusion weight selected from the image/video discovery screen.
class HfImageSearchResult {
  final HfImagePipeline pipeline;
  final HfRepoFiles files;
  final HfFile file;

  const HfImageSearchResult({
    required this.pipeline,
    required this.files,
    required this.file,
  });
}

/// Models > Search Hugging Face (FX-12): find any public GGUF repository,
/// pick a quantization, and add it to the library with its verified digest.
/// When [imagePipeline] is set, the same screen searches only image or video
/// generation models and returns the selected diffusion weight to its caller.
class HfSearchPage extends ConsumerStatefulWidget {
  final HfImagePipeline? imagePipeline;

  const HfSearchPage({super.key, this.imagePipeline});
  @override
  ConsumerState<HfSearchPage> createState() => _HfSearchPageState();
}

class _HfSearchPageState extends ConsumerState<HfSearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<HfRepo>? _results;
  String? _error;
  bool _searching = false;
  int _searchVersion = 0;
  late HfImagePipeline? _pipeline;

  @override
  void initState() {
    super.initState();
    _pipeline = widget.imagePipeline;
  }

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _searchVersion++;
    setState(() => _searching = false);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    final version = ++_searchVersion;
    final pipeline = _pipeline;
    if (q.trim().length < 2) {
      if (mounted) setState(() => _results = null);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final repository = ref.read(hfRepositoryProvider);
      final r = pipeline == null
          ? await repository.search(q)
          : await repository.searchImageGeneration(q, pipeline: pipeline);
      if (mounted && _query.text == q && version == _searchVersion) {
        setState(() => _results = r);
      }
    } catch (e) {
      if (mounted && version == _searchVersion) {
        setState(
          () => _error = pipeline == null
              ? '$e'.replaceFirst('FormatException: ', '')
              : context.l10n.desktopHfSearchError,
        );
      }
    } finally {
      if (mounted && version == _searchVersion) {
        setState(() => _searching = false);
      }
    }
  }

  void _setPipeline(HfImagePipeline pipeline) {
    if (_pipeline == pipeline) return;
    _debounce?.cancel();
    _searchVersion++;
    setState(() {
      _pipeline = pipeline;
      _results = null;
      _error = null;
      _searching = false;
    });
    if (_query.text.trim().length >= 2) {
      unawaited(_search(_query.text));
    }
  }

  Future<void> _open(HfRepo repo) async {
    setState(() => _error = null);
    final pipeline = _pipeline;
    final HfRepoFiles files;
    try {
      final repository = ref.read(hfRepositoryProvider);
      files = pipeline == null
          ? await repository.files(repo.id)
          : await repository.imageGenerationFiles(repo.id);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = pipeline == null
              ? '$e'.replaceFirst('FormatException: ', '')
              : context.l10n.imageDiscoverFilesError,
        );
      }
      return;
    }
    if (!mounted) return;
    final picked = await showMorphSheet<HfFile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _FilesSheet(files: files, imageGeneration: pipeline != null),
    );
    if (picked == null || !mounted) return;
    if (pipeline != null) {
      Navigator.pop(
        context,
        HfImageSearchResult(pipeline: pipeline, files: files, file: picked),
      );
      return;
    }
    final family = HuggingFace.guessFamily(repo.id);
    final model = HuggingFace.modelFor(files, picked, family);
    await ref.read(modelManagerProvider.notifier).save(model);
    if (mounted) {
      showIslandToast(
        context,
        context.l10n.hfAdded(
          model.displayName,
          model.sizeLabel,
          family == ModelFamily.other
              ? context.l10n.hfFromMetadata
              : family.name,
        ),
        tone: IslandTone.done,
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pipeline = _pipeline;
    final library = pipeline == null
        ? ref.watch(modelManagerProvider).catalog
        : const <ModelInfo>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          pipeline == null
              ? context.l10n.uiHfSearchPageSearchHuggingFace
              : context.l10n.imageDiscoverTitle,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (pipeline != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.phonePage,
                  AppSpace.sm,
                  AppSpace.phonePage,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<HfImagePipeline>(
                        segments: [
                          ButtonSegment(
                            value: HfImagePipeline.textToImage,
                            label: Text(context.l10n.imageModeImage),
                            icon: const Icon(Icons.image_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: HfImagePipeline.textToVideo,
                            label: Text(context.l10n.imageVideo),
                            icon: const Icon(Icons.movie_outlined, size: 18),
                          ),
                        ],
                        selected: {pipeline},
                        onSelectionChanged: (value) =>
                            _setPipeline(value.single),
                      ),
                    ),
                    const SizedBox(height: AppSpace.row),
                    Text(
                      pipeline == HfImagePipeline.textToImage
                          ? context.l10n.imageDiscoverFilterImage
                          : context.l10n.imageDiscoverFilterVideo,
                      style: context.text.small.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.phonePage,
                AppSpace.sm,
                AppSpace.phonePage,
                AppSpace.sm,
              ),
              child: TextField(
                key: const Key('hf-query'),
                controller: _query,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: pipeline == null
                      ? context.l10n.uiHfSearchPageModelNameEGQwen34B
                      : context.l10n.imageDiscoverSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpace.md),
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.phonePage,
                ),
                child: Text(
                  _error!,
                  style: context.text.bodyMuted.copyWith(color: c.danger),
                ),
              ),
            Expanded(
              child: _results == null
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpace.phonePage),
                      child: Text(
                        pipeline == null
                            ? context.l10n.hfIntro
                            : context.l10n.imageDiscoverIntro,
                        style: context.text.bodyMuted,
                      ),
                    )
                  : _results!.isEmpty
                  ? Center(
                      child: Text(
                        pipeline == null
                            ? context.l10n.uiHfSearchPageNoGGUFRepositoriesMatch
                            : context.l10n.imageDiscoverEmpty,
                        style: context.text.bodyMuted,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results!.length,
                      itemBuilder: (_, i) {
                        final r = _results![i];
                        final have = library.any(
                          (m) => m.downloadUrl?.contains('/${r.id}/') ?? false,
                        );
                        return ListTile(
                          key: Key('hf-repo-$i'),
                          leading: ModelBrandIcon(r.id),
                          title: Text(
                            r.id,
                            style: context.text.mono.copyWith(color: c.text),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ModelCapabilityBadges(
                                tags: r.tags,
                                showFit: false,
                              ),
                              Text(
                                '${context.l10n.hfRepoStats(_count(r.downloads), r.likes)}'
                                '${r.lastModified != null ? ' · ${r.lastModified!.toIso8601String().substring(0, 10)}' : ''}'
                                '${have ? ' · ${context.l10n.hfInLibrary}' : ''}',
                                style: context.text.mono.copyWith(
                                  color: c.textFaint,
                                ),
                              ),
                            ],
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: c.textMuted,
                          ),
                          onTap: () => _open(r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _count(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1)}M'
      : n >= 1000
      ? '${(n / 1000).toStringAsFixed(0)}k'
      : '$n';
}

class _FilesSheet extends StatelessWidget {
  final HfRepoFiles files;
  final bool imageGeneration;
  const _FilesSheet({required this.files, this.imageGeneration = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final usable = imageGeneration ? files.imageModels : files.models;
    final other = imageGeneration
        ? const <HfFile>[]
        : files.files.where((f) => f.isProjector).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => AppSheet(
        title: files.repo,
        meta: context.l10n.hfLicenseRevision(
          files.license,
          files.revision.substring(0, 7),
        ),
        scrollable: false,
        children: [
          CustomScrollView(
            controller: scroll,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.zero,
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverList.list(
                      children: [
                        ModelBrandIcon(files.repo),
                        ModelCapabilityBadges(
                          tags: files.tags,
                          contextLength: files.contextLength,
                          showFit: false,
                        ),
                        if (!imageGeneration) HfModelCard(files: files),
                        if (usable.isEmpty)
                          Text(
                            imageGeneration
                                ? context.l10n.imageDiscoverNoFiles
                                : context
                                      .l10n
                                      .uiHfSearchPageNoSingleFileGGUFWeightsIn,
                            style: context.text.bodyMuted,
                          ),
                      ],
                    ),
                    SliverList.separated(
                      itemCount: usable.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpace.md),
                      itemBuilder: (context, index) {
                        final f = usable[index];
                        return ListTile(
                          key: Key('hf-file-${f.name}'),
                          dense: true,
                          title: Text(
                            f.displayName,
                            style: context.text.mono.copyWith(color: c.text),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!imageGeneration)
                                ModelCapabilityBadges(
                                  model: HuggingFace.modelFor(
                                    files,
                                    f,
                                    HuggingFace.guessFamily(files.repo),
                                  ),
                                  tags: files.tags,
                                  contextLength: files.contextLength,
                                ),
                              Text(
                                imageGeneration
                                    ? _gb(files.totalSize(f))
                                    : '${ModelQuantization.tagOf(f.name) ?? f.quantization.name.toUpperCase()} · ${_gb(files.totalSize(f))}',
                                style: context.text.mono.copyWith(
                                  color: c.textFaint,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(
                            Icons.add_circle_outline,
                            size: 20,
                          ),
                          onTap: () => Navigator.pop(context, f),
                        );
                      },
                    ),
                    if (other.isNotEmpty)
                      SliverMainAxisGroup(
                        slivers: [
                          SliverList.list(
                            children: [
                              const SizedBox(height: AppSpace.md),
                              Text(
                                context.l10n.uiHfSearchPageNotAddableHere,
                                style: context.text.label.copyWith(
                                  color: c.textFaint,
                                ),
                              ),
                            ],
                          ),
                          SliverList.separated(
                            itemCount: other.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: AppSpace.md),
                            itemBuilder: (context, index) {
                              final f = other[index];
                              return ListTile(
                                dense: true,
                                enabled: false,
                                title: Text(f.name, style: context.text.mono),
                                subtitle: Text(
                                  f.isProjector
                                      ? context.l10n.hfVisionProjector
                                      : context.l10n.hfSplitFile,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _gb(int bytes) =>
    '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
