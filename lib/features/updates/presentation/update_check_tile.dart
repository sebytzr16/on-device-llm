import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';
import '../../../core/design/app_sheet.dart';
import '../../../core/island/status_island.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/motion/motion.dart';
import '../../../core/utils/external_links.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../update_checker.dart';

/// Settings > About: the manual check (owner request, 2026-11-08). No call is
/// made until this row is tapped.
class UpdateCheckTile extends StatefulWidget {
  final UpdateChecker? checker;

  const UpdateCheckTile({super.key, this.checker});

  @override
  State<UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<UpdateCheckTile> {
  late final UpdateChecker _checker;
  UpdateCheck? _result;

  @override
  void initState() {
    super.initState();
    _checker = widget.checker ?? UpdateChecker();
  }

  Future<void> _check() async {
    if (_result?.status == UpdateStatus.checking) return;
    setState(() => _result = UpdateCheck.checking(_checker.currentVersion));
    final result = await _checker.check();
    if (!mounted) return;
    setState(() => _result = result);
    final release = result.release;
    if (result.status == UpdateStatus.available && release != null) {
      await _showRelease(result, release);
    }
  }

  Future<void> _showRelease(UpdateCheck result, UpdateRelease release) =>
      showMorphSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => AppSheet(
          title: sheet.l10n.updateReleaseNotesTitle(release.version),
          meta: sheet.l10n.updateCurrentVersion(result.currentVersion),
          primary: FilledButton.icon(
            key: const Key('open-release-page'),
            onPressed: () => _openRelease(sheet, release.pageUrl),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(sheet.l10n.updateOpenReleasePage),
          ),
          children: [
            Text(
              release.notes.isEmpty
                  ? sheet.l10n.updateNoReleaseNotes
                  : release.notes,
              style: sheet.text.body,
            ),
          ],
        ),
      );

  Future<void> _openRelease(BuildContext sheet, String url) async {
    try {
      await openExternalLink(url);
      if (sheet.mounted) Navigator.maybePop(sheet);
    } catch (_) {
      if (sheet.mounted) {
        showIslandToast(
          sheet,
          sheet.l10n.couldNotOpenLink,
          tone: IslandTone.error,
        );
      }
    }
  }

  String _subtitle(AppLocalizations t) {
    final result = _result;
    if (result == null) return t.updateCheckHint;
    return switch (result.status) {
      UpdateStatus.checking => t.checkingForUpdates,
      UpdateStatus.upToDate => t.updateUpToDate(result.currentVersion),
      UpdateStatus.available => t.updateAvailable(
        result.release?.version ?? result.currentVersion,
      ),
      UpdateStatus.offline => t.updateCheckOffline,
      UpdateStatus.failed => t.updateCheckFailed,
    };
  }

  Widget _trailing() {
    if (_result?.status == UpdateStatus.checking) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      _result?.status == UpdateStatus.available
          ? Icons.open_in_new
          : Icons.chevron_right,
      size: 18,
      color: context.colors.textMuted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return SettingsRow(
      key: const Key('check-for-updates'),
      leading: const Icon(Icons.system_update_alt),
      title: Text(t.checkForUpdates),
      subtitle: Text(_subtitle(t)),
      trailing: _trailing(),
      onTap: _check,
    );
  }
}
