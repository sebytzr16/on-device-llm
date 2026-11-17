import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/tips/tip_anchor.dart';
import '../core/tips/tips_store.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/optimize/optimized_models_provider.dart';
import 'load_settings_dialog.dart';

/// First-run guide step 4 (owner 2026-11-16): once a local model is loaded
/// and was never optimized, a bubble on the model chip offers "Optimize for
/// this device". Optimize opens the model's load settings and starts the
/// same measured run as its Optimize button (output check included).
class DesktopOptimizeOffer extends ConsumerWidget {
  const DesktopOptimizeOffer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(modelManagerProvider);
    final loaded = models.loadedModel;
    final optimized = ref.watch(optimizedModelsProvider).value;
    final generating = ref.watch(chatProvider.select((s) => s.isGenerating));
    final t = context.l10n;
    final active =
        loaded != null &&
        loaded.localPath != null &&
        optimized != null &&
        !optimized.contains(loaded.id) &&
        !models.isLoadingModel &&
        !generating;
    return TipAnchor(
      id: TipIds.optimizeOffer,
      title: t.optimizeOfferTitle,
      body: t.optimizeOfferBody,
      active: active,
      actionLabel: t.optimizeOfferAction,
      dismissLabel: t.optimizeOfferLater,
      // Opening the model menu is not an answer to the offer.
      dismissOnTargetTap: false,
      onAction: () {
        if (loaded == null) return;
        showDesktopLoadSettings(context, loaded, autoOptimize: true);
      },
      child: child,
    );
  }
}
