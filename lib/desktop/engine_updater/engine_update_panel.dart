import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';
import '../../core/platform/engine_versions.dart';
import '../../features/settings/presentation/widgets/settings_widgets.dart';
import 'engine_update_controller.dart';

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
        if (installed != null)
          SettingsTile(
            key: const Key('engine-update-use-built-in'),
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(t.engineUpdateUseBuiltIn),
            onTap: v.busy ? null : n.useBundled,
          ),
        if (installed != null || v.phase == EngineUpdatePhase.ready)
          SettingsTile(
            key: const Key('engine-update-remove'),
            leading: const Icon(Icons.delete_outline),
            title: Text(t.engineUpdateRemove),
            onTap: v.busy ? null : n.removeAll,
          ),
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
      EngineUpdatePhase.error => t.engineUpdateFailed(v.message ?? ''),
    };
  }

  String _when(BuildContext context, DateTime utcOrLocal) {
    final time = utcOrLocal.toLocal();
    final m = MaterialLocalizations.of(context);
    return '${m.formatShortDate(time)} ${m.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
  }
}
