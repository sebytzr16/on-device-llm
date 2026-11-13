part of 'chat_provider.dart';

extension _ChatTools on ChatNotifier {
  /// The typed tools this turn offers (those enabled whose host gate is
  /// open), and their instructions added to [system]: the text protocol
  /// when the template cannot carry tools, the tool policy, and the
  /// research steps added to [turnNotes] for a model-driven research turn.
  ({ToolRunner? runner, List<ToolSpec> tools, bool native, bool clock})
  _offerTools(
    String input, {
    required InferenceSettings settings,
    required TextEngine engine,
    required StringBuffer system,
    required StringBuffer turnNotes,
    required List<SearchResult> sources,
    required bool researchTurn,
    bool remoteBrain = false,
    bool userTools = true,
    required bool continuing,
    bool allowRecall = true,
    bool register = true,
    String? helperMessageId,
    _Turn? turn,
    bool primeOnly = false,
  }) {
    ToolRunner? offered;
    if (engine is DiffusionGemmaEngine) {
      return (runner: null, tools: const [], native: false, clock: false);
    }
    // Typed tools (roadmap P2): offered only when enabled and only those
    // whose host gate is open. A template that cannot carry tool
    // definitions gets the plain-text protocol instead.
    List<ToolSpec> tools = const [];
    var nativeTools = false;
    var clock = false;
    // A greeting or one-word message gets no tools at all: offered a
    // search tool, small models call it on "hi" (report 2026-09-20).
    // On the phone, neither does a message with nothing to look up or work
    // out: the descriptions cost about 700 tokens before the first word
    // (review 2026-09-28). A chat that had tools keeps them.
    final chat = register ? _chatState.chatId : null;
    // Phone actions (alarms, calls, apps) have no Windows equivalent.
    final phoneActions =
        !DesktopHost.active &&
        settings.toolActions &&
        (PhoneActions.wanted(input) ||
            remoteBrain ||
            (chat != null && _actionChats.contains(chat)));
    // After an action, retaining the native schema keeps the conversation's
    // system prefix reusable. Small talk uses toolChoice=none and ignores
    // any unsolicited call; it still gets an ordinary spoken answer.
    final keepActionPrefix =
        !settings.usesRemote &&
        engine.metrics['supportsTools'] == true &&
        chat != null &&
        _actionChats.contains(chat);
    final project = _chatRef
        .read(conversationWorkspaceProvider)
        .projects
        .where((p) => p.id == _projectId)
        .firstOrNull;
    final fileCancel = _retrievalCancel;
    final fileProjectId = _projectId;
    final fileDb = _database;
    final folder = DesktopHost.active && userTools ? project?.folder : null;
    final fileTools = folder == null
        ? null
        : ProjectFileTools(
            folder: folder,
            backupDirectory: () async => Directory(
              path.join(
                (await getApplicationSupportDirectory()).path,
                'project_file_backups',
              ),
            ),
            approve: (change) {
              final id = _chatState.chatId;
              if (id == null) return Future.value(false);
              return _chatRef
                  .read(fileApprovalProvider)
                  .request(
                    id,
                    folder,
                    change,
                    fileCancel,
                    read: () async =>
                        AgentWebDecisions.decode(
                              (await fileDb.getChat(id))?.overridesJson ?? '{}',
                            )['_fileEditsAllowed:$folder']
                            as bool?,
                    save: () => fileDb.transaction(() async {
                      final chat = await fileDb.getChat(id);
                      if (chat == null) {
                        throw StateError('Chat no longer exists');
                      }
                      await (fileDb.update(
                        fileDb.chats,
                      )..where((t) => t.id.equals(id))).write(
                        ChatsCompanion(
                          overridesJson: drift.Value(
                            jsonEncode({
                              ...AgentWebDecisions.decode(chat.overridesJson),
                              '_fileEditsAllowed:$folder': true,
                            }),
                          ),
                        ),
                      );
                    }),
                  );
            },
            permitted: () =>
                _alive &&
                !_cancelled &&
                fileCancel?.isCancelled != true &&
                _projectId == fileProjectId &&
                DesktopHost.active &&
                _chatRef
                    .read(effectiveSettingsProvider)
                    .effective
                    .toolsEnabled &&
                _chatRef
                    .read(conversationWorkspaceProvider)
                    .projects
                    .any((p) => p.id == fileProjectId && p.folder == folder),
            changed: (_) => _chatRef.read(fileApprovalProvider).refresh(),
          );
    final mcp = DesktopHost.active && Platform.isWindows
        ? _chatRef.read(mcpRegistryProvider)
        : null;
    final mcpTools = userTools
        ? mcp?.specs ?? const <ToolSpec>[]
        : const <ToolSpec>[];
    // Turning Tools off mid-turn stops the MCP calls still to come.
    final globalTools = _chatRef.read(settingsProvider).toolsEnabled;
    // A picture to change: this message's own image, else the newest one in
    // the chat (attached earlier or drawn by the chat).
    final editSource = DesktopHost.active ? _pictureToEdit(turn) : null;
    final editing = editSource != null && RetrievalPlan.wantsImageEdit(input);
    final mayNeed =
        editing ||
        fileTools != null ||
        mcpTools.isNotEmpty ||
        // Summaries, translations and drafts of supplied text are the
        // helper's work, which the retrieval gate would leave out.
        (settings.toolHelper && settings.helperModelId.isNotEmpty) ||
        researchTurn ||
        phoneActions ||
        (_canRecall(settings) && UserMemory.personalQuery(input)) ||
        settings.usesRemote ||
        settings.toolChoice == ToolChoice.required ||
        (chat != null && _toolChats.contains(chat)) ||
        RetrievalPlan.mayNeedTools(
          input,
          documents:
              settings.toolDocuments && settings.knowledgeCollection.isNotEmpty,
        );
    // Phone actions only prepare a card the user confirms, so they are
    // offered for an action request even with the other tools off.
    if ((settings.toolsEnabled || phoneActions) &&
        !continuing &&
        !settings.structuredOutput &&
        (!RetrievalPlan.smallTalk(input) ||
            keepActionPrefix ||
            fileTools != null) &&
        mayNeed) {
      final runner = ToolRunner(
        projectFiles: fileTools,
        helperOwnsDeadline: true,
        helperMaxConcurrent: settings.agentMaxConcurrent,
        scraper: _chatRef.read(duckDuckGoScraperProvider),
        reader: _chatRef.read(webPageReaderProvider),
        knowledge: _chatRef.read(knowledgeStoreProvider),
        settings: settings,
        cancel: _retrievalCancel,
        remote: settings.usesRemote,
        researchRecipe: researchTurn ? ResearchRecipe.forQuestion(input) : null,
        newsDesk: _chatRef.read(newsDeskProvider),
        recall: _canRecall(settings) && !researchTurn && allowRecall
            ? (query) => _recallMemory(query, settings)
            : null,
        // Settings > Tools > Helper model: side jobs on a small second
        // model. A refusal (not downloaded, no memory) reaches the chat
        // model as a tool error, so it does the job itself.
        helper:
            // The helper is the user's own opt-in (Settings > Tools > Helper
            // model): it is offered whenever this runner exists, so a remote
            // research turn with the Tools switch off still gets it (R01).
            settings.toolHelper && settings.helperModelId.isNotEmpty
            ? (task, text) async {
                try {
                  final reply = await _chatRef
                      .read(helperRunnerProvider)
                      .run(
                        modelId: settings.helperModelId,
                        agentSettings: settings,
                        task: task,
                        input: text,
                        messageId: helperMessageId,
                        webTools: ToolRunner(
                          scraper: _chatRef.read(duckDuckGoScraperProvider),
                          reader: _chatRef.read(webPageReaderProvider),
                          settings: settings,
                          cancel: _retrievalCancel,
                          userText: input,
                          webOnly: true,
                        ),
                        approveWeb: (cancel) async {
                          final id = _chatState.chatId;
                          if (id == null) return false;
                          final decisions = AgentWebDecisions(_database);
                          return _chatRef
                              .read(agentWebApprovalProvider)
                              .request(
                                chatId: id,
                                mode: settings.agentWebAccess,
                                read: () => decisions.read(id),
                                save: (allow) => decisions.write(id, allow),
                                cancel: cancel,
                              );
                        },
                        cancel: _retrievalCancel,
                      );
                  return 'Helper model: ${reply.modelName}\n${reply.text}';
                } on HelperUnavailable catch (e) {
                  throw StateError(
                    'The helper is unavailable (${e.reason}); do the job yourself.',
                  );
                }
              }
            : null,
        // The prime offers the same tool list as the first real turn so the
        // cached prefix matches; it never runs a tool.
        generateImage: turn == null
            ? (primeOnly
                  ? (_, _, _, _) async =>
                        throw StateError('Image tool used during prime.')
                  : null)
            : (prompt, width, height, steps) =>
                  _generateImageForTool(turn, prompt, width, height, steps),
        editImage: turn == null || !editing
            ? null
            : (instruction, strength, steps) => _editImageForTool(
                turn,
                editSource,
                instruction,
                strength,
                steps,
              ),
        phoneActions: phoneActions,
        actionsOnly: !settings.toolsEnabled,
        webOnly: !userTools,
        userText: input,
        externalTools: mcpTools,
        externalRun: mcp == null
            ? null
            : (call) => mcp.call(
                call,
                explain: (error) => mcpExplain(_t, error),
                unsupportedContent: _t.mcpUnsupportedContent,
                permitted: () =>
                    _alive &&
                    !_cancelled &&
                    DesktopHost.active &&
                    userTools &&
                    settings.toolsEnabled &&
                    (!globalTools ||
                        _chatRef.read(settingsProvider).toolsEnabled),
              ),
      );
      offered = runner;
      tools = runner.specs();
      if (tools.any((t) => t.name == 'ask_helper')) {
        turnNotes.writeln(HelperRequest.mergeInstruction);
      }
      if (HelperRequest.wanted(input) &&
          tools.any((t) => t.name == 'ask_helper')) {
        turnNotes.writeln(
          'The user explicitly requested a helper/sub-agent. Start ALL helper jobs in your FIRST round: make one ask_helper call per independent part together, then keep working while they run in the background. Their replies will be added before your final answer. If the user asks for N sub-agents/helpers (e.g. "use 3 sub-agents" or "two helpers"), make N calls.',
        );
      }
      // Evidence is already in the prompt: offering the web tools too
      // invites a needless extra round (each one a full request).
      if (sources.isNotEmpty && !researchTurn && !remoteBrain) {
        tools = [
          for (final t in tools)
            if (!const {
              'search_web',
              'search_news',
              'read_url',
              'find_in_page',
            }.contains(t.name))
              t,
        ];
      }
      if (tools.isNotEmpty && chat != null) _toolChats.add(chat);
      if (phoneActions && !remoteBrain && chat != null) _actionChats.add(chat);
      nativeTools =
          tools.isNotEmpty &&
          (settings.usesRemote || engine.metrics['supportsTools'] == true);
      // "Tomorrow at 9" needs today's date and the local time. On the
      // phone it goes with the request (the caller adds it): a system
      // prompt that changes every minute made each turn of a chat with
      // phone actions read the whole conversation again.
      if (tools.any((t) => PhoneActions.kinds.contains(t.name)) ||
          remoteBrain) {
        if (settings.usesRemote) {
          system.write('\n${TurnPrompts.clockLine()}');
        } else {
          clock = true;
        }
      }
      if (tools.isNotEmpty) {
        system.write(
          TurnPrompts.toolSystemText(
            tools,
            native: nativeTools,
            required:
                researchTurn || settings.toolChoice == ToolChoice.required,
            research: researchTurn || remoteBrain,
          ),
        );
      }
      if (remoteBrain && tools.any((t) => t.name == 'search_web')) {
        system.write('\n${TurnPrompts.remoteBrainText}');
      }
      if (researchTurn && tools.any((t) => t.name == 'search_web')) {
        turnNotes.write(
          NewsIntent.of(input) != null &&
                  tools.any((t) => t.name == 'search_news')
              ? '\nResearch before answering: call search_news for the latest stories, read one or two of the most relevant with read_url if details are needed, then answer from them with [n] citations.'
              : '\nResearch before answering: call search_web with a focused query of a few keywords, read the most promising result with read_url (or find_in_page for one detail), search again with different words if the first results do not answer, then answer from what you read with [n] citations. Say so when the pages do not settle the question.',
        );
        turnNotes.write(
          '\nResearch recipe: ${ResearchRecipe.forQuestion(input).instructions}',
        );
      }
    }
    return (runner: offered, tools: tools, native: nativeTools, clock: clock);
  }

  /// The picture edit_image changes: an image attached to this message,
  /// else the newest image in the chat (the user's or the assistant's).
  /// Null when the chat has none.
  Attachment? _pictureToEdit(_Turn? t) {
    final own = t?.attachments.where((a) => a.isImage).lastOrNull;
    if (own != null) return own;
    for (final m in _chatState.messages.reversed) {
      if (!ChatNotifier.isLive(m)) continue;
      final found = m.attachments.where((a) => a.isImage).lastOrNull;
      if (found != null) return found;
    }
    return null;
  }

  /// The edit_image tool: the picture model selected in Create draws from
  /// [source] (image to image) and the PNG is attached to this answer.
  Future<String> _editImageForTool(
    _Turn t,
    Attachment source,
    String instruction,
    double? strength,
    int? steps,
  ) async {
    final settings = t.settings;
    final local = settings == null || !settings.usesRemote;
    final locale =
        settings?.localeCode ?? _chatRef.read(settingsProvider).localeCode;
    final t18n = stringsFor(locale);
    _chatState = _chatState.copyWith(notice: t18n.chatImagePreparing);
    final picture = await _chatRef
        .read(chatImageGeneratorProvider)
        .edit(
          source: source,
          instruction: instruction,
          strength: strength,
          steps: steps,
          localeCode: locale,
          cancel: _retrievalCancel,
          onProgress: (step, total) {
            if (_alive && !_cancelled && total > 0) {
              _chatState = _chatState.copyWith(
                notice: t18n.chatImageEditing(step, total),
              );
            }
          },
          unloadChatModel: !local
              ? null
              : () => _chatRef
                    .read(modelManagerProvider.notifier)
                    .unloadModel(ownsBusy: true),
          reloadChatModel: !local || settings == null || t.model == null
              ? null
              : () => _chatRef
                    .read(modelManagerProvider.notifier)
                    .loadModel(t.model!, forChat: true, settings: settings),
        );
    t.generatedImages.add(picture.attachment);
    if (_alive && _chatState.temporary) {
      await TemporaryFiles.remember([picture.attachment.path]);
    }
    return 'Picture edited with ${picture.modelName} and attached under '
        'your answer (${picture.width}×${picture.height}). The user sees it '
        'already: do not write a link and do not say you cannot edit pictures.';
  }

  /// The generate_image tool: the picture model selected in Create draws
  /// [prompt] and the PNG is attached to this answer. Progress and Stop use
  /// the turn's notice and cancellation, as every other tool does.
  Future<String> _generateImageForTool(
    _Turn t,
    String prompt,
    int? width,
    int? height,
    int? steps,
  ) async {
    final settings = t.settings;
    // A remote answer has no local chat model to unload or reload.
    final local = settings == null || !settings.usesRemote;
    final locale =
        settings?.localeCode ?? _chatRef.read(settingsProvider).localeCode;
    final t18n = stringsFor(locale);
    _chatState = _chatState.copyWith(notice: t18n.chatImagePreparing);
    final picture = await _chatRef
        .read(chatImageGeneratorProvider)
        .generate(
          prompt: prompt,
          width: width,
          height: height,
          steps: steps,
          localeCode: locale,
          cancel: _retrievalCancel,
          onProgress: (step, total) {
            if (_alive && !_cancelled && total > 0) {
              _chatState = _chatState.copyWith(
                notice: t18n.chatImageDrawing(step, total),
              );
            }
          },
          unloadChatModel: !local
              ? null
              : () => _chatRef
                    .read(modelManagerProvider.notifier)
                    .unloadModel(ownsBusy: true),
          reloadChatModel: !local || settings == null || t.model == null
              ? null
              : () => _chatRef
                    .read(modelManagerProvider.notifier)
                    .loadModel(t.model!, forChat: true, settings: settings),
        );
    t.generatedImages.add(picture.attachment);
    if (_alive && _chatState.temporary) {
      await TemporaryFiles.remember([picture.attachment.path]);
    }
    return 'Picture generated with ${picture.modelName} and attached under '
        'your answer (${picture.width}×${picture.height}). The user sees it '
        'already: do not write a link and do not say you cannot make pictures.';
  }
}
