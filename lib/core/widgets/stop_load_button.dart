import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/models/presentation/providers/model_manager_provider.dart';
import '../l10n/l10n.dart';

/// Stops the model load in flight, wherever the load is shown. The same
/// compact control as the desktop load pill: a phone had no way to stop a
/// load at all (audit P1-19, owner request OR-02).
class StopLoadButton extends ConsumerWidget {
  const StopLoadButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: context.l10n.stopLoading,
    visualDensity: VisualDensity.compact,
    iconSize: 16,
    icon: const Icon(Icons.stop_circle_outlined),
    onPressed: () => ref.read(modelManagerProvider.notifier).stopLoad(),
  );
}
