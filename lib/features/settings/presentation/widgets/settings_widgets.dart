import '../../../../core/l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../providers/settings_provider.dart';
import '../../../../core/motion/motion.dart';
import '../../../../core/design/app_dialog.dart';

/// A muted section label above one grouped card.
class SettingsSection extends StatelessWidget {
  final String label;
  final IconData? icon;
  final List<Widget> children;
  const SettingsSection({
    super.key,
    required this.label,
    this.icon,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: AppDesign.xl, bottom: AppDesign.sm),
        child: Semantics(
          header: true,
          child: Text(
            label,
            style: context.text.label.copyWith(color: context.colors.textMuted),
          ),
        ),
      ),
      if (children.isNotEmpty) SettingsGroup(children: children),
    ],
  );
}

/// A clipped surface with dividers aligned after each row's icon tile.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  const SettingsGroup({super.key, required this.children})
    : itemCount = null,
      itemBuilder = null;

  /// Large groups participate in the page's scroll view without building
  /// every row or nesting a shrink-wrapped list.
  const SettingsGroup.sliver({
    super.key,
    required int this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
  }) : children = const [];

  @override
  Widget build(BuildContext context) {
    final builder = itemBuilder;
    if (builder != null) {
      return DecoratedSliver(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppDesign.radius(AppDesign.rLg),
          border: Border.all(color: context.colors.hairline),
        ),
        sliver: SliverList.separated(
          itemCount: itemCount!,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            color: context.colors.hairline,
            indent: AppDesign.lg + AppDesign.iconTile + AppDesign.md,
          ),
          itemBuilder: (context, index) => ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: index == 0
                  ? const Radius.circular(AppDesign.rLg)
                  : Radius.zero,
              bottom: index == itemCount! - 1
                  ? const Radius.circular(AppDesign.rLg)
                  : Radius.zero,
            ),
            child: builder(context, index),
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      color: context.colors.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppDesign.radius(AppDesign.rLg),
        side: BorderSide(color: context.colors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: context.colors.hairline,
                indent: AppDesign.lg + AppDesign.iconTile + AppDesign.md,
              ),
            SpringEntrance(
              delay: SpringEntrance.cascade(i, stepMs: 30),
              from: const Offset(0, AppDesign.sm),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// Keeps existing ListTile semantics and keys with the shared row geometry.
class SettingsRow extends ListTile {
  const SettingsRow({
    super.key,
    super.title,
    super.subtitle,
    super.leading,
    super.trailing,
    super.onTap,
    super.onLongPress,
    super.enabled,
    super.dense,
    super.isThreeLine,
    super.contentPadding,
    super.selected,
    super.selectedTileColor,
    super.tileColor,
    super.visualDensity,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      enabled: enabled && (onTap != null || trailing != null),
      child: ListTile(
        enabled: enabled,
        selected: selected,
        selectedTileColor: selectedTileColor,
        tileColor: tileColor,
        dense: dense,
        isThreeLine: isThreeLine,
        visualDensity: visualDensity,
        minTileHeight: dense == true ? null : AppDesign.rowHeight,
        minVerticalPadding: dense == true ? AppDesign.sm : AppDesign.md,
        horizontalTitleGap: AppDesign.md,
        contentPadding:
            contentPadding ??
            const EdgeInsets.symmetric(horizontal: AppDesign.lg),
        // A list entry (a memory, a search result) has no icon rather than
        // a placeholder one (audit, 2026-10-20).
        leading: leading == null
            ? null
            : Container(
                width: AppDesign.iconTile,
                height: AppDesign.iconTile,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent.fade(0.12),
                  borderRadius: AppDesign.radius(AppDesign.rMd),
                ),
                child: IconTheme(
                  data: IconThemeData(
                    size: AppDesign.iconSize,
                    color: c.accent,
                  ),
                  child: leading!,
                ),
              ),
        title: title,
        titleTextStyle: context.text.body,
        subtitle: subtitle,
        subtitleTextStyle: context.text.small.copyWith(color: c.textMuted),
        trailing:
            trailing ??
            (onTap == null ? null : const Icon(Icons.chevron_right)),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

/// The existing spring switch and haptics on a standard settings row.
class SettingsSwitchRow extends SpringSwitchTile {
  const SettingsSwitchRow({
    super.key,
    required super.value,
    required super.onChanged,
    super.title,
    super.subtitle,
    super.secondary,
    super.dense,
    super.contentPadding,
    super.isThreeLine,
  });

  @override
  Widget build(BuildContext context) => SettingsRow(
    leading: secondary,
    title: title,
    subtitle: subtitle,
    enabled: onChanged != null,
    dense: dense,
    isThreeLine: isThreeLine,
    contentPadding: contentPadding,
    trailing: SpringSwitch(value: value, onChanged: onChanged),
    onTap: onChanged == null
        ? null
        : () {
            AppHaptics.tick();
            onChanged!(!value);
          },
  );
}

/// One-line mono text used for compact value summaries in list rows; a
/// summary too long for the row slides so it can be read in full.
class MonoSummary extends StatelessWidget {
  final String text;
  final Color? color;
  const MonoSummary(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => MarqueeText(
    text,
    style: context.text.mono.copyWith(color: color ?? context.colors.textMuted),
  );
}

/// Slider row: label, live mono value, one-line explanation, then the track.
class SettingSlider extends StatelessWidget {
  final String label;
  final String hint;
  final double value, min, max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const SettingSlider({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.lg,
        AppDesign.md,
        AppDesign.lg,
        AppDesign.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.text.body)),
              RollingText(
                display,
                style: context.text.monoStrong.copyWith(color: c.accent),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(hint, style: context.text.small.copyWith(color: c.textFaint)),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              padding: const EdgeInsets.symmetric(vertical: AppDesign.sm),
            ),
            child: RubberBand(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: display,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Enum picker row with human-readable option names.
class SettingDropdown<T> extends StatelessWidget {
  final String label;
  final String hint;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  const SettingDropdown({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsRow(
      leading: icon == null ? null : Icon(icon),
      title: Text(label),
      subtitle: Text(hint),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.contains(value) ? value : items.first,
          dropdownColor: c.surfaceOverlay,
          borderRadius: AppDesign.radius(AppDesign.rMd),
          style: context.text.bodyMuted.copyWith(color: c.text),
          iconEnabledColor: c.textMuted,
          items: [
            for (final e in items)
              DropdownMenuItem(value: e, child: Text(labelOf(e))),
          ],
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

/// Muted or emphasised inline note; [tone] null means plain muted text.
class SettingsNote extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? tone;
  const SettingsNote(
    this.text, {
    super.key,
    this.icon = Icons.info_outline,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = tone ?? c.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.xs,
        AppDesign.md,
        AppDesign.xs,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppDesign.sm),
          Expanded(
            child: Text(text, style: context.text.small.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// "✓ Saved" in a settings page's app bar for a moment after each write:
/// settings apply and save as they change, which nothing used to show.
class SavedIndicator extends ConsumerStatefulWidget {
  const SavedIndicator({super.key});

  @override
  ConsumerState<SavedIndicator> createState() => _SavedIndicatorState();
}

class _SavedIndicatorState extends ConsumerState<SavedIndicator> {
  Timer? _hide;
  bool _shown = false;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsSavedAtProvider, (_, at) {
      if (at == null) return;
      setState(() => _shown = true);
      _hide?.cancel();
      _hide = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _shown = false);
      });
    });
    final c = context.colors;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: context.motion.fade(AppMotion.fadeIn),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDesign.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 16, color: c.success),
            const SizedBox(width: AppDesign.xs),
            Text(
              context.l10n.savedNotice,
              style: context.text.label.copyWith(color: c.success),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bar pinned under a page of typed fields while they differ from what
/// is stored: "Unsaved changes" and a Save button (report: request
/// limits typed on the remote connection page were lost because only the
/// keyboard's Done key saved them). Pages that use it also save when the
/// user leaves.
class UnsavedChangesBar extends StatelessWidget {
  final bool visible;
  final VoidCallback? onSave;
  const UnsavedChangesBar({
    super.key,
    required this.visible,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SpringSize(
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Material(
              color: c.surfaceRaised,
              child: SafeArea(
                top: false,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.hairline)),
                  ),
                  padding: const EdgeInsets.fromLTRB(
                    AppDesign.lg,
                    AppDesign.sm,
                    AppDesign.lg,
                    AppDesign.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note, size: 18, color: c.warning),
                      const SizedBox(width: AppDesign.sm),
                      Expanded(
                        child: Text(
                          context.l10n.unsavedChanges,
                          style: context.text.body,
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('unsaved-save'),
                        onPressed: onSave,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(context.l10n.commonSave),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Error surface for provider-level failures (e.g. settings could not be saved).
class DangerCard extends StatelessWidget {
  final String text;
  const DangerCard(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppDesign.radius(AppDesign.rLg),
        side: BorderSide(color: c.danger.fade(0.5)),
      ),
      color: c.danger.fade(0.08),
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: c.danger),
            const SizedBox(width: AppDesign.md),
            Expanded(
              child: Text(
                text,
                style: context.text.bodyMuted.copyWith(color: c.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stepped choice row for values that span orders of magnitude (context,
/// response length): preset chips plus an optional free-form entry, so a
/// slider does not have to squeeze 2k and 1M onto one track.
class SettingChoice<T> extends StatelessWidget {
  final String label;
  final String hint;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  /// When set, a trailing "Custom…" chip opens the caller's entry flow.
  final VoidCallback? onCustom;

  const SettingChoice({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final custom = !options.contains(value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.lg,
        AppDesign.md,
        AppDesign.lg,
        AppDesign.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.text.body)),
              Text(
                labelOf(value),
                style: context.text.monoStrong.copyWith(color: c.accent),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(hint, style: context.text.small.copyWith(color: c.textFaint)),
          const SizedBox(height: AppDesign.sm),
          Wrap(
            spacing: AppDesign.xs,
            runSpacing: AppDesign.xs,
            children: [
              for (final o in options)
                ChoiceChip(
                  key: Key('choice-$label-${labelOf(o)}'),
                  label: Text(labelOf(o)),
                  labelStyle: context.text.mono.copyWith(
                    color: o == value ? c.accent : c.textMuted,
                  ),
                  selected: o == value,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onChanged(o),
                ),
              if (onCustom != null)
                ChoiceChip(
                  key: Key('choice-$label-custom'),
                  label: Text(
                    custom ? 'Custom · ${labelOf(value)}' : 'Custom…',
                  ),
                  labelStyle: context.text.mono.copyWith(
                    color: custom ? c.accent : c.textMuted,
                  ),
                  selected: custom,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onCustom!(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for one integer within [min]..[max]; null when dismissed or invalid.
Future<int?> askInteger(
  BuildContext context, {
  required String title,
  required int current,
  required int min,
  required int max,
  String? hint,
}) async {
  final text = await promptText(
    context,
    title: title,
    initial: '$current',
    hint: hint ?? '$min – $max',
    helper: '$min – $max',
    confirmLabel: context.l10n.uiSettingsWidgetsApply,
    keyboardType: TextInputType.number,
  );
  final result = text == null ? null : int.tryParse(text);
  if (result == null) return null;
  return result.clamp(min, max);
}
