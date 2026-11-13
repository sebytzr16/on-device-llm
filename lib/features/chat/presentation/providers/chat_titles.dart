part of 'chat_provider.dart';

extension _ChatTitles on ChatNotifier {
  /// Memory and the chat's title after a completed, fresh exchange.
  /// Returns the notes to show as learned.
  ///
  /// Memory: on the phone it runs while the turn still counts as busy, so
  /// the engine is not shared; a remote connection gets its own client and
  /// learns in the background, so the turn ends when the answer does (a
  /// second hosted request per message made remote chats feel slow). A
  /// remote model's notes wait for the title, so both go in one request.
  ///
  /// The model names a new chat after its first exchange (report
  /// 2026-10-04: "the model should name the chat"), unless the user has
  /// renamed it already. Local: while the turn is still busy, a few
  /// tokens; remote: in the background on its own client. A spoken turn
  /// leaves both for [nameChatLater], once the voice is quiet.
  Future<List<Memory>> _learnAndName(_Turn t) async {
    var learned = _chatState.learned;
    final model = t.model, settings = t.settings;
    if (model == null || settings == null) return learned;
    final input = t.input, said = t.answer.toString();
    final chatId = t.chatId, messageId = t.sourceMessageId;
    final facts = t.memoryFacts;
    final fresh =
        t.failure == null &&
        !_cancelled &&
        t.insertUser &&
        t.resume == null &&
        t.learn &&
        said.isNotEmpty &&
        !_chatState.temporary;
    _MemoryJob? remoteNotes;
    if (fresh &&
        UserMemory.worthExtracting(input) &&
        _chatRef.read(settingsProvider).memoryEnabled) {
      final remainingFacts = UserMemory.maxFactsPerTurn - learned.length;
      final needsExtraction =
          remainingFacts > 0 && UserMemory.needsModelExtraction(input);
      final modelLearningAllowed =
          !settings.usesRemote ||
          (settings.activeRemoteProfile?.shareMemory == true &&
              settings.activeRemoteProfile?.learnMemory == true);
      if (modelLearningAllowed && needsExtraction && settings.usesRemote) {
        remoteNotes = (
          existing: facts,
          remainingFacts: remainingFacts,
          sourceMessageId: messageId,
        );
      } else if (modelLearningAllowed && needsExtraction && _spoken) {
        final localEngine = t.localEngine;
        _memoryLater = (keep) async {
          if (!keep()) return;
          final extracted = await _learn(
            localEngine,
            model,
            settings,
            existing: facts,
            userMessage: input,
            answer: said,
            remainingFacts: remainingFacts,
            chatId: chatId,
            sourceMessageId: messageId,
          );
          if (extracted != null &&
              extracted.isNotEmpty &&
              _alive &&
              _chatState.chatId == chatId) {
            _chatState = _chatState.copyWith(
              learned: [..._chatState.learned, ...extracted],
            );
          }
        };
      } else if (modelLearningAllowed && needsExtraction) {
        _chatState = _chatState.copyWith(notice: _t.noticeUpdatingMemory);
        final extracted = await _learn(
          t.engine,
          model,
          settings,
          existing: facts,
          userMessage: input,
          answer: said,
          remainingFacts: remainingFacts,
          chatId: chatId,
          sourceMessageId: messageId,
        );
        learned = [...learned, ...?extracted];
      }
    }
    final wantsTitle =
        fresh &&
        t.promptOverride == null &&
        input.isNotEmpty &&
        settings.autoTitles &&
        chatId != null &&
        _chatState.messages.where((m) => m.role == ChatRole.user).length == 1;
    if (settings.usesRemote && (wantsTitle || remoteNotes != null)) {
      unawaited(
        _afterRemoteTurn(
          model,
          settings,
          chatId: chatId,
          question: input,
          answer: said,
          attachments: t.attachments,
          title: wantsTitle,
          memory: remoteNotes,
        ),
      );
    } else if (wantsTitle) {
      if (_spoken) {
        final localEngine = t.localEngine;
        _titleLater = (keep) => _nameChat(
          localEngine,
          model,
          settings,
          chatId: chatId,
          question: input,
          answer: said,
          keep: keep,
        );
      } else {
        _chatState = _chatState.copyWith(notice: _t.noticeNamingChat);
        await _nameChat(
          t.engine,
          model,
          settings,
          chatId: chatId,
          question: input,
          answer: said,
          attachments: t.attachments,
        );
      }
    }
    return learned;
  }

  /// Writes the title (and memory) a spoken turn left for later ([send]'s
  /// `spoken`), now that the answer has been heard. A new turn stops it; it is tried again
  /// on the next call.
  Future<void> _finishDeferredNaming() async {
    if (_memoryLater != null &&
        _naming == null &&
        !_chatState.isGenerating &&
        !_chatRef.read(modelManagerProvider).isLoadingModel) {
      final memory = _memoryLater!;
      _memoryLater = null;
      _namingStopped = false;
      final learning = memory(() => !_namingStopped);
      _naming = learning;
      try {
        await learning;
      } catch (_) {
        // Memory is best effort.
      } finally {
        _naming = null;
      }
      // Stopped by a new turn: tried again after it.
      if (_namingStopped) _memoryLater ??= memory;
    }
    final run = _titleLater;
    if (run == null ||
        _naming != null ||
        _chatState.isGenerating ||
        _chatRef.read(modelManagerProvider).isLoadingModel) {
      return;
    }
    _namingStopped = false;
    final naming = run(() => !_namingStopped);
    _naming = naming;
    try {
      await naming;
    } finally {
      _naming = null;
    }
    if (!_namingStopped && identical(_titleLater, run)) _titleLater = null;
  }
}
