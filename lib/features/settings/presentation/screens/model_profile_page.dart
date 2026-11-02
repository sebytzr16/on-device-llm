import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../models/domain/entities/model_info.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../../models/presentation/providers/model_recommendations_provider.dart';
import '../../../models/presentation/widgets/config_card_flow.dart';
import '../../../presets/domain/preset.dart';
import '../providers/effective_settings_provider.dart';
import '../providers/model_profiles_provider.dart';
import '../providers/settings_provider.dart';
import 'overrides_page.dart';

/// The override editor for one model. What it inherits is what the model
/// gets without a profile: the app's settings and, for sampling, the
/// model's own recommended values (sampling is per model since 2026-11-01).
class ModelProfilePage extends ConsumerWidget {
  final ModelInfo model;
  const ModelProfilePage({super.key, required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(modelProfilesProvider);
    final inherited = resolveSettings(
      global: ref.watch(settingsProvider),
      defaults: ref.watch(settingsProvider.notifier).defaults,
      profiles: const {},
      preset: Preset.general,
      chat: const {},
      recommendations: ref.watch(modelRecommendationsProvider),
      model: model,
    ).effective;
    return OverridesPage(
      title: context.l10n.modelProfileTitle(model.displayName),
      scopeLabel: context.l10n.modelProfileScope,
      overrides: profiles[model.id] ?? const {},
      inherited: inherited,
      onChanged: (o) =>
          ref.read(modelProfilesProvider.notifier).set(model.id, o),
      actions: [
        PopupMenuButton<String>(
          key: const Key('config-menu'),
          tooltip: context.l10n.uiModelsScreenShareOrImportAConfiguration,
          icon: const Icon(Icons.ios_share),
          onSelected: (v) => switch (v) {
            'share' => shareConfigCard(context, ref, model),
            'copy' => copyConfigCard(context, ref, model),
            'paste' => importConfigCard(
              context,
              ref,
              fromFile: false,
              into: model,
            ),
            _ => importConfigCard(context, ref, fromFile: true, into: model),
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'share',
              child: Text(context.l10n.uiModelsScreenShareConfiguration),
            ),
            PopupMenuItem(
              value: 'copy',
              child: Text(context.l10n.uiModelsScreenCopyAsText),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'paste',
              child: Text(context.l10n.uiModelsScreenImportFromClipboard),
            ),
            PopupMenuItem(
              value: 'file',
              child: Text(context.l10n.uiModelsScreenImportFromAFile),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens the profile of the model a new message would use; sampling is set
/// there. Without a downloaded model there is nothing to set yet.
void openActiveModelProfile(BuildContext context, WidgetRef ref) {
  final id = ref.read(activeModelIdProvider);
  final model = ref
      .read(modelManagerProvider)
      .catalog
      .where((m) => m.id == id)
      .firstOrNull;
  if (model == null) {
    showIslandToast(context, context.l10n.convNoModel);
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => ModelProfilePage(model: model)),
  );
}
