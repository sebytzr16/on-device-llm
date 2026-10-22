import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/settings/domain/entities/inference_settings.dart';
import '../design/app_design.dart';
import '../motion/motion.dart';

/// Dark is the designed scheme; light and the accent choice are derived from
/// the same tokens (Settings > Appearance). Widgets read colours through
/// `context.colors` / `context.text`, so a scheme swap needs no widget work.
class AppTheme {
  static ThemeData get dark => _build(AppColors.dark);
  static ThemeData get light => _build(AppColors.light);

  /// The pair of themes for an accent choice.
  static ThemeData of(AccentChoice accent, {required bool dark}) =>
      _build(palette(accent, dark: dark));

  static AppColors palette(AccentChoice accent, {required bool dark}) {
    final base = dark ? AppColors.dark : AppColors.light;
    if (accent == AccentChoice.amber) return base;
    final (Color a, Color deep) = switch (accent) {
      AccentChoice.blue =>
        dark
            ? (const Color(0xFF6FA8FF), const Color(0xFF3F79D6))
            : (const Color(0xFF2B5CBF), const Color(0xFF1F4A9E)),
      AccentChoice.green =>
        dark
            ? (const Color(0xFF58C27D), const Color(0xFF2F9A57))
            : (const Color(0xFF16713A), const Color(0xFF156A36)),
      AccentChoice.rose =>
        dark
            ? (const Color(0xFFF07A9A), const Color(0xFFC94F70))
            : (const Color(0xFFAE2F53), const Color(0xFF962B49)),
      AccentChoice.violet =>
        dark
            ? (const Color(0xFFB08CFF), const Color(0xFF7F5AD6))
            : (const Color(0xFF6A46C7), const Color(0xFF50339B)),
      AccentChoice.teal =>
        dark
            ? (const Color(0xFF4FC8C0), const Color(0xFF2B9C95))
            : (const Color(0xFF126C65), const Color(0xFF156A65)),
      AccentChoice.amber => (base.accent, base.accentDeep),
    };
    return base.copyWith(
      accent: a,
      accentDeep: deep,
      onAccent: dark ? const Color(0xFF0A0B0E) : Colors.white,
    );
  }

  static SystemUiOverlayStyle overlayFor(AppColors c) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: c.isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: c.ink,
    systemNavigationBarIconBrightness: c.isDark
        ? Brightness.light
        : Brightness.dark,
  );

  static ThemeData _build(AppColors c) {
    final dark = c.isDark;
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: Color.alphaBlend(
        c.accent.fade(dark ? .22 : .16),
        c.surface,
      ),
      onPrimaryContainer: dark ? c.accent : c.accentDeep,
      secondary: c.info,
      onSecondary: c.ink,
      secondaryContainer: Color.alphaBlend(c.info.fade(.18), c.surface),
      onSecondaryContainer: c.info,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceContainerLowest: c.ink,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceRaised,
      surfaceContainerHigh: c.surfaceOverlay,
      surfaceContainerHighest: c.surfaceOverlay,
      outline: c.hairlineStrong,
      outlineVariant: c.hairline,
      error: c.danger,
      onError: c.ink,
      errorContainer: Color.alphaBlend(c.danger.fade(.2), c.surface),
      onErrorContainer: c.danger,
      tertiary: c.success,
      inverseSurface: c.text,
      onInverseSurface: c.ink,
    );

    final text = const TextTheme(
      displayLarge: AppText.display,
      displayMedium: AppText.display,
      headlineLarge: AppText.display,
      headlineMedium: AppText.headline,
      headlineSmall: AppText.headline,
      titleLarge: AppText.title,
      titleMedium: AppText.title,
      titleSmall: AppText.label,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      bodySmall: AppText.bodyMuted,
      labelLarge: AppText.title,
      labelMedium: AppText.label,
      labelSmall: AppText.mono,
    ).apply(bodyColor: c.text, displayColor: c.text);

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      fontFamily: AppDesign.sans,
      textTheme: text,
      scaffoldBackgroundColor: c.ink,
      canvasColor: c.ink,
      splashFactory: InkSparkle.splashFactory,
      extensions: [c],
      // Pages slide in on a calm spring over a page that sinks back.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SpringPageTransitionsBuilder(),
          TargetPlatform.iOS: SpringPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlayFor(c),
        titleTextStyle: AppText.title.copyWith(color: c.text),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.radius(AppDesign.rLg),
          side: BorderSide(color: c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceRaised,
        hintStyle: AppText.body.copyWith(color: c.textFaint),
        labelStyle: AppText.body.copyWith(color: c.textMuted),
        helperStyle: AppText.bodyMuted.copyWith(color: c.textMuted),
        border: OutlineInputBorder(
          borderRadius: AppDesign.radius(AppDesign.rLg),
          borderSide: BorderSide(color: c.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppDesign.radius(AppDesign.rLg),
          borderSide: BorderSide(color: c.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppDesign.radius(AppDesign.rLg),
          borderSide: BorderSide(color: c.accent.fade(0.7)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          textStyle: AppText.title.copyWith(fontSize: 15),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.hairlineStrong),
          textStyle: AppText.title.copyWith(fontSize: 15),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          foregroundColor: c.accent,
          textStyle: AppText.title.copyWith(fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.textMuted),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: StadiumBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceRaised,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: c.hairline),
        labelStyle: AppText.bodyMuted.copyWith(fontSize: 13, color: c.text),
        secondaryLabelStyle: AppText.bodyMuted.copyWith(
          fontSize: 13,
          color: c.accent,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.radius(AppDesign.rFull),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceOverlay,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.hairlineStrong,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.surfaceOverlay,
        thumbColor: c.accent,
        overlayColor: c.accent.fade(0.12),
        trackHeight: 3,
        valueIndicatorColor: c.surfaceOverlay,
        valueIndicatorTextStyle: AppText.monoStrong.copyWith(color: c.text),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textMuted,
        textColor: c.text,
        // Titles a step heavier than their descriptions so a row scans
        // by its name; leading icons line up in one column.
        titleTextStyle: AppText.body.copyWith(
          fontWeight: FontWeight.w500,
          color: c.text,
        ),
        subtitleTextStyle: AppText.bodyMuted.copyWith(
          fontSize: 13,
          color: c.textMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minLeadingWidth: 24,
        horizontalTitleGap: 14,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.hairlineStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDesign.rXl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppText.headline.copyWith(fontSize: 21, color: c.text),
        contentTextStyle: AppText.bodyMuted.copyWith(color: c.textMuted),
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.radius(AppDesign.rXl),
          side: BorderSide(color: c.hairline),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(AppDesign.rXl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceOverlay,
        contentTextStyle: AppText.body.copyWith(fontSize: 14, color: c.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.radius(AppDesign.rMd),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        textStyle: AppText.body.copyWith(fontSize: 14, color: c.text),
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.radius(AppDesign.rMd),
          side: BorderSide(color: c.hairline),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceOverlay,
        circularTrackColor: c.surfaceOverlay,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surfaceOverlay,
          borderRadius: AppDesign.radius(AppDesign.rSm),
          border: Border.all(color: c.hairline),
        ),
        textStyle: AppText.bodyMuted.copyWith(fontSize: 12, color: c.text),
      ),
    );
  }
}
