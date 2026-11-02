import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/blur_switcher.dart';
import '../core/motion/pressable.dart';
import '../core/motion/spring_entrance.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../features/settings/presentation/screens/advanced_pages_2.dart';
import '../features/settings/presentation/screens/advanced_pages.dart';
import '../features/settings/presentation/screens/knowledge_page.dart';
import '../features/settings/presentation/screens/memory_page.dart';
import '../features/settings/presentation/screens/remote_server_page.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/settings/presentation/widgets/settings_widgets.dart';
import 'desktop_theme.dart';
import '../core/platform/desktop_preferences.dart';
import 'advanced_toggle.dart';
import 'engine_files_panel.dart';
import 'focus_ring.dart';
import 'keyboard_shortcuts.dart';
import 'models_folder_setting.dart';
import 'tray.dart';

/// Settings as Windows lays them out: categories on the left, the chosen
/// one on the right. General is drawn for the desktop; the rest reuse the
/// shared settings pages, each in its own navigator inside the panel.
class DesktopSettingsPanel extends ConsumerStatefulWidget {
  const DesktopSettingsPanel({super.key});

  @override
  ConsumerState<DesktopSettingsPanel> createState() =>
      _DesktopSettingsPanelState();
}

class _DesktopSettingsPanelState extends ConsumerState<DesktopSettingsPanel> {
  int _selected = 0;
  bool _wasAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final advanced = ref.watch(desktopPreferencesProvider).advanced;
    if (_wasAdvanced != advanced) _selected = 0;
    _wasAdvanced = advanced;
    final categories = <(IconData, String, Widget)>[
      (Icons.tune_rounded, l10n.desktopGeneral, const _GeneralSettings()),
      (
        Icons.palette_outlined,
        l10n.uiSettingsScreenAppearance,
        const AppearancePage(),
      ),
      (
        Icons.auto_awesome_outlined,
        l10n.sectionAssistant,
        const SettingsScreen(only: SettingsPart.assistant),
      ),
      (
        Icons.record_voice_over_outlined,
        l10n.sectionVoice,
        const SettingsScreen(only: SettingsPart.voice),
      ),
      (Icons.psychology_alt_outlined, l10n.memory, const MemoryPage()),
      (
        Icons.local_library_outlined,
        l10n.knowledgeLibrary,
        const KnowledgePage(),
      ),
      (Icons.dns_outlined, l10n.remoteServer, const RemoteServerPage()),
      (
        Icons.shield_outlined,
        l10n.sectionData,
        const SettingsScreen(only: SettingsPart.data),
      ),
      if (advanced) ...[
        (
          Icons.data_array_rounded,
          l10n.contextAndBatch,
          const ContextBatchPage(),
        ),
        (Icons.developer_board_outlined, l10n.hardware, const HardwarePage()),
        (
          Icons.travel_explore_rounded,
          l10n.reasoningAndSearch,
          const ReasoningSearchPage(),
        ),
        (Icons.build_outlined, l10n.uiSettingsScreenTools, const ToolsPage()),
        (
          Icons.more_horiz_rounded,
          l10n.desktopMoreSettings,
          const SettingsScreen(only: SettingsPart.advanced),
        ),
      ],
      (
        Icons.info_outline_rounded,
        l10n.sectionAbout,
        const SettingsScreen(only: SettingsPart.about),
      ),
    ];
    // The advanced pages sit under their own heading, before About.
    final advancedStart = advanced ? 8 : -1;
    if (_selected >= categories.length) _selected = 0;
    final (_, _, page) = categories[_selected];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 0, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.settings, style: context.text.headline),
                    const SizedBox(height: 6),
                    Text(
                      l10n.desktopSettingsExplanation,
                      style: context.text.small,
                    ),
                    const SizedBox(height: 12),
                    const DesktopAdvancedToggle(),
                  ],
                ),
              ),
              for (var i = 0; i < categories.length; i++) ...[
                if (i == advancedStart)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 0, 6),
                    child: Text(
                      l10n.sectionAdvanced,
                      style: context.text.caption.copyWith(color: c.textMuted),
                    ),
                  ),
                SpringEntrance(
                  delay: SpringEntrance.cascade(i),
                  from: const Offset(-10, 0),
                  child: _CategoryRow(
                    icon: categories[i].$1,
                    label: categories[i].$2,
                    selected: i == _selected,
                    onTap: () => setState(() => _selected = i),
                  ),
                ),
              ],
            ],
          ),
        ),
        VerticalDivider(width: 1, color: c.hairline),
        Expanded(
          child: BlurSwitcher(
            alignment: Alignment.topLeft,
            child: Align(
              key: ValueKey((advanced, _selected)),
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Theme(
                    data: _pageTheme(context),
                    child: Navigator(
                      onGenerateRoute: (_) =>
                          MaterialPageRoute(builder: (_) => page),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Every settings page's app bar becomes a Windows page title: a large
/// heading on the page itself, no bar colour, no shadow. Pages paint the
/// panel's own colour: a transparent one let the page below show through
/// while the next slid in (owner 2026-11-01, Assistant > Prompt shortcuts).
ThemeData _pageTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.copyWith(
    scaffoldBackgroundColor: DesktopTheme.contentLayer(context.colors),
    appBarTheme: theme.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 76,
      titleSpacing: 16,
      titleTextStyle: context.text.headline.copyWith(fontSize: 26),
    ),
  );
}

class _CategoryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      pressedScale: 0.97,
      child: DesktopFocusRing(
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppDesign.radius(AppDesign.rMd),
          child: _row(context, c),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, AppColors c) => AnimatedContainer(
    duration: DesktopTheme.fast,
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: selected ? c.text.fade(0.08) : Colors.transparent,
      borderRadius: AppDesign.radius(AppDesign.rMd),
    ),
    child: Row(
      children: [
        AnimatedContainer(
          duration: DesktopTheme.fast,
          width: 3,
          height: selected ? 16 : 0,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: AppDesign.radius(2),
          ),
        ),
        Icon(icon, size: 17, color: selected ? c.text : c.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: context.text.body.copyWith(
              fontSize: 13.5,
              color: selected ? c.text : c.textMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The settings people change most, laid out as desktop setting cards.
/// Thinking and web research live on the Assistant page, the theme on
/// Appearance.
class _GeneralSettings extends ConsumerWidget {
  const _GeneralSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final prefs = ref.watch(desktopPreferencesProvider);
    void set(InferenceSettings next) =>
        ref.read(settingsProvider.notifier).update(next);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.desktopGeneral),
        actions: const [SavedIndicator()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                key: const Key('language-row'),
                leading: const Icon(Icons.translate),
                title: Text(l10n.language),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: s.localeCode,
                    borderRadius: AppDesign.radius(AppDesign.rMd),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(l10n.desktopLanguageSystem),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(l10n.languageEnglish),
                      ),
                      DropdownMenuItem(
                        value: 'fr',
                        child: Text(l10n.languageFrench),
                      ),
                      DropdownMenuItem(
                        value: 'es',
                        child: Text(l10n.languageSpanish),
                      ),
                    ],
                    onChanged: (v) => set(s.copyWith(localeCode: v ?? '')),
                  ),
                ),
              ),
              SettingsSwitchRow(
                key: const Key('desktop-lean-prompt'),
                secondary: const Icon(Icons.bolt_outlined),
                title: Text(l10n.desktopLeanPrompt),
                subtitle: Text(l10n.desktopLeanPromptHint),
                value: prefs.leanPrompt,
                onChanged: (value) => ref
                    .read(desktopPreferencesProvider.notifier)
                    .set(leanPrompt: value),
              ),
              SettingSlider(
                label: l10n.temperature,
                hint: l10n.uiAdvancedPagesRandomnessLowerIsMoreFocusedHigher,
                value: s.temperature,
                min: 0,
                max: 2,
                divisions: 40,
                display: s.temperature.toStringAsFixed(2),
                onChanged: (v) => set(s.copyWith(temperature: v)),
              ),
              SettingSlider(
                key: const Key('desktopDeep-global-vramReserveMb'),
                label: l10n.desktopDeepVramReserveMb,
                hint: l10n.desktopDeepVramReserveHint,
                value: s.vramReserveMb.toDouble(),
                min: 0,
                max: 8192,
                divisions: 128,
                display: '${s.vramReserveMb}',
                onChanged: (v) => set(s.copyWith(vramReserveMb: v.round())),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const ModelsFolderSetting(),
          const DesktopTraySettingsPanel(),
          const SizedBox(height: 20),
          if (prefs.advanced) const EngineFilesPanel(),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => showDesktopShortcuts(
                context,
                DesktopShortcutScope.of(context),
              ),
              icon: const Icon(Icons.keyboard_outlined),
              label: Text('${l10n.desktopKeyboardShortcuts} (Ctrl+/)'),
            ),
          ),
        ],
      ),
    );
  }
}
