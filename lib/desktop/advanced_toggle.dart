import '../core/motion/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/platform/desktop_preferences.dart';

class DesktopAdvancedToggle extends ConsumerWidget {
  const DesktopAdvancedToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SegmentedButton<bool>(
    key: const Key('desktop-advanced-toggle'),
    showSelectedIcon: false,
    segments: [
      ButtonSegment(value: false, label: Text(context.l10n.desktopBasic)),
      ButtonSegment(value: true, label: Text(context.l10n.desktopAdvanced)),
    ],
    selected: {ref.watch(desktopPreferencesProvider).advanced},
    onSelectionChanged: (value) => ref
        .read(desktopPreferencesProvider.notifier)
        .set(advanced: value.single),
  );
}

class DesktopSidebarSection extends ConsumerWidget {
  final Widget child;
  const DesktopSidebarSection({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(desktopPreferencesProvider).sidebarCollapsed;
    final duration = context.motion.fade(AppMotion.glide);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: DesktopAdvancedToggle()),
            IconButton(
              key: const Key('sidebar-collapse'),
              tooltip: collapsed
                  ? context.l10n.sidebarExpand
                  : context.l10n.sidebarCollapse,
              onPressed: () => ref
                  .read(desktopPreferencesProvider.notifier)
                  .set(sidebarCollapsed: !collapsed),
              icon: AnimatedRotation(
                turns: collapsed ? 0.5 : 0,
                duration: duration,
                curve: AppMotion.ease,
                child: const Icon(Icons.expand_less),
              ),
            ),
          ],
        ),
        ClipRect(
          child: AnimatedSize(
            duration: duration,
            curve: AppMotion.ease,
            alignment: Alignment.topCenter,
            child: collapsed ? const SizedBox(width: double.infinity) : child,
          ),
        ),
      ],
    );
  }
}
