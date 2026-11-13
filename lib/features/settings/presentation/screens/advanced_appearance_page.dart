part of 'advanced_pages_2.dart';

// Theme, accent, text scale, bubble density.

/// Theme selection and reading comfort.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final dark = context.colors.isDark;
    return _Scaffold(
      title: context.l10n.uiAdvancedAppearancePageAppearance,
      children: [
        SettingsGroup(
          children: [
            SettingDropdown<ThemeChoice>(
              icon: Icons.dark_mode_outlined,
              label: context.l10n.uiAdvancedAppearancePageTheme,
              hint: context.isDesktop
                  ? context.l10n.themeHintPc
                  : context
                        .l10n
                        .uiAdvancedAppearancePageDarkIsTheDesignedDefaultLight,
              value: s.themeChoice,
              items: ThemeChoice.values,
              labelOf: (v) => switch (v) {
                ThemeChoice.system => context.byFormFactor(
                  context.l10n.languageSystem,
                  context.l10n.desktopThemeSystem,
                ),
                ThemeChoice.dark => context.byFormFactor(
                  context.l10n.desktopThemeDark,
                  context.l10n.desktopThemeDark,
                ),
                ThemeChoice.light => context.byFormFactor(
                  context.l10n.desktopThemeLight,
                  context.l10n.desktopThemeLight,
                ),
              },
              onChanged: (v) => n.update(s.copyWith(themeChoice: v)),
            ),
            SettingDropdown<MotionChoice>(
              icon: Icons.animation_rounded,
              key: const Key('motion-choice'),
              label: context.l10n.motionLabel,
              hint: (context.isDesktop
                  ? context.l10n.motionHintPc
                  : context.l10n.motionHint),
              value: s.motion,
              items: MotionChoice.values,
              labelOf: (v) => switch (v) {
                MotionChoice.full => context.l10n.motionFull,
                MotionChoice.subtle => context.l10n.motionSubtle,
                MotionChoice.off => context.l10n.motionOff,
              },
              onChanged: (v) => n.update(s.copyWith(motion: v)),
            ),
            SettingsTile(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.uiAdvancedAppearancePageAccentColour),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.md,
                    children: [
                      for (final a in AccentChoice.values)
                        GestureDetector(
                          key: Key('accent-${a.name}'),
                          onTap: () => n.update(s.copyWith(accent: a)),
                          child: Container(
                            width: AppDesign.iconTile,
                            height: AppDesign.iconTile,
                            decoration: BoxDecoration(
                              color: AppTheme.palette(a, dark: dark).accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: s.accent == a
                                    ? context.colors.text
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: s.accent == a
                                ? Icon(
                                    Icons.check,
                                    size: 18,
                                    color: AppTheme.palette(
                                      a,
                                      dark: dark,
                                    ).onAccent,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedAppearancePageTextSize,
              hint: context.l10n.appearanceTextScaleHint,
              value: s.textScale,
              min: .85,
              max: 1.4,
              divisions: 11,
              display: '${(s.textScale * 100).round()}%',
              onChanged: (v) => n.update(s.copyWith(textScale: v)),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.chat_bubble_outline_rounded),
              title: Text(context.l10n.uiAdvancedAppearancePageCompactBubbles),
              subtitle: Text(
                context
                    .l10n
                    .uiAdvancedAppearancePageTighterSpacingInTheConversation,
              ),
              value: s.compactBubbles,
              onChanged: (v) => n.update(s.copyWith(compactBubbles: v)),
            ),
          ],
        ),
      ],
    );
  }
}
