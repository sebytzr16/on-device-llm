import 'package:flutter/material.dart';

import '../core/design/app_design.dart';
import '../core/motion/spring_routes.dart';
import '../core/platform/form_factor.dart';
import '../core/theme/app_theme.dart';
import '../features/settings/domain/entities/inference_settings.dart';

/// The app's theme with desktop density: a mouse and keyboard need smaller
/// targets than a thumb, hover instead of ink ripples, thin scrollbars, and
/// menus that look like Windows context menus.
abstract final class DesktopTheme {
  /// Hover, panel and page changes: short and calm, no overshoot.
  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;

  static const titleBarHeight = 40.0;
  static const sidebarMin = 220.0;
  static const sidebarMax = 360.0;
  static const readingWidth = 820.0;

  /// Windows 11 layering: the title bar and sidebar sit on the base (the
  /// palette's ink); the main area is a slightly raised layer over it.
  static Color contentLayer(AppColors c) => Color.lerp(c.ink, c.surface, 0.55)!;

  static ThemeData of(AccentChoice accent, {required bool dark}) {
    final base = AppTheme.of(accent, dark: dark);
    final c = AppTheme.palette(accent, dark: dark);
    const compactPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final menuShape = RoundedRectangleBorder(
      borderRadius: AppDesign.radius(AppDesign.rMd),
      side: BorderSide(color: c.hairline),
    );
    WidgetStateProperty<BorderSide?> focusSide([BorderSide? normal]) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: c.accent, width: 2)
              : normal,
        );
    return base.copyWith(
      // Shared pages read this to lay out and word themselves for a PC.
      extensions: [...base.extensions.values, FormFactor.pc],
      // Dropdown values and dialog questions read titleMedium: at desktop
      // size it is control text, not a 16 px heading.
      textTheme: base.textTheme.copyWith(
        titleMedium: AppText.body.copyWith(
          color: c.text,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: c.text.fade(0.05),
      focusColor: c.accent.fade(0.16),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(side: focusSide()),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.windows: SpringPageTransitionsBuilder()},
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(c.text.fade(0.18)),
        crossAxisMargin: 2,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        textStyle: AppText.small.copyWith(color: c.text),
        decoration: BoxDecoration(
          color: c.surfaceOverlay,
          borderRadius: AppDesign.radius(AppDesign.rSm),
          border: Border.all(color: c.hairline),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        elevation: 8,
        shape: menuShape,
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        textStyle: AppText.body.copyWith(color: c.text, fontSize: 13.5),
        // Material 3 items read the label style, not textStyle.
        labelTextStyle: WidgetStatePropertyAll(
          AppText.body.copyWith(color: c.text, fontSize: 13.5),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
          shape: WidgetStatePropertyAll(menuShape),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
          minimumSize: const WidgetStatePropertyAll(Size(200, 0)),
        ),
      ),
      // Context-menu rows at Windows size: 13.5 px text, rounded hover.
      menuButtonTheme: MenuButtonThemeData(
        style: MenuItemButton.styleFrom(
          textStyle: AppText.body.copyWith(fontSize: 13.5),
          foregroundColor: c.text,
          iconColor: c.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(
            borderRadius: AppDesign.radius(AppDesign.rSm),
          ),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.radius(AppDesign.rLg),
          side: BorderSide(color: c.hairline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          textStyle: AppText.title.copyWith(fontSize: 13.5),
          padding: compactPadding,
          minimumSize: const Size(0, 34),
          shape: const StadiumBorder(),
        ).copyWith(side: focusSide()),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.hairlineStrong),
          textStyle: AppText.title.copyWith(fontSize: 13.5),
          padding: compactPadding,
          minimumSize: const Size(0, 34),
          shape: const StadiumBorder(),
        ).copyWith(side: focusSide(BorderSide(color: c.hairlineStrong))),
      ),
      // The phone's amber pill selection, not Material's tonal blue.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: c.accent.fade(0.16),
          selectedForegroundColor: c.accent,
          foregroundColor: c.textMuted,
          side: BorderSide(color: c.hairlineStrong),
          textStyle: AppText.title.copyWith(fontSize: 13),
          shape: const StadiumBorder(),
        ).copyWith(side: focusSide(BorderSide(color: c.hairlineStrong))),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          textStyle: AppText.title.copyWith(fontSize: 13.5),
          minimumSize: const Size(0, 34),
          shape: const StadiumBorder(),
        ).copyWith(side: focusSide()),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: AppDesign.radius(AppDesign.rMd),
          borderSide: BorderSide(color: c.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppDesign.radius(AppDesign.rMd),
          borderSide: BorderSide(color: c.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppDesign.radius(AppDesign.rMd),
          borderSide: BorderSide(color: c.accent.fade(0.7)),
        ),
      ),
    );
  }
}
