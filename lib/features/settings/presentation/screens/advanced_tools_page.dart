part of 'advanced_pages_2.dart';

// Typed tools: which are offered, Auto/Required, round limit.

/// Typed tools (roadmap P2): the switch, the round limit and each tool's
/// gate, with the host permission it depends on spelled out.
class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final c = context.colors;
    final supportsTools = ref.watch(
      chatProvider.select((x) => x.metrics['supportsTools']),
    );
    return _Scaffold(
      title: context.l10n.uiAdvancedToolsPageTools,
      children: [
        SettingsGroup(
          children: [
            SettingsSwitchRow(
              secondary: const Icon(Icons.build_outlined),
              key: const Key('tools-enabled'),
              title: Text(context.l10n.uiAdvancedToolsPageLetTheModelCallTools),
              subtitle: Text(
                context.l10n.uiAdvancedToolsPageTheModelCanDecideToSearch,
              ),
              value: s.toolsEnabled,
              onChanged: (v) => n.update(s.copyWith(toolsEnabled: v)),
            ),
            SettingDropdown<ToolChoice>(
              icon: Icons.build_circle_outlined,
              label: context.l10n.uiAdvancedToolsPageToolUse,
              hint:
                  context.l10n.uiAdvancedToolsPageAutoLetsTheModelDecideWhether,
              value: s.toolChoice,
              items: ToolChoice.values,
              labelOf: (v) => switch (v) {
                ToolChoice.auto => 'Auto',
                ToolChoice.required => 'Required',
              },
              onChanged: (v) => n.update(s.copyWith(toolChoice: v)),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedToolsPageRoundsPerAnswer,
              hint: context.l10n.uiAdvancedToolsPageHowManyTimesTheModelMay,
              value: s.toolMaxRounds.toDouble(),
              min: 1,
              max: InferenceSettings.maxToolRounds.toDouble(),
              divisions: InferenceSettings.maxToolRounds - 1,
              display: '${s.toolMaxRounds}',
              onChanged: (v) => n.update(s.copyWith(toolMaxRounds: v.round())),
            ),
          ],
        ),
        SettingsSection(
          label: context.l10n.sectionTools,
          children: [
            SettingsSwitchRow(
              secondary: const Icon(Icons.calculate_outlined),
              title: Text(context.l10n.uiAdvancedToolsPageCalculator),
              subtitle: Text(
                context
                    .l10n
                    .uiAdvancedToolsPageExactArithmeticNoPermissionNeeded,
              ),
              value: s.toolCalculator,
              onChanged: (v) => n.update(s.copyWith(toolCalculator: v)),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.public_rounded),
              title: Text(
                context.l10n.uiAdvancedToolsPageSearchWebReadUrlFindIn,
              ),
              subtitle: Text(
                s.webSearchEnabled
                    ? 'DuckDuckGo search and public pages, under the same limits as web research.'
                    : 'Needs web research on (the Local pill or Settings): it is off, so these are not offered.',
                style: TextStyle(color: s.webSearchEnabled ? null : c.warning),
              ),
              value: s.toolWeb,
              onChanged: (v) => n.update(s.copyWith(toolWeb: v)),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.find_in_page_outlined),
              title: Text(context.l10n.uiAdvancedToolsPageSearchDocuments),
              subtitle: Text(
                s.knowledgeCollection.isNotEmpty
                    ? 'Searches the “${s.knowledgeCollection}” collection.'
                    : 'Needs a knowledge collection selected under Settings > Knowledge: none is, so it is not offered.',
                style: TextStyle(
                  color: s.knowledgeCollection.isNotEmpty ? null : c.warning,
                ),
              ),
              value: s.toolDocuments,
              onChanged: (v) => n.update(s.copyWith(toolDocuments: v)),
            ),
          ],
        ),
        SettingsNote(
          supportsTools == true
              ? 'The loaded model\'s chat template supports native tool calls.'
              : supportsTools == false
              ? 'The loaded model\'s template has no tool-call format; tools are described in the prompt instead and the model answers with a JSON block. Small models do this less reliably.'
              : 'Whether a model has native tool-call support is shown here once it is loaded.',
          icon: Icons.build_outlined,
        ),
        const SettingsNote(
          'Every call is bounded: one query or page per call, 30 s per call, results cut at 6,000 characters, pages read through the public-web policy only. Calls and results are kept in the answer\'s run record.',
        ),
      ],
    );
  }
}
