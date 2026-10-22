import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_design.dart';
import '../../../core/l10n/l10n.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../domain/prompt_shortcut.dart';
import '../prompt_shortcuts_provider.dart';
import '../../../core/design/app_dialog.dart';

/// Settings > Prompt shortcuts: the built-ins and the user's own `/name`
/// prompts, with add, edit (a built-in is copied, never changed) and delete.
class ShortcutsPage extends ConsumerWidget {
  const ShortcutsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = Localizations.localeOf(context).languageCode;
    final shortcuts = [
      for (final s in ref.watch(promptShortcutsProvider)) s.localized(lang),
    ];
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.shortcutsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('shortcut-add'),
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.shortcutNew),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDesign.lg,
            AppDesign.sm,
            AppDesign.lg,
            96,
          ),
          children: [
            SettingsNote(
              context.l10n.shortcutsIntro,
              icon: Icons.bolt_outlined,
            ),
            const SizedBox(height: AppDesign.md),
            SettingsGroup(
              children: [
                for (final s in shortcuts)
                  SettingsRow(
                    key: Key('shortcut-row-${s.name}'),
                    title: Text(
                      '/${s.name}',
                      style: context.text.mono.copyWith(color: c.accent),
                    ),
                    subtitle: Text(
                      s.description.isEmpty ? s.template : s.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: s.builtIn
                        ? Text(
                            context.l10n.shortcutBuiltIn,
                            style: context.text.label,
                          )
                        : IconButton(
                            tooltip: context.l10n.shortcutDelete(s.name),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => ref
                                .read(promptShortcutsProvider.notifier)
                                .remove(s.name),
                          ),
                    onTap: () => _edit(context, ref, s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PromptShortcut? existing,
  ) async {
    final saved = await showAppDialog<PromptShortcut>(
      context: context,
      builder: (_) => _ShortcutDialog(existing: existing),
    );
    if (saved == null) return;
    await ref
        .read(promptShortcutsProvider.notifier)
        .put(
          saved,
          previousName: existing == null || existing.builtIn
              ? null
              : existing.name,
        );
  }
}

class _ShortcutDialog extends StatefulWidget {
  final PromptShortcut? existing;
  const _ShortcutDialog({this.existing});

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _template = TextEditingController(
    text: widget.existing?.template ?? '{input}',
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _template.dispose();
    super.dispose();
  }

  String? get _nameError {
    final n = _name.text.trim();
    if (n.isEmpty) return null;
    return PromptShortcut.validName.hasMatch(n)
        ? null
        : context.l10n.shortcutNameRule;
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _nameError == null &&
      _template.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final builtIn = widget.existing?.builtIn == true;
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? context.l10n.shortcutNew
            : builtIn
            ? context.l10n.shortcutYourVersion(widget.existing!.name)
            : context.l10n.shortcutEdit(widget.existing!.name),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppDesign.md,
          children: [
            TextField(
              key: const Key('shortcut-name'),
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.l10n.shortcutName,
                prefixText: '/',
                errorText: _nameError,
              ),
            ),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: context.l10n.shortcutDescription,
              ),
            ),
            TextField(
              key: const Key('shortcut-template'),
              controller: _template,
              onChanged: (_) => setState(() {}),
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: context.l10n.shortcutPrompt,
              ),
            ),
            Text(
              context.l10n.shortcutPromptHelp('{input}'),
              style: context.text.small.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                  context,
                  PromptShortcut(
                    name: _name.text.trim(),
                    description: _description.text.trim(),
                    template: _template.text,
                    defaultArg: widget.existing?.defaultArg ?? '',
                  ),
                )
              : null,
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
