part of 'chat_provider.dart';

extension _ChatStreaming on ChatNotifier {
  /// CHAT-01: the assistant row exists before the first token, so a kill
  /// mid-answer leaves an interrupted message, not a missing one. Then the
  /// timers that save and paint the answer as it streams.
  Future<void> _startStreamingAnswer(_Turn t, _Prompt prompt) async {
    final db = t.db;
    final status = t.compareWith == null
        ? 'generating'
        : 'alternative:generating';
    t.newParser();
    if (t.resume != null) {
      await db.updateMessage(
        t.assistantId,
        MessagesCompanion(status: drift.Value(status)),
      );
    } else {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: t.assistantId,
          chatId: t.chatId!,
          role: 'assistant',
          content: '',
          timestamp: DateTime.now(),
          sequence: t.sequence + 1,
          status: drift.Value(status),
          sourcesJson: drift.Value(
            jsonEncode(_sourceMaps(t.displayedSources())),
          ),
          modelId: drift.Value(t.modelId),
          parentId: drift.Value(t.answerParent),
        ),
      );
    }
    t.placeholderSaved = true;
    final answer = t.answer, thinking = t.thinking;
    var checkpointed = 0;
    t.checkpoint = Timer.periodic(ChatNotifier.checkpointInterval, (_) {
      final length = answer.length + thinking.length;
      if (length == checkpointed || !_alive) return;
      checkpointed = length;
      // Serialize writes so a late checkpoint cannot overwrite the final row.
      t.pendingWrite = t.pendingWrite.then(
        (_) => db.updateMessage(
          t.assistantId,
          MessagesCompanion(
            content: drift.Value(answer.toString()),
            reasoning: drift.Value(
              thinking.isEmpty ? null : thinking.toString(),
            ),
          ),
        ),
        onError: (_) {},
      );
    });
    final reasoningId = const Uuid().v4();
    final tools = prompt.tools;
    var painted = (-1, -1);
    final toolWriting = ToolWritingTracker();
    var answerRevision = t.answerRevision;
    String? preparing, busy;
    final remote = t.engine is RemoteEngine ? t.engine as RemoteEngine : null;
    t.repaint = Timer.periodic(ChatNotifier.repaintInterval, (_) {
      // A busy provider's wait says so, counting down to the next try.
      // A provider slow to start answering says so after a few seconds.
      final retrying = remote?.retrying, since = remote?.waitingSince;
      final waited = since == null
          ? 0
          : DateTime.now().difference(since).inSeconds;
      final waitNote = retrying != null
          ? _t.noticeProviderBusy(
              retrying.status,
              max(1, retrying.until.difference(DateTime.now()).inSeconds + 1),
            )
          : waited >= 3
          ? _t.noticeProviderWaiting(waited)
          : null;
      if (_alive && waitNote != busy) {
        final shown = busy;
        busy = waitNote;
        if (waitNote != null) {
          _chatState = _chatState.copyWith(notice: waitNote);
        } else if (_chatState.notice == shown) {
          _chatState = _chatState.copyWith(clearNotice: true);
        }
      }
      // Nothing new since the last frame (prefill, a tool running): no
      // _chatState change, so nothing listening to the stream rebuilds.
      final lengths = (answer.length, thinking.length);
      if (_alive &&
          (lengths != painted || answerRevision != t.answerRevision)) {
        painted = lengths;
        if (answerRevision != t.answerRevision) {
          toolWriting.reset();
          answerRevision = t.answerRevision;
        }
        final answerText = answer.toString();
        // A call being written says so before its arguments are complete.
        final writing = tools.isEmpty && !t.serverWorkspace
            ? null
            : toolWriting.writing(answerText);
        final notice = writing != null && writing != preparing
            ? (writing.isEmpty
                  ? _t.noticePreparingToolCall
                  : _t.noticePreparingTool(writing))
            : null;
        preparing = writing;
        _chatState = _chatState.copyWith(
          notice: notice ?? _chatState.notice,
          // A tool call being written is not part of the answer.
          partialAnswer: t.holdAnswer
              ? ''
              : tools.isEmpty && !t.serverWorkspace
              ? answerText
              : ToolMarkup.visible(answerText),
          hasReasoningTokens: t.hasReasoningTokens,
          reasoning: thinking.isEmpty
              ? null
              : ReasoningBlock(id: reasoningId, content: thinking.toString()),
        );
      }
    });
  }
}
