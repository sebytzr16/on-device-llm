import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../features/settings/presentation/widgets/settings_widgets.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../data/storage/model_folders.dart';
import '../data/storage/model_storage.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';

class ModelsFolderSetting extends ConsumerStatefulWidget {
  const ModelsFolderSetting({super.key});
  @override
  ConsumerState<ModelsFolderSetting> createState() =>
      _ModelsFolderSettingState();
}

class _ModelsFolderSettingState extends ConsumerState<ModelsFolderSetting> {
  late Future<ModelFolders> _folders = ModelStorage.desktopFolders();
  bool _busy = false;
  double? _progress;
  String? _error;

  Future<void> _change(String target) async {
    final t = context.l10n;
    final move = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.desktopModelsFolder),
        content: Text(t.desktopModelsFolderChoice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t.desktopModelsFolderLeave),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t.desktopModelsFolderMove),
          ),
        ],
      ),
    );
    if (move == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      await ref
          .read(modelManagerProvider.notifier)
          .changeModelsFolder(
            Directory(target),
            move: move,
            onProgress: (value) {
              if (mounted) setState(() => _progress = value);
            },
          );
      if (mounted) setState(() => _folders = ModelStorage.desktopFolders());
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error) {
            ModelFolderException(
              reason: ModelFolderFailure.insufficientSpace,
            ) =>
              t.desktopModelsFolderSpace,
            ModelFolderException(reason: ModelFolderFailure.conflict) =>
              t.desktopModelsFolderConflict,
            ModelFolderException(reason: ModelFolderFailure.busy) =>
              t.desktopModelsFolderBusy,
            _ => t.desktopModelsFolderWritable,
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return FutureBuilder<ModelFolders>(
      future: _folders,
      builder: (context, snapshot) {
        final folders = snapshot.data;
        return SettingsTile(
          title: Text(t.desktopModelsFolder),
          leading: const Icon(Icons.folder_outlined),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpace.row),
              if (folders != null)
                SelectableText(folders.current.path, style: context.text.mono),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy || folders == null
                        ? null
                        : () async {
                            final path = await FilePicker.getDirectoryPath(
                              initialDirectory: folders.current.path,
                            );
                            if (path != null && mounted) {
                              await _change(path);
                            }
                          },
                    child: Text(t.desktopModelsFolderChange),
                  ),
                  OutlinedButton(
                    onPressed: _busy || folders == null
                        ? null
                        : () async {
                            try {
                              await folders.current.create(recursive: true);
                              await Process.start('explorer.exe', [
                                folders.current.path,
                              ]);
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _error = t.desktopModelsFolderOpenError,
                                );
                              }
                            }
                          },
                    child: Text(t.desktopModelsFolderOpen),
                  ),
                  TextButton(
                    onPressed: _busy || folders == null
                        ? null
                        : () => _change(folders.defaultDirectory.path),
                    child: Text(t.desktopModelsFolderReset),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _progress,
                  semanticsLabel: t.desktopModelsFolderMoving,
                ),
                const SizedBox(height: AppSpace.row),
                Text(t.desktopModelsFolderMoving),
              ],
              if (_error != null || snapshot.hasError) ...[
                const SizedBox(height: AppSpace.row),
                Text(
                  _error ?? t.desktopModelsFolderWritable,
                  style: context.text.small.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
