import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/app_design.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  test('light body, hints and statuses remain readable on every surface', () {
    final c = AppColors.light;
    for (final ink in [
      c.text,
      c.textMuted,
      c.textFaint,
      c.accent,
      c.info,
      c.success,
      c.warning,
      c.danger,
    ]) {
      for (final background in [
        c.ink,
        c.surface,
        c.surfaceRaised,
        c.surfaceOverlay,
      ]) {
        expect(
          contrast(ink, background),
          greaterThanOrEqualTo(4.5),
          reason: '$ink on $background',
        );
      }
    }
    for (final accent in AccentChoice.values) {
      final palette = AppTheme.palette(accent, dark: false);
      expect(
        contrast(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(4.5),
        reason: accent.name,
      );
    }
  });
  test('Material overrides use the active light palette', () {
    final theme = AppTheme.light;
    final c = AppColors.light;
    expect(theme.listTileTheme.titleTextStyle!.color, c.text);
    expect(theme.listTileTheme.subtitleTextStyle!.color, c.textMuted);
    expect(theme.dialogTheme.contentTextStyle!.color, c.textMuted);
    expect(theme.dialogTheme.titleTextStyle!.color, c.text);
    expect(theme.snackBarTheme.contentTextStyle!.color, c.text);
    expect(theme.popupMenuTheme.textStyle!.color, c.text);
    expect(theme.sliderTheme.valueIndicatorTextStyle!.color, c.text);
    expect(theme.inputDecorationTheme.hintStyle!.color, c.textFaint);
  });
  testWidgets('fallback palette follows Material brightness', (tester) async {
    late AppColors colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Builder(
          builder: (context) {
            colors = context.colors;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(colors, AppColors.light);
  });
}
