import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n.dart';
import '../../data/local/database/app_database.dart';
import 'backup_cipher.dart';
import 'local_backup_service.dart';
import '../../core/design/app_design.dart';
import '../../core/design/app_dialog.dart';
import '../../core/island/status_island.dart';
import '../settings/presentation/widgets/settings_widgets.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _working = false;
  String? _notice;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final t = context.l10n;
    if (_password.text.length < BackupCipher.minPasswordLength) {
      setState(() => _notice = t.backupPasswordTooShort);
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _notice = t.backupPasswordsMismatch);
      return;
    }
    setState(() {
      _working = true;
      _notice = null;
    });
    File? file;
    try {
      file = await LocalBackupService.createFile(
        ref.read(appDatabaseProvider),
        _password.text,
      );
      if (!mounted) return;
      final action = await _showSaveDialog(context);
      if (action == _SaveAction.share) {
        await _shareBackup(file, t);
      } else if (action == _SaveAction.saveToFile) {
        await _saveBackupToFile(file, t);
      }
    } catch (error) {
      if (mounted) {
        showIslandToast(
          context,
          t.backupFailedNotice('$error'),
          tone: IslandTone.error,
        );
      }
    } finally {
      if (file != null && await file.exists()) await file.delete();
      if (mounted) setState(() => _working = false);
    }
  }

  /// Owner 2026-11-12: a backup can be saved to a file here, not only
  /// shared.
  Future<_SaveAction?> _showSaveDialog(BuildContext context) {
    final t = context.l10n;
    return showModalBottomSheet<_SaveAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: Text(t.backupSaveToFile),
              onTap: () => Navigator.pop(context, _SaveAction.saveToFile),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(t.backupShareAction),
              onTap: () => Navigator.pop(context, _SaveAction.share),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareBackup(File file, AppLocalizations t) async {
    final box = mounted ? context.findRenderObject() as RenderBox? : null;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        fileNameOverrides: ['ondevice-llm-backup.odllm'],
        subject: t.backupSaveDialog,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    if (!mounted) return;
    showIslandToast(
      context,
      result.status == ShareResultStatus.dismissed
          ? t.backupSaveCancelled
          : result.status == ShareResultStatus.success
          ? t.backupSavedNotice
          : t.backupExportReady,
      tone: result.status == ShareResultStatus.success
          ? IslandTone.done
          : IslandTone.info,
    );
  }

  Future<void> _saveBackupToFile(File file, AppLocalizations t) async {
    try {
      // Android writes through the system picker and needs the bytes; the
      // desktop picker returns a path and the file is copied there.
      final android = Platform.isAndroid;
      final saved = await FilePicker.saveFile(
        dialogTitle: t.backupSaveToFile,
        fileName: 'ondevice-llm-backup.odllm',
        bytes: android ? await file.readAsBytes() : Uint8List(0),
        type: FileType.custom,
        allowedExtensions: ['odllm'],
      );
      if (saved != null && !android) await file.copy(saved.toFilePath());
      if (!mounted) return;
      showIslandToast(
        context,
        saved != null ? t.backupSavedToFile : t.backupSaveCancelled,
        tone: saved != null ? IslandTone.done : IslandTone.info,
      );
    } catch (error) {
      if (mounted) {
        showIslandToast(
          context,
          t.backupSaveFailed('$error'),
          tone: IslandTone.error,
        );
      }
    }
  }

  Future<void> _restore() async {
    final t = context.l10n;
    if (_password.text.isEmpty) {
      setState(() => _notice = t.backupEnterPassword);
      return;
    }
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['odllm'],
    );
    if (picked == null) return;
    if (!mounted) return;
    final approved = await confirmAction(
      context,
      title: t.backupReplaceQuestion,
      message: t.backupReplaceHint,
      confirmLabel: t.backupRestoreAction,
    );
    if (approved != true || !mounted) return;
    setState(() {
      _working = true;
      _notice = null;
    });
    try {
      final path = picked.path;
      if ((await picked.length() ?? 0) > BackupCipher.maxFileBytes + 52) {
        throw FormatException(t.backupTooLarge);
      }
      if (path != null &&
          await File(path).length() > BackupCipher.maxFileBytes + 52) {
        throw FormatException(t.backupTooLarge);
      }
      if (path != null) {
        await LocalBackupService.stageFile(File(path), _password.text);
      } else {
        if ((await picked.length() ?? 0) > BackupCipher.maxEncryptedBytes) {
          throw FormatException(t.backupTooLarge);
        }
        await LocalBackupService.stage(
          Uint8List.fromList(await picked.readAsBytes()),
          _password.text,
        );
      }
      if (mounted) {
        showIslandToast(context, t.backupVerifiedNotice, tone: IslandTone.done);
      }
    } catch (error) {
      if (mounted) {
        showIslandToast(
          context,
          t.backupRestoreFailed('$error'),
          tone: IslandTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final minLen = BackupCipher.minPasswordLength;
    return Scaffold(
      appBar: AppBar(title: Text(t.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppDesign.lg),
        children: [
          Text(t.backupIntro),
          SettingsSection(
            label: t.backupPasswordLabel,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppDesign.lg),
                child: Column(
                  spacing: AppDesign.md,
                  children: [
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t.backupPasswordLabel,
                        helperText: t.backupPasswordMinLength(minLen),
                        counterText: _password.text.length < minLen
                            ? '${_password.text.length}/$minLen'
                            : '',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      controller: _confirmation,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t.backupConfirmPassword,
                        helperText: _password.text.isNotEmpty
                            ? (_password.text == _confirmation.text
                                  ? t.backupPasswordsMatch
                                  : t.backupPasswordsMismatch)
                            : null,
                        helperStyle: TextStyle(
                          color:
                              _password.text.isNotEmpty &&
                                  _password.text == _confirmation.text
                              ? c.success
                              : c.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesign.xl),
          FilledButton.icon(
            onPressed: _working ? null : _create,
            icon: const Icon(Icons.lock_outline),
            label: Text(t.backupCreateAction),
          ),
          OutlinedButton.icon(
            onPressed: _working ? null : _restore,
            icon: const Icon(Icons.restore),
            label: Text(t.backupRestoreBackup),
          ),
          if (_working) const LinearProgressIndicator(),
          if (_notice != null) ...[
            const SizedBox(height: AppDesign.lg),
            Text(_notice!),
          ],
        ],
      ),
    );
  }
}

enum _SaveAction { saveToFile, share }
