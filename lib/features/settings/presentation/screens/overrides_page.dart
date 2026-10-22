import '../../../../core/l10n/l10n.dart';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../domain/entities/inference_settings.dart';
import '../../domain/setting_specs.dart';
import '../setting_labels.dart';
import '../../domain/settings_scope.dart';
import '../widgets/settings_widgets.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

/// Edits one scope's overrides (model profile, preset, chat): every
/// overridable setting is listed with the value it inherits from the layers
/// below; tapping sets an explicit value for this scope, the clear icon
/// returns it to inherited. Saved on every change through [onChanged].
class OverridesPage extends StatefulWidget {
  final String title;
  final String scopeLabel;
  final Map<String, dynamic> overrides;

  /// What the setting is when this scope does not override it.
  final InferenceSettings inherited;
  final Future<void> Function(Map<String, dynamic> overrides) onChanged;

  /// Extra app-bar actions (the model profile's share/import menu).
  final List<Widget> actions;
  final String? error;
  const OverridesPage({
    super.key,
    required this.title,
    required this.scopeLabel,
    required this.overrides,
    required this.inherited,
    required this.onChanged,
    this.actions = const [],
    this.error,
  });

  @override
  State<OverridesPage> createState() => _OverridesPageState();
}

class _OverridesPageState extends State<OverridesPage> {
  late Map<String, dynamic> _overrides = Map.of(widget.overrides);
  String? _error;

  @override
  void didUpdateWidget(OverridesPage old) {
    super.didUpdateWidget(old);
    // Replaced from outside (an imported configuration): show the new one.
    if (!identical(old.overrides, widget.overrides) &&
        jsonEncode(widget.overrides) != jsonEncode(_overrides)) {
      _overrides = Map.of(widget.overrides);
    }
  }

  Future<void> _set(String key, Object? value) async {
    setState(() {
      _overrides = {..._overrides};
      if (value == null) {
        _overrides.remove(key);
      } else {
        _overrides[key] = value;
      }
    });
    try {
      await widget.onChanged(SettingsResolver.sanitize(_overrides));
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inheritedJson = widget.inherited.toJson();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_overrides.isNotEmpty)
            TextButton(
              onPressed: () async {
                setState(() => _overrides = {});
                try {
                  await widget.onChanged(const {});
                } catch (e) {
                  if (mounted) setState(() => _error = '$e');
                }
              },
              child: Text(context.l10n.uiOverridesPageClearAll),
            ),
          ...widget.actions,
        ],
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
              '${widget.scopeLabel} · ${_overrides.length}\n${context.l10n.settingScopeHint}',
              icon: Icons.layers_outlined,
            ),
            if (_error != null || widget.error != null)
              SettingsNote(
                _error ?? widget.error!,
                icon: Icons.error_outline,
                tone: c.danger,
              ),
            for (final group in SettingSpec.groups) ...[
              SettingsSection(
                label: settingGroupLabel(group, context.l10n),
                children: [
                  for (final spec in SettingSpec.all.where(
                    (s) => s.group == group,
                  ))
                    _row(context, spec, inheritedJson[spec.key], c),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    SettingSpec spec,
    Object? inherited,
    AppColors c,
  ) {
    final overridden = _overrides.containsKey(spec.key);
    final value = overridden ? _overrides[spec.key] : inherited;
    return SettingsRow(
      key: Key('override-${spec.key}'),
      title: Text(
        '${spec.labelIn(context.l10n)}${spec.reloadRequired ? ' ↻' : ''}',
        style: TextStyle(color: overridden ? c.accent : null),
      ),
      subtitle: Text(
        '${overridden ? context.l10n.settingExplicit : context.l10n.settingInherited} · ${spec.display(value)}',
      ),
      trailing: overridden
          ? IconButton(
              tooltip: context.l10n.uiOverridesPageInherit,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => _set(spec.key, null),
            )
          : Icon(Icons.chevron_right, color: c.textFaint),
      onTap: () async {
        final v = await editSettingValue(
          context,
          spec,
          current: value,
          inherited: inherited,
        );
        if (v == null) return;
        await _set(spec.key, v.value);
      },
    );
  }
}

/// A picked value, wrapped so that "inherit" (null) and "cancelled" differ.
class SettingEdit {
  final Object? value;
  const SettingEdit(this.value);
}

/// Type-appropriate entry for one setting. Returns null when cancelled.
Future<SettingEdit?> editSettingValue(
  BuildContext context,
  SettingSpec spec, {
  required Object? current,
  Object? inherited,
}) async {
  switch (spec.kind) {
    case SettingKind.boolean:
      return showAppDialog<SettingEdit>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(spec.labelIn(context.l10n)),
          children: [
            if (inherited != null)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(context, const SettingEdit(null)),
                child: Text(
                  context.l10n.settingInherit(spec.display(inherited)),
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, const SettingEdit(true)),
              child: Text(context.l10n.uiOverridesPageOn),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, const SettingEdit(false)),
              child: Text(context.l10n.uiOverridesPageOff),
            ),
          ],
        ),
      );
    case SettingKind.choice:
      return showAppDialog<SettingEdit>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(spec.labelIn(context.l10n)),
          children: [
            if (inherited != null)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(context, const SettingEdit(null)),
                child: Text(
                  context.l10n.settingInherit(spec.display(inherited)),
                ),
              ),
            for (final o in spec.options)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, SettingEdit(o)),
                child: Text(
                  spec.display(o),
                  style: o == current
                      ? const TextStyle(fontWeight: FontWeight.w600)
                      : null,
                ),
              ),
          ],
        ),
      );
    case SettingKind.integer:
    case SettingKind.number:
    case SettingKind.text:
    case SettingKind.stringList:
      final controller = TextEditingController(
        text: switch (current) {
          null => '',
          List() => current.join('\n'),
          _ => current.toString(),
        },
      );
      final multiline =
          spec.kind == SettingKind.text || spec.kind == SettingKind.stringList;
      return showAppDialog<SettingEdit>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(spec.labelIn(context.l10n)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: multiline ? 8 : 1,
            keyboardType: multiline
                ? TextInputType.multiline
                : const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
            decoration: InputDecoration(
              hintText: switch (spec.kind) {
                SettingKind.stringList => context.l10n.settingOnePerLine,
                SettingKind.text => spec.hint.isEmpty ? null : spec.hint,
                _ => '${spec.min ?? ''} – ${spec.max ?? ''}',
              },
              helperText: inherited == null
                  ? null
                  : context.l10n.settingInherit(spec.display(inherited)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.uiOverridesPageCancel),
            ),
            if (inherited != null)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const SettingEdit(null)),
                child: Text(context.l10n.uiOverridesPageInherit),
              ),
            FilledButton(
              onPressed: () {
                final raw = controller.text;
                final Object parsed = switch (spec.kind) {
                  SettingKind.stringList => [
                    for (final l in raw.split('\n'))
                      if (l.trim().isNotEmpty) l.trim(),
                  ],
                  SettingKind.integer => int.tryParse(raw.trim()) ?? raw,
                  SettingKind.number => double.tryParse(raw.trim()) ?? raw,
                  _ => raw,
                };
                final v = spec.coerce(parsed);
                if (v == null) {
                  showIslandToast(
                    context,
                    context.l10n.uiOverridesPageNotAValidValue,
                  );
                  return;
                }
                Navigator.pop(context, SettingEdit(v));
              },
              child: Text(context.l10n.uiOverridesPageSave),
            ),
          ],
        ),
      );
  }
}
