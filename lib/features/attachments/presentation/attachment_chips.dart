import 'dart:io';
import 'dart:typed_data';
import '../../../core/storage/device_encryption.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/island/status_island.dart';

import '../../../core/design/app_design.dart';
import '../../../core/design/app_sheet.dart';
import '../domain/attachment.dart';
import '../../../core/motion/motion.dart';
import '../../../core/l10n/l10n.dart';

/// Thumbnails for photos, name chips for documents. [onRemove] turns the
/// row into the composer's pending list; without it the row is read-only
/// (a sent turn) and tapping a document shows its extracted text.
class AttachmentChips extends StatelessWidget {
  final List<Attachment> attachments;
  final ValueChanged<Attachment>? onRemove;

  /// Bigger previews, for pictures an answer made (generate_image).
  final bool large;
  const AttachmentChips({
    super.key,
    required this.attachments,
    this.onRemove,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: AppDesign.sm,
      runSpacing: AppDesign.sm,
      children: [
        for (final a in attachments)
          a.isImage
              ? _Thumb(a, onRemove: onRemove, large: large)
              : InputChip(
                  key: Key('attachment-${a.id}'),
                  avatar: Icon(
                    a.text == null
                        ? Icons.error_outline
                        : Icons.description_outlined,
                    size: 16,
                    color: a.text == null ? c.warning : c.textMuted,
                  ),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      a.name,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.mono.copyWith(color: c.text),
                    ),
                  ),
                  onDeleted: onRemove == null ? null : () => onRemove!(a),
                  onPressed: onRemove == null
                      ? () => _showText(context, a)
                      : null,
                ),
      ],
    );
  }

  static void _showText(
    BuildContext context,
    Attachment a,
  ) => showMorphSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final c = context.colors;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (context, scroll) => AppSheet(
          title: a.name,
          meta:
              '${a.mime} · ${(a.sizeBytes / 1024).toStringAsFixed(0)} KB'
              '${a.text != null ? ' · ${a.text!.length} characters given to the model' : ''}',
          scrollable: false,
          children: [
            ListView(
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                if (a.isImage && a.text != null ||
                    a.text?.contains('(OCR;') == true) ...[
                  Text(
                    context.l10n.scanQualityHint,
                    style: context.text.bodyMuted,
                  ),
                  if (a.ocrConfidence != null)
                    Text(
                      '${context.l10n.scanConfidence} · ${(a.ocrConfidence! * 100).round()}%',
                      style: context.text.bodyMuted,
                    ),
                  const SizedBox(height: AppDesign.sm),
                ],
                SelectableText(
                  a.text ?? a.error ?? 'No text.',
                  style: a.text == null
                      ? context.text.bodyMuted.copyWith(color: c.warning)
                      : context.text.body,
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _Thumb extends StatelessWidget {
  final Attachment a;
  final ValueChanged<Attachment>? onRemove;
  final bool large;
  const _Thumb(this.a, {this.onRemove, this.large = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = large ? 240.0 : 72.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          // A sent picture opens full size (zoom + save); a pending one in
          // the composer still shows what the model will be given.
          onTap: () => onRemove == null
              ? showAttachmentImageViewer(context, a)
              : AttachmentChips._showText(context, a),
          child: MouseRegion(
            cursor: SystemMouseCursors.zoomIn,
            child: ClipRRect(
              borderRadius: AppDesign.radius(AppDesign.rMd),
              child: FutureBuilder<Uint8List>(
                future: DeviceEncryption.instance.read(File(a.path)),
                builder: (context, snapshot) => snapshot.hasData
                    ? Image.memory(
                        snapshot.data!,
                        key: Key('attachment-${a.id}'),
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: size,
                          height: size,
                          color: c.surfaceRaised,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: c.textFaint,
                          ),
                        ),
                      )
                    : SizedBox(
                        width: size,
                        height: size,
                        child: Icon(
                          snapshot.hasError
                              ? Icons.lock_outline
                              : Icons.image_outlined,
                        ),
                      ),
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: c.surfaceOverlay,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onRemove!(a),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-screen picture: zoom, Save (a decrypted copy, through the system
/// save dialog) and, when there is any, the text the model was given.
Future<void> showAttachmentImageViewer(BuildContext context, Attachment a) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _ImageViewer(a, opener: context),
    );

class _ImageViewer extends StatefulWidget {
  final Attachment a;

  /// Shows the "Saved to" toast once the viewer has closed (a toast under
  /// the dialog's barrier would not be seen).
  final BuildContext opener;
  const _ImageViewer(this.a, {required this.opener});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final Future<Uint8List> _bytes = DeviceEncryption.instance.read(
    File(widget.a.path),
  );

  Future<void> _save() async {
    final l = context.l10n;
    final a = widget.a;
    try {
      final bytes = await _bytes;
      final named = p.extension(a.name).replaceFirst('.', '');
      // Chat pictures are named "Generated image" with no extension; take
      // it from the MIME type so the saved file opens anywhere.
      final ext = named.isNotEmpty
          ? named
          : switch (a.mime) {
              'image/jpeg' => 'jpg',
              'image/webp' => 'webp',
              'image/gif' => 'gif',
              'image/bmp' => 'bmp',
              _ => 'png',
            };
      final saved = await FilePicker.saveFile(
        dialogTitle: l.imageSavePicture,
        fileName: named.isEmpty ? '${a.name}.$ext' : a.name,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      final path = saved?.toFilePath();
      if (path == null || !mounted) return;
      Navigator.of(context).pop();
      final opener = widget.opener;
      if (opener.mounted) {
        showIslandToast(opener, l.imageSaved(path), tone: IslandTone.done);
      }
    } catch (e) {
      if (mounted) {
        showIslandToast(context, l.exportFailed('$e'), tone: IslandTone.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final a = widget.a;
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(
                child: FutureBuilder<Uint8List>(
                  future: _bytes,
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.memory(
                          snapshot.data!,
                          key: const Key('attachment-viewer-image'),
                          fit: BoxFit.contain,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          Positioned(
            top: AppDesign.md,
            right: AppDesign.md,
            child: SafeArea(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.text != null || a.error != null) ...[
                    IconButton.filledTonal(
                      tooltip: l.attachmentDetails,
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => AttachmentChips._showText(context, a),
                    ),
                    const SizedBox(width: AppDesign.sm),
                  ],
                  IconButton.filledTonal(
                    key: const Key('attachment-viewer-save'),
                    tooltip: l.imageSavePicture,
                    icon: const Icon(Icons.download_outlined),
                    onPressed: _save,
                  ),
                  const SizedBox(width: AppDesign.sm),
                  IconButton.filledTonal(
                    key: const Key('attachment-viewer-close'),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
