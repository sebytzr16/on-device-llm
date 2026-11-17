import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/widgets/settings_widgets.dart';
import '../island/status_island.dart';
import '../l10n/l10n.dart';
import 'tips_store.dart';

/// Settings row that brings every first-run tip back (owner 2026-11-16).
class ShowTipsAgainRow extends ConsumerWidget {
  const ShowTipsAgainRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    return SettingsRow(
      key: const Key('show-tips-again'),
      leading: const Icon(Icons.auto_awesome_outlined),
      title: Text(t.tipsShowAgain),
      subtitle: Text(t.tipsShowAgainHint),
      onTap: () async {
        await ref.read(tipsProvider.notifier).resetAll();
        if (context.mounted) {
          showIslandToast(
            context,
            t.tipsShowAgainDone,
            icon: Icons.auto_awesome_outlined,
          );
        }
      },
    );
  }
}
