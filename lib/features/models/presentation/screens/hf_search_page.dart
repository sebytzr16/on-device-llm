import '../../../../core/l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../data/network/hugging_face.dart';
import '../../domain/entities/model_info.dart';
import '../providers/model_manager_provider.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/motion/motion.dart';

/// Models > Search Hugging Face (FX-12): find any public GGUF repository,
/// pick a quantization, and add it to the library with its verified digest.
class HfSearchPage extends ConsumerStatefulWidget {
  const HfSearchPage({super.key});
  @override
  ConsumerState<HfSearchPage> createState() => _HfSearchPageState();
}

class _HfSearchPageState extends ConsumerState<HfSearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<HfRepo>? _results;
  String? _error;
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await HuggingFace.search(q);
      if (mounted && _query.text == q) setState(() => _results = r);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('FormatException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _open(HfRepo repo) async {
    setState(() => _error = null);
    final HfRepoFiles files;
    try {
      files = await HuggingFace.files(repo.id);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('FormatException: ', ''));
      }
      return;
    }
    if (!mounted) return;
    final picked = await showMorphSheet<HfFile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FilesSheet(files: files),
    );
    if (picked == null || !mounted) return;
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
    final library = ref.watch(modelManagerProvider).catalog;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.uiHfSearchPageSearchHuggingFace)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.lg,
                AppDesign.sm,
                AppDesign.lg,
                AppDesign.sm,
              ),
              child: TextField(
                key: const Key('hf-query'),
                controller: _query,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: context.l10n.uiHfSearchPageModelNameEGQwen34B,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(AppDesign.md),
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
                padding: const EdgeInsets.symmetric(horizontal: AppDesign.lg),
                child: Text(
                  _error!,
                  style: context.text.bodyMuted.copyWith(color: c.danger),
                ),
              ),
            Expanded(
              child: _results == null
                  ? Padding(
                      padding: const EdgeInsets.all(AppDesign.xl),
                      child: Text(
                        context.l10n.hfIntro,
                        style: context.text.bodyMuted,
                      ),
                    )
                  : _results!.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.uiHfSearchPageNoGGUFRepositoriesMatch,
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
                          title: Text(
                            r.id,
                            style: context.text.mono.copyWith(color: c.text),
                          ),
                          subtitle: Text(
                            '${context.l10n.hfRepoStats(_count(r.downloads), r.likes)}'
                            '${r.lastModified != null ? ' · ${r.lastModified!.toIso8601String().substring(0, 10)}' : ''}'
                            '${have ? ' · ${context.l10n.hfInLibrary}' : ''}',
                            style: context.text.mono.copyWith(
                              color: c.textFaint,
                            ),
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
  const _FilesSheet({required this.files});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final usable = files.files
        .where((f) => !f.isProjector && !f.isSplit)
        .toList();
    final other = files.files.where((f) => f.isProjector || f.isSplit).toList();
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
                        if (usable.isEmpty)
                          Text(
                            context
                                .l10n
                                .uiHfSearchPageNoSingleFileGGUFWeightsIn,
                            style: context.text.bodyMuted,
                          ),
                      ],
                    ),
                    SliverList.separated(
                      itemCount: usable.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppDesign.md),
                      itemBuilder: (context, index) {
                        final f = usable[index];
                        return ListTile(
                          key: Key('hf-file-${f.name}'),
                          dense: true,
                          title: Text(
                            f.name,
                            style: context.text.mono.copyWith(color: c.text),
                          ),
                          subtitle: Text(
                            '${f.quantization.name.toUpperCase()} · ${(f.size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
                            style: context.text.mono.copyWith(
                              color: c.textFaint,
                            ),
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
                              const SizedBox(height: AppDesign.md),
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
                                const SizedBox(height: AppDesign.md),
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
