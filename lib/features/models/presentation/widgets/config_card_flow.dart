import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../settings/presentation/providers/model_profiles_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/setting_labels.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/model_config_card.dart';
import '../providers/model_manager_provider.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

/// The card for [model] as this phone runs it.
ModelConfigCard configCardFor(WidgetRef ref, ModelInfo model) =>
    ModelConfigCard.from(
      model: model,
      global: ref.read(settingsProvider),
      profile: ref.read(modelProfilesProvider)[model.id] ?? const {},
    );

/// Shares [model]'s configuration as a small `.odllm.json` file through the
/// system share sheet (messages, mail, Drive, Nearby Share…).
Future<void> shareConfigCard(
  BuildContext context,
  WidgetRef ref,
  ModelInfo model,
) async {
  final card = configCardFor(ref, model);
  final slug = model.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, '$slug${ModelConfigCard.fileExtension}'));
  await file.writeAsString(card.encode(), flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: card.name,
      text:
          '${card.name} — open it with OnDevice LLM (Share to OnDevice LLM, or Models > Import configuration).',
    ),
  );
}

/// Copies the card as text, for pasting into any message.
Future<void> copyConfigCard(
  BuildContext context,
  WidgetRef ref,
  ModelInfo model,
) async {
  await Clipboard.setData(
    ClipboardData(text: configCardFor(ref, model).encode()),
  );
  if (context.mounted) {
    showIslandToast(context, context.l10n.configCopied, tone: IslandTone.done);
  }
}

/// Reads a card from the clipboard or a picked file and offers to apply
/// it. [into] forces the target model (the profile page it was opened
/// from); otherwise the card's own model is looked up on this phone.
Future<void> importConfigCard(
  BuildContext context,
  WidgetRef ref, {
  required bool fromFile,
  ModelInfo? into,
}) async {
  String? text;
  if (fromFile) {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    if ((await files.first.length() ?? 0) > 256 * 1024) {
      if (context.mounted) {
        _say(context, context.l10n.configTooLarge);
      }
      return;
    }
    text = utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
  } else {
    text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }
  final card = text == null ? null : ModelConfigCard.decode(text);
  if (!context.mounted) return;
  if (card == null) {
    _say(
      context,
      fromFile
          ? context.l10n.configNotAFile
          : context.l10n.configNotInClipboard,
    );
    return;
  }
  await showConfigCardPreview(context, ref, card, into: into);
}

void _say(BuildContext context, String text) => showIslandToast(context, text);

/// What the card sets and on which model, then Apply. Returns whether it
/// was applied.
Future<bool> showConfigCardPreview(
  BuildContext context,
  WidgetRef ref,
  ModelConfigCard card, {
  ModelInfo? into,
}) async {
  final models = ref.read(modelManagerProvider).catalog;
  final downloaded = models.where((m) => m.isDownloaded).toList();
  final match = card.model.matchIn(downloaded);
  var target = into ?? match;
  final applied = await showAppDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.colors;
        return AlertDialog(
          title: Text(card.name),
          content: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  context.l10n.configMadeFor(
                    '${card.model.displayName}'
                    '${card.model.quantization.isEmpty ? '' : ' (${card.model.quantization})'}',
                  ),
                  style: context.text.bodyMuted,
                ),
                const SizedBox(height: AppDesign.sm),
                if (match == null && into == null)
                  Text(
                    card.model.downloadUrl != null &&
                            models.any((m) => m.id == card.model.id)
                        ? context.l10n.configNotDownloaded
                        : context.l10n.configNotOnPhone,
                    style: context.text.bodyMuted.copyWith(color: c.warning),
                  ),
                if (downloaded.isNotEmpty)
                  DropdownButton<ModelInfo>(
                    key: const Key('config-target'),
                    isExpanded: true,
                    value: target,
                    hint: Text(context.l10n.chooseModel),
                    items: [
                      for (final m in downloaded)
                        DropdownMenuItem(
                          value: m,
                          child: Text(
                            m == match
                                ? context.l10n.configSameModel(m.displayName)
                                : m.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (m) => setState(() => target = m),
                  ),
                const SizedBox(height: AppDesign.sm),
                if (card.settings.isEmpty)
                  Text(context.l10n.configEmpty, style: context.text.bodyMuted),
                for (final (label, value) in card.describe(
                  (s) => s.labelIn(context.l10n),
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(label, style: context.text.body)),
                        const SizedBox(width: AppDesign.sm),
                        Flexible(
                          child: Text(
                            value,
                            style: context.text.mono,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (card.dropped.isNotEmpty) ...[
                  const SizedBox(height: AppDesign.sm),
                  Text(
                    context.l10n.configLeftOut(card.dropped.join(', ')),
                    style: context.text.label.copyWith(color: c.textFaint),
                  ),
                ],
                const SizedBox(height: AppDesign.sm),
                Text(
                  context.l10n.configApplyNote,
                  style: context.text.label.copyWith(color: c.textFaint),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.commonCancel),
            ),
            FilledButton(
              key: const Key('config-apply'),
              onPressed: target == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(context.l10n.configApply),
            ),
          ],
        );
      },
    ),
  );
  if (applied != true || target == null) return false;
  await ref.read(modelProfilesProvider.notifier).set(target!.id, card.settings);
  if (context.mounted) {
    _say(context, context.l10n.configApplied(target!.displayName));
  }
  return true;
}
