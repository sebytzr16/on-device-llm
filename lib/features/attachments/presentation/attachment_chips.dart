import 'dart:io';

import 'package:flutter/material.dart';

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
  const AttachmentChips({super.key, required this.attachments, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: AppDesign.sm,
      runSpacing: AppDesign.sm,
      children: [
        for (final a in attachments)
          a.isImage
              ? _Thumb(a, onRemove: onRemove)
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
  const _Thumb(this.a, {this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => AttachmentChips._showText(context, a),
          child: ClipRRect(
            borderRadius: AppDesign.radius(AppDesign.rMd),
            child: Image.file(
              File(a.path),
              key: Key('attachment-${a.id}'),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 72,
                height: 72,
                color: c.surfaceRaised,
                child: Icon(Icons.broken_image_outlined, color: c.textFaint),
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
