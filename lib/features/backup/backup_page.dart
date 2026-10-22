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
import '../settings/presentation/widgets/settings_widgets.dart';
import '../../core/design/app_dialog.dart';

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
    if (_password.text.length < 12) {
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
    try {
      final file = await LocalBackupService.createFile(
        ref.read(appDatabaseProvider),
        _password.text,
      );
      try {
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
        if (mounted) {
          setState(
            () => _notice = result.status == ShareResultStatus.dismissed
                ? t.backupSaveCancelled
                : result.status == ShareResultStatus.success
                ? t.backupSavedNotice
                : t.backupExportReady,
          );
        }
      } finally {
        if (await file.exists()) await file.delete();
      }
    } catch (error) {
      if (mounted) setState(() => _notice = t.backupFailedNotice('$error'));
    } finally {
      if (mounted) setState(() => _working = false);
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
        setState(() => _notice = t.backupVerifiedNotice);
      }
    } catch (error) {
      if (mounted) setState(() => _notice = t.backupRestoreFailed('$error'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.backupTitle)),
    body: ListView(
      padding: const EdgeInsets.all(AppDesign.lg),
      children: [
        Text(context.l10n.backupIntro),
        SettingsSection(
          label: context.l10n.backupPasswordLabel,
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
                      labelText: context.l10n.backupPasswordLabel,
                    ),
                  ),
                  TextField(
                    controller: _confirmation,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: context.l10n.backupConfirmPassword,
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
          label: Text(context.l10n.backupCreateAction),
        ),
        OutlinedButton.icon(
          onPressed: _working ? null : _restore,
          icon: const Icon(Icons.restore),
          label: Text(context.l10n.backupRestoreBackup),
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
