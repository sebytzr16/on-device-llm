import '../../../core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_design.dart';
import '../../settings/domain/entities/inference_settings.dart';
import '../../../core/motion/motion.dart';
import '../../settings/presentation/providers/effective_settings_provider.dart';
import '../../chat/presentation/providers/chat_provider.dart';

/// Tool calling from the composer's "+" sheet (request, 2026-09-19): turn
/// tools off for a plain question, or pick which ones the model may call,
/// without a trip to Settings > Tools. Changes apply to this chat through
/// the same settings cascade used by the next response.
class ToolsQuickPanel extends ConsumerWidget {
  const ToolsQuickPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(effectiveSettingsProvider).effective;
    void update(InferenceSettings next) {
      final before = s.toJson(), after = next.toJson();
      ref.read(chatProvider.notifier).setChatOverrides({
        ...ref.read(chatOverridesProvider),
        for (final key in before.keys)
          if (before[key] != after[key]) key: after[key],
      });
    }

    final c = context.colors;
    final on = s.toolsEnabled;
    final webOff = !s.webSearchEnabled;
    final noCollection = s.knowledgeCollection.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        SpringSwitchTile(
          key: const Key('quick-tools-enabled'),
          secondary: Icon(Icons.build_outlined, color: c.textMuted),
          title: Text(context.l10n.uiToolsQuickPanelLetTheModelCallTools),
          subtitle: Text(
            on
                ? 'Search, read pages, search your documents, calculate.'
                : 'Off: the model answers from what it knows and what you attach.',
          ),
          value: on,
          onChanged: (v) => update(s.copyWith(toolsEnabled: v)),
        ),
        if (on) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDesign.lg,
              AppDesign.xs,
              AppDesign.lg,
              0,
            ),
            child: Text(
              context.l10n.uiToolsQuickPanelTHISMODELMAYCALL,
              style: context.text.label.copyWith(
                color: c.textFaint,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _ToolRow(
            keyName: 'quick-tool-calculator',
            label: context.l10n.uiToolsQuickPanelCalculator,
            hint: context.l10n.uiToolsQuickPanelExactArithmetic,
            value: s.toolCalculator,
            onChanged: (v) => update(s.copyWith(toolCalculator: v)),
          ),
          _ToolRow(
            keyName: 'quick-tool-web',
            label: context.l10n.uiToolsQuickPanelSearchWebReadUrlFindIn,
            hint: webOff
                ? 'Web research is off (the globe pill): not offered.'
                : 'DuckDuckGo and public pages.',
            warn: webOff,
            value: s.toolWeb,
            onChanged: (v) => update(s.copyWith(toolWeb: v)),
          ),
          _ToolRow(
            keyName: 'quick-tool-documents',
            label: context.l10n.uiToolsQuickPanelSearchDocuments,
            hint: noCollection
                ? 'No knowledge collection selected: not offered.'
                : 'Searches “${s.knowledgeCollection}”.',
            warn: noCollection,
            value: s.toolDocuments,
            onChanged: (v) => update(s.copyWith(toolDocuments: v)),
          ),
          ListTile(
            key: const Key('quick-tool-choice'),
            dense: true,
            title: Text(context.l10n.uiToolsQuickPanelToolUse),
            subtitle: Text(
              s.toolChoice == ToolChoice.required
                  ? 'Required: a tool is called before the first answer.'
                  : 'Auto: the model decides whether a tool is needed.',
            ),
            trailing: SegmentedButton<ToolChoice>(
              key: const Key('quick-tool-choice-segments'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                ButtonSegment(
                  value: ToolChoice.auto,
                  label: Text(context.l10n.uiToolsQuickPanelAuto),
                ),
                ButtonSegment(
                  value: ToolChoice.required,
                  label: Text(context.l10n.uiToolsQuickPanelRequired),
                ),
              ],
              selected: {s.toolChoice},
              onSelectionChanged: (v) =>
                  update(s.copyWith(toolChoice: v.first)),
            ),
          ),
        ],
        const SizedBox(height: AppDesign.sm),
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  final String keyName, label, hint;
  final bool value, warn;
  final ValueChanged<bool> onChanged;
  const _ToolRow({
    required this.keyName,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SpringSwitchTile(
      key: Key(keyName),
      dense: true,
      title: Text(label, style: context.text.mono),
      subtitle: Text(
        hint,
        style: TextStyle(color: warn ? c.warning : c.textMuted),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
