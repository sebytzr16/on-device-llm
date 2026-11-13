import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../data/network/hugging_face.dart';
import '../features/image_gen/domain/entities/image_gen_model.dart';
import '../features/image_gen/image_gen_imports.dart';
import '../features/models/presentation/screens/hf_search_page.dart';

/// Adds one GGUF or safetensors file from a public Hugging Face repository,
/// showing its size and licence before anything is downloaded.
Future<ImageGenModel?> showImageGenImportDialog(BuildContext context) =>
    showAppDialog<ImageGenModel>(
      context: context,
      builder: (_) => const ImageGenImportDialog(),
    );

/// Opens Hugging Face discovery for image and video generation models. The
/// search is already filtered to diffusion GGUF and Diffusers repositories.
Future<HfImageSearchResult?> showImageGenDiscovery(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    MaterialPageRoute(
      builder: (_) =>
          const HfSearchPage(imagePipeline: HfImagePipeline.textToImage),
    ),
  );
}

class ImageGenImportDialog extends ConsumerStatefulWidget {
  const ImageGenImportDialog({super.key});

  @override
  ConsumerState<ImageGenImportDialog> createState() =>
      _ImageGenImportDialogState();
}

class _ImageGenImportDialogState extends ConsumerState<ImageGenImportDialog> {
  final _repo = TextEditingController();
  ImageGenMode _mode = ImageGenMode.image;
  HfRepoFiles? _files;
  HfFile? _selected;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  List<HfFile> get _usable => [
    for (final file in _files?.files ?? const <HfFile>[])
      if (!file.isSplit &&
          !file.isProjector &&
          isSupportedImageGenFile(file.name))
        file,
  ];

  Future<void> _find() async {
    final repo = _repo.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      _files = null;
      _selected = null;
    });
    try {
      final files = await HuggingFace.files(
        repo,
        extensions: imageGenImportExtensions,
      );
      if (!mounted) return;
      setState(() {
        _files = files;
        final usable = _usable;
        _selected = usable.length == 1 ? usable.single : null;
        _error = null;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _add() {
    final files = _files, file = _selected;
    if (files == null || file == null) return;
    try {
      Navigator.pop(
        context,
        importedImageGenModel(
          repo: files.repo,
          revision: files.revision,
          file: file,
          license: files.license,
          mode: _mode,
        ),
      );
    } on FormatException {
      setState(() => _error = context.l10n.imageImportUnsupported(file.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final files = _files;
    final usable = _usable;
    final selected = _selected;
    return AlertDialog(
      title: Text(context.l10n.imageImportTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('image-import-repo'),
                controller: _repo,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: context.l10n.imageImportRepo,
                  hintText: context.l10n.imageImportRepoHint,
                  isDense: true,
                ),
                onSubmitted: (_) => _find(),
              ),
              const SizedBox(height: AppDesign.md),
              Text(context.l10n.imageImportMode, style: context.text.label),
              const SizedBox(height: AppDesign.xs),
              SegmentedButton<ImageGenMode>(
                segments: [
                  ButtonSegment(
                    value: ImageGenMode.image,
                    label: Text(context.l10n.imageModeImage),
                  ),
                  ButtonSegment(
                    value: ImageGenMode.video,
                    label: Text(context.l10n.imageVideo),
                  ),
                  ButtonSegment(
                    value: ImageGenMode.upscale,
                    label: Text(context.l10n.imageUpscale),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _loading
                    ? null
                    : (value) => setState(() => _mode = value.single),
              ),
              const SizedBox(height: AppDesign.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('image-import-find'),
                  onPressed: _loading ? null : _find,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search, size: 16),
                  label: Text(context.l10n.imageImportFind),
                ),
              ),
              if (files != null) ...[
                const SizedBox(height: AppDesign.md),
                Text(files.repo, style: context.text.monoStrong),
                Text(
                  context.l10n.licenseLabel(files.license),
                  style: context.text.small,
                ),
                const SizedBox(height: AppDesign.sm),
                if (usable.isEmpty)
                  Text(
                    context.l10n.imageImportNoSupported,
                    style: context.text.small.copyWith(color: c.danger),
                  )
                else
                  DropdownButtonFormField<HfFile>(
                    key: ValueKey(
                      'image-import-file-${files.repo}-${files.revision}',
                    ),
                    initialValue: selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.l10n.imageImportFile,
                      isDense: true,
                    ),
                    items: [
                      for (final file in usable)
                        DropdownMenuItem(
                          value: file,
                          child: Text(
                            '${file.name} · ${_size(file.size)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (file) => setState(() => _selected = file),
                  ),
              ],
              if (selected != null) ...[
                const SizedBox(height: AppDesign.sm),
                Text(
                  '${_size(selected.size)} · '
                  '${context.l10n.licenseLabel(files!.license)}',
                  style: context.text.caption,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppDesign.sm),
                Text(
                  _error!,
                  style: context.text.small.copyWith(color: c.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const Key('image-import-add'),
          onPressed: selected == null ? null : _add,
          child: Text(context.l10n.imageImportDownload),
        ),
      ],
    );
  }
}

String _size(int bytes) => bytes < 1 << 30
    ? '${(bytes / (1 << 20)).round()} MB'
    : '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
