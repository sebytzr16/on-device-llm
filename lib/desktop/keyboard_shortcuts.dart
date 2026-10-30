import 'package:flutter/material.dart';

import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';

class DesktopShortcut {
  final SingleActivator activator;
  final String label;
  final VoidCallback action;
  const DesktopShortcut(this.activator, this.label, this.action);

  String get keys => [
    if (activator.control) 'Ctrl',
    if (activator.shift) 'Shift',
    if (activator.alt) 'Alt',
    if (activator.meta) 'Win',
    activator.trigger.keyLabel,
  ].join('+');

  /// The label without a key hint some strings carry for tooltips elsewhere.
  String get name =>
      label.replaceFirst(RegExp(r'\s*\((Ctrl|Shift|Alt|Win)\+[^)]*\)$'), '');
}

class DesktopShortcutScope extends InheritedWidget {
  final List<DesktopShortcut> shortcuts;
  const DesktopShortcutScope({
    super.key,
    required this.shortcuts,
    required super.child,
  });
  static List<DesktopShortcut> of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesktopShortcutScope>()!
      .shortcuts;
  @override
  bool updateShouldNotify(DesktopShortcutScope oldWidget) => true;
}

String desktopShortcutTooltip(BuildContext context, String label) {
  final scope = context
      .dependOnInheritedWidgetOfExactType<DesktopShortcutScope>();
  final binding = scope?.shortcuts
      .where((shortcut) => shortcut.label == label)
      .firstOrNull;
  if (binding == null || binding.name != label) return label;
  return '$label (${binding.keys})';
}

Future<void> showDesktopShortcuts(
  BuildContext context,
  List<DesktopShortcut> shortcuts,
) => showAppDialog<void>(
  context: context,
  builder: (_) => DesktopShortcutsDialog(shortcuts: shortcuts),
);

class DesktopShortcutsDialog extends StatelessWidget {
  final List<DesktopShortcut> shortcuts;
  const DesktopShortcutsDialog({super.key, required this.shortcuts});
  @override
  Widget build(BuildContext context) {
    // Two keys for one action (Ctrl+K and Ctrl+F) share a row.
    final rows = <String, List<String>>{};
    for (final shortcut in shortcuts) {
      (rows[shortcut.name] ??= []).add(shortcut.keys);
    }
    return AlertDialog(
      title: Text(context.l10n.desktopKeyboardShortcuts),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in rows.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(row.key)),
                      Text(row.value.join(' / ')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.desktopClose),
        ),
      ],
    );
  }
}
