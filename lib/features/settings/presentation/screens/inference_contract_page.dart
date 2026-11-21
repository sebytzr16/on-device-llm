import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../domain/entities/inference_settings.dart';
import '../../domain/setting_specs.dart';
import '../../domain/settings_scope.dart';
import '../providers/effective_settings_provider.dart';
import '../providers/settings_provider.dart';
import 'overrides_page.dart';

/// Global and scoped inference editors share the same labels, kinds, limits,
/// choices and reload rules. Existing compact shortcuts remain available.
class InferenceContractPage extends ConsumerWidget {
  const InferenceContractPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final defaults = notifier.defaults;
    final json = settings.toJson(), inherited = defaults.toJson();
    // Sampling belongs to each model (SettingSpec.perModel): the resolver
    // drops it from the global layer, so this page must neither offer it nor
    // reset it when an unrelated setting saves (audit 2026-11-20 P1-2).
    bool exposed(SettingSpec spec) => spec.available && !spec.perModel;
    InferenceSettings globalWith(Map<String, dynamic> values) =>
        SettingsResolver.editGlobal(
          ref.read(settingsProvider),
          values,
          resetMissingTo: defaults,
          resets: exposed,
        );
    return OverridesPage(
      title: context.l10n.modelSettingsAll,
      scopeLabel: context.l10n.modelSettingsGlobal,
      error: ref.watch(settingsErrorProvider),
      engine: settings.usesRemote ? null : ref.watch(activeModelEngineProvider),
      inherited: defaults,
      filter: exposed,
      overrides: {
        for (final spec in SettingSpec.visible)
          if (exposed(spec) &&
              (settings.explicitOverrides.contains(spec.key) ||
                  jsonEncode(json[spec.key]) !=
                      jsonEncode(inherited[spec.key])))
            spec.key: json[spec.key],
      },
      // This page edits the user's own settings: preview the cascade with
      // them so the web question still sees a preset or chat Off above.
      change: (values) => SettingsChange(global: globalWith(values)),
      onChanged: (values) => notifier.update(globalWith(values)),
    );
  }
}
