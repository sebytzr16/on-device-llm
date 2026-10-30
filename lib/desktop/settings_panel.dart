import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/blur_switcher.dart';
import '../core/motion/pressable.dart';
import '../core/motion/spring_controls.dart';
import '../core/motion/spring_entrance.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../features/settings/presentation/screens/advanced_pages_2.dart';
import '../features/settings/presentation/screens/advanced_pages.dart';
import '../features/settings/presentation/screens/knowledge_page.dart';
import '../features/settings/presentation/screens/memory_page.dart';
import '../features/settings/presentation/screens/remote_server_page.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
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
      if (advanced) ...[
        (Icons.casino_outlined, l10n.sampling, const SamplingPage()),
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
      ],
      (Icons.psychology_alt_outlined, l10n.memory, const MemoryPage()),
      (
        Icons.local_library_outlined,
        l10n.knowledgeLibrary,
        const KnowledgePage(),
      ),
      (Icons.dns_outlined, l10n.remoteServer, const RemoteServerPage()),
      if (advanced)
        (
          Icons.more_horiz_rounded,
          l10n.desktopMoreSettings,
          const SettingsScreen(),
        ),
    ];
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
              for (var i = 0; i < categories.length; i++)
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
                constraints: const BoxConstraints(maxWidth: 760),
                child: Navigator(
                  onGenerateRoute: (_) =>
                      MaterialPageRoute(builder: (_) => page),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
class _GeneralSettings extends ConsumerWidget {
  const _GeneralSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    void set(InferenceSettings next) =>
        ref.read(settingsProvider.notifier).update(next);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
        children: [
          Text(l10n.desktopGeneral, style: context.text.headline),
          SwitchListTile(
            key: const Key('desktop-lean-prompt'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.desktopLeanPrompt),
            subtitle: Text(l10n.desktopLeanPromptHint),
            value: ref.watch(desktopPreferencesProvider).leanPrompt,
            onChanged: (value) => ref
                .read(desktopPreferencesProvider.notifier)
                .set(leanPrompt: value),
          ),
          const SizedBox(height: 20),
          _Card(
            index: 0,
            title: l10n.language,
            trailing: DropdownButton<String>(
              value: s.localeCode,
              underline: const SizedBox.shrink(),
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
                DropdownMenuItem(value: 'fr', child: Text(l10n.languageFrench)),
                DropdownMenuItem(
                  value: 'es',
                  child: Text(l10n.languageSpanish),
                ),
              ],
              onChanged: (v) => set(s.copyWith(localeCode: v ?? '')),
            ),
          ),
          _Card(
            index: 1,
            title: l10n.uiAdvancedAppearancePageTheme,
            trailing: SegmentedButton<ThemeChoice>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeChoice.dark,
                  icon: const Icon(Icons.dark_mode_outlined, size: 16),
                  label: Text(l10n.desktopThemeDark),
                ),
                ButtonSegment(
                  value: ThemeChoice.light,
                  icon: const Icon(Icons.light_mode_outlined, size: 16),
                  label: Text(l10n.desktopThemeLight),
                ),
                ButtonSegment(
                  value: ThemeChoice.system,
                  icon: const Icon(Icons.contrast_rounded, size: 16),
                  label: Text(l10n.desktopThemeSystem),
                ),
              ],
              selected: {s.themeChoice},
              onSelectionChanged: (v) => set(s.copyWith(themeChoice: v.first)),
            ),
          ),
          _Card(
            index: 2,
            title: l10n.webResearch,
            subtitle: switch (s.webMode) {
              WebMode.off => l10n.webModeOff,
              WebMode.auto => l10n.webModeAuto,
              WebMode.always => l10n.webModeAlways,
            },
            trailing: SegmentedButton<WebMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: WebMode.off, label: Text(l10n.webLocal)),
                ButtonSegment(
                  value: WebMode.auto,
                  label: Text(_capital(l10n.webAuto)),
                ),
                ButtonSegment(
                  value: WebMode.always,
                  label: Text(_capital(l10n.webAlways)),
                ),
              ],
              selected: {s.webMode},
              onSelectionChanged: (v) => set(s.copyWith(webMode: v.first)),
            ),
          ),
          _Card(
            index: 3,
            title: l10n.thinkingMode,
            subtitle: l10n.thinkingModeHint,
            trailing: SpringSwitch(
              value: s.thinkingModeEnabled,
              onChanged: (v) => set(s.copyWith(thinkingModeEnabled: v)),
            ),
          ),
          _Card(
            index: 4,
            title: l10n.temperature,
            trailing: SizedBox(
              width: 260,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: s.temperature.clamp(0, 2),
                      max: 2,
                      divisions: 40,
                      onChanged: (v) => set(s.copyWith(temperature: v)),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      s.temperature.toStringAsFixed(2),
                      style: context.text.mono,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _Card(
            index: 5,
            title: l10n.desktopDeepVramReserveMb,
            subtitle: l10n.desktopDeepVramReserveHint,
            trailing: SizedBox(
              width: 260,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const Key('desktopDeep-global-vramReserveMb'),
                      value: s.vramReserveMb.toDouble(),
                      max: 8192,
                      divisions: 128,
                      onChanged: (v) =>
                          set(s.copyWith(vramReserveMb: v.round())),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text('${s.vramReserveMb}', style: context.text.mono),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const ModelsFolderSetting(),
          const DesktopTraySettingsPanel(),
          const SizedBox(height: 20),
          if (ref.watch(desktopPreferencesProvider).advanced)
            const EngineFilesPanel(),
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

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;

  /// Place in the page's cascade.
  final int index;
  const _Card({
    required this.title,
    required this.trailing,
    this.subtitle,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppDesign.radius(AppDesign.rLg),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.body.copyWith(fontSize: 14)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.text.small.copyWith(fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
    return SpringEntrance(delay: SpringEntrance.cascade(index), child: card);
  }
}

/// The phone's composer pill says "auto" in lower case; a settings control
/// starts with a capital like its neighbours.
String _capital(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
