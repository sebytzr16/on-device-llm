part of 'chat_provider.dart';

/// Memory extraction after an exchange (in the background for remote models).
mixin _ChatMemory on _ChatBase {
  bool _canRecall(InferenceSettings settings) {
    final model = ref.read(modelManagerProvider).loadedModel;
    return settings.memoryEnabled &&
        settings.toolsEnabled &&
        !settings.structuredOutput &&
        (settings.usesRemote
            ? settings.activeRemoteProfile?.shareMemory == true
            : (model?.parameterCountB ?? 0) >= 4);
  }

  Future<String> _recallMemory(String query, InferenceSettings turn) async {
    final current = ref.read(settingsProvider);
    if (!_alive ||
        !current.memoryEnabled ||
        (turn.usesRemote &&
            current.remoteProfiles
                    .where((p) => p.id == turn.activeRemoteProfile?.id)
                    .firstOrNull
                    ?.shareMemory !=
                true)) {
      return 'Memory is unavailable.';
    }
    final rows = (await ref.read(memoryStoreProvider).all())
        .where(
          (m) => m.expiresAt == null || m.expiresAt!.isAfter(DateTime.now()),
        )
        .toList();
    final latest = ref.read(settingsProvider);
    if (!_alive ||
        !latest.memoryEnabled ||
        _retrievalCancel?.isCancelled == true ||
        (turn.usesRemote &&
            latest.remoteProfiles
                    .where((p) => p.id == turn.activeRemoteProfile?.id)
                    .firstOrNull
                    ?.shareMemory !=
                true)) {
      return 'Memory is unavailable.';
    }
    final selected = UserMemory.relevant(query, [
      for (final m in rows) m.content,
    ], personalOnly: false);
    if (selected.isEmpty) return 'No matching saved notes.';
    return UserMemory.promptBlock(
      [for (final i in selected) rows[i].content],
      notedAt: [for (final i in selected) rows[i].updatedAt],
    );
  }

  Future<List<String>> _activeMemoryFacts() async => [
    for (final memory in await ref.read(memoryStoreProvider).all())
      if (memory.expiresAt == null || memory.expiresAt!.isAfter(DateTime.now()))
        memory.content,
  ];

  /// Local parsing does not transmit stored notes to a remote provider.
  Future<List<Memory>?> _learnExplicit(
    String userMessage, {
    String? chatId,
    String? sourceMessageId,
  }) async {
    try {
      final store = ref.read(memoryStoreProvider);
      final existing = await _activeMemoryFacts();
      final facts = UserMemory.explicitFacts(userMessage, existing: existing);
      if (!_alive || !ref.read(settingsProvider).memoryEnabled) return null;
      return [
        for (final fact in facts)
          await store.add(
            fact,
            sourceChatId: chatId,
            sourceMessageId: sourceMessageId,
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Names the chat with the model's title when its title is still the
  /// first message (a rename by the user, even during generation, wins).
  Future<void> _nameChat(
    TextEngine engine,
    ModelInfo model,
    InferenceSettings settings, {
    required String chatId,
    required String question,
    required String answer,
    List<Attachment> attachments = const [],
    Duration deadline = const Duration(seconds: 12),
    // False once the title is no longer wanted (a new turn cut it short).
    bool Function()? keep,
  }) async {
    final db = _database;
    final initial = ChatTitles.defaultTitle(question, attachments);
    Future<String>? pending;
    try {
      if ((await db.getChat(chatId))?.title != initial) return;
      pending = engine
          .generate(
            messages: ChatTitles.titleMessages(question, answer),
            fallbackTemplate: model.family.fallbackTemplate,
            settings: settings.copyWith(
              maxTokens: 24,
              temperature: 0,
              thinkingModeEnabled: false,
              responseFormat: ResponseFormat.text,
              toolsEnabled: false,
            ),
          )
          .join();
      final title = ChatTitles.parseTitle(await pending.timeout(deadline));
      if (title == null || keep?.call() == false) return;
      if ((await db.getChat(chatId))?.title != initial) return;
      await db.renameChat(chatId, title);
    } on TimeoutException {
      engine.cancel();
      await pending?.catchError((_) => '');
    } catch (_) {
      // A title is a nicety; the first message stays the title.
    }
  }

  /// [_nameChat] for a remote connection, after the turn, on its own client.
  Future<void> _nameChatLater(
    ModelInfo model,
    InferenceSettings settings, {
    required String chatId,
    required String question,
    required String answer,
    List<Attachment> attachments = const [],
  }) async {
    final engine = ref.read(remoteMemoryEngineFactoryProvider)();
    try {
      await _nameChat(
        engine,
        model,
        settings,
        chatId: chatId,
        question: question,
        answer: answer,
        attachments: attachments,
        deadline: const Duration(seconds: 30),
      );
    } finally {
      engine.dispose();
    }
  }

  /// Asks the model for new facts about the user in this exchange and
  /// stores them. Returns the stored rows, or null when nothing was learned.
  /// Remote memory extraction after the turn has ended, on a client of its
  /// own; what it learns is shown when it arrives if the chat is still open.
  Future<void> _learnLater(
    ModelInfo model,
    InferenceSettings settings, {
    required List<String> existing,
    required String userMessage,
    required String answer,
    int remainingFacts = UserMemory.maxFactsPerTurn,
    String? chatId,
    String? sourceMessageId,
  }) async {
    final engine = ref.read(remoteMemoryEngineFactoryProvider)();
    try {
      final learned = await _learn(
        engine,
        model,
        settings,
        existing: existing,
        userMessage: userMessage,
        answer: answer,
        remainingFacts: remainingFacts,
        chatId: chatId,
        sourceMessageId: sourceMessageId,
      ).timeout(const Duration(seconds: 45), onTimeout: () => null);
      if (learned != null &&
          learned.isNotEmpty &&
          _alive &&
          state.chatId == chatId &&
          state.messages.where((m) => m.role == ChatRole.user).lastOrNull?.id ==
              sourceMessageId) {
        state = state.copyWith(learned: [...state.learned, ...learned]);
      }
    } catch (_) {
      // Memory is best effort.
    } finally {
      engine.dispose();
    }
  }

  Future<List<Memory>?> _learn(
    TextEngine engine,
    ModelInfo model,
    InferenceSettings settings, {
    required List<String> existing,
    required String userMessage,
    required String answer,
    int remainingFacts = UserMemory.maxFactsPerTurn,
    String? chatId,
    String? sourceMessageId,
  }) async {
    try {
      final known = await _activeMemoryFacts();
      final raw = await engine
          .generate(
            messages: UserMemory.extractionMessages(
              existing: known,
              userMessage: userMessage,
              assistantAnswer: answer,
            ),
            fallbackTemplate: model.family.fallbackTemplate,
            settings: settings.copyWith(
              maxTokens: 360,
              temperature: 0,
              thinkingModeEnabled: false,
              responseFormat: ResponseFormat.text,
              toolsEnabled: false,
            ),
          )
          .join();
      return await _storeFacts(
        raw,
        settings,
        userMessage: userMessage,
        remainingFacts: remainingFacts,
        chatId: chatId,
        sourceMessageId: sourceMessageId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Stores the facts in a model's [raw] notes that [userMessage] states,
  /// when memory (and, for a remote model, its profile's learning) is still
  /// allowed.
  Future<List<Memory>?> _storeFacts(
    String raw,
    InferenceSettings settings, {
    required String userMessage,
    required int remainingFacts,
    String? chatId,
    String? sourceMessageId,
  }) async {
    final facts = UserMemory.parseFacts(
      raw,
      existing: await _activeMemoryFacts(),
      source: userMessage,
    );
    if (facts.isEmpty || !_alive) return null;
    final current = ref.read(settingsProvider);
    if (!current.memoryEnabled) return null;
    if (settings.usesRemote) {
      final profile = current.remoteProfiles
          .where((p) => p.id == settings.activeRemoteProfile?.id)
          .firstOrNull;
      if (profile?.shareMemory != true || profile?.learnMemory != true) {
        return null;
      }
    }
    final store = ref.read(memoryStoreProvider);
    return [
      for (final f in facts.take(remainingFacts))
        await store.add(
          f,
          sourceChatId: chatId,
          sourceMessageId: sourceMessageId,
        ),
    ];
  }

  /// A remote turn's background work: the chat title ([title]) and the
  /// memory notes ([memory]) go in one request when both are due, else
  /// each alone as before.
  Future<void> _afterRemoteTurn(
    ModelInfo model,
    InferenceSettings settings, {
    required String? chatId,
    required String question,
    required String answer,
    List<Attachment> attachments = const [],
    required bool title,
    _MemoryJob? memory,
  }) async {
    if (memory == null || !title || chatId == null) {
      if (title && chatId != null) {
        await _nameChatLater(
          model,
          settings,
          chatId: chatId,
          question: question,
          answer: answer,
          attachments: attachments,
        );
      } else if (memory != null) {
        await _learnLater(
          model,
          settings,
          existing: memory.existing,
          userMessage: question,
          answer: answer,
          remainingFacts: memory.remainingFacts,
          chatId: chatId,
          sourceMessageId: memory.sourceMessageId,
        );
      }
      return;
    }
    final engine = ref.read(remoteMemoryEngineFactoryProvider)();
    try {
      final db = _database;
      final initial = ChatTitles.defaultTitle(question, attachments);
      final raw = await engine
          .generate(
            messages: ChatTitles.titleAndNotesMessages(
              question,
              answer,
              notes: await _activeMemoryFacts(),
            ),
            fallbackTemplate: model.family.fallbackTemplate,
            settings: settings.copyWith(
              maxTokens: 400,
              temperature: 0,
              thinkingModeEnabled: false,
              responseFormat: ResponseFormat.text,
              toolsEnabled: false,
            ),
          )
          .join()
          .timeout(const Duration(seconds: 45));
      final reply = ChatTitles.splitTitleAndNotes(raw);
      if (reply.title case final name?) {
        if ((await db.getChat(chatId))?.title == initial) {
          await db.renameChat(chatId, name);
        }
      }
      final learned = await _storeFacts(
        reply.notes,
        settings,
        userMessage: question,
        remainingFacts: memory.remainingFacts,
        chatId: chatId,
        sourceMessageId: memory.sourceMessageId,
      );
      if (learned != null &&
          learned.isNotEmpty &&
          _alive &&
          state.chatId == chatId &&
          state.messages.where((m) => m.role == ChatRole.user).lastOrNull?.id ==
              memory.sourceMessageId) {
        state = state.copyWith(learned: [...state.learned, ...learned]);
      }
    } on TimeoutException {
      engine.cancel();
    } catch (_) {
      // Both are niceties: the first message stays the title.
    } finally {
      engine.dispose();
    }
  }
}

/// Memory extraction waiting for a remote turn's title (see
/// [_ChatMemory._afterRemoteTurn]).
typedef _MemoryJob = ({
  List<String> existing,
  int remainingFacts,
  String? sourceMessageId,
});
