import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../settings/presentation/widgets/settings_widgets.dart';
import '../../core/design/app_sheet.dart';
import '../../core/l10n/l10n.dart';
import '../../core/motion/motion.dart';
import '../models/domain/entities/model_info.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../settings/presentation/providers/settings_provider.dart';

/// Which model Conversation answers with: the remote connection when one is
/// on (tester, 2026-10-18: a remote model is faster and smarter, and it
/// decides itself when to search), otherwise Qwen3.5 0.8B on the phone
/// (tester, 2026-10-09: spoken answers are short, and its speed is what
/// makes the voice work). Picking the 0.8B keeps Conversation on the phone
/// even with a remote connection. Another downloaded model answers only
/// when no 0.8B is on the phone, with a notice.
abstract final class ConversationModel {
  /// The everyday 0.8B (Q8_0), and an older 0.8B a phone may still hold.
  static const defaultId = 'qwen35-0.8b-q8_0';
  static const _fast = [defaultId, 'qwen35-0.8b-iq4nl'];

  /// The picker's remote choice (saved as the automatic choice, '').
  static const remoteId = 'remote';

  /// Conversation answers with the remote connection: one is on and the
  /// user did not pick a model on the phone for Conversation.
  static bool usesRemote(String chosenId, InferenceSettings settings) =>
      settings.usesRemote && !_fast.contains(chosenId);

  /// How the remote connection is named in the picker and the top bar.
  static String remoteName(InferenceSettings settings) {
    final profile = settings.activeRemoteProfile;
    final model = settings.remoteModel.trim();
    final name = profile?.name.trim() ?? '';
    if (name.isEmpty) return model;
    if (model.isEmpty || name.toLowerCase() == model.toLowerCase()) {
      return name;
    }
    return '$name · $model';
  }

  /// The 0.8B builds on the phone, the default first.
  static List<ModelInfo> choices(List<ModelInfo> catalog) => [
    for (final id in _fast)
      ...catalog.where((m) => m.id == id && m.isDownloaded),
  ];

  /// The model to load: the chosen 0.8B build, else the default one, else
  /// the model already loaded, else the smallest downloaded. Null: none
  /// downloaded. A choice saved before (Gemma 4) is ignored.
  static ModelInfo? pick(
    String chosenId,
    List<ModelInfo> catalog, {
    String? loadedId,
  }) {
    final have = catalog.where((m) => m.isDownloaded).toList()
      ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    ModelInfo? byId(String? id) => have.where((m) => m.id == id).firstOrNull;
    return (_fast.contains(chosenId) ? byId(chosenId) : null) ??
        _fast.map(byId).nonNulls.firstOrNull ??
        byId(loadedId) ??
        have.firstOrNull;
  }

  /// The 0.8B when it is not on the phone (for a notice), or null.
  static ModelInfo? missing(String chosenId, List<ModelInfo> catalog) {
    if (catalog.any((m) => m.isDownloaded && _fast.contains(m.id))) {
      return null;
    }
    return catalog.where((m) => m.id == defaultId).firstOrNull;
  }
}

/// Lists the downloaded models; picking one makes Conversation use it.
/// True when the choice changed.
Future<bool> showConversationModelPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final picked = await showMorphSheet<String>(
    context: context,
    builder: (context) => const _ModelSheet(),
  );
  if (picked == null) return false;
  final n = ref.read(settingsProvider.notifier);
  final s = ref.read(settingsProvider);
  // The 0.8B is saved by name when a remote connection would otherwise
  // answer; the remote (or, without one, the default 0.8B) is automatic.
  final id = picked == ConversationModel.remoteId
      ? ''
      : picked == ConversationModel.defaultId && !s.usesRemote
      ? ''
      : picked;
  if (id == s.conversationModelId) return false;
  await n.update(s.copyWith(conversationModelId: id));
  return true;
}

class _ModelSheet extends ConsumerWidget {
  const _ModelSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final c = context.colors;
    final catalog = ref.watch(modelManagerProvider.select((m) => m.catalog));
    final settings = ref.watch(settingsProvider);
    final remote = ConversationModel.usesRemote(
      settings.conversationModelId,
      settings,
    );
    final current = remote
        ? null
        : ConversationModel.pick(
            settings.conversationModelId,
            catalog,
            loadedId: ref.watch(
              modelManagerProvider.select((m) => m.loadedModelId),
            ),
          );
    final choices = ConversationModel.choices(catalog);
    Widget mark(bool on) => Icon(
      on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      color: on ? c.accent : c.textMuted,
    );
    return AppSheet(
      title: t.convModelTitle,
      meta: t.convModelHint,
      children: [
        if (settings.usesRemote)
          ListTile(
            key: const Key('conv-model-remote'),
            leading: mark(remote),
            title: Text(ConversationModel.remoteName(settings)),
            subtitle: Text(t.convModelRemote),
            onTap: () => Navigator.pop(context, ConversationModel.remoteId),
          ),
        if (choices.isEmpty && !settings.usesRemote)
          ListTile(title: Text(t.convNoModel))
        else
          for (final m in choices)
            ListTile(
              key: Key('conv-model-${m.id}'),
              leading: mark(m.id == current?.id),
              title: Text(m.displayName),
              subtitle: Text(
                m.id == ConversationModel.defaultId
                    ? '${m.sizeLabel} · ${t.convModelFastest}'
                    : m.sizeLabel,
              ),
              onTap: () => Navigator.pop(context, m.id),
            ),
      ],
    );
  }
}

/// Settings › Voice: the model Conversation answers with.
class ConversationModelTile extends ConsumerWidget {
  const ConversationModelTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final catalog = ref.watch(modelManagerProvider.select((m) => m.catalog));
    final settings = ref.watch(settingsProvider);
    final m = ConversationModel.pick(
      settings.conversationModelId,
      catalog,
      loadedId: ref.watch(modelManagerProvider.select((m) => m.loadedModelId)),
    );
    return SettingsRow(
      key: const Key('conversation-model'),
      leading: const Icon(Icons.forum_outlined),
      title: Text(t.convModelTitle),
      subtitle: Text(
        ConversationModel.usesRemote(settings.conversationModelId, settings)
            ? ConversationModel.remoteName(settings)
            : m?.displayName ?? t.convNoModel,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showConversationModelPicker(context, ref),
    );
  }
}
