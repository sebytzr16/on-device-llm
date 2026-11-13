import 'package:flutter/material.dart';

/// Single source of truth for the visual system: dark, editorial-meets-
/// technical. Serif display type for headlines, a neutral sans for reading,
/// mono for numbers and code, one warm accent on near-black charcoal.
///
/// Widgets take colours from `Theme.of(context).colorScheme` and the
/// extension below; never hard-code hex values in a screen.
abstract final class AppDesign {
  // ----- Spacing scale (4px base) -----
  static const double xs = AppSpace.xs;
  static const double sm = AppSpace.sm;
  static const double md = AppSpace.md;
  static const double lg = AppSpace.lg;
  static const double xl = AppSpace.xl;
  static const double xxl = AppSpace.xxl;
  static const double xxxl = 48;

  // Shared component dimensions from the reference board.
  static const double actionHeight = 48;
  static const double rowHeight = 56;
  static const double iconTile = 36;
  static const double iconSize = 20;

  // ----- Radius -----
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 18;
  static const double rXl = 26;
  static const double rFull = 999;
  static BorderRadius radius(double v) => BorderRadius.circular(v);

  // Durations and curves live in AppMotion (core/motion/motion.dart).

  // ----- Palette (the designed dark scheme; see AppColors.light) -----
  /// Page background: near-black with a warm cast.
  static const Color ink = Color(0xFF0A0B0E);

  /// Cards, sheets, bubbles.
  static const Color surface = Color(0xFF13161C);

  /// Raised elements on a surface (chips, inputs, hover).
  static const Color surfaceRaised = Color(0xFF1B1F27);

  /// Overlays, menus, tooltips.
  static const Color surfaceOverlay = Color(0xFF232833);

  /// Hairline borders.
  static const Color hairline = Color(0xFF2A303B);
  static const Color hairlineStrong = Color(0xFF3A4150);

  static const Color text = Color(0xFFECEEF2);
  static const Color textMuted = Color(0xFF9AA3B2);
  static const Color textFaint = Color(0xFF636C7A);

  /// Warm amber accent: the only saturated colour in the UI.
  static const Color accent = Color(0xFFF2B544);
  static const Color accentDeep = Color(0xFFC98B1A);
  static const Color onAccent = Color(0xFF1A1200);

  /// Secondary cool tone for links, info and the "thinking" channel.
  static const Color info = Color(0xFF7AA2F7);
  static const Color success = Color(0xFF58C27D);
  static const Color warning = Color(0xFFF2B544);
  static const Color danger = Color(0xFFF26D6D);

  /// Reasoning channel tint: cool, subdued, visually subordinate.
  static const Color reasoning = Color(0xFF8FA6D9);

  // ----- Typography -----
  static const String display = 'Fraunces';
  static const String sans = 'Inter';
  static const String mono = 'JetBrainsMono';
}

/// Cross-version alpha helper.
extension ColorAlphaX on Color {
  Color fade(double opacity) => withValues(alpha: opacity.clamp(0.0, 1.0));
}

/// Semantic colours that ColorScheme has no slot for.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color ink,
      surface,
      surfaceRaised,
      surfaceOverlay,
      hairline,
      hairlineStrong;
  final Color text, textMuted, textFaint;
  final Color accent,
      accentDeep,
      onAccent,
      info,
      success,
      warning,
      danger,
      reasoning;
  const AppColors({
    required this.ink,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.hairline,
    required this.hairlineStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentDeep,
    required this.onAccent,
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
    required this.reasoning,
  });

  static const dark = AppColors(
    ink: AppDesign.ink,
    surface: AppDesign.surface,
    surfaceRaised: AppDesign.surfaceRaised,
    surfaceOverlay: AppDesign.surfaceOverlay,
    hairline: AppDesign.hairline,
    hairlineStrong: AppDesign.hairlineStrong,
    text: AppDesign.text,
    textMuted: AppDesign.textMuted,
    textFaint: AppDesign.textFaint,
    accent: AppDesign.accent,
    accentDeep: AppDesign.accentDeep,
    onAccent: AppDesign.onAccent,
    info: AppDesign.info,
    success: AppDesign.success,
    warning: AppDesign.warning,
    danger: AppDesign.danger,
    reasoning: AppDesign.reasoning,
  );

  /// The light scheme: a plain mid grey, never white or light grey (owner
  /// 2026-11-12: "it has to be gray, just gray"). Text and statuses are
  /// darkened to keep WCAG AA (4.5:1) on every surface; cards sit one step
  /// above the page.
  static const light = AppColors(
    ink: Color(0xFF898C91),
    surface: Color(0xFF8E9196),
    surfaceRaised: Color(0xFF95989D),
    surfaceOverlay: Color(0xFF9A9DA2),
    hairline: Color(0xFF74777C),
    hairlineStrong: Color(0xFF5F6267),
    text: Color(0xFF000000),
    textMuted: Color(0xFF0C0D0F),
    textFaint: Color(0xFF0E0F11),
    accent: Color(0xFF2E1E00),
    accentDeep: Color(0xFF3A2600),
    onAccent: Color(0xFFFFFFFF),
    info: Color(0xFF08194A),
    success: Color(0xFF02240F),
    warning: Color(0xFF2E1E00),
    danger: Color(0xFF480A0A),
    reasoning: Color(0xFF17213A),
  );

  // Text, not ink: the light theme's mid-grey ink is darker than 50 %.
  bool get isDark => text.computeLuminance() > 0.5;

  @override
  bool operator ==(Object other) =>
      other is AppColors &&
      other.ink == ink &&
      other.surface == surface &&
      other.text == text &&
      other.accent == accent &&
      other.reasoning == reasoning;

  @override
  int get hashCode => Object.hash(ink, surface, text, accent, reasoning);

  @override
  AppColors copyWith({Color? accent, Color? accentDeep, Color? onAccent}) =>
      AppColors(
        ink: ink,
        surface: surface,
        surfaceRaised: surfaceRaised,
        surfaceOverlay: surfaceOverlay,
        hairline: hairline,
        hairlineStrong: hairlineStrong,
        text: text,
        textMuted: textMuted,
        textFaint: textFaint,
        accent: accent ?? this.accent,
        accentDeep: accentDeep ?? this.accentDeep,
        onAccent: onAccent ?? this.onAccent,
        info: info,
        success: success,
        warning: warning,
        danger: danger,
        reasoning: reasoning,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => this;
}

/// Text styles coloured for the active palette. Widgets use
/// `context.text.body` etc.; [AppText] keeps the dark-palette constants for
/// the theme definition and const contexts.
class AppTextTheme {
  final TextStyle display,
      headline,
      title,
      body,
      bodyMuted,
      small,
      label,
      caption,
      mono,
      monoStrong,
      reasoning;
  const AppTextTheme({
    required this.display,
    required this.headline,
    required this.title,
    required this.body,
    required this.bodyMuted,
    required this.small,
    required this.label,
    required this.caption,
    required this.mono,
    required this.monoStrong,
    required this.reasoning,
  });

  factory AppTextTheme.of(AppColors c) => AppTextTheme(
    display: AppText.display.copyWith(color: c.text),
    headline: AppText.headline.copyWith(color: c.text),
    title: AppText.title.copyWith(color: c.text),
    body: AppText.body.copyWith(color: c.text),
    bodyMuted: AppText.bodyMuted.copyWith(color: c.textMuted),
    small: AppText.small.copyWith(color: c.textMuted),
    label: AppText.label.copyWith(color: c.textMuted),
    caption: AppText.caption.copyWith(color: c.textMuted),
    mono: AppText.mono.copyWith(color: c.textMuted),
    monoStrong: AppText.monoStrong.copyWith(color: c.text),
    reasoning: AppText.reasoning.copyWith(color: c.reasoning),
  );

  static final _cache = <AppColors, AppTextTheme>{};
  static AppTextTheme cached(AppColors c) =>
      _cache.putIfAbsent(c, () => AppTextTheme.of(c));
}

extension AppColorsX on BuildContext {
  AppColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark
            ? AppColors.dark
            : AppColors.light);
  }

  /// Text styles in the active palette's colours.
  AppTextTheme get text => AppTextTheme.cached(colors);
}

/// Text styles that the Material text theme does not name.
abstract final class AppText {
  static const TextStyle display = TextStyle(
    fontFamily: AppDesign.display,
    fontSize: 32,
    height: 1.12,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    color: AppDesign.text,
  );
  static const TextStyle headline = TextStyle(
    fontFamily: AppDesign.display,
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    color: AppDesign.text,
  );
  static const TextStyle title = TextStyle(
    fontFamily: AppDesign.sans,
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppDesign.text,
  );
  static const TextStyle body = TextStyle(
    fontFamily: AppDesign.sans,
    fontSize: 15,
    height: 1.55,
    fontWeight: FontWeight.w400,
    color: AppDesign.text,
  );
  static const TextStyle bodyMuted = TextStyle(
    fontFamily: AppDesign.sans,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppDesign.textMuted,
  );

  /// Secondary lines, hints and footnotes.
  static const TextStyle small = TextStyle(
    fontFamily: AppDesign.sans,
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppDesign.textMuted,
  );

  /// Badges, chip labels and timestamps.
  static const TextStyle caption = TextStyle(
    fontFamily: AppDesign.sans,
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: AppDesign.textMuted,
  );
  static const TextStyle label = TextStyle(
    fontFamily: AppDesign.sans,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: AppDesign.textMuted,
  );
  static const TextStyle mono = TextStyle(
    fontFamily: AppDesign.mono,
    fontSize: 12.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppDesign.textMuted,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle monoStrong = TextStyle(
    fontFamily: AppDesign.mono,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: AppDesign.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle reasoning = TextStyle(
    fontFamily: AppDesign.sans,
    fontSize: 13.5,
    height: 1.55,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    color: AppDesign.reasoning,
  );
}

/// Shared spacing for desktop pages and phone content.
abstract final class AppSpace {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
  static const double desktopPage = xl, phonePage = lg, section = xl, row = sm;
}

/// Editorial page heading with optional actions and tabs or filters.
class AppPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottom;
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: context.text.headline),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(subtitle!, style: context.text.bodyMuted),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpace.lg),
            // Align fills the share Flexible gets, so the actions sit at the
            // far right instead of where that share ends (owner 2026-11-12).
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: actions,
                ),
              ),
            ),
          ],
        ],
      ),
      if (bottom != null) ...[const SizedBox(height: AppSpace.lg), bottom!],
    ],
  );
}

/// Amber tonal actions remain secondary in both palettes and desktop themes.
ButtonStyle appTonalButtonStyle(BuildContext context) => FilledButton.styleFrom(
  foregroundColor: context.colors.accent,
  backgroundColor: context.colors.accent.fade(0.12),
);
