part of 'chat_provider.dart';

void _primeThinking(
  StringBuffer system,
  InferenceSettings settings,
  TextEngine engine,
) {
  if (settings.thinkingModeEnabled &&
      engine.metrics['supportsThinking'] != true) {
    system.write(
      '\nIf your model supports reasoning, put your explanation in <think> and </think> before your final answer.',
    );
  }
}

extension _ChatPrime on ChatNotifier {
  /// Called only for completed loads on the chat's local engine.
  Future<void> _primeLoadedModel(ModelInfo model) async {
    if (model.id == diffusionGemmaModelId) return;
    if (!DesktopHost.active || !_alive) return;
    final engine = _chatRef.read(llamaEngineProvider);
    if (!engine.isLoaded || engine.isBusy || _primedLoad == engine.loadCount) {
      return;
    }
    final epoch = _primeEpoch;
    final navigation = _navigation;
    final load = engine.loadCount;
    bool eligible() =>
        _alive &&
        DesktopHost.active &&
        epoch == _primeEpoch &&
        navigation == _navigation &&
        load == engine.loadCount &&
        engine.isLoaded &&
        !engine.isBusy &&
        !_chatState.isGenerating &&
        !_chatRef.read(sessionBusyProvider) &&
        _chatRef.read(modelManagerProvider).loadedModelId == model.id;
    if (!eligible()) return;
    try {
      final project = _chatRef
          .read(conversationWorkspaceProvider)
          .projects
          .where((p) => p.id == _projectId)
          .firstOrNull;
      var settings = resolveSettings(
        global: _chatRef.read(settingsProvider),
        defaults: _chatRef.read(settingsProvider.notifier).defaults,
        profiles: _chatRef.read(modelProfilesProvider),
        preset: _chatRef.read(presetsProvider).active,
        chat: _chatRef.read(chatOverridesProvider),
        recommendations: _chatRef.read(modelRecommendationsProvider),
        model: model,
        project: project == null || project.collection.isEmpty
            ? const {}
            : {'knowledgeCollection': project.collection},
        projectLabel: project?.name ?? 'Project',
      ).effective;
      if (_chatState.temporary)
        settings = settings.copyWith(memoryEnabled: false);
      if (settings.usesRemote || !settings.promptCache) return;
      _primedLoad = load;
      // No question-specific instructions, history or tool registrations.
      const neutral = 'Explain how a rainbow forms.';
      final shared = await _baseSystem(
        neutral,
        settings: settings,
        preset: _chatRef.read(presetsProvider).active,
        spoken: false,
      );
      if (!eligible()) return;
      final system = StringBuffer('${shared.system}${shared.notes}');
      _primeThinking(system, settings, engine);
      final offered = _offerTools(
        neutral,
        settings: settings,
        engine: engine,
        system: system,
        turnNotes: StringBuffer(),
        sources: const [],
        researchTurn: false,
        continuing: false,
        register: false,
        primeOnly: true,
      );
      await engine.primePrompt(
        system: system.toString(),
        fallbackTemplate: model.family.fallbackTemplate,
        settings: settings,
        tools: offered.native ? offered.tools : const [],
        toolChoice: offered.native && settings.toolChoice == ToolChoice.required
            ? 'required'
            : 'auto',
      );
    } catch (error, stack) {
      Logger('chat.prime').fine('Chat prompt priming skipped', error, stack);
    }
  }
}
