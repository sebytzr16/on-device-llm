import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/platform/build_identity.dart';
import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/utils/external_links.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../domain/entities/inference_settings.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_labels.dart';
import '../widgets/settings_widgets.dart';
import '../../../adapters/adapter_store.dart';
import '../providers/effective_settings_provider.dart';
import 'advanced_pages.dart';
import 'advanced_pages_2.dart';
import 'effective_settings_page.dart';
import 'inference_contract_page.dart';
import 'knowledge_page.dart';
import 'memory_page.dart';
import 'settings_search_page.dart';
import 'remote_server_page.dart';
import '../../../hosting/presentation/device_hosting_page.dart';
import '../../../schedule/schedule_page.dart';
import '../../../shortcuts/presentation/shortcuts_page.dart';
import '../../../backup/backup_page.dart';
import '../../../voice/voice_settings.dart';
import '../../../../core/motion/motion.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

// Keep in sync with pubspec.yaml; no package_info dependency by design.
const _appVersion = BuildIdentity.version;
const _llamaCppUrl = 'https://github.com/ggml-org/llama.cpp';

/// Layer 2 (North Star 6.6): the short screen. Everything numeric lives one
/// tap deeper under ADVANCED.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final error = ref.watch(settingsErrorProvider);
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settings),
        actions: [
          const SavedIndicator(),
          IconButton(
            tooltip: context.l10n.settingsSearch,
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const SettingsSearchPage(),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: context.l10n.more,
            onSelected: (_) => _confirmReset(context, n),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'reset',
                child: Text(context.l10n.resetToDefaults),
              ),
            ],
          ),
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
            const _PrivacyCard(),
            if (error != null) ...[
              const SizedBox(height: AppDesign.md),
              DangerCard(error),
            ],
            SettingsSection(
              label: context.l10n.sectionAssistant,
              icon: Icons.auto_awesome_outlined,
              children: [
                SettingsRow(
                  key: const Key('thinking-row'),
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(context.l10n.thinkingMode),
                  subtitle: Text(
                    '${thinkingLevelLabel(s.thinkingLevel, context.l10n)} · '
                    '${thinkingLevelHint(s.thinkingLevel, context.l10n)}',
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _pickThinking(context, s, n),
                ),
                SettingsRow(
                  leading: const Icon(Icons.travel_explore),
                  title: Text(context.l10n.webResearch),
                  subtitle: Text(webModeLabel(s.webMode, context.l10n)),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _pickWebMode(context, s, n),
                ),
                SettingsRow(
                  key: const Key('knowledge-row'),
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(context.l10n.knowledgeLibrary),
                  subtitle: Text(
                    s.knowledgeCollection.isEmpty
                        ? context.l10n.knowledgeOff
                        : context.l10n.knowledgeOn(s.knowledgeCollection),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const KnowledgePage(),
                    ),
                  ),
                ),
                SettingsRow(
                  key: const Key('memory-row'),
                  leading: const Icon(Icons.psychology_outlined),
                  title: Text(context.l10n.memory),
                  subtitle: Text(
                    s.memoryEnabled
                        ? context.l10n.memoryOnHint
                        : context.l10n.memoryOffHint,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const MemoryPage()),
                  ),
                ),
                SettingsRow(
                  leading: const Icon(Icons.edit_note),
                  title: Text(context.l10n.customInstructions),
                  subtitle: Text(
                    s.systemPrompt.isEmpty
                        ? context.l10n.customInstructionsHint
                        : s.systemPrompt,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _editSystemPrompt(context, s, n),
                ),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionVoice,
              icon: Icons.record_voice_over_outlined,
              children: [
                SettingsSwitchRow(
                  key: const Key('read-aloud'),
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: Text(context.l10n.readAloudSetting),
                  subtitle: Text(context.l10n.readAloudHint),
                  value: s.readAloud,
                  onChanged: (v) => n.update(s.copyWith(readAloud: v)),
                ),
                SettingsSwitchRow(
                  key: const Key('voice-on-device'),
                  secondary: const Icon(Icons.mic_none),
                  title: Text(context.l10n.dictationOnDevice),
                  // Three lines: what "off" allows is the privacy point.
                  subtitle: Text(context.l10n.dictationOnDeviceHint),
                  value: s.voiceOnDeviceOnly,
                  onChanged: (v) => n.update(s.copyWith(voiceOnDeviceOnly: v)),
                ),
                const NaturalVoiceSettings(),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionAutomation,
              icon: Icons.bolt_outlined,
              children: [
                SettingsRow(
                  key: const Key('shortcuts-row'),
                  leading: const Icon(Icons.short_text),
                  title: Text(context.l10n.shortcutsTitle),
                  subtitle: Text(context.l10n.shortcutsRowHint),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ShortcutsPage(),
                    ),
                  ),
                ),
                SettingsRow(
                  key: const Key('schedule-row'),
                  leading: const Icon(Icons.alarm),
                  title: Text(context.l10n.scheduleTitle),
                  subtitle: Text(context.l10n.scheduleRowHint),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const SchedulePage(),
                    ),
                  ),
                ),
                SettingsSwitchRow(
                  key: const Key('auto-titles'),
                  secondary: const Icon(Icons.title),
                  title: Text(context.l10n.autoTitlesSetting),
                  subtitle: Text(context.l10n.autoTitlesHint),
                  value: s.autoTitles,
                  onChanged: (v) => n.update(s.copyWith(autoTitles: v)),
                ),
                SettingsSwitchRow(
                  key: const Key('battery-saver'),
                  secondary: const Icon(Icons.battery_saver_outlined),
                  title: Text(context.l10n.batterySaver),
                  subtitle: Text(
                    s.batterySaver
                        ? context.l10n.batterySaverOn(s.batterySaverLevel)
                        : context.l10n.batterySaverOff,
                  ),
                  value: s.batterySaver,
                  onChanged: (v) => n.update(s.copyWith(batterySaver: v)),
                ),
                if (s.batterySaver)
                  SettingsRow(
                    key: const Key('battery-saver-level'),
                    leading: const SizedBox(width: AppDesign.xl),
                    title: Text(context.l10n.batterySaverLevel),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value:
                            const [
                              10,
                              15,
                              20,
                              30,
                              50,
                            ].contains(s.batterySaverLevel)
                            ? s.batterySaverLevel
                            : 20,
                        items: [
                          for (final v in const [10, 15, 20, 30, 50])
                            DropdownMenuItem(value: v, child: Text('$v%')),
                        ],
                        onChanged: (v) => v == null
                            ? null
                            : n.update(s.copyWith(batterySaverLevel: v)),
                      ),
                    ),
                  ),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionModelConnections,
              icon: Icons.memory_outlined,
              children: [
                const _ActiveModelRow(),
                _DrillRow(
                  icon: Icons.dns_outlined,
                  title: context.l10n.remoteServer,
                  summary: s.usesRemote
                      ? context.l10n.remoteRowOn(
                          '${s.activeRemoteProfile!.label}${s.remoteModel.isEmpty ? '' : ' · ${s.remoteModel}'}',
                        )
                      : context.l10n.remoteRowOff,
                  page: const RemoteServerPage(),
                ),
                _DrillRow(
                  icon: Icons.wifi_tethering,
                  title: context.l10n.hostTitle,
                  summary: context.l10n.hostRowHint,
                  page: const DeviceHostingPage(),
                ),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionAppearanceLanguage,
              icon: Icons.palette_outlined,
              children: [
                _DrillRow(
                  icon: Icons.contrast,
                  title: context.l10n.uiSettingsScreenAppearance,
                  summary:
                      '${s.themeChoice.name} · ${s.accent.name} · ${(s.textScale * 100).round()}%',
                  page: const AppearancePage(),
                ),
                SettingsRow(
                  key: const Key('language-row'),
                  leading: const Icon(Icons.translate),
                  title: Text(context.l10n.language),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: s.localeCode,
                      items: [
                        for (final code in supportedLanguageCodes)
                          DropdownMenuItem(
                            value: code,
                            child: Text(switch (code) {
                              'en' => context.l10n.languageEnglish,
                              'fr' => context.l10n.languageFrench,
                              'es' => context.l10n.languageSpanish,
                              _ => context.l10n.languageSystem,
                            }),
                          ),
                      ],
                      onChanged: (v) => v == null
                          ? null
                          : n.update(s.copyWith(localeCode: v)),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionData,
              icon: Icons.shield_outlined,
              children: [
                _DrillRow(
                  icon: Icons.backup_outlined,
                  title: context.l10n.uiSettingsScreenEncryptedBackup,
                  summary: context.l10n.backupRowHint,
                  page: const BackupPage(),
                ),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionAdvanced,
              icon: Icons.tune,
              children: [
                _DrillRow(
                  icon: Icons.tune,
                  title: context.l10n.modelSettingsAll,
                  summary: context.l10n.modelSettingsAllHint,
                  page: const InferenceContractPage(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: AppDesign.xs,
                right: AppDesign.xs,
                bottom: AppDesign.md,
              ),
              child: Text(context.l10n.advancedNote, style: context.text.small),
            ),
            SettingsGroup(
              children: [
                _DrillRow(
                  icon: Icons.data_array,
                  mono: true,
                  title: context.l10n.contextAndBatch,
                  summary:
                      '${tokenCount(s.contextSize)} ctx · ${s.batchSize == 0 ? 'auto' : s.batchSize} batch · cache ${s.promptCache ? 'on' : 'off'}',
                  page: const ContextBatchPage(),
                ),
                _DrillRow(
                  icon: Icons.developer_board,
                  mono: true,
                  title: context.l10n.hardware,
                  summary:
                      '${backendShort(s.backend)} · '
                      '${s.nGpuLayers == 999 ? 'all' : s.nGpuLayers} layers · '
                      '${s.cpuThreads == 0 ? 'auto' : s.cpuThreads}/${s.batchThreads == 0 ? 'auto' : s.batchThreads} thr · '
                      '${s.kvCacheType.name} kv',
                  page: const HardwarePage(),
                ),
                _DrillRow(
                  icon: Icons.tune,
                  mono: true,
                  title: context.l10n.sampling,
                  summary: () {
                    // What the sampler uses: the model's recommended values
                    // where the user set none (request 2026-10-04).
                    final e = ref.watch(effectiveSettingsProvider).effective;
                    return 'T ${e.temperature.toStringAsFixed(2)} · '
                        'top-p ${e.topP.toStringAsFixed(2)} · '
                        'top-k ${e.topK} · max ${tokenCount(e.maxTokens)}';
                  }(),
                  page: const SamplingPage(),
                ),
                _DrillRow(
                  icon: Icons.manage_search,
                  mono: true,
                  title: context.l10n.reasoningAndSearch,
                  summary:
                      'think ${s.thinkingBudgetTokens == 0 ? 'unlimited' : tokenCount(s.thinkingBudgetTokens)} · '
                      '${s.maxSearchResults} results · ${s.maxPagesRead} pages · '
                      '${s.evidencePassages} passages · ${s.researchTimeBudgetSeconds} s',
                  page: const ReasoningSearchPage(),
                ),
                _DrillRow(
                  icon: Icons.casino_outlined,
                  mono: true,
                  title: context.l10n.uiSettingsScreenMoreSampling,
                  summary:
                      'seed ${s.seed == 0 ? 'random' : s.seed} · '
                      '${s.stopSequences.length} stop · '
                      'presence ${s.presencePenalty.toStringAsFixed(1)} · freq ${s.frequencyPenalty.toStringAsFixed(1)}'
                      '${s.dryMultiplier > 0 ? ' · dry' : ''}${s.xtcProbability > 0 ? ' · xtc' : ''}',
                  page: const SamplingExtrasPage(),
                ),
                _DrillRow(
                  icon: Icons.storage_outlined,
                  mono: true,
                  title: context.l10n.uiSettingsScreenMemoryRoPESpeculation,
                  summary:
                      'K ${s.kvCacheType.name} · V ${s.vCacheType?.name ?? 'same'} · rope ${s.ropeScaling.name}'
                      '${s.draftModelId.isEmpty ? '' : ' · draft on'}',
                  page: const MemoryRopePage(),
                ),
                _DrillRow(
                  icon: Icons.data_object,
                  mono: true,
                  title: context.l10n.uiSettingsScreenStructuredOutput,
                  summary: switch (s.responseFormat) {
                    ResponseFormat.text => 'free text',
                    ResponseFormat.json => 'JSON',
                    ResponseFormat.jsonSchema => 'JSON schema',
                    ResponseFormat.gbnf => 'GBNF grammar',
                  },
                  page: const StructuredOutputPage(),
                ),
                _DrillRow(
                  icon: Icons.handyman_outlined,
                  mono: true,
                  title: context.l10n.uiSettingsScreenTools,
                  summary: s.toolsEnabled
                      ? 'on · ${s.toolMaxRounds} rounds'
                            '${s.toolCalculator ? ' · calc' : ''}'
                            '${s.toolWeb && s.webSearchEnabled ? ' · web' : ''}'
                            '${s.toolDocuments && s.knowledgeCollection.isNotEmpty ? ' · docs' : ''}'
                      : 'off',
                  page: const ToolsPage(),
                ),
                _DrillRow(
                  icon: Icons.extension_outlined,
                  mono: true,
                  title: context.l10n.uiSettingsScreenLoRAAdapters,
                  summary: () {
                    final a = ref.watch(adaptersProvider);
                    final attached = a.attachments.values.fold<int>(
                      0,
                      (n, l) => n + l.length,
                    );
                    return '${a.adapters.length} imported · $attached attached';
                  }(),
                  page: const AdaptersPage(),
                ),
                _DrillRow(
                  icon: Icons.fact_check_outlined,
                  mono: true,
                  title: context.l10n.uiSettingsScreenEffectiveSettings,
                  summary: () {
                    final r = ref.watch(effectiveSettingsProvider);
                    final n = r.overriddenKeys.length;
                    return n == 0
                        ? 'nothing overridden'
                        : '$n overridden by profile, preset or chat';
                  }(),
                  page: const EffectiveSettingsPage(),
                ),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionAbout,
              icon: Icons.info_outline,
              children: [
                SettingsRow(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text(AppConstants.appName),
                  subtitle: const MonoSummary(
                    'v$_appVersion · ${BuildIdentity.source}',
                  ),
                  trailing: Text(
                    context.l10n.openSourceMit,
                    style: context.text.small.copyWith(color: c.textFaint),
                  ),
                ),
                SettingsRow(
                  leading: const Icon(Icons.code),
                  title: Text(context.l10n.builtOnLlama),
                  subtitle: Text(context.l10n.builtOnLlamaHint),
                  trailing: Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: c.textMuted,
                  ),
                  onTap: () => _openLink(context, _llamaCppUrl),
                ),
                SettingsRow(
                  key: const Key('open-source-licences'),
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(context.l10n.openSourceLicences),
                  subtitle: Text(context.l10n.openSourceLicencesHint),
                  trailing: Icon(Icons.chevron_right, color: c.textMuted),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppConstants.appName,
                    applicationVersion: 'v$_appVersion',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The default thinking level for new chats; the Think pill changes it
  /// per chat. The hint under the list says reasoning is not proof.
  Future<void> _pickThinking(
    BuildContext context,
    InferenceSettings s,
    SettingsNotifier n,
  ) async {
    final picked = await showMorphSheet<ThinkingLevel>(
      context: context,
      useSafeArea: true,
      builder: (context) => AppSheet(
        title: context.l10n.thinkingMode,
        children: [
          for (final level in ThinkingLevel.values)
            RadioListTile<ThinkingLevel>(
              key: Key('thinking-${level.name}'),
              value: level,
              // ignore: deprecated_member_use
              groupValue: s.thinkingLevel,
              title: Text(thinkingLevelLabel(level, context.l10n)),
              subtitle: Text(thinkingLevelHint(level, context.l10n)),
              // ignore: deprecated_member_use
              onChanged: (v) => Navigator.pop(context, v),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDesign.lg,
              AppDesign.xs,
              AppDesign.lg,
              AppDesign.md,
            ),
            child: Text(
              context.l10n.thinkingModeHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == s.thinkingLevel) return;
    await n.update(
      picked == ThinkingLevel.off
          ? s.copyWith(thinkingModeEnabled: false)
          : s.copyWith(
              thinkingModeEnabled: true,
              thinkingBudgetTokens: picked.budget,
            ),
    );
  }

  Future<void> _pickWebMode(
    BuildContext context,
    InferenceSettings s,
    SettingsNotifier n,
  ) async {
    final picked = await showMorphSheet<WebMode>(
      context: context,
      useSafeArea: true,
      builder: (context) => AppSheet(
        title: context.l10n.webResearchShort,
        children: [
          for (final m in WebMode.values)
            RadioListTile<WebMode>(
              key: Key('web-mode-${m.name}'),
              value: m,
              // ignore: deprecated_member_use
              groupValue: s.webMode,
              title: Text(webModeLabel(m, context.l10n)),
              subtitle: Text(switch (m) {
                WebMode.off => context.l10n.webOffHint,
                WebMode.auto => context.l10n.webAutoHint,
                WebMode.always => context.l10n.webAlwaysHint,
              }),
              // ignore: deprecated_member_use
              onChanged: (v) => Navigator.pop(context, v),
            ),
        ],
      ),
    );
    if (picked == null || picked == s.webMode) return;
    if (picked != WebMode.off &&
        s.webMode == WebMode.off &&
        context.mounted &&
        !await _confirmWebSearch(context)) {
      return;
    }
    await n.update(s.copyWith(webMode: picked));
  }

  Future<void> _confirmReset(BuildContext context, SettingsNotifier n) async {
    final ok = await confirmAction(
      context,
      title: context.l10n.resetQuestion,
      message: context.l10n.resetHint,
      confirmLabel: context.l10n.reset,
      destructive: true,
    );
    if (ok == true) await n.reset();
  }

  /// Web search is the one feature that sends user text off the device, so
  /// turning it on is an explicit, informed step.
  Future<bool> _confirmWebSearch(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: context.l10n.enableWebQuestion,
      message: context.l10n.enableWebHint,
      confirmLabel: context.l10n.enable,
    );
    return ok == true;
  }

  Future<void> _editSystemPrompt(
    BuildContext context,
    InferenceSettings s,
    SettingsNotifier n,
  ) async {
    final next = await promptText(
      context,
      title: context.l10n.systemInstructions,
      initial: s.systemPrompt,
      hint: context.l10n.systemInstructionsHint,
      confirmLabel: context.l10n.save,
      minLines: 3,
      maxLines: 8,
      maxLength: 16000,
      allowEmpty: true,
    );
    if (next != null) await n.update(s.copyWith(systemPrompt: next));
  }

  Future<void> _openLink(BuildContext context, String url) async {
    try {
      await openExternalLink(url);
    } catch (_) {
      if (context.mounted) {
        showIslandToast(
          context,
          context.l10n.couldNotOpenLink,
          tone: IslandTone.error,
        );
      }
    }
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.accent.fade(0.12),
                borderRadius: AppDesign.radius(AppDesign.rMd),
              ),
              child: Icon(Icons.lock_outline, size: 18, color: c.accent),
            ),
            const SizedBox(width: AppDesign.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.privateByDefault,
                    style: context.text.headline,
                  ),
                  const SizedBox(height: AppDesign.xs),
                  Text(
                    context.l10n.privateByDefaultHint,
                    style: context.text.bodyMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveModelRow extends ConsumerWidget {
  const _ActiveModelRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final m = ref.watch(modelManagerProvider.select((s) => s.loadedModel));
    final tags = m == null
        ? null
        : [
            m.quantization.name.toUpperCase(),
            if (m.parameterCountB != null) '${m.parameterCountB}B',
            m.sizeLabel,
            m.family.name,
          ].join(' · ');
    return SettingsRow(
      leading: Icon(
        Icons.memory_outlined,
        color: m == null ? c.textFaint : c.accent,
      ),
      title: Text(m?.displayName ?? context.l10n.noModelLoadedTitle),
      subtitle: tags != null
          ? MonoSummary(tags)
          : Text(context.l10n.chooseFromLibrary),
      trailing: Icon(Icons.chevron_right, color: c.textMuted),
      onTap: () => Navigator.pushNamed(context, AppRoutes.models),
    );
  }
}

class _DrillRow extends StatelessWidget {
  final String title;
  final String summary;
  final Widget page;
  final IconData? icon;

  /// Technical values (token counts, sampler numbers) read best in mono;
  /// plain sentences do not.
  final bool mono;
  const _DrillRow({
    required this.title,
    required this.summary,
    required this.page,
    this.icon,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) => SettingsRow(
    leading: icon == null ? null : Icon(icon),
    title: Text(title),
    subtitle: mono ? MonoSummary(summary) : Text(summary),
    trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
    onTap: () =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page)),
  );
}
