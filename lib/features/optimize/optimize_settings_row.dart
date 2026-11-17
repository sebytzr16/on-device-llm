import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';
import '../../desktop/load_settings_dialog.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../settings/presentation/widgets/settings_widgets.dart';
import 'optimize_controller.dart';
import 'optimize_page.dart';
import 'optimized_models_provider.dart';

/// Settings entry for "Optimize for this device" (owner 2026-11-16): runs
/// Optimize for the loaded model; with none loaded it says to load one.
class OptimizeSettingsRow extends ConsumerWidget {
  const OptimizeSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final c = context.colors;
    final loaded = ref.watch(modelManagerProvider.select((m) => m.loadedModel));
    final model = loaded?.localPath == null ? null : loaded;
    final done =
        model != null &&
        (ref.watch(optimizedModelsProvider).value?.contains(model.id) ?? false);
    final mobile = ref.watch(optimizeMobileProvider);
    return SettingsRow(
      key: const Key('optimize-settings-row'),
      leading: Icon(Icons.auto_fix_high_rounded, color: c.accent),
      title: Text(t.optimizeSettingsTitle),
      subtitle: Text(
        model == null
            ? t.optimizeSettingsNoModel
            : t.optimizeSettingsHint(model.displayName),
      ),
      trailing: done
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_rounded, size: 16, color: c.accent),
                const SizedBox(width: 4),
                Text(
                  t.optimizeSettingsDone,
                  style: context.text.caption.copyWith(color: c.accent),
                ),
              ],
            )
          : const Icon(Icons.chevron_right, size: 20),
      enabled: model != null,
      onTap: model == null
          ? null
          : () => mobile
                ? OptimizePage.open(context, model, autoStart: !done)
                : showDesktopLoadSettings(context, model, autoOptimize: !done),
    );
  }
}
