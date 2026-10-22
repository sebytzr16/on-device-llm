import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../domain/setting_specs.dart';
import '../../domain/settings_scope.dart';
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
    return OverridesPage(
      title: context.l10n.modelSettingsAll,
      scopeLabel: context.l10n.modelSettingsGlobal,
      error: ref.watch(settingsErrorProvider),
      inherited: defaults,
      overrides: {
        for (final spec in SettingSpec.all)
          if (settings.explicitOverrides.contains(spec.key) ||
              jsonEncode(json[spec.key]) != jsonEncode(inherited[spec.key]))
            spec.key: json[spec.key],
      },
      onChanged: (values) => notifier.update(
        SettingsResolver.editGlobal(
          ref.read(settingsProvider),
          values,
          resetMissingTo: defaults,
        ),
      ),
    );
  }
}
