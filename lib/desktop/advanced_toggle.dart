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
