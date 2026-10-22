import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_design.dart';
import '../../../core/design/app_sheet.dart';
import '../../settings/domain/entities/inference_settings.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import '../../settings/presentation/screens/overrides_page.dart';
import '../../settings/presentation/widgets/settings_labels.dart';
import '../domain/preset.dart';
import 'providers/presets_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/motion/motion.dart';
import '../../../core/design/app_dialog.dart';

/// Composer sheet: pick a preset, or create / edit / duplicate / delete.
/// It grows out of [from] (the preset pill) when given.
Future<void> showPresetSheet(BuildContext context, {BuildContext? from}) =>
    showMorphSheet<void>(
      context: context,
      from: from,
      isScrollControlled: true,
      builder: (_) => const _PresetSheet(),
    );

class _PresetSheet extends ConsumerWidget {
  const _PresetSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final state = ref.watch(presetsProvider);
    final n = ref.read(presetsProvider.notifier);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (context, scroll) => AppSheet(
        title: context.l10n.presets,
        scrollable: false,
        primary: FilledButton.icon(
          key: const Key('preset-new'),
          onPressed: () async {
            final draft = await showPresetEditor(context);
            if (draft != null) await n.create(draft);
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.l10n.newLabel),
        ),
        children: [
          ListView(
            controller: scroll,
            padding: EdgeInsets.zero,
            children: [
              for (final p in state.presets)
                ListTile(
                  key: Key('preset-${p.id}'),
                  leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
                  title: Text(p.name),
                  subtitle: Text(
                    p.systemPrompt.isEmpty
                        ? context.l10n.noExtraInstructions
                        : p.systemPrompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.small,
                  ),
                  selected: p.id == state.activeId,
                  selectedTileColor: c.accent.fade(0.08),
                  trailing: PopupMenuButton<String>(
                    tooltip: context.l10n.more,
                    onSelected: (a) async {
                      switch (a) {
                        case 'edit':
                          final edited = await showPresetEditor(
                            context,
                            existing: p,
                          );
                          if (edited != null) await n.update(edited);
                        case 'overrides':
                          if (context.mounted) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => Consumer(
                                  builder: (context, ref, _) => OverridesPage(
                                    title: '${p.name} · overrides',
                                    scopeLabel: 'Preset',
                                    overrides:
                                        ref
                                            .watch(presetsProvider)
                                            .presets
                                            .where((x) => x.id == p.id)
                                            .firstOrNull
                                            ?.overrides ??
                                        p.overrides,
                                    inherited: ref.watch(settingsProvider),
                                    onChanged: (o) =>
                                        n.update(p.copyWith(overrides: o)),
                                  ),
                                ),
                              ),
                            );
                          }
                        case 'copy':
                          await n.duplicate(p);
                        case 'delete':
                          await n.remove(p.id);
                      }
                    },
                    itemBuilder: (_) => [
                      if (!p.builtIn)
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(context.l10n.edit),
                        ),
                      if (!p.builtIn)
                        PopupMenuItem(
                          value: 'overrides',
                          child: Text(
                            p.overrides.isEmpty
                                ? 'More overrides'
                                : 'More overrides · ${p.overrides.length}',
                          ),
                        ),
                      PopupMenuItem(
                        value: 'copy',
                        child: Text(context.l10n.duplicate),
                      ),
                      if (!p.builtIn)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(context.l10n.delete),
                        ),
                    ],
                  ),
                  onTap: () async {
                    await n.activate(p.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              const SizedBox(height: AppDesign.md),
              Text(
                context.l10n.presetsHint,
                style: context.text.mono.copyWith(color: c.textFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Create or edit dialog; returns the preset to save, or null.
Future<Preset?> showPresetEditor(
  BuildContext context, {
  Preset? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final emoji = TextEditingController(text: existing?.emoji ?? '✨');
  final prompt = TextEditingController(text: existing?.systemPrompt ?? '');
  var temperature = existing?.temperature;
  var thinking = existing?.thinking;
  var webMode = existing?.webMode;
  final result = await showAppDialog<Preset>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          existing == null ? context.l10n.newPreset : context.l10n.editPreset,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppDesign.md,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: emoji,
                      textAlign: TextAlign.center,
                      maxLength: 2,
                      decoration: const InputDecoration(counterText: ''),
                    ),
                  ),
                  const SizedBox(width: AppDesign.sm),
                  Expanded(
                    child: TextField(
                      key: const Key('preset-name'),
                      controller: name,
                      decoration: InputDecoration(labelText: context.l10n.name),
                    ),
                  ),
                ],
              ),
              TextField(
                key: const Key('preset-prompt'),
                controller: prompt,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: context.l10n.instructions,
                  hintText: context.l10n.instructionsHint,
                ),
              ),
              DropdownButtonFormField<double?>(
                initialValue: temperature,
                decoration: InputDecoration(
                  labelText: context.l10n.temperature,
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.l10n.useSetting),
                  ),
                  DropdownMenuItem(
                    value: 0.0,
                    child: Text(context.l10n.uiPresetSheet00Exact),
                  ),
                  DropdownMenuItem(
                    value: 0.3,
                    child: Text(context.l10n.uiPresetSheet03Focused),
                  ),
                  DropdownMenuItem(
                    value: 0.7,
                    child: Text(context.l10n.uiPresetSheet07Balanced),
                  ),
                  DropdownMenuItem(
                    value: 1.0,
                    child: Text(context.l10n.uiPresetSheet10Creative),
                  ),
                ],
                onChanged: (v) => setState(() => temperature = v),
              ),
              DropdownButtonFormField<bool?>(
                initialValue: thinking,
                decoration: InputDecoration(labelText: context.l10n.thinking),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.l10n.useSetting),
                  ),
                  DropdownMenuItem(value: true, child: Text(context.l10n.on)),
                  DropdownMenuItem(value: false, child: Text(context.l10n.off)),
                ],
                onChanged: (v) => setState(() => thinking = v),
              ),
              DropdownButtonFormField<WebMode?>(
                initialValue: webMode,
                decoration: InputDecoration(
                  labelText: context.l10n.webResearchShort,
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.l10n.useSetting),
                  ),
                  for (final m in WebMode.values)
                    DropdownMenuItem(value: m, child: Text(webModeShort(m))),
                ],
                onChanged: (v) => setState(() => webMode = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const Key('preset-save'),
            onPressed: () => Navigator.pop(
              context,
              Preset(
                id: existing?.id ?? '',
                name: name.text,
                emoji: emoji.text,
                systemPrompt: prompt.text.trim(),
                temperature: temperature,
                thinking: thinking,
                webMode: webMode,
              ),
            ),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  emoji.dispose();
  prompt.dispose();
  return result;
}
