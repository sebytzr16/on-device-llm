import '../../../../core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../domain/entities/inference_settings.dart';
import '../../domain/setting_specs.dart';
import '../setting_labels.dart';
import '../../domain/settings_scope.dart';
import '../providers/effective_settings_provider.dart';
import '../widgets/settings_widgets.dart';
import '../../../../core/design/app_dialog.dart';

/// Effective-value inspection (roadmap P1.4): for every setting, what will
/// actually be used for the next message, which layer decided it, what the
/// other layers asked for, and whether the loaded model already runs with
/// it or will reload.
class EffectiveSettingsPage extends ConsumerWidget {
  const EffectiveSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(effectiveSettingsProvider);
    final c = context.colors;
    final engine = ref.watch(chatProvider.select((s) => s.metrics));
    final running = engine['effectiveSettings'] is Map
        ? Map<String, dynamic>.from(engine['effectiveSettings'] as Map)
        : const <String, dynamic>{};
    final json = r.effective.toJson();
    final overridden = r.overriddenKeys;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.uiEffectiveSettingsPageEffectiveSettings),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDesign.lg,
            AppDesign.sm,
            AppDesign.lg,
            AppDesign.xxl,
          ),
          children: [
            SettingsNote(
              overridden.isEmpty
                  ? context.l10n.effectiveNothingOverridden
                  : context.l10n.effectiveOverrideSummary(overridden.length),
              icon: Icons.layers_outlined,
            ),
            SettingsSection(
              label: context.l10n.sectionLayers,
              children: [
                for (final l in r.layers)
                  SettingsRow(
                    dense: true,
                    title: Text(l.label),
                    subtitle: Text(
                      l.id == SettingsLayer.idDefault
                          ? context.l10n.effectiveEverySetting
                          : l.values.isEmpty
                          ? context.l10n.effectiveLayerEmpty
                          : context.l10n.effectiveLayerSettingCount(
                              l.values.length,
                              l.values.keys.take(6).join(', '),
                              l.values.length > 6 ? '…' : '',
                            ),
                    ),
                  ),
              ],
            ),
            for (final group in SettingSpec.groups) ...[
              SettingsSection(
                label: settingGroupLabel(group, context.l10n),
                children: [
                  for (final spec in SettingSpec.visible.where(
                    (s) => s.group == group,
                  ))
                    _row(context, spec, json[spec.key], r, running, c),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _layerName(String id, AppLocalizations l10n) => switch (id) {
    SettingsLayer.idDefault => l10n.effectiveLayerDefault,
    SettingsLayer.idDevice => l10n.effectiveLayerDevice,
    SettingsLayer.idRecommended => l10n.effectiveLayerRecommended,
    SettingsLayer.idGlobal => l10n.effectiveLayerGlobal,
    SettingsLayer.idModel => l10n.effectiveLayerModel,
    SettingsLayer.idPreset => l10n.desktopSourcePreset,
    SettingsLayer.idChat => l10n.desktopSourceChat,
    SettingsLayer.idProject => l10n.desktopSourceProject,
    SettingsLayer.idTurn => l10n.effectiveLayerTurn,
    _ => id,
  };

  /// The engine's report uses a few different names for load-time keys.
  static Object? _runningValue(String key, Map<String, dynamic> running) =>
      switch (key) {
        'contextSize' => running['contextSize'],
        'kvCacheType' => running['kvCacheType'],
        'vCacheType' => running['vCacheType'],
        'ropeScaling' => running['ropeScaling'],
        'cpuThreads' => running['threads'],
        'batchThreads' => running['batchThreads'],
        'nGpuLayers' => running['requestedGpuLayers'],
        _ => null,
      };

  Widget _row(
    BuildContext context,
    SettingSpec spec,
    Object? value,
    ResolvedSettings r,
    Map<String, dynamic> running,
    AppColors c,
  ) {
    final origin = r.originOf(spec.key);
    final fromScope =
        origin == SettingsLayer.idModel ||
        origin == SettingsLayer.idPreset ||
        origin == SettingsLayer.idProject ||
        origin == SettingsLayer.idChat ||
        origin == SettingsLayer.idTurn;
    final live = _runningValue(spec.key, running);
    // Auto (0) threads and similar resolve at load; only a literal mismatch
    // means a reload is pending.
    final stale =
        spec.reloadRequired &&
        live != null &&
        value is! bool &&
        value != 0 &&
        '$live' != '$value';
    return SettingsRow(
      key: Key('effective-${spec.key}'),
      dense: true,
      title: Text(spec.labelIn(context.l10n)),
      subtitle: Text(
        '${spec.display(value)} · ${_layerName(origin, context.l10n)}'
        '${stale ? context.l10n.effectiveReloadNextMessage(spec.display(live)) : ''}',
        style: TextStyle(color: stale ? c.warning : null),
      ),
      trailing: fromScope
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesign.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: c.accent.fade(.15),
                borderRadius: AppDesign.radius(AppDesign.rFull),
              ),
              child: Text(
                _layerName(origin, context.l10n),
                style: context.text.caption.copyWith(color: c.accent),
              ),
            )
          : null,
      onTap: () => showAppDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(spec.labelIn(context.l10n)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppDesign.md,
            children: [
              Text(context.l10n.settingEffectiveValue(spec.display(value))),
              Text(
                context.l10n.effectiveDefaultValue(
                  spec.display(const InferenceSettings().toJson()[spec.key]),
                ),
              ),
              for (final req
                  in r.requested[spec.key] ?? const <(String, Object?)>[])
                Text(
                  context.l10n.effectiveLayerRequestedValue(
                    _layerName(req.$1, context.l10n),
                    spec.display(req.$2),
                  ),
                ),
              if (spec.reloadRequired) ...[
                const SizedBox(height: AppDesign.sm),
                Text(
                  context.l10n.uiEffectiveSettingsPageAppliesWhenTheModelLoads,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.uiEffectiveSettingsPageClose),
            ),
          ],
        ),
      ),
    );
  }
}
