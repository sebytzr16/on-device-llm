import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../models/domain/entities/model_info.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../../models/presentation/providers/model_recommendations_provider.dart';
import '../../../models/domain/model_recommendations.dart';
import '../../../presets/domain/preset.dart';
import '../../../presets/presentation/providers/presets_provider.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../chat/presentation/providers/chat_model_pins.dart';
import '../../../chat/domain/conversation_workspace.dart';
import '../../domain/entities/inference_settings.dart';
import '../../domain/settings_scope.dart';
import 'model_profiles_provider.dart';
import 'settings_provider.dart';

/// The cascade for one model. Shared by the provider below (watching) and
/// by callers that must not depend on the provider, such as the model
/// manager (which the provider itself watches).
ResolvedSettings resolveSettings({
  required InferenceSettings global,
  required InferenceSettings defaults,
  required Map<String, Map<String, dynamic>> profiles,
  required Preset preset,
  required Map<String, dynamic> chat,
  required Map<String, ModelRecommendation> recommendations,
  ModelInfo? model,
  Map<String, dynamic> turn = const {},
  Map<String, dynamic> project = const {},
  String projectLabel = 'Project',
}) {
  final rec = model == null
      ? const ModelRecommendation()
      : recommendationFor(model, recommendations);
  return SettingsResolver.resolve(
    global: global,
    deviceDefaults: defaults,
    recommended: rec.values,
    recommendedThinking: rec.thinking,
    recommendedLabel: rec.sources.isEmpty
        ? "Model's recommended"
        : "Model's recommended · ${rec.sources.join(', ')}",
    model: model == null ? const {} : profiles[model.id] ?? const {},
    modelLabel: model == null
        ? 'Model profile'
        : '${model.displayName} profile',
    preset: preset.toOverrides(),
    presetLabel: 'Preset · ${preset.name}',
    chat: chat,
    project: project,
    projectLabel: projectLabel,
    turn: turn,
  );
}

/// Overrides of the chat that is open right now (chats.overrides_json).
/// The chat notifier sets it when a chat opens; the chat settings sheet
/// edits it and persists through the notifier.
final chatOverridesProvider = StateProvider<Map<String, dynamic>>(
  (ref) => const {},
);

/// The selected project before the first question creates a conversation row.
final newChatProjectProvider = StateProvider<String?>((ref) => null);
final currentProjectProvider = Provider<ChatProject?>((ref) {
  final workspace = ref.watch(conversationWorkspaceProvider);
  final chatId = ref.watch(chatProvider.select((s) => s.chatId));
  final id = chatId == null
      ? ref.watch(newChatProjectProvider)
      : workspace.memberships[chatId];
  return workspace.projects.where((p) => p.id == id).firstOrNull;
});

/// The model a new message would use: the loaded one, else the first
/// downloaded catalog entry (same rule as the chat's send path).
final activeModelIdProvider = Provider<String?>((ref) {
  final m = ref.watch(modelManagerProvider);
  final chatId = ref.watch(chatProvider.select((s) => s.chatId));
  final pinned = ref.watch(chatModelPinsProvider)[chatId];
  return (m.catalog.any((x) => x.id == pinned && x.isDownloaded)
          ? pinned
          : null) ??
      m.loadedModelId ??
      m.catalog.where((x) => x.isDownloaded).firstOrNull?.id;
});

/// The settings cascade resolved for the current model, preset and chat.
/// Screens read [ResolvedSettings.effective]; the inspector shows origins.
final effectiveSettingsProvider = Provider<ResolvedSettings>((ref) {
  final global = ref.watch(settingsProvider);
  final defaults = ref.watch(settingsProvider.notifier).defaults;
  final modelId = ref.watch(activeModelIdProvider);
  final profiles = ref.watch(modelProfilesProvider);
  final presets = ref.watch(presetsProvider);
  final chat = ref.watch(chatOverridesProvider);
  final project = ref.watch(currentProjectProvider);
  final model = modelId == null
      ? null
      : ref
            .watch(modelManagerProvider)
            .catalog
            .where((m) => m.id == modelId)
            .firstOrNull;
  return resolveSettings(
    global: global,
    defaults: defaults,
    profiles: profiles,
    preset: presets.active,
    chat: chat,
    recommendations: ref.watch(modelRecommendationsProvider),
    model: model,
    project: project == null || project.collection.isEmpty
        ? const {}
        : {'knowledgeCollection': project.collection},
    projectLabel: project?.name ?? 'Project',
  );
});
