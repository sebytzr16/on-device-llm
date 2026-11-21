import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';
import '../../core/platform/engine_versions.dart';
import '../../features/settings/presentation/widgets/settings_widgets.dart';
import '../../inference/engine/engine_registry_provider.dart';
import 'engine_update_controller.dart';
import 'engine_updater.dart';

/// The localized text for a failed engine check or install: the updater
/// returns a typed reason and keeps the raw detail in the log, so no English
/// from the engine code reaches the UI (release review P2 l10n).
String engineUpdateProblemText(
  AppLocalizations t,
  EngineUpdateProblem? problem,
) => switch (problem) {
  EngineUpdateProblem.noPinnedBuild => t.engineUpdateProblemNoPinnedBuild,
  EngineUpdateProblem.noUpdateAvailable => t.engineUpdateProblemNoUpdate,
  EngineUpdateProblem.downloadFailed => t.engineUpdateProblemDownload,
  EngineUpdateProblem.smokeFailed => t.engineUpdateProblemSmoke,
  EngineUpdateProblem.installFailed => t.engineUpdateProblemInstall,
  EngineUpdateProblem.useBundledFailed => t.engineUpdateProblemUseBuiltIn,
  EngineUpdateProblem.removeFailed => t.engineUpdateProblemRemove,
  EngineUpdateProblem.checkFailed => t.engineUpdateProblemCheck,
  null => t.engineUpdateProblemCheck,
};

/// Settings -> Engine updates (Windows): what engine runs, the automatic
/// switch, a manual check with install, and the way back to the built-in
/// engine. Everything applies on the next model load.
class EngineUpdatePanel extends ConsumerWidget {
  const EngineUpdatePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final v = ref.watch(engineUpdateProvider);
    final n = ref.read(engineUpdateProvider.notifier);
    final installed = v.installed;
    final status = _status(context, v);
    return Column(
      key: const Key('engine-update-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsTile(
          leading: const Icon(Icons.memory_outlined),
          title: Text(t.engineUpdateTitle),
          subtitle: Text(
            installed == null
                ? t.engineUpdateBuiltIn(EnginePins.llamaCppTag)
                : t.engineUpdatePack(installed),
          ),
        ),
        if (v.reverted)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.undo, size: 18, color: context.colors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.engineUpdateReverted,
                    style: context.text.body.copyWith(
                      color: context.colors.warning,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: n.acknowledgeRevert,
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ],
            ),
          ),
        if (v.unverified)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.report_outlined,
                  size: 18,
                  color: context.colors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.engineUpdateUnverified,
                    style: context.text.body.copyWith(
                      color: context.colors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SettingsSwitchRow(
          key: const Key('engine-update-auto'),
          value: v.autoCheck,
          onChanged: (value) => n.setAutoCheck(value),
          title: Text(t.engineUpdateAuto),
          subtitle: Text(t.engineUpdateAutoHint),
        ),
        SettingsTile(
          key: const Key('engine-update-check'),
          leading: v.phase == EngineUpdatePhase.checking
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt),
          title: Text(t.engineUpdateCheckNow),
          subtitle: v.lastCheck == null
              ? null
              : Text(t.engineUpdateLastCheck(_when(context, v.lastCheck!))),
          onTap: v.busy ? null : n.checkNow,
          trailing: v.phase == EngineUpdatePhase.available
              ? FilledButton(
                  key: const Key('engine-update-install'),
                  onPressed: n.update,
                  child: Text(t.engineUpdateInstall),
                )
              : null,
        ),
        if (v.phase == EngineUpdatePhase.downloading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: v.total > 0 ? (v.received / v.total).clamp(0, 1) : null,
            ),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Text(
              status,
              style: v.phase == EngineUpdatePhase.error
                  ? context.text.body.copyWith(color: context.colors.warning)
                  : context.text.bodyMuted,
            ),
          ),
        // An installed pack that no longer verifies, or one the crash guard
        // reverted, is still on disk: keep both rows so it can be removed or
        // switched away from (P2-1, P3). Removal follows the folders alone, so
        // acknowledging the revert notice does not hide it (P2).
        if (installed != null || v.unverified || v.reverted)
          SettingsTile(
            key: const Key('engine-update-use-built-in'),
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(t.engineUpdateUseBuiltIn),
            onTap: v.busy ? null : n.useBundled,
          ),
        if (installed != null ||
            v.packsOnDisk ||
            v.unverified ||
            v.reverted ||
            v.phase == EngineUpdatePhase.ready)
          SettingsTile(
            key: const Key('engine-update-remove'),
            leading: const Icon(Icons.delete_outline),
            title: Text(t.engineUpdateRemove),
            onTap: v.busy ? null : n.removeAll,
          ),
        // The optional ik_llama.cpp engine stays out of the UI until this app
        // knows which build to install.
        if (ref.watch(ikEngineAvailableProvider)) const _IkEnginePackRow(),
      ],
    );
  }

  String? _status(BuildContext context, EngineUpdateView v) {
    final t = context.l10n;
    return switch (v.phase) {
      EngineUpdatePhase.idle || EngineUpdatePhase.checking => null,
      EngineUpdatePhase.upToDate => t.engineUpdateUpToDate,
      EngineUpdatePhase.available => t.engineUpdateAvailable(
        v.latest ?? '',
        (v.total / (1024 * 1024)).toStringAsFixed(0),
      ),
      EngineUpdatePhase.downloading => t.engineUpdateDownloading(
        v.latest ?? '',
        v.total > 0 ? '${(100 * v.received / v.total).floor()}' : '0',
      ),
      EngineUpdatePhase.ready => t.engineUpdateReady,
      EngineUpdatePhase.offline => t.engineUpdateNoGitHub,
      EngineUpdatePhase.error => t.engineUpdateFailed(
        engineUpdateProblemText(t, v.problem),
      ),
    };
  }

  String _when(BuildContext context, DateTime utcOrLocal) {
    final time = utcOrLocal.toLocal();
    final m = MaterialLocalizations.of(context);
    return '${m.formatShortDate(time)} ${m.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
  }
}

/// Settings row for the optional ik_llama.cpp pack: one press checks the
/// signed releases, installs the pack for the pinned commit, shows what the
/// check returned and leaves the llama.cpp engine untouched.
class _IkEnginePackRow extends ConsumerStatefulWidget {
  const _IkEnginePackRow();

  @override
  ConsumerState<_IkEnginePackRow> createState() => _IkEnginePackRowState();
}

class _IkEnginePackRowState extends ConsumerState<_IkEnginePackRow> {
  bool _busy = false;
  bool _upToDate = false;
  bool _offline = false;
  EngineUpdateProblem? _problem;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _problem = null;
      _offline = false;
    });
    final result = await ref
        .read(engineUpdateProvider.notifier)
        .checkIkEnginePack(install: true);
    if (!mounted) return;
    // The installed and unverified state stays the controller's: its refresh
    // reads the verified folder after every check, install and failed load.
    setState(() {
      _busy = false;
      _upToDate =
          result.state == EngineCheckState.upToDate &&
          ref.read(engineUpdateProvider).ikInstalled == null;
      // Only the typed reason reaches the UI; the raw detail stays in the log.
      _problem = result.state == EngineCheckState.error
          ? result.problem ?? EngineUpdateProblem.checkFailed
          : null;
      _offline = result.state == EngineCheckState.offline;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final view = ref.watch(engineUpdateProvider);
    final status = _offline
        ? t.engineUpdateNoGitHub
        : _problem == null
        ? null
        : t.engineUpdateFailed(engineUpdateProblemText(t, _problem));
    final subtitle = status != null
        ? Text(
            status,
            style: context.text.body.copyWith(color: context.colors.warning),
          )
        : view.ikUnverified
        ? Text(
            t.engineUpdateUnverified,
            style: context.text.body.copyWith(color: context.colors.warning),
          )
        : Text(
            view.ikInstalled != null
                ? t.engineUpdateIkInstalled(view.ikInstalled!)
                : _upToDate
                ? t.engineUpdateUpToDate
                : t.engineUpdateIkHint,
          );
    return SettingsTile(
      key: const Key('engine-update-ik'),
      leading: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.memory_outlined),
      title: Text(t.engineUpdateIkTitle),
      subtitle: subtitle,
      onTap: _busy ? null : _install,
    );
  }
}
