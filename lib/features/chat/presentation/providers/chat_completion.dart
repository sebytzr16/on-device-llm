part of 'chat_provider.dart';

extension _ChatCompletion on ChatNotifier {
  /// The turn's last step, however it ended: the answer cleaned, checked
  /// and saved, then memory, the title and the closing notice.
  Future<void> _endTurn(_Turn t) async {
    t.deadline?.cancel();
    _retrievalCancel?.cancel('Turn ended');
    t.lease.transition(TurnStage.saving);
    try {
      t.repaint?.cancel();
      await t.canvasSub?.cancel();
      t.checkpoint?.cancel();
      t.parser?.close();
      await t.answerSub?.cancel();
      await t.thinkSub?.cancel();
      await t.pendingWrite;
      t.lease.transition(
        t.failure != null
            ? TurnStage.failed
            : _cancelled
            ? TurnStage.stopped
            : TurnStage.complete,
      );
      if (_alive) {
        _cleanAnswer(t);
        await _checkAnswer(t);
        final grounding = _groundingNotice(t);
        // A check that found something to doubt rides with the answer: the
        // triangle under it opens the whole warning (tester, 2026-10-19).
        final warning =
            grounding != null &&
                t.sources.isNotEmpty &&
                grounding != _t.noticeCitationsMatched
            ? grounding
            : null;
        await _saveAnswer(t, warning: warning);
        final learned = await _learnAndName(t);
        _showTurnEnd(t, grounding: grounding, learned: learned);
      }
    } finally {
      _turns.release(t.lease);
      _turnOwner = null;
      if (_alive) {
        _chatRef.read(sessionBusyProvider.notifier).state = false;
        if (_chatState.isGenerating) {
          _chatState = _chatState.copyWith(
            isGenerating: false,
            isLoadingModel: false,
          );
        }
      }
    }
  }

  /// The answer as it is saved: a restated answer once, without stray
  /// closing tags or lines narrating the request; a spoken one cut to
  /// length; the app's own answers in place of the model's.
  void _cleanAnswer(_Turn t) {
    final ok = t.failure == null && !_cancelled;
    var cleaned = AnswerCleanup.dropAskedBack(
      AnswerCleanup.dropNarration(
        AnswerCleanup.dropRepeats(ToolMarkup.stripOrphans(t.answer.toString())),
        sentences: t.spoken || t.sources.isNotEmpty,
      ),
      t.input,
    );
    final most = _chatRef.read(settingsProvider).spokenSentences;
    if (t.spoken && most > 0) {
      cleaned = AnswerCleanup.spokenLength(cleaned, max: most);
    }
    if (cleaned.length < t.answer.length) t.replaceAnswer(cleaned);
    final aboutUser = t.aboutUser;
    if (aboutUser != null && ok) {
      final own = AboutUser.ownFacts(t.answer.toString(), aboutUser);
      if (own != t.answer.toString()) t.replaceAnswer(own);
    }
    // A spoken sum or name is said as the app knows it, and nothing else.
    final appAnswer = t.appAnswer;
    if (appAnswer != null && ok) t.replaceAnswer(appAnswer);
    // Nothing was read: a citation number points at nothing. The phone's
    // model too: Qwen3.5 0.8B copied "[1]" from the turn before into an
    // answer with no sources (Conversation probe, 2026-10-20).
    if (t.sources.isEmpty) {
      final plain = AnswerCleanup.dropCitations(t.answer.toString());
      if (plain.length < t.answer.length) t.replaceAnswer(plain);
    }
    // An attached file or photo is the source: no closing note that live
    // data is unavailable. Qwen3.5 0.8B added one to a figure it read from
    // a spreadsheet (media probe, 2026-10-21).
    if (t.attachments.isNotEmpty && ok) {
      final kept = AnswerCleanup.dropLiveNote(t.answer.toString());
      if (kept.length < t.answer.length) t.replaceAnswer(kept);
    }
    // Copied twice: say so rather than show the prompt as an answer.
    if (t.echoStopped) t.replaceAnswer(_t.echoedAnswer);
    // Gemma 4 E2B often says nothing after preparing an action (phone probe
    // 2026-10-07): the card alone, under an empty bubble. A spoken phone
    // answer that describes the card's steps says the app's line instead:
    // the 0.8B told the user "you've tapped Yes to confirm" before anything
    // was tapped (Conversation probe round 7, 2026-10-18). A remote model
    // too: LM Studio Gemma 4 E4B said "I have set a timer… You can tap on
    // that notification to start it!" while the card still waited (round
    // 9).
    if (ok &&
        (t.answer.toString().trim().isEmpty ||
            (t.spoken && AnswerChecks.actionTalk(t.answer.toString()))) &&
        (t.runner?.trace.any(
              (r) => r.ok && PhoneActions.kinds.contains(r.call.name),
            ) ??
            false)) {
      t.replaceAnswer(_t.actionReadyAnswer);
    }
    // A picture with no words under it: the app's line, so the answer (and
    // its attachment) is saved.
    if (ok &&
        t.answer.toString().trim().isEmpty &&
        t.generatedImages.isNotEmpty) {
      t.replaceAnswer(_t.chatImageAnswer);
    }
    // A model can spend its entire final budget on thinking or another
    // call, even after the no-tools retry. Preserve useful evidence rather
    // than saving an empty bubble (and a citations warning alone).
    if (ok && t.answer.toString().trim().isEmpty) {
      final evidence = <String>[
        for (var i = 0; i < t.sources.length; i++)
          '- ${t.sources[i].title}: ${t.sources[i].snippet} [${i + 1}]',
      ];
      if (evidence.isEmpty) {
        for (final result in t.runner?.trace ?? const <ToolResult>[]) {
          if (result.call.name == 'ask_helper') {
            final text = TextToolProtocol.strip(
              ToolRunner.helperReplyText(result.output),
            );
            if (text.isNotEmpty) evidence.add(text);
          }
        }
      }
      if (evidence.isNotEmpty) {
        t.replaceAnswer('Available findings:\n\n${evidence.join('\n\n')}');
      }
    }
  }

  /// An answer from sources: its citations matched by wording and
  /// figures, its sentences checked against the pages, and a changing
  /// figure dated by its newest source.
  Future<void> _checkAnswer(_Turn t) async {
    if (t.serverWorkspace) return;
    if (t.failure != null || _cancelled || t.echoStopped) return;
    final sources = t.sources;
    if (sources.isNotEmpty &&
        !AnswerChecks.refusal.hasMatch(t.answer.toString())) {
      // A partly cited answer gets its uncited sentences matched too
      // (tester, 2026-10-07: "missing [n] citations are added").
      final hadCitations = CitationMatch.hasCitations(t.answer.toString());
      String? cited;
      try {
        cited = CitationMatch.attach(
          t.answer.toString(),
          t.sourceTexts(),
          fill: true,
        );
      } catch (_) {
        // Best effort: a page the matcher cannot read (D1 benchmark,
        // 2026-10-11) leaves the answer as written, never loses it.
      }
      if (cited != null && cited != t.answer.toString()) {
        t.matchedCitations = !hadCitations;
        t.replaceAnswer(cited);
      }
      // Every sentence against the sources: words, names, years and (with
      // the embedding model) meaning. Run for spoken answers too so the
      // transcript and UI can show claim check status; the speakable text
      // retains citation markers for reference.
      if (_chatRef.read(settingsProvider).figureCheck) {
        t.claims = await ClaimCheckRunner.run(
          t.answer.toString(),
          sources,
          embedder: _webEmbedder(),
          judge: _supportJudge(),
        );
      }
    }
    // A changing figure says how recent its pages are (tester, 2026-10-19:
    // no refusal, but the date the sources were updated). A forecast is
    // not a figure: "the sources do not say when they were last updated"
    // under tomorrow's weather read oddly (remote sweep, 2026-10-21).
    final answer = t.answer.toString();
    if (!_cancelled &&
        t.appAnswer == null &&
        !t.newsAnswer &&
        !InstantAnswers.isWeather(t.askedInContext) &&
        RetrievalPlan.timeSensitive(t.askedInContext) &&
        !AnswerChecks.refusal.hasMatch(answer) &&
        !SourceDates.dated(answer)) {
      final cited = SourceDates.cited(answer, sources);
      if (cited.isNotEmpty) {
        final newest = SourceDates.newest(cited);
        final line = newest == null
            ? _t.answerSourcesUndated
            : _t.answerSourcesDated(SourceDates.format(newest, _t.localeName));
        t.answer.write('\n\n$line');
      }
    }
  }

  /// What the notice says about the answer's grounding: matched
  /// citations, a figure or claim the sources do not back, or why an
  /// answer that refused had no sources.
  String? _groundingNotice(_Turn t) {
    if (t.failure != null || _cancelled) return null;
    final answer = t.answer.toString();
    final sources = t.sources;
    final figureCheck = _chatRef.read(settingsProvider).figureCheck;
    String? doubted() => figureCheck
        ? AnswerChecks.figureNotice(answer, sources, _t) ??
              ClaimCheckRunner.notice(t.claims, _t)
        : null;
    if (sources.isNotEmpty) {
      // Show grounding notice for spoken turns too so the transcript can
      // display claim check status and source information.
      if (t.matchedCitations) return doubted() ?? _t.noticeCitationsMatched;
      return AnswerChecks.groundingNotice(answer, sources.length, _t) ??
          doubted();
    }
    if (!AnswerChecks.refusal.hasMatch(answer)) return null;
    if (_chatRef.read(settingsProvider).webMode == WebMode.off) {
      return _t.noticeNoSourcesWebOff;
    }
    return _chatState.notice?.isNotEmpty == true
        ? _chatState.notice
        : _t.noticeNoSourcesNoSearch;
  }

  /// Saves the answer over its placeholder row with the record of what
  /// produced it (CHAT-04), or removes the placeholder when nothing came.
  Future<void> _saveAnswer(_Turn t, {String? warning}) async {
    final db = t.db;
    final chatId = t.chatId;
    final resume = t.resume;
    if (!t.accepted ||
        chatId == null ||
        (t.answer.isEmpty && t.thinking.isEmpty)) {
      if (t.placeholderSaved) {
        // Nothing was generated: an empty interrupted row would only confuse.
        try {
          await db.deleteMessage(t.assistantId);
        } catch (e, st) {
          quietFailure('chat_provider:2709', e, st);
        }
      }
      if (t.accepted && !_cancelled && t.failure == null) {
        t.failure = _t.chatErrorNoText;
      }
      return;
    }
    final answer = t.answer.toString();
    final thinking = t.thinking.toString().trim();
    final model = t.model, settings = t.settings;
    final runner = t.runner;
    final budget = t.budget;
    final failed = t.failure != null;
    final msg = ChatMessage(
      id: t.assistantId,
      role: ChatRole.assistant,
      content: answer,
      reasoning: thinking.isEmpty ? null : thinking,
      timestamp: resume?.timestamp ?? DateTime.now(),
      modelId: t.modelId,
      tokenCount: t.metrics?['tokens'] as int?,
      status: t.compareWith != null
          ? failed
                ? 'alternative:error'
                : _cancelled
                ? 'alternative:stopped'
                : 'alternative'
          : failed
          ? 'error'
          : _cancelled
          ? 'stopped'
          : 'complete',
      sourcesJson:
          resume?.sourcesJson ?? jsonEncode(_sourceMaps(t.displayedSources())),
      attachments: [...?resume?.attachments, ...t.generatedImages],
      parentId: t.answerParent,
      // CHAT-04: what produced this answer, for fair comparisons and bug
      // reports. A resumed answer keeps its first run's record.
      runJson:
          resume?.runJson ??
          (model != null && settings != null
              ? TurnRun.capture(
                  settings: settings,
                  preset: _chatRef.read(presetsProvider).active,
                  model: model,
                  metrics: {
                    ...?t.metrics,
                    'lifecycle': t.lease.trace,
                    'contextAudit': t.contextAudit(_fittedOmitted),
                    'memoryUsed': [
                      ...t.usedMemoryNotes
                          .split('\n')
                          .where((s) => s.startsWith('- ')),
                      if (runner != null)
                        for (final result in runner.trace)
                          if (result.call.name == 'recall' && result.ok)
                            ...result.output
                                .split('\n')
                                .where((s) => s.startsWith('- ')),
                    ],
                    if (budget != null) 'operationTokens': budget.usedTokens,
                    'warning': ?warning,
                    if (t.claims.isNotEmpty)
                      'claimCheck': {
                        'sentences': t.claims.length,
                        'flagged': [
                          for (final v in t.claims)
                            if (v.status != ClaimStatus.supported) v.toJson(),
                        ],
                      },
                    'evidenceAudit': EvidenceAudit.check(
                      answer,
                      t.sourceTexts(),
                    ).toJson(),
                  },
                  sources: t.sources.length,
                  origins: t.resolved?.origin ?? const {},
                  toolTrace: t.serverWorkspace
                      ? t.serverToolTrace
                      : runner == null
                      ? const []
                      : [for (final r in runner.trace) r.toJson()],
                ).encode()
              : null),
    );
    try {
      await db.transaction(() async {
        // insertOnConflictUpdate: replaces the placeholder, or creates the
        // row if the placeholder write itself failed.
        await db.insertMessage(
          MessagesCompanion.insert(
            id: msg.id,
            chatId: chatId,
            role: 'assistant',
            content: msg.content,
            reasoning: drift.Value(msg.reasoning),
            timestamp: msg.timestamp,
            sequence: t.sequence + 1,
            status: drift.Value(msg.status),
            sourcesJson: drift.Value(msg.sourcesJson),
            modelId: drift.Value(t.modelId),
            tokenCount: drift.Value(msg.tokenCount),
            parentId: drift.Value(msg.parentId),
            runJson: drift.Value(msg.runJson),
            attachmentsJson: drift.Value(
              jsonEncode([for (final a in msg.attachments) a.toJson()]),
            ),
          ),
        );
        await (db.update(db.chats)..where((c) => c.id.equals(chatId))).write(
          ChatsCompanion(updatedAt: drift.Value(DateTime.now())),
        );
      });
    } catch (e) {
      t.failure = _t.chatErrorSave('$e');
    }
    _chatState = _chatState.copyWith(
      messages: [..._chatState.messages, msg],
      answerSaved: true,
    );
  }

  /// The turn's end on screen: generation off, the metrics, and the one
  /// notice that matters most (stopped, an output limit, grounding,
  /// trimmed context, throttling, the photo or battery notes).
  void _showTurnEnd(
    _Turn t, {
    required String? grounding,
    required List<Memory> learned,
  }) {
    final ok = t.failure == null && !_cancelled;
    final settings = t.settings;
    final budget = t.budget;
    final saverReason = t.saverReason;
    final answer = t.answer.toString();
    final trimmed = t.metrics?['trimmedMessages'] as int? ?? 0;
    final finish = t.metrics?['finishReason'] as String? ?? '';
    String? outputNote;
    if (ok) {
      if (finish == 'length') {
        outputNote = _t.noticeTokenLimit(settings?.maxTokens ?? 0);
      } else if (finish == 'stop') {
        outputNote = _t.noticeStopSequence;
      }
      if (t.researchSkipped && answer.isNotEmpty) {
        outputNote = _t.noticeResearchSkipped;
      }
      if (settings != null && settings.structuredOutput && answer.isNotEmpty) {
        final problem = AnswerChecks.structuredOutputProblem(
          answer,
          settings,
          truncated: finish == 'length',
          t: _t,
        );
        if (problem != null) outputNote = problem;
      }
    }
    final imageNote = t.attachments.any((a) => a.isImage) && !t.vision
        ? (_chatRef.read(settingsProvider).usesRemote
              ? null
              : _chatState.notice)
        : null;
    // A remote server's speed says nothing about the phone's heat (remote
    // probe, 2026-10-18: "Speed dropped 48%" on LM Studio).
    final throttle = ok && t.engine is! RemoteEngine
        ? _throttleNotice(t.engine.metrics)
        : null;
    _chatState = _chatState.copyWith(
      isGenerating: false,
      isLoadingModel: false,
      clearReasoning: true,
      partialAnswer: '',
      answerSaved: false,
      error: t.failure,
      metrics: {
        ...?t.metrics,
        'lifecycle': t.lease.trace,
        'build': BuildIdentity.toJson(),
        'contextAudit': t.contextAudit(_fittedOmitted),
        if (budget != null) 'operationTokens': budget.usedTokens,
        'evidenceAudit': EvidenceAudit.check(answer, t.sourceTexts()).toJson(),
        'stages': {...t.stages, 'generateMs': t.stageClock.elapsedMilliseconds},
        'batterySaver': ?saverReason,
        'queries': ?t.searchQueries,
        if (t.searchQueries != null)
          'searchProviders': [
            _chatRef.read(duckDuckGoScraperProvider).health.toJson(),
          ],
      },
      clearNotice:
          !_cancelled &&
          trimmed == 0 &&
          throttle == null &&
          grounding == null &&
          imageNote == null &&
          saverReason == null &&
          outputNote == null,
      learned: learned,
      notice: _cancelled
          ? _t.noticeStopped
          : outputNote ??
                grounding ??
                (trimmed > 0
                    ? _t.noticeTrimmed(trimmed)
                    : throttle ??
                          imageNote ??
                          (saverReason == null
                              ? null
                              : BatterySaver.notice(saverReason, _t))),
    );
  }

  List<Map<String, Object>> _sourceMaps(List<SearchResult> sources) {
    final out = <Map<String, Object>>[];
    var evidenceNumber = 0;
    for (final source in sources) {
      if (!source.sponsored) evidenceNumber++;
      out.add({
        if (!source.sponsored) 'number': evidenceNumber,
        'title': source.title,
        'url': source.url,
        'snippet': source.snippet,
        'coverage': source.coverage,
        if (source.archiveDate != null) 'archiveDate': source.archiveDate!,
        if (source.archiveId != null) 'archiveId': source.archiveId!,
        if (source.archiveLanguage != null)
          'archiveLanguage': source.archiveLanguage!,
        'retrievalStatus': source.sponsored
            ? 'sponsored_not_used'
            : source.newsItem
            ? 'news_story'
            : source.pageText == null
            ? 'snippet_only'
            : 'page_read',
        if (source.sponsored) 'sponsored': true,
        // Pages a tool read keep their whole text in memory; the stored copy
        // is bounded (large TEXT reads from SQLite are implicated in the
        // release heap corruption).
        if (source.pageText != null)
          'excerpt': source.pageText!.length <= ChatNotifier.storedExcerptChars
              ? source.pageText!
              : '${source.pageText!.substring(0, ChatNotifier.storedExcerptChars)}…',
        if (source.finalUrl != null) 'finalUrl': source.finalUrl!,
        if (source.fetchedAt != null)
          'fetchedAt': source.fetchedAt!.toIso8601String(),
        if (source.publishedAt != null)
          'publishedAt': source.publishedAt!.toIso8601String(),
        if (source.updatedAt != null)
          'updatedAt': source.updatedAt!.toIso8601String(),
        if (source.stale) 'stale': true,
        if (source.readError != null) 'readError': source.readError!,
        if (source.outlet != null) 'outlet': source.outlet!,
        if (source.newsItem) 'newsItem': true,
        if (source.remembered) 'remembered': true,
      });
    }
    return out;
  }
}
