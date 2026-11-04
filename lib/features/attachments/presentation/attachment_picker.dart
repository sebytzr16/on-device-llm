import '../../../core/motion/motion.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/presentation/providers/effective_settings_provider.dart';
import '../../../inference/remote/workspace_client.dart';

import '../../../core/design/app_design.dart';
import '../../../core/design/app_sheet.dart';
import '../../../core/platform/desktop_host.dart';
import '../data/attachment_store.dart';
import '../domain/attachment.dart';
import '../domain/scan_options.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/island/status_island.dart';

/// Longest side a picked photo is scaled to before it reaches the model.
const double kPhotoMaxSide = 1280;

/// One choice in the attachment sheet's row: an icon over a short label,
/// with the longer explanation as its tooltip. [onTap] gets the sheet's
/// context (to close it).
class AttachTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final void Function(BuildContext sheet) onTap;
  const AttachTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tile = Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.hairline),
        borderRadius: AppDesign.radius(AppDesign.rMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.xs,
            vertical: AppDesign.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppDesign.sm,
            children: [
              Icon(icon, color: c.accent),
              Text(
                label,
                style: context.text.small.copyWith(color: c.text),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip, child: tile);
  }
}

/// Bottom sheet: camera, photo library or any document. Returns the imported
/// attachments (already copied and text-extracted), or an empty list.
/// [source] skips the sheet: 'camera', 'gallery' or 'file'. [more] joins the
/// row of choices and [below] goes under it (the chat adds its tool
/// switches). The choices sit in one row so the sheet fits without
/// scrolling (tester, 2026-10-20). [from] is the button tapped: the sheet
/// grows out of it.
Future<List<Attachment>> pickAttachments(
  BuildContext context, {
  String? source,
  List<AttachTile> more = const [],
  List<Widget> below = const [],
  BuildContext? from,
}) async {
  final choice =
      source ??
      await showMorphSheet<String>(
        context: context,
        from: from,
        isScrollControlled: below.isNotEmpty,
        builder: (context) => AppSheet(
          title: context.l10n.sheetAttachments,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppDesign.sm,
              children: [
                for (final tile in [
                  // Windows has no image_picker camera.
                  if (!DesktopHost.active)
                    AttachTile(
                      key: const Key('attach-camera'),
                      icon: Icons.photo_camera_outlined,
                      label: context.l10n.attachCamera,
                      tooltip: context.l10n.takePhoto,
                      onTap: (sheet) => Navigator.pop(sheet, 'camera'),
                    ),
                  AttachTile(
                    key: const Key('attach-gallery'),
                    icon: Icons.photo_library_outlined,
                    label: context.l10n.photos,
                    tooltip: context.l10n.photosHint,
                    onTap: (sheet) => Navigator.pop(sheet, 'gallery'),
                  ),
                  AttachTile(
                    key: const Key('attach-file'),
                    icon: Icons.attach_file,
                    label: context.l10n.attachFile,
                    tooltip: context.l10n.documentHint,
                    onTap: (sheet) => Navigator.pop(sheet, 'file'),
                  ),
                  ...more,
                ])
                  Expanded(child: tile),
              ],
            ),
            ...below,
          ],
        ),
      );
  if (choice == null || !context.mounted) return const [];
  final sources = <(String name, String? path, Uint8List? bytes)>[];
  try {
    switch (choice) {
      // A 12 MP photo is resized by the vision encoder anyway; handing it
      // over at 1280 px saves the decode and ~7 MB per bitmap on the phone.
      case 'camera':
        final x = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: kPhotoMaxSide,
          maxHeight: kPhotoMaxSide,
          imageQuality: 90,
        );
        if (x != null) sources.add((x.name, x.path, null));
      case 'gallery':
        for (final x in await ImagePicker().pickMultiImage(
          limit: 6,
          maxWidth: kPhotoMaxSide,
          maxHeight: kPhotoMaxSide,
          imageQuality: 90,
        )) {
          sources.add((x.name, x.path, null));
        }
      case 'file':
        final files = await FilePicker.pickFiles(type: FileType.any);
        for (final f in files) {
          if ((await f.length() ?? 0) > AttachmentStore.maxDocumentBytes) {
            throw const FormatException('File is larger than 64 MB.');
          }
          sources.add((
            f.name,
            f.path,
            f.path == null ? await f.readAsBytes() : null,
          ));
        }
    }
  } catch (e) {
    if (context.mounted) {
      showIslandToast(
        context,
        context.l10n.couldNotOpenPicker('$e'),
        tone: IslandTone.error,
      );
    }
    return const [];
  }
  if (sources.isEmpty || !context.mounted) return const [];
  return importAttachments(context, sources);
}

/// Imports files (name, path or bytes) behind a progress dialog; failures
/// are listed in a snackbar. Used by the picker and by shared files.
Future<List<Attachment>> importAttachments(
  BuildContext context,
  List<(String, String?, Uint8List?)> sources, {
  @visibleForTesting
  Future<Attachment> Function({
        required String name,
        String? sourcePath,
        Uint8List? bytes,
        bool Function()? cancelled,
        void Function(int page, int total)? progress,
      })
      importFile =
      AttachmentStore.import,
}) async {
  final localeCode = context.l10n.localeName;
  var deferProcessing = false;
  if (importFile == AttachmentStore.import) {
    final settings = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(effectiveSettingsProvider).effective;
    if (settings.usesRemote) {
      final client = WorkspaceClient();
      try {
        deferProcessing = await client.supported(settings);
      } finally {
        client.dispose();
      }
      if (!context.mounted) return const [];
    }
  }
  final importLocalized = importFile == AttachmentStore.import
      ? ({
          required String name,
          String? sourcePath,
          Uint8List? bytes,
          bool Function()? cancelled,
          void Function(int, int)? progress,
        }) => AttachmentStore.import(
          name: name,
          sourcePath: sourcePath,
          bytes: bytes,
          localeCode: localeCode,
          deferProcessing: deferProcessing,
          cancelled: cancelled,
          progress: progress,
        )
      : importFile;
  final out = <Attachment>[];
  final failures = <String>[];
  var cancelled = false;
  final progress = ValueNotifier<String>(context.l10n.readingAttachments);
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancelled = true;
      },
      child: AlertDialog(
        content: Row(
          spacing: AppDesign.md,
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (_, value, _) => Text(value),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
            },
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    ),
  );
  final done = navigator.push(route);
  for (final (name, path, bytes) in sources) {
    if (cancelled || !context.mounted) break;
    try {
      out.add(
        await importLocalized(
          name: name,
          sourcePath: path,
          bytes: bytes,
          cancelled: () => cancelled || !context.mounted,
          progress: (page, total) => progress.value = '$name · $page / $total',
        ),
      );
    } on ScanCancelled {
      break;
    } catch (e) {
      failures.add('$name: $e');
    }
  }
  if (route.isActive) navigator.removeRoute(route);
  if (context.mounted) {
    if (failures.isNotEmpty) {
      showIslandToast(context, failures.join('\n'), tone: IslandTone.error);
    }
  }
  await done.catchError((_) {});
  await route.completed;
  progress.dispose();
  return out;
}
