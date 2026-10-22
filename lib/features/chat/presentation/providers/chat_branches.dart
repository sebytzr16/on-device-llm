part of 'chat_provider.dart';

/// Editing, regenerating, continuing and comparing turns, restoring branches, and the learned-memory banner.
mixin _ChatBranches on _ChatBase {
  Future<MessageDeletion?> deleteTurn(
    String messageId, {
    bool pair = false,
  }) async {
    final id = state.chatId;
    if (id == null || state.isGenerating || ref.read(sessionBusyProvider)) {
      return null;
    }
    state = state.copyWith(isGenerating: true);
    try {
      final db = _database;
      final deletion = await MessageDeletion.delete(
        db,
        id,
        messageId,
        pair: pair,
      );
      if (_alive && state.chatId == id) {
        state = state.copyWith(
          messages: (await db.getMessages(id)).map(_fromRow).toList(),
        );
      }
      return deletion;
    } finally {
      if (_alive) state = state.copyWith(isGenerating: false);
    }
  }

  Future<bool> undoDelete(MessageDeletion deletion) async {
    if (state.isGenerating || ref.read(sessionBusyProvider)) return false;
    final db = _database;
    state = state.copyWith(isGenerating: true);
    try {
      final ok = await deletion.undo(db);
      if (ok && _alive && state.chatId == deletion.chatId) {
        state = state.copyWith(
          messages: (await db.getMessages(
            deletion.chatId,
          )).map(_fromRow).toList(),
        );
      }
      return ok;
    } finally {
      if (_alive) state = state.copyWith(isGenerating: false);
    }
  }

  /// Edits any earlier question (FX-05): that turn and everything after it
  /// become one retained branch, and the new text is asked in their place.
  Future<bool> editTurn(ChatMessage user, String text) async {
    if (state.isGenerating || text.trim().isEmpty) return false;
    final at = state.messages.indexOf(user);
    if (at < 0 || user.role != ChatRole.user || !ChatNotifier.isLive(user)) {
      return false;
    }
    if (ref.read(sessionBusyProvider) ||
        ref.read(modelManagerProvider).isLoadingModel) {
      return false;
    }
    final branch = const Uuid().v4();
    final members = state.messages.skip(at).where(ChatNotifier.isLive).toList();
    final statuses = {
      for (final m in members) m.id: 'superseded:$branch:${m.status}',
    };
    final db = _database;
    // Block navigation and competing engine work before the first await.
    _navigation++;
    state = state.copyWith(isGenerating: true, clearError: true);
    ref.read(sessionBusyProvider.notifier).state = true;
    try {
      await db.transaction(() async {
        for (final m in members) {
          await db.updateMessage(
            m.id,
            MessagesCompanion(status: drift.Value(statuses[m.id]!)),
          );
        }
      });
      if (!_alive) return false;
      state = state.copyWith(
        messages: [
          for (final m in state.messages)
            statuses.containsKey(m.id) ? m.copyWith(status: statuses[m.id]) : m,
        ],
      );
    } catch (e) {
      if (_alive) {
        state = state.copyWith(error: 'Could not edit this branch: $e');
      }
      return false;
    } finally {
      if (_alive) {
        state = state.copyWith(isGenerating: false);
        ref.read(sessionBusyProvider.notifier).state = false;
      }
    }
    return send(text, attachments: user.attachments, parentId: user.parentId);
  }

  /// Brings a retained branch back. The conversation is a tree (every turn
  /// knows its parent); the branch's last turn, followed down to its newest
  /// descendant, is the new head, and the live conversation is that head's
  /// ancestry. Whatever is live now but off that path is set aside as a
  /// branch of its own; whatever is on the path but set aside — including
  /// ancestors an even later edit had set aside — returns to its original
  /// status. Rows written before ancestry existed fall back to the branch's
  /// storage order.
  Future<bool> restoreBranch(String branch) async {
    if (state.isGenerating) return false;
    final members = state.messages.where((m) => m.branch == branch).toList();
    if (members.isEmpty) return false;
    final byId = {for (final m in state.messages) m.id: m};
    // Newest descendant of the branch's last turn, skipping comparisons.
    var head = members.last;
    while (true) {
      final children = state.messages
          .where((m) => m.parentId == head.id && !m.isAlternative)
          .toList();
      if (children.isEmpty) break;
      head = children.last;
    }
    final path = <String>{};
    for (ChatMessage? m = head; m != null; m = byId[m.parentId]) {
      if (!path.add(m.id)) break;
    }
    final legacy = members.any((m) => m.parentId == null) && members.length > 1;
    if (legacy) {
      // No ancestry: the branch is a suffix in storage order (pre-v7 rows).
      final first = state.messages.indexOf(members.first);
      path
        ..clear()
        ..addAll(members.map((m) => m.id))
        ..addAll([
          for (final m in state.messages.take(first))
            if (ChatNotifier.isLive(m)) m.id,
        ]);
    }
    final replacement = const Uuid().v4();
    // Order: rows that stay put keep their order; every row that becomes
    // live moves to the end in conversation order so context and display
    // read top to bottom.
    final restored = <ChatMessage>[];
    final kept = <ChatMessage>[];
    for (final m in state.messages) {
      final onPath = path.contains(m.id);
      if (m.isAlternative) {
        kept.add(m);
      } else if (onPath && m.isSuperseded) {
        restored.add(m.copyWith(status: m.originalStatus));
      } else if (!onPath && ChatNotifier.isLive(m)) {
        kept.add(m.copyWith(status: 'superseded:$replacement:${m.status}'));
      } else {
        kept.add(m);
      }
    }
    // Conversation order along the path: root first.
    final order = <String, int>{};
    for (ChatMessage? m = head; m != null; m = byId[m.parentId]) {
      order[m.id] = -order.length;
      if (order.length > state.messages.length) break;
    }
    if (!legacy) {
      restored.sort((a, b) => (order[a.id] ?? 0).compareTo(order[b.id] ?? 0));
    }
    final next = [...kept, ...restored];
    final db = _database;
    // Two passes avoid collisions with the unique (chat, sequence) index.
    state = state.copyWith(isGenerating: true);
    try {
      await db.transaction(() async {
        final rows = await db.getMessages(state.chatId!);
        final offset =
            rows.fold(0, (n, r) => r.sequence > n ? r.sequence : n) + 1;
        for (var i = 0; i < next.length; i++) {
          await db.updateMessage(
            next[i].id,
            MessagesCompanion(sequence: drift.Value(offset + i)),
          );
        }
        for (var i = 0; i < next.length; i++) {
          await db.updateMessage(
            next[i].id,
            MessagesCompanion(
              sequence: drift.Value(i),
              status: drift.Value(next[i].status),
            ),
          );
        }
      });
      state = state.copyWith(messages: next);
    } finally {
      state = state.copyWith(isGenerating: false);
    }
    return true;
  }

  /// Drops the "Remembered" banner; the facts stay unless [discard].
  Future<void> dismissLearned({bool discard = false}) async {
    final rows = state.learned;
    state = state.copyWith(learned: const []);
    if (discard) {
      final store = ref.read(memoryStoreProvider);
      for (final m in rows) {
        await store.remove(m.id);
      }
    }
  }

  /// Replaces the just-learned facts with what the user typed (one per
  /// line); empty lines delete.
  Future<void> editLearned(List<String> contents) async {
    final rows = state.learned;
    final store = ref.read(memoryStoreProvider);
    for (var i = 0; i < rows.length; i++) {
      final text = i < contents.length ? contents[i].trim() : '';
      if (text.isEmpty) {
        await store.remove(rows[i].id);
      } else if (text != rows[i].content) {
        await store.edit(rows[i], text);
      }
    }
    state = state.copyWith(learned: const []);
  }

  /// Answers the last question again with [other] (FX-04). The answer is
  /// stored as an `alternative` turn: shown beside the original, never part
  /// of the model context, using the same web evidence. The previously
  /// loaded model is loaded back afterwards.
  Future<bool> compare(ModelInfo other) async {
    if (state.isGenerating) return false;
    final user = _lastLiveUser, original = _lastLiveAssistant;
    if (user == null || original == null) return false;
    final before = ref.read(modelManagerProvider).loadedModel;
    final ok = await send(
      user.content,
      insertUser: false,
      attachments: user.attachments,
      compareWith: other,
      reuseSourcesJson: original.sourcesJson,
    );
    if (ok && before != null && before.id != other.id && _alive) {
      try {
        await ref.read(modelManagerProvider.notifier).loadModel(before);
      } catch (_) {}
    }
    return ok;
  }

  /// The last answer becomes a retained earlier version; the same question
  /// is answered again (with retrieval re-run).
  Future<bool> regenerate() async {
    if (state.isGenerating) return false;
    final user = _lastLiveUser, assistant = _lastLiveAssistant;
    if (user == null) return false;
    if (assistant != null &&
        state.messages.indexOf(assistant) > state.messages.indexOf(user)) {
      await _supersede(assistant);
    }
    return send(user.content, insertUser: false, attachments: user.attachments);
  }

  /// Answers the last question again with a web search, replacing the
  /// answer the model gave from memory, and keeps the question locally as
  /// a phrasing the keyword lists missed ([searchMissesProvider]).
  Future<bool> searchAgain() async {
    if (state.isGenerating) return false;
    final user = _lastLiveUser, assistant = _lastLiveAssistant;
    if (user == null) return false;
    if (!state.temporary) {
      unawaited(ref.read(searchMissesProvider.notifier).add(user.content));
    }
    if (assistant != null &&
        state.messages.indexOf(assistant) > state.messages.indexOf(user)) {
      await _supersede(assistant);
    }
    return send(
      user.content,
      insertUser: false,
      attachments: user.attachments,
      forceResearch: true,
    );
  }

  /// Resumes a stopped, interrupted or failed answer from its saved text.
  Future<bool> continueAnswer() async {
    if (state.isGenerating) return false;
    final assistant = _lastLiveAssistant, user = _lastLiveUser;
    if (assistant == null ||
        user == null ||
        assistant != state.messages.where(ChatNotifier.isLive).last ||
        assistant.content.isEmpty ||
        !const {'stopped', 'interrupted', 'error'}.contains(assistant.status)) {
      return false;
    }
    return send(
      user.content,
      insertUser: false,
      resume: assistant,
      attachments: user.attachments,
    );
  }

  /// Replaces the last question: the old question and its answer are kept as
  /// superseded versions and the new text is asked.
  Future<bool> editLast(String text) async {
    if (state.isGenerating || text.trim().isEmpty) return false;
    final user = _lastLiveUser;
    if (user == null) return false;
    return editTurn(user, text);
  }
}
