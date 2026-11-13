part of 'chat_provider.dart';

extension _ChatSend on ChatNotifier {
  /// [insertUser] false re-answers the existing last question; [resume]
  /// continues that assistant message from its saved text instead of
  /// starting a new one.
  ///
  /// A turn runs in named steps on one [_Turn]: [_prepareTurn] (settings,
  /// model, the saved question), [_planRetrieval], [_lookUp] (judge, web,
  /// Wikipedia), [_assemblePrompt], [_startAnswer], [_runRounds] (the
  /// model and its tools) and [_endTurn] (clean, check, save, learn).
  Future<bool> _send(
    String input, {
    bool insertUser = true,
    ChatMessage? resume,
    List<Attachment> attachments = const [],
    String? audioPath,
    ModelInfo? compareWith,
    String? reuseSourcesJson,
    String? parentId,
    Map<String, dynamic> turnOverrides = const {},
    // Callers that drive the chat (Goals): [extraSystem] joins the system
    // prompt; [forceResearch] researches even when Auto would not (web
    // research must still be on); [isolated] sends this message without the
    // earlier turns; [promptOverride] replaces what the model is given for
    // this message (the visible message stays [input]) and
    // [answerSources] are stored as the answer's sources, with no retrieval.
    String? extraSystem,
    bool forceResearch = false,
    bool isolated = false,
    String? promptOverride,
    List<SearchResult>? answerSources,
    // False when [input] is not the user's own words about themself (a
    // prompt shortcut wrapped their text: "/translate My name is…" is text
    // to translate, not a fact to remember).
    bool learn = true,
    // Goals: the names the turn must stay on. Planned search queries are
    // repaired to them and pages about a neighbouring model are dropped
    // before and after reading ([SubjectTerms]); names in [subjectAllowed]
    // (the user's own words) are never treated as drift.
    SubjectTerms? subject,
    String subjectAllowed = '',
    TurnBudget? budget,
    // Conversation mode (tester, 2026-10-07): always the phone's own model,
    // even when a remote server is set up.
    bool localOnly = false,
    // Conversation: the answer is heard, so one from web pages is a few
    // spoken sentences instead of a list.
    bool spoken = false,
    // A Goal's step: the goal's Stop ends only its own turns.
    Object? owner,
  }) async {
    input = input.trim();
    _primeEpoch++;
    _chatRef.read(llamaEngineProvider).cancelPriming();
    if (_naming case final naming?) {
      // A late title gives way to the next turn; it is tried again later.
      _namingStopped = true;
      _chatRef.read(llamaEngineProvider).cancel();
      await naming;
    }
    if (_chatState.isGenerating ||
        _chatRef.read(sessionBusyProvider) ||
        (input.isEmpty && attachments.isEmpty) ||
        _chatRef.read(modelManagerProvider).isLoadingModel) {
      return false;
    }
    _chatRef.read(helperJobsProvider.notifier).dismiss();
    final localEngine = _chatRef.read(llamaEngineProvider);
    final remoteEngine = _chatRef.read(remoteEngineProvider);
    final diffusionEngine = _chatRef.read(diffusionGemmaEngineProvider);
    final models = _chatRef.read(modelManagerProvider.notifier);
    final lease = _turns.begin(() {
      models.stopLoad();
      localEngine.cancel();
      diffusionEngine.cancel();
      remoteEngine.cancel();
    });
    _turnOwner = owner;
    _spoken = spoken;
    _chatState = _chatState.copyWith(
      isGenerating: true,
      clearError: true,
      clearReasoning: true,
      hasReasoningTokens: false,
      partialAnswer: '',
      notice: '',
      learned: const [],
      answerSaved: false,
    );
    _chatRef.read(sessionBusyProvider.notifier).state = true;
    final t = _Turn(
      input,
      db: _database,
      localEngine: localEngine,
      lease: lease,
      insertUser: insertUser,
      resume: resume,
      attachments: attachments,
      audioPath: audioPath,
      compareWith: compareWith,
      reuseSourcesJson: reuseSourcesJson,
      parentId: parentId,
      turnOverrides: turnOverrides,
      extraSystem: extraSystem,
      forceResearch: forceResearch,
      isolated: isolated,
      promptOverride: promptOverride,
      answerSources: answerSources,
      learn: learn,
      subject: subject,
      subjectAllowed: subjectAllowed,
      budget: budget,
      localOnly: localOnly,
      spoken: spoken,
    );
    if (resume != null) {
      // The saved partial answer is both the display prefix and the model's
      // prefill; only new text streams in.
      t.answer.write(resume.content);
      t.tail.add(resume.content);
      if (resume.reasoning != null) t.thinking.write(resume.reasoning);
      _chatState = _chatState.copyWith(
        messages: _chatState.messages.where((m) => m.id != resume.id).toList(),
        partialAnswer: resume.content,
      );
    }
    final remainingTime = budget?.remainingTime;
    if (remainingTime != null) {
      t.deadline = Timer(
        remainingTime < Duration.zero ? Duration.zero : remainingTime,
        cancel,
      );
    }
    _fittedOmitted = 0;
    final turnClock = Stopwatch()..start();
    _turnLog.info(
      'Turn started: ${input.length} chars'
      '${attachments.isEmpty ? '' : ', ${attachments.length} attachment(s)'}'
      '${resume != null ? ', resuming' : ''}',
    );
    try {
      final asked = await _prepareTurn(t);
      if (asked == null) return t.accepted;
      if (t.settings!.usesRemote && !t.localOnly) {
        final workspace = WorkspaceClient();
        try {
          if (await workspace.supported(t.settings!)) {
            await _runServerWorkspace(t, asked, workspace);
            return t.accepted;
          }
        } finally {
          workspace.dispose();
        }
      }
      final planned = await _planRetrieval(t, asked.user);
      if (planned == null) return t.accepted;
      final found = await _lookUp(t, asked, planned);
      if (found == null) return t.accepted;
      final prompt = await _assemblePrompt(t, asked.user, planned, found);
      if (prompt == null) return t.accepted;
      await _startAnswer(t, prompt);
      await _runRounds(t, prompt);
      await _searchAfterRecall(t, asked, planned);
    } catch (e, stack) {
      t.failure = switch (e) {
        StateError(:final message) => message,
        _ => '$e',
      };
      _turnLog.warning('Turn failed: ${t.failure}', e, stack);
    } finally {
      await _endTurn(t);
      _turnLog.info(
        'Turn ${t.failure != null
            ? 'failed'
            : _cancelled
            ? 'stopped'
            : 'finished'} '
        'in ${turnClock.elapsedMilliseconds} ms, ${t.answer.length} answer chars, '
        '${t.sources.length} source(s)',
      );
    }
    return t.accepted;
  }

  /// While "Use this device as a server" runs, the phone's chats use the
  /// served model: another model would unload it under the client (a
  /// clear error instead), and a request in progress is waited for rather
  /// than raced. False when the user stopped the wait.
  Future<bool> _shareWithHosting(ModelInfo model) async {
    var hosting = _chatRef.read(deviceHostingProvider);
    // Its own runtime (desktop): nothing shared, nothing to wait for.
    if (!hosting.running || hosting.ownEngine) return true;
    if (hosting.modelId != null && hosting.modelId != model.id) {
      // The desktop moves the served model to its own runtime on load.
      if (_chatRef.read(engineHandoffProvider) != null) return true;
      throw StateError(_t.chatErrorServing(hosting.modelId!));
    }
    final clock = Stopwatch()..start();
    while (hosting.running && hosting.activeClient != null) {
      if (_cancelled || !_alive) return false;
      if (clock.elapsed > ChatNotifier.hostedWait) {
        throw StateError(_t.chatErrorServerBusy('${hosting.activeClient}'));
      }
      _chatState = _chatState.copyWith(
        notice: _t.noticeWaitingServer('${hosting.activeClient}'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      hosting = _chatRef.read(deviceHostingProvider);
    }
    return true;
  }
}
