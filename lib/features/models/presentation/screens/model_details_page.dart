import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/platform/desktop_host.dart';
import '../../../../core/platform/form_factor.dart';
import '../../../../core/l10n/l10n.dart';
import '../../domain/entities/model_catalog.dart';
import '../../domain/entities/model_info.dart';
import '../../../settings/domain/setting_specs.dart';
import '../../../settings/presentation/setting_labels.dart';
import '../../../settings/presentation/providers/model_profiles_provider.dart';
import '../widgets/model_brand.dart';
import '../widgets/model_capabilities.dart';
import '../widgets/model_tags.dart';

void openModelDetails(BuildContext context, ModelInfo model) {
  if (DesktopHost.active) {
    showAppDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        key: const Key('desktop-model-details'),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.radius(AppDesign.rXl),
        ),
        child: SizedBox(
          width: 720,
          height: MediaQuery.sizeOf(dialog).height * 0.8,
          child: ModelDetailsPage(model: model, dialog: true),
        ),
      ),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ModelDetailsPage(model: model)),
  );
}

class ModelDetailsPage extends ConsumerWidget {
  final ModelInfo model;
  final bool dialog;
  const ModelDetailsPage({super.key, required this.model, this.dialog = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final path = model.localPath;
    final facts = path == null
        ? null
        : ref.watch(modelMetadataProvider(path)).asData?.value;
    final profile =
        ref.watch(modelProfilesProvider)[model.id] ?? const <String, dynamic>{};
    final uri = Uri.tryParse(model.downloadUrl ?? '');
    final source =
        uri?.host == 'huggingface.co' && uri!.pathSegments.length >= 2
        ? uri.pathSegments.take(2).join('/')
        : t.modelUnknown;
    final projector = model.projector ?? visionProjectors[model.id];
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.small),
          SelectableText(value, style: context.text.body),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !dialog,
        title: Text(t.modelDetails),
        actions: dialog
            ? [CloseButton(onPressed: () => Navigator.of(context).pop())]
            : null,
      ),
      body: ListView(
        padding: EdgeInsets.all(
          context.isDesktop ? AppSpace.desktopPage : AppSpace.phonePage,
        ),
        children: [
          Row(
            children: [
              ModelBrandIcon('$source ${model.displayName}'),
              const SizedBox(width: AppSpace.row),
              Expanded(
                child: Text(model.displayName, style: context.text.title),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.row),
          ModelCapabilityBadges(model: model),
          const SizedBox(height: AppSpace.row),
          fact(t.modelSize, model.sizeLabel),
          fact(t.modelQuantization, model.quantLabel),
          fact(t.modelArchitecture, facts?.architecture ?? model.family.name),
          fact(
            t.modelContextLength,
            facts?.contextLength?.toString() ?? t.modelUnknown,
          ),
          if (facts?.parameterCount case final count?)
            fact(t.modelParameters(''), '${(count / 1e9).toStringAsFixed(2)}B')
          else if (paramLabel(model).isNotEmpty)
            fact(t.modelParameters(''), paramLabel(model)),
          fact(t.licenseLabel(''), model.license),
          fact(t.modelSource, source),
          if (model.downloadedAt case final date?)
            fact(
              t.desktopHfDownloaded,
              MaterialLocalizations.of(
                context,
              ).formatMediumDate(date.toLocal()),
            ),
          const SizedBox(height: AppSpace.section),
          const Divider(),
          const SizedBox(height: AppSpace.row),
          Text(t.modelFiles, style: context.text.title),
          if (model.parts.isEmpty)
            fact(
              model.fileName,
              '${model.localPath ?? model.fileName} · ${model.sizeLabel}',
            )
          else
            for (final part in model.parts)
              fact(part.fileName, bytesLabel(part.sizeBytes)),
          if (projector != null)
            fact(
              t.hfVisionProjector,
              '${projector.fileName} · ${bytesLabel(projector.sizeBytes)}',
            ),
          if (projector != null)
            SwitchListTile(
              key: const Key('model-vision'),
              contentPadding: EdgeInsets.zero,
              title: Text(t.settingLabelVisionEnabled),
              subtitle: Text(t.settingVisionHint),
              value: profile['visionEnabled'] != false,
              onChanged: (on) =>
                  ref.read(modelProfilesProvider.notifier).set(model.id, {
                    for (final e in profile.entries)
                      if (e.key != 'visionEnabled') e.key: e.value,
                    if (!on) 'visionEnabled': false,
                  }),
            ),
          if (model.sha256 case final hash?) fact(t.verifyingSha, hash),
          const SizedBox(height: AppSpace.section),
          const Divider(),
          const SizedBox(height: AppSpace.row),
          Text(t.modelProfile, style: context.text.title),
          if (profile.isEmpty)
            Text(t.modelProfileDefaults, style: context.text.body)
          else
            for (final spec in SettingSpec.all.where(
              (s) => profile.containsKey(s.key),
            ))
              fact(spec.labelIn(t), '${profile[spec.key]}'),
        ],
      ),
    );
  }
}
