part of 'chat_provider.dart';

extension _ChatRetrieval on ChatNotifier {
  /// What the turn looks up: the question's own plan, then what a
  /// follow-up adds (pages this chat read, the earlier subject, a new
  /// search). Null when the turn was stopped.
  Future<_Planned?> _planRetrieval(_Turn t, ChatMessage user) async {
    final input = t.input;
    final settings = t.settings!;
    final remoteBrain = t.remoteBrain;
    final webAllowed =
        settings.webSearchEnabled &&
        (!settings.usesRemote || settings.remoteWebResearch);
    var plan = RetrievalPlan.of(
      input,
      // A continuation keeps its original context; no new retrieval. A
      // comparison reuses the original answer's evidence below.
      webEnabled:
          webAllowed &&
          !remoteBrain &&
          t.resume == null &&
          t.reuseSourcesJson == null &&
          t.promptOverride == null,
      // Always searches every message except a greeting, which has no
      // question in it.
      always:
          t.forceResearch ||
          (settings.webMode == WebMode.always &&
              !RetrievalPlan.greetingOnly(input) &&
              !RetrievalPlan.aboutAssistant(input)),
    );
    if (t.reuseSourcesJson case final reused?) {
      final stored = SearchSteps.sourcesFromJson(reused);
      t.sources = stored.where((s) => !s.sponsored).toList();
      t.sponsored = stored.where((s) => s.sponsored).toList();
    }
    // Follow-ups look at what this chat already read before anything else
    // (the page memory): "tell me more about the second story" needs that
    // story's article and "why?" the last answer's evidence — not a web
    // search for the words "second story".
    // A chain of follow-ups keeps the question that named the subject: the
    // third "and the battery?" after "what about its price?" is still about
    // the camera of the first question (report 2026-10-04).
    final previousQuestion = RetrievalPlan.conversationTopic([
      for (final m in _chatState.messages)
        if (m.role == ChatRole.user &&
            ChatNotifier.isLive(m) &&
            m.id != user.id)
          m.content,
    ]);
    final contextual = previousQuestion == null
        ? input
        : RetrievalPlan.withContext(
            input,
            previousQuestion,
            previousAnswer: _lastLiveAssistant?.content,
          );
    t.askedInContext = contextual;
    // "Are you able to do online searches?" is answered about the
    // assistant, not searched (report 2026-10-07).
    final selfQuestion =
        !t.forceResearch &&
        RetrievalPlan.aboutAssistant(
          input,
          afterQuestion: previousQuestion != null,
        );
    if (selfQuestion && plan.mode != RetrievalMode.readUrls) {
      plan = RetrievalPlan(
        mode: RetrievalMode.none,
        urls: const [],
        query: plan.query,
        wantsWeb: false,
      );
    }
    var recalledTurn = false;
    var followUpSearch = false;
    if (!selfQuestion &&
        !remoteBrain &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        !t.isolated &&
        previousQuestion != null &&
        plan.mode != RetrievalMode.readUrls &&
        RetrievalPlan.looksLikeFollowUp(input) &&
        !_cancelled) {
      final recalled = await _recall(
        input,
        previousQuestion: previousQuestion,
        settings: settings,
        webAllowed: webAllowed,
        operationBudget: t.budget,
      );
      if (_cancelled || !_alive) return null;
      t.stage('recallMs');
      if (recalled.isNotEmpty) {
        t.sources = recalled;
        recalledTurn = true;
        t.searchIfLacking = webAllowed;
        plan = RetrievalPlan(
          mode: RetrievalMode.none,
          urls: const [],
          query: contextual,
          wantsWeb: plan.wantsWeb,
        );
        final fresh = recalled.where((s) => !s.remembered).length;
        _chatState = _chatState.copyWith(
          notice: fresh > 0
              ? _t.noticeRecallArticle(recalled.length - fresh)
              : _t.noticeRecallPages(recalled.length),
        );
      } else if (plan.mode == RetrievalMode.search) {
        // Search for what the follow-up is about, not for its pronouns.
        plan = RetrievalPlan(
          mode: plan.mode,
          urls: plan.urls,
          query: contextual,
          wantsWeb: plan.wantsWeb,
        );
      } else if (NewsIntent.of(previousQuestion) != null &&
          NewsIntent.of(contextual) != null &&
          webAllowed) {
        // "What about sports?" after a briefing is still a news question.
        plan = RetrievalPlan.of(contextual, webEnabled: true, always: true);
      } else if (webAllowed &&
          AnswerChecks.asksFact.hasMatch(input) &&
          // "What is 5 times that?" and "What's my name?" are the chat's.
          MathQuestion.expression(input) == null &&
          !AboutUser.asks(input) &&
          !RetrievalPlan.aboutAssistant(input) &&
          !AnswerChecks.notAFact.hasMatch(input) &&
          _chatState.messages.any(
            (m) =>
                m.role == ChatRole.assistant &&
                ChatNotifier.isLive(m) &&
                m.sourcesJson.trim().startsWith('[{') &&
                SearchSteps.sourcesFromJson(
                  m.sourcesJson,
                ).any((s) => !s.sponsored),
          )) {
        // A follow-up in a chat that read the web, which the pages read do
        // not cover, searches again: Gemma 4 E2B guessed "300 to 400 shots"
        // for the Z30's battery (app quality probe, 2026-10-19).
        plan = RetrievalPlan.of(contextual, webEnabled: true, always: true);
        // Shown while it searches (tester, 2026-10-19).
        followUpSearch = plan.mode == RetrievalMode.search;
      }
    }
    return (
      plan: plan,
      contextual: contextual,
      previousQuestion: previousQuestion,
      selfQuestion: selfQuestion,
      recalledTurn: recalledTurn,
      followUpSearch: followUpSearch,
    );
  }

  /// Runs the plan: the judge (a hosted model's "does this need the
  /// web?"), the search itself, and Wikipedia for a stable fact. Null when
  /// the turn was stopped.
  Future<_Found?> _lookUp(_Turn t, _Asked asked, _Planned planned) async {
    final input = t.input;
    final settings = t.settings!;
    final engine = t.engine;
    final model = t.model!;
    final remoteBrain = t.remoteBrain;
    final webAllowed =
        settings.webSearchEnabled &&
        (!settings.usesRemote || settings.remoteWebResearch);
    final user = asked.user;
    var plan = planned.plan;
    // The part of the system prompt every path shares. Built before the
    // judge so the judge's prompt is a prefix-compatible extension of the
    // real turn: the engine then keeps the conversation's KV cache instead
    // of prefilling the whole chat twice (report: search feels slow).
    // The judge gets an ordinary turn's notes, the more common outcome.
    final shared = await _baseSystem(
      input,
      settings: settings,
      preset: asked.preset,
      extraSystem: t.extraSystem,
    );
    t.memoryFacts = shared.facts;
    // Auto: when no keyword fired, let a hosted model judge whether the
    // question needs current or external information. Otherwise a model
    // that was never handed sources truthfully says it cannot browse (tester
    // report). Not on the phone ([TurnPolicy.judgeLocalModels]).
    if (plan.mode == RetrievalMode.none &&
        settings.webMode == WebMode.auto &&
        webAllowed &&
        (settings.usesRemote || TurnPolicy.judgeLocalModels) &&
        !remoteBrain &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        !planned.recalledTurn &&
        !planned.selfQuestion &&
        !RetrievalPlan.smallTalk(input) &&
        !RetrievalPlan.localTask(input) &&
        // The attached file is the source for this turn. Explicit web and
        // timely requests already set plan.mode above and still search.
        !t.attachments.any((a) => !a.isImage) &&
        t.budget == null &&
        !_cancelled) {
      _chatState = _chatState.copyWith(notice: _t.noticeCheckingSearch);
      if (await _needsWeb(
        engine,
        model,
        settings,
        input,
        system: '${shared.system}${shared.notes}',
        // Rendered exactly as the answering turn will render them, so the
        // two prompts share their prefix.
        history: [
          for (final m in _chatState.messages.where(ChatNotifier.isLive))
            if (m.id != user.id)
              TurnPrompts.renderTurn(
                m,
                vision: settings.usesRemote
                    ? settings.remoteVision
                    : engine.metrics['supportsVision'] == true,
                documents: !settings.usesRemote || settings.remoteDocuments,
                documentQuestion: input,
              ),
        ],
      )) {
        plan = RetrievalPlan.of(
          planned.contextual,
          webEnabled: true,
          always: true,
        );
      }
      t.stage('judgeMs');
      if (_cancelled || !_alive) return null;
    }
    // "Where I live", "near me": the place the user named in this chat,
    // not wherever a result page locates the phone.
    if (plan.mode == RetrievalMode.search) {
      final placed = RetrievalPlan.withUserPlace(plan.query, [
        for (final m in _chatState.messages)
          if (m.role == ChatRole.user &&
              ChatNotifier.isLive(m) &&
              m.id != user.id)
            m.content,
      ]);
      if (placed != plan.query) {
        plan = RetrievalPlan(
          mode: plan.mode,
          urls: plan.urls,
          query: placed,
          wantsWeb: plan.wantsWeb,
        );
      }
    }
    final timely = plan.wantsWeb;
    // Model-driven research (overhaul phase 2): a question that would be
    // searched goes to the tool loop instead; pasted links are still read
    // directly. The first round must call a tool.
    final researchTurn =
        settings.researchLoop &&
        settings.toolsEnabled &&
        settings.toolWeb &&
        !settings.structuredOutput &&
        plan.mode == RetrievalMode.search &&
        t.resume == null &&
        t.reuseSourcesJson == null;
    if (researchTurn) {
      plan = RetrievalPlan.of(plan.query, webEnabled: false);
      _chatState = _chatState.copyWith(notice: _t.noticeResearchingTools);
    }
    // One web permission for every way a plan is made (audit P1-05): a
    // Remote profile with web research off fetches nothing.
    if (!webAllowed && plan.mode != RetrievalMode.none) {
      plan = RetrievalPlan.of(plan.query, webEnabled: false);
    }
    if (researchTurn || plan.mode == RetrievalMode.search) {
      t.lease.transition(TurnStage.researching);
    }
    final web = await _gatherWeb(
      plan,
      settings: settings,
      engine: engine,
      model: model,
      sources: t.sources,
      sponsored: t.sponsored,
      timely: timely,
      researchTurn: researchTurn,
      recalledTurn: planned.recalledTurn,
      followUpSearch: planned.followUpSearch,
      stage: t.stage,
      subject: t.subject,
      subjectAllowed: t.subjectAllowed,
      operationBudget: t.budget,
      earlier: planned.contextual == input ? null : planned.previousQuestion,
    );
    if (web == null) return null;
    t.sources = web.sources;
    // Web search off: an imported offline Wikipedia still answers a factual
    // question about a subject it has an article on.
    if (t.sources.isEmpty &&
        !settings.webSearchEnabled &&
        !researchTurn &&
        plan.mode == RetrievalMode.none &&
        t.resume == null &&
        t.attachments.isEmpty &&
        RetrievalPlan.encyclopedic(input)) {
      final article = await _offlineWikipedia(input);
      if (_cancelled || !_alive) return null;
      if (article != null) t.sources = [article];
    }
    // Web search on, nothing searched: a stable fact the phone's small
    // model would answer from memory gets the subject's Wikipedia article
    // (offline archive first). Qwen3.5 0.8B answered "Sydney" for
    // Australia's capital (phone probe, 2026-10-18) and "born in Paris" for
    // Marie Curie (D1 benchmark, 2026-10-11); a remote model decides for
    // itself.
    if (t.sources.isEmpty &&
        AnswerChecks.wikipediaFactCheck(
          input,
          webOn: settings.webSearchEnabled,
          remote: engine is RemoteEngine || remoteBrain,
        ) &&
        !researchTurn &&
        !planned.selfQuestion &&
        !planned.recalledTurn &&
        plan.mode == RetrievalMode.none &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        t.attachments.isEmpty &&
        t.budget == null) {
      _chatState = _chatState.copyWith(notice: _t.noticeCheckingWikipedia);
      final article = await _joinWikipedia(_wikipedia(input, settings));
      t.stage('wikipediaMs');
      if (_cancelled || !_alive) return null;
      if (article != null) t.sources = [article];
      if (_chatState.notice == _t.noticeCheckingWikipedia) {
        _chatState = _chatState.copyWith(clearNotice: true);
      }
    }
    if (plan.mode == RetrievalMode.search) t.searchQueries = web.queries;
    t.sponsored = web.sponsored;
    t.newsAnswer = web.newsTurn;
    if (_cancelled) return null;
    return (
      plan: plan,
      shared: shared,
      timely: timely,
      researchTurn: researchTurn,
      queries: web.queries,
      newsIntent: web.newsIntent,
      newsTurn: web.newsTurn,
    );
  }

  /// A follow-up answered from pages read earlier that say they lack the
  /// answer: searches the web once and answers again from what it finds.
  /// "And how many shots does its battery last?" kept the Z30's Wikipedia
  /// page, which has no battery figure, and Qwen3.5 0.8B said so twice
  /// (app quality probe, 2026-10-20). Nothing found: the first answer stays.
  Future<void> _searchAfterRecall(
    _Turn t,
    _Asked asked,
    _Planned planned,
  ) async {
    if (!t.searchIfLacking ||
        t.failure != null ||
        _cancelled ||
        !_alive ||
        t.echoStopped ||
        t.resume != null) {
      return;
    }
    t.parser?.close();
    final said = t.answer.toString().trim();
    if (said.length > 400 ||
        !(AnswerCleanup.deniesFigure(said, t.input) ||
            ClaimCheck.saysSourcesLack(said))) {
      return;
    }
    final plan = RetrievalPlan.of(
      planned.contextual,
      webEnabled: true,
      always: true,
    );
    if (plan.mode != RetrievalMode.search) return;
    final recalled = t.sources, sponsored = t.sponsored;
    void restore() {
      t.sources = recalled;
      t.sponsored = sponsored;
      t.replaceAnswer(said);
    }

    t.searchIfLacking = false;
    t.clearAnswer();
    t.thinking.write(
      '\n(The pages read earlier lack the answer; searched the web.)\n',
    );
    t.sources = [];
    t.sponsored = [];
    final searched = (
      plan: plan,
      contextual: planned.contextual,
      previousQuestion: planned.previousQuestion,
      selfQuestion: false,
      recalledTurn: false,
      followUpSearch: true,
    );
    final found = await _lookUp(t, asked, searched);
    if (found == null || t.sources.isEmpty || _cancelled || !_alive) {
      if (_alive) restore();
      return;
    }
    final prompt = await _assemblePrompt(t, asked.user, searched, found);
    if (prompt == null || _cancelled || !_alive) {
      if (_alive) restore();
      return;
    }
    t.newParser();
    await _runRounds(t, prompt);
  }
}
