import '../../../../core/l10n/l10n.dart';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../adapters/adapter_store.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../domain/entities/inference_settings.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_labels.dart';
import '../widgets/settings_widgets.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/design/app_dialog.dart';

part 'advanced_sampling_page.dart';
part 'advanced_memory_rope_page.dart';
part 'advanced_structured_output_page.dart';
part 'advanced_tools_page.dart';
part 'advanced_appearance_page.dart';
part 'advanced_adapters_page.dart';

class _Scaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  const _Scaffold({
    required this.title,
    required this.children,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [const SavedIndicator(), ...actions],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDesign.lg,
          AppDesign.sm,
          AppDesign.lg,
          AppDesign.xxl,
        ),
        children: children,
      ),
    ),
  );
}

class _NumberRow extends StatelessWidget {
  final String label, hint, offLabel;
  final double value, off;
  final double? max;
  final bool integer;
  final ValueChanged<double> onChanged;
  final IconData? icon;
  const _NumberRow({
    this.icon,
    required this.label,
    required this.value,
    required this.off,
    required this.offLabel,
    required this.hint,
    required this.onChanged,
    this.max,
    this.integer = false,
  });

  @override
  Widget build(BuildContext context) => SettingsRow(
    leading: icon == null ? null : Icon(icon),
    title: Text(label),
    subtitle: Text(
      value == off
          ? offLabel
          : integer
          ? value.toInt().toString()
          : value.toString(),
    ),
    trailing: const Icon(Icons.edit_outlined, size: 20),
    onTap: () async {
      final result = await promptText(
        context,
        title: label,
        initial: value == off ? '' : (integer ? '${value.toInt()}' : '$value'),
        hint: hint,
        helper: context.l10n.settingEmptyMeans(offLabel),
        confirmLabel: context.l10n.uiAdvancedPages2Save,
        allowEmpty: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validate: (text) {
          if (text.isEmpty) return null;
          final v = double.tryParse(text);
          return v == null || !v.isFinite || (max != null && v > max!) || v < 0
              ? context.l10n.uiAdvancedPages2NotAValidValue
              : null;
        },
      );
      if (result != null) {
        onChanged(result.isEmpty ? off : double.parse(result));
      }
    },
  );
}
