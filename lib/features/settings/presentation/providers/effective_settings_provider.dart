import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../inference/engine/engine_registry_provider.dart';
import '../../../../inference/engine/engine_descriptor.dart';
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
  return _downloadedModel(m, pinned)?.id ?? _unpinnedModelId(m);
});

final activeModelEngineProvider = Provider<EngineDescriptor?>((ref) {
  final id = ref.watch(activeModelIdProvider);
  final model = ref.watch(
    modelManagerProvider.select(
      (s) => s.catalog.where((m) => m.id == id).firstOrNull,
    ),
  );
  return model == null
      ? null
      : ref.watch(engineRegistryProvider).descriptorFor(model);
});

ModelInfo? _downloadedModel(ModelManagerState models, String? id) =>
    models.catalog.where((m) => m.id == id && m.isDownloaded).firstOrNull;

String? _unpinnedModelId(ModelManagerState models) =>
    models.loadedModelId ??
    models.catalog.where((m) => m.isDownloaded).firstOrNull?.id;

/// The settings cascade resolved for the current model, preset and chat.
/// Screens read [ResolvedSettings.effective]; the inspector shows origins.
final effectiveSettingsProvider = Provider<ResolvedSettings>(
  (ref) => _cascade(ref, preset: ref.watch(presetsProvider).active),
);

/// What a chat override inherits: the cascade for the chat's real model with
/// this chat's own overrides left out (audit 2026-11-20 P1-4).
final chatInheritedSettingsProvider = Provider<InferenceSettings>(
  (ref) => _cascade(
    ref,
    preset: ref.watch(presetsProvider).active,
    chat: const {},
  ).effective,
);

/// One layer of the cascade as it would be after a change: [global] replaces
/// the user's settings, [profile] the profile of [profileModelId], [preset]
/// the active preset, [chat] this chat's overrides. Previewing it keeps the
/// web research confirmation honest about the chat's real model, whatever
/// path asked (audit 2026-11-20 P1-4).
class SettingsChange {
  final InferenceSettings? global;
  final String? profileModelId;
  final Map<String, dynamic>? profile;
  final Preset? preset;
  final bool editingPreset;
  final Map<String, dynamic>? chat;
  final ModelInfo? loadedModel;
  final bool changingPin;
  final String? pin;
  final bool newChat;
  final String? projectId;
  const SettingsChange({
    this.global,
    this.profileModelId,
    this.profile,
    this.preset,
    this.editingPreset = false,
    this.chat,
    this.loadedModel,
    this.changingPin = false,
    this.pin,
    this.newChat = false,
    this.projectId,
  });
}

/// The cascade [change] would leave for the model the next message uses.
/// Auto-disposed: it only previews an edit.
final settingsPreviewProvider = Provider.autoDispose
    .family<ResolvedSettings, SettingsChange>((ref, change) {
      final presets = ref.watch(presetsProvider);
      return _cascade(
        ref,
        preset: change.editingPreset && change.preset?.id != presets.activeId
            ? presets.active
            : change.preset ?? presets.active,
        global: change.global,
        profiles: change.profileModelId == null
            ? null
            : {
                ...ref.watch(modelProfilesProvider),
                change.profileModelId!: change.profile ?? const {},
              },
        chat: change.chat,
        destination: change,
      );
    });

/// Whether the next turn can start making network lookups.
bool webTurnsOn(ResolvedSettings now, ResolvedSettings next) =>
    !_allowsWebLookups(now.effective) && _allowsWebLookups(next.effective);

bool _allowsWebLookups(InferenceSettings settings) =>
    settings.webMode != WebMode.off &&
    (!settings.usesRemote || settings.remoteWebResearch);

/// The keys a model profile can set that decide whether a turn looks things
/// up. A change that leaves all of them alone cannot turn lookups on, so it
/// never needs the question (and the settings cascade it is asked from).
const webLookupKeys = {'webMode'};

/// The app supplies the same confirmation dialog used by settings screens.
final webResearchConfirmationProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () async => false,
);

/// A pending decision for a transition that enables lookups.
/// The cascade reads the notifiers whose actions call this, so take a
/// snapshot from the container without making it a notifier dependency.
Future<bool>? requestWebModeChange(
  ProviderContainer container,
  SettingsChange change,
) =>
    webTurnsOn(
      container.read(effectiveSettingsProvider),
      container.read(settingsPreviewProvider(change)),
    )
    ? container.read(webResearchConfirmationProvider)()
    : null;

ResolvedSettings _cascade(
  Ref ref, {
  required Preset preset,
  InferenceSettings? global,
  Map<String, Map<String, dynamic>>? profiles,
  Map<String, dynamic>? chat,
  SettingsChange? destination,
}) {
  final InferenceSettings settings = global ?? ref.watch(settingsProvider);
  final defaults = ref.watch(settingsProvider.notifier).defaults;
  final models = ref.watch(modelManagerProvider);
  final newChat = destination?.newChat ?? false;
  final changingPin = destination?.changingPin ?? false;
  final loaded = destination?.loadedModel;
  final String? modelId;
  if (newChat) {
    modelId = _unpinnedModelId(models);
  } else if (changingPin) {
    modelId =
        _downloadedModel(models, destination?.pin)?.id ??
        _unpinnedModelId(models);
  } else if (loaded != null) {
    final chatId = ref.watch(chatProvider.select((s) => s.chatId));
    final pin = ref.watch(chatModelPinsProvider)[chatId];
    modelId = _downloadedModel(models, pin)?.id ?? loaded.id;
  } else {
    modelId = ref.watch(activeModelIdProvider);
  }
  final model = loaded?.id == modelId
      ? loaded
      : models.catalog.where((m) => m.id == modelId).firstOrNull;
  final project = newChat
      ? ref
            .watch(conversationWorkspaceProvider)
            .projects
            .where((p) => p.id == destination?.projectId)
            .firstOrNull
      : ref.watch(currentProjectProvider);
  return resolveSettings(
    global: settings,
    defaults: defaults,
    profiles: profiles ?? ref.watch(modelProfilesProvider),
    preset: preset,
    chat: chat ?? (newChat ? const {} : ref.watch(chatOverridesProvider)),
    recommendations: ref.watch(modelRecommendationsProvider),
    model: model,
    project: project == null || project.collection.isEmpty
        ? const {}
        : {'knowledgeCollection': project.collection},
    projectLabel: project?.name ?? 'Project',
  );
}
