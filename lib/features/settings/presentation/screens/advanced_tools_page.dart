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
              subtitle: Text(context.l10n.toolWebGlobeHint),
              value: s.webSearchEnabled && s.toolWeb,
              onChanged: (v) => n.update(
                s.copyWith(webMode: webModeFor(s, v), toolWeb: true),
              ),
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
            SettingsSwitchRow(
              secondary: const Icon(Icons.psychology_alt_outlined),
              title: Text(context.l10n.toolRecallLabel),
              subtitle: Text(
                s.memoryEnabled
                    ? context.l10n.toolRecallHint
                    : context.l10n.toolRecallOff,
                style: TextStyle(color: s.memoryEnabled ? null : c.warning),
              ),
              value: s.toolMemory,
              onChanged: (v) => n.update(s.copyWith(toolMemory: v)),
            ),
            if (!DesktopHost.active)
              SettingsSwitchRow(
                secondary: const Icon(Icons.alarm_outlined),
                title: Text(context.l10n.toolActionsLabel),
                subtitle: Text(context.l10n.toolActionsHint),
                value: s.toolActions,
                onChanged: (v) => n.update(s.copyWith(toolActions: v)),
              ),
            SettingsSwitchRow(
              key: const Key('tool-helper'),
              secondary: const Icon(Icons.handshake_outlined),
              title: Text(context.l10n.toolHelperLabel),
              subtitle: Text(context.l10n.toolHelperHint),
              value: s.toolHelper,
              onChanged: (v) => n.update(s.copyWith(toolHelper: v)),
            ),
            if (s.toolHelper) const _HelperModelRow(),
            if (s.toolHelper) const AgentsSettingsSection(),
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

/// The helper's model: any downloaded text model; a small one is best.
class _HelperModelRow extends ConsumerWidget {
  const _HelperModelRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = context.colors;
    final models = [
      for (final m in ref.watch(modelManagerProvider).catalog)
        if (m.isDownloaded &&
            modelCategory(m.localPath ?? m.id) == ModelCategory.llm)
          m,
    ]..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    final picked = models.where((m) => m.id == s.helperModelId).firstOrNull;
    final sameAsChat = s.helperModelId == HelperRunner.sameAsChat;
    return SettingsRow(
      key: const Key('tool-helper-model'),
      leading: const Icon(Icons.smart_toy_outlined),
      title: Text(
        sameAsChat
            ? context.l10n.toolHelperSameAsChat
            : picked?.displayName ?? context.l10n.toolHelperPick,
      ),
      subtitle: sameAsChat
          ? Text(context.l10n.toolHelperSameAsChatHint)
          : picked == null
          ? models.isEmpty
                ? Text(
                    context.l10n.toolHelperNoModels,
                    style: TextStyle(color: c.warning),
                  )
                : null
          : Text(picked.sizeLabel),
      trailing: models.isEmpty
          ? null
          : MenuAnchor(
              builder: (context, menu, _) => IconButton(
                key: const Key('tool-helper-model-menu'),
                icon: const Icon(Icons.expand_more),
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              ),
              menuChildren: [
                MenuItemButton(
                  key: const ValueKey('tool-helper-model-chat'),
                  leadingIcon: Icon(
                    sameAsChat ? Icons.check : null,
                    size: 18,
                    color: c.accent,
                  ),
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .update(
                        s.copyWith(helperModelId: HelperRunner.sameAsChat),
                      ),
                  child: Text(context.l10n.toolHelperSameAsChat),
                ),
                for (final m in models)
                  MenuItemButton(
                    key: ValueKey('tool-helper-model-${m.id}'),
                    leadingIcon: Icon(
                      m.id == s.helperModelId ? Icons.check : null,
                      size: 18,
                      color: c.accent,
                    ),
                    trailingIcon: Text(
                      m.sizeLabel,
                      style: context.text.small.copyWith(color: c.textMuted),
                    ),
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .update(s.copyWith(helperModelId: m.id)),
                    child: Text(m.displayName),
                  ),
              ],
            ),
    );
  }
}

class AgentsSettingsSection extends ConsumerWidget {
  const AgentsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final t = context.l10n;
    Widget number(
      String label,
      double value,
      void Function(double) changed, {
      double? max,
      bool integer = false,
      bool inherit = false,
    }) => _NumberRow(
      label: label,
      value: value,
      off: inherit ? -1 : -999,
      offLabel: t.agentModelDefault,
      hint: label,
      max: max,
      integer: integer,
      onChanged: changed,
    );
    return SettingsSection(
      key: const Key('agents-settings'),
      label: t.agentsSection,
      children: [
        number(
          t.agentMaxTokens,
          s.agentMaxTokens.toDouble(),
          (v) => n.update(s.copyWith(agentMaxTokens: v.round())),
          max: 4096,
          integer: true,
        ),
        number(
          t.agentTemperature,
          s.agentTemperature,
          (v) => n.update(s.copyWith(agentTemperature: v)),
          max: 2,
        ),
        number(
          t.agentTopP,
          s.agentTopP,
          (v) => n.update(s.copyWith(agentTopP: v)),
          max: 1,
          inherit: true,
        ),
        number(
          t.agentMinP,
          s.agentMinP,
          (v) => n.update(s.copyWith(agentMinP: v)),
          max: 1,
          inherit: true,
        ),
        number(
          t.agentTopK,
          s.agentTopK.toDouble(),
          (v) => n.update(s.copyWith(agentTopK: v.round())),
          max: 1000,
          integer: true,
          inherit: true,
        ),
        number(
          t.agentRepeatPenalty,
          s.agentRepeatPenalty,
          (v) => n.update(s.copyWith(agentRepeatPenalty: v)),
          max: 2,
          inherit: true,
        ),
        number(
          t.agentContextSize,
          s.agentContextSize.toDouble(),
          (v) => n.update(s.copyWith(agentContextSize: v.round())),
          max: 65536,
          integer: true,
        ),
        SettingSlider(
          label: t.agentMaxConcurrent,
          hint: '',
          value: s.agentMaxConcurrent.toDouble(),
          min: 1,
          max: 4,
          divisions: 3,
          display: '${s.agentMaxConcurrent}',
          onChanged: (v) => n.update(s.copyWith(agentMaxConcurrent: v.round())),
        ),
        SettingsSwitchRow(
          title: Text(t.agentThinking),
          value: s.agentThinking,
          onChanged: (v) => n.update(s.copyWith(agentThinking: v)),
        ),
        SettingSlider(
          label: t.agentToolRounds,
          hint: '',
          value: s.agentToolRounds.toDouble(),
          min: 1,
          max: 8,
          divisions: 7,
          display: '${s.agentToolRounds}',
          onChanged: (v) => n.update(s.copyWith(agentToolRounds: v.round())),
        ),
        SettingDropdown<AgentWebAccess>(
          label: t.agentWebAccess,
          hint: '',
          value: s.agentWebAccess,
          items: AgentWebAccess.values,
          labelOf: (v) => switch (v) {
            AgentWebAccess.askOnce => t.agentWebAskOnce,
            AgentWebAccess.alwaysAllow => t.agentWebAlwaysAllow,
            AgentWebAccess.never => t.agentWebNever,
          },
          onChanged: (v) => n.update(s.copyWith(agentWebAccess: v)),
        ),
        SettingsRow(
          title: Text(t.agentInstructions),
          subtitle: s.agentInstructions.isEmpty
              ? null
              : Text(
                  s.agentInstructions,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () async {
            final value = await promptText(
              context,
              title: t.agentInstructions,
              initial: s.agentInstructions,
              allowEmpty: true,
              maxLines: 6,
              maxLength: 8000,
              confirmLabel: t.uiAdvancedPages2Save,
            );
            if (value != null) {
              await n.update(s.copyWith(agentInstructions: value));
            }
          },
        ),
        number(
          t.agentInputBudget,
          s.agentInputBudget.toDouble(),
          (v) => n.update(s.copyWith(agentInputBudget: v.round())),
          max: 65536,
          integer: true,
        ),
        SettingsRow(
          key: const Key('agents-reset'),
          leading: const Icon(Icons.restart_alt),
          title: Text(t.agentReset),
          onTap: () => n.update(s.resetAgents()),
        ),
      ],
    );
  }
}
