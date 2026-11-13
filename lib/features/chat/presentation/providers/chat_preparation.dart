part of 'chat_provider.dart';

extension _ChatPreparation on ChatNotifier {
  /// The turn's settings and model, then the saved question. Null when the
  /// turn stops first: stopped, or the phone's model busy serving another
  /// device.
  Future<_Asked?> _prepareTurn(_Turn t) async {
    final input = t.input;
    final manager = _chatRef.read(modelManagerProvider.notifier);
    await _temporaryReady;
    await _chatRef.read(conversationWorkspaceProvider.notifier).ready;
    if (_chatState.chatId != null && !_chatState.temporary) {
      _projectId = _chatRef
          .read(conversationWorkspaceProvider)
          .memberships[_chatState.chatId];
    }
    await _chatRef.read(settingsProvider.notifier).ready;
    t.budget?.check();
    await manager.ready;
    await _chatRef.read(presetsProvider.notifier).ready;
    await _chatRef.read(modelProfilesProvider.notifier).ready;
    await _chatRef.read(adaptersProvider.notifier).ready;
    await _chatRef.read(chatModelPinsProvider.notifier).ready;
    // The settings cascade for this turn (roadmap P1.4): your settings →
    // the model's profile → the active preset (FX-03) → this chat → this
    // turn. The preset's instructions join the system prompt later.
    final preset = _chatRef.read(presetsProvider).active;
    final library = _chatRef.read(modelManagerProvider);
    // A model pinned to this chat wins over the picker (when it is still
    // downloaded).
    final candidate =
        t.compareWith ??
        pinnedModel(_chatState.chatId) ??
        library.loadedModel ??
        library.catalog.where((m) => m.isDownloaded).firstOrNull;
    final project = _chatRef
        .read(conversationWorkspaceProvider)
        .projects
        .where((p) => p.id == _projectId)
        .firstOrNull;
    final resolved = t.resolved = resolveSettings(
      global: _chatRef.read(settingsProvider),
      defaults: _chatRef.read(settingsProvider.notifier).defaults,
      profiles: _chatRef.read(modelProfilesProvider),
      preset: preset,
      chat: _chatRef.read(chatOverridesProvider),
      recommendations: _chatRef.read(modelRecommendationsProvider),
      project: project == null || project.collection.isEmpty
          ? const {}
          : {'knowledgeCollection': project.collection},
      projectLabel: project?.name ?? 'Project',
      model: candidate,
      turn: t.turnOverrides,
    );
    // Battery saver: a lighter local turn when the battery is low or the
    // phone is hot (nothing that would reload the model changes).
    final base = resolved.effective;
    final saverReason = t.saverReason = BatterySaver.reason(
      base,
      base.batterySaver && !base.usesRemote ? await DevicePower.read() : null,
    );
    var settings = saverReason == null ? base : BatterySaver.apply(base);
    final diffusion =
        DesktopHost.active &&
        (!settings.usesRemote || t.localOnly) &&
        candidate?.id == diffusionGemmaModelId;
    if (diffusion) {
      settings = settings.copyWith(
        remoteEnabled: false,
        webMode: WebMode.off,
        toolsEnabled: false,
        thinkingModeEnabled: false,
        memoryEnabled: false,
      );
      t.engine = _chatRef.read(diffusionGemmaEngineProvider);
    }
    if (_chatState.temporary) {
      settings = settings.copyWith(memoryEnabled: false);
    }
    if (t.localOnly && settings.usesRemote) {
      settings = settings.copyWith(remoteEnabled: false);
    }
    if (saverReason != null) {
      _chatState = _chatState.copyWith(
        notice: BatterySaver.notice(saverReason, _t),
      );
    }
    // Remote brain (decision 2026-10-18): a remote model is bigger
    // than the phone's rules and judge, so it decides itself whether to
    // search, what to search for and which pages to read, through the web
    // tools. Gemma on the Gemini API, a model that refused tools and Goal
    // steps keep the app's planning.
    final remoteBrain = t.remoteBrain =
        settings.usesRemote &&
        settings.webSearchEnabled &&
        settings.remoteWebResearch &&
        RemoteEngine.acceptsTools(settings) &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        t.answerSources == null &&
        t.compareWith == null &&
        // Goal steps keep their own guarded research (subject lock, read
        // budgets, checks).
        !t.forceResearch &&
        !t.localOnly &&
        !settings.structuredOutput;
    // Research turns on the web tools only: the user's Tools switch still
    // decides MCP, recall and document tools (audit P1-04).
    t.userTools = settings.toolsEnabled;
    if (remoteBrain) {
      settings = settings.copyWith(
        toolsEnabled: true,
        toolWeb: true,
        toolMaxRounds: max(
          settings.toolMaxRounds,
          TurnPrompts.remoteBrainRounds,
        ),
      );
    }
    // The connection's own sampling, length and context (decision
    // 2026-10-18), unless its profile turned that off.
    if (settings.usesRemote &&
        (settings.activeRemoteProfile?.serverSettings ?? false)) {
      settings = settings.copyWith(serverSampling: true);
    }
    t.settings = settings;
    if (settings.usesRemote) {
      // The user's own server does the inference; no local model needed.
      t.engine = _chatRef.read(remoteEngineProvider);
      final model = ModelInfo(
        id: 'remote:${settings.remoteModel.trim()}',
        displayName: settings.remoteModel.trim().isEmpty
            ? 'server default'
            : settings.remoteModel.trim(),
        fileName: '',
        sizeBytes: 0,
        family: ModelFamily.other,
        quantization: ModelQuantization.fp16,
      );
      t.model = model;
      t.modelId = model.id;
      t.stage('loadMs');
      _chatState = _chatState.copyWith(metrics: t.engine.metrics);
    } else {
      final model = candidate;
      if (model == null) throw StateError(_t.chatErrorNoModel);
      t.model = model;
      t.modelId = model.id;
      // This phone may be serving its model to another device: the chat
      // shares that model and waits for a request in progress.
      if (!await _shareWithHosting(model)) return null;
      // "Loading" shows only when a load starts: an unchanged model is
      // used as it is (audit P1-18).
      await manager.loadModel(
        model,
        forChat: true,
        settings: settings,
        onLoadStart: () =>
            _chatState = _chatState.copyWith(isLoadingModel: true),
        // The projector loads only for a chat with a photo in it.
        vision:
            t.attachments.any((a) => a.isImage) ||
            _chatState.messages.any(
              (m) =>
                  ChatNotifier.isLive(m) &&
                  m.role == ChatRole.user &&
                  m.attachments.any((a) => a.isImage),
            ),
      );
      t.stage('loadMs');
      _chatState = _chatState.copyWith(
        isLoadingModel: false,
        metrics: t.engine.metrics,
      );
    }
    if (_cancelled) return null;
    final saved = await _saveQuestion(
      input,
      attachments: t.attachments,
      insertUser: t.insertUser,
      parentId: t.parentId,
      resume: t.resume,
      modelId: t.modelId,
    );
    if (_chatState.temporary) {
      await TemporaryFiles.remember(t.attachments.map((a) => a.path));
    }
    final user = saved.user;
    t.chatId = saved.chatId;
    t.sourceMessageId = user.id;
    t.sequence = saved.sequence;
    t.accepted = true;
    // Scan each saved user message even if generation later stops or fails.
    if (t.insertUser &&
        t.resume == null &&
        t.learn &&
        !_chatState.temporary &&
        _chatRef.read(settingsProvider).memoryEnabled) {
      final captured = await _learnExplicit(
        input,
        chatId: saved.chatId,
        sourceMessageId: user.id,
      );
      if (_alive && captured != null && captured.isNotEmpty) {
        _chatState = _chatState.copyWith(learned: captured);
      }
    }
    t.answerParent =
        t.resume?.parentId ?? (t.insertUser ? user.id : _lastLiveUser?.id);
    return (user: user, preset: preset);
  }

  /// Stores the question (and the chat, the first time) and returns the
  /// chat id, the question and the answer's sequence slot minus one.
  Future<({String chatId, ChatMessage user, int sequence})> _saveQuestion(
    String input, {
    required List<Attachment> attachments,
    required bool insertUser,
    String? parentId,
    ChatMessage? resume,
    String? modelId,
  }) async {
    final db = _database;
    final id = _chatState.chatId ?? const Uuid().v4();
    final now = DateTime.now();
    // Ancestry: a new question continues the last live turn; a
    // re-asked question (edit) is a sibling of the one it replaces.
    final user = !insertUser && _lastLiveUser != null
        ? _lastLiveUser!
        : ChatMessage(
            id: const Uuid().v4(),
            role: ChatRole.user,
            content: input,
            timestamp: now,
            attachments: attachments,
            parentId:
                parentId ??
                _chatState.messages.where(ChatNotifier.isLive).lastOrNull?.id,
          );
    // The assistant row takes sequence + 1: after a new question, after
    // the existing last row, or (resuming) its own original slot.
    final storedRows = await db.getMessages(id);
    final lastSequence = storedRows.fold(
      -1,
      (n, r) => r.sequence > n ? r.sequence : n,
    );
    final sequence = resume != null
        ? (await db.getMessages(
                id,
              )).firstWhere((r) => r.id == resume.id).sequence -
              1
        : insertUser
        ? lastSequence + 1
        : lastSequence;
    if (insertUser) {
      await db.transaction(() async {
        if (await db.getChat(id) == null) {
          await db.upsertChat(
            ChatsCompanion.insert(
              id: id,
              title: ChatTitles.defaultTitle(input, attachments),
              modelId: drift.Value(modelId),
              createdAt: now,
              updatedAt: now,
              overridesJson: drift.Value(
                jsonEncode(_chatRef.read(chatOverridesProvider)),
              ),
            ),
          );
        }
        await db.insertMessage(
          MessagesCompanion.insert(
            id: user.id,
            chatId: id,
            role: 'user',
            content: input,
            timestamp: now,
            sequence: sequence,
            attachmentsJson: drift.Value(
              jsonEncode([for (final a in attachments) a.toJson()]),
            ),
            parentId: drift.Value(user.parentId),
          ),
        );
        await (db.update(db.chats)..where((t) => t.id.equals(id))).write(
          ChatsCompanion(updatedAt: drift.Value(now)),
        );
      });
      if (!_chatState.temporary && _projectId != null) {
        try {
          await _chatRef.read(conversationWorkspaceProvider.notifier).assign([
            id,
          ], _projectId);
        } catch (e) {
          // A metadata failure must not hide the already committed question.
          if (_alive) _chatState = _chatState.copyWith(notice: '$e');
        }
      }
      _chatState = _chatState.copyWith(
        chatId: id,
        messages: [..._chatState.messages, user],
      );
    }
    return (chatId: id, user: user, sequence: sequence);
  }
}
