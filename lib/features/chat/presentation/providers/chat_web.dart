part of 'chat_provider.dart';

/// Web retrieval for a turn: instant answers, news desk, search, page reads, recall of earlier pages and the evidence budget.
// Question words a follow-up's evidence need not contain ("how many",
// "combien", "cuántos"): the page that answers says "330 shots".
const _vagueTerms = {
  'many', 'much', 'long', 'often', 'last', 'time', 'combien', 'temp', 'dure', //
  'cuánto', 'cuánta', 'cuántos', 'cuántas', 'dura', 'tiempo',
};

mixin _ChatWeb on _ChatBase {
  /// The web stage of a turn: an instant answer (weather), the news desk,
  /// or a search with an optional planned query, then the page reads. The
  /// notices along the way are set here. Null when the turn was cancelled.
  Future<
    ({
      List<SearchResult> sources,
      List<SearchResult> sponsored,
      List<String> queries,
      NewsIntent? newsIntent,
      bool newsTurn,
    })?
  >
  _gatherWeb(
    RetrievalPlan plan, {
    required InferenceSettings settings,
    required TextEngine engine,
    required ModelInfo model,
    required List<SearchResult> sources,
    required List<SearchResult> sponsored,
    required bool timely,
    required bool researchTurn,
    required bool recalledTurn,
    required void Function(String) stage,
    bool followUpSearch = false,
    SubjectTerms? subject,
    String subjectAllowed = '',
    TurnBudget? operationBudget,
    String? earlier,
  }) async {
    sources = List.of(sources);
    final lock = subject != null && subject.isNotEmpty ? subject : null;
    String textOf(SearchResult r) =>
        '${r.title}\n${r.snippet}\n${r.pageText ?? ''}';
    var sponsoredSources = List.of(sponsored);
    var queries = <String>[plan.query];
    // Passages are ranked by meaning too when the embedding model is here:
    // load it while the search and page reads are on the network.
    if (plan.mode == RetrievalMode.search) unawaited(_webEmbedder()?.warm());
    // Structured instant answer (weather): one keyless DuckDuckGo call
    // instead of a search plus three page reads of script-heavy weather
    // sites — the difference between ~2 s and a minute on a hosted model.
    var instant = false;
    if (plan.mode == RetrievalMode.search && !_cancelled) {
      final place = InstantAnswers.wantsForecast(plan.query)
          ? InstantAnswers.weatherPlace(plan.query)
          : null;
      if (place != null) {
        operationBudget?.useTool();
        state = state.copyWith(notice: _t.noticeWeatherLoading(place));
        final answer = await ref
            .read(instantAnswersProvider)
            .weather(place, cancelToken: _retrievalCancel);
        if (_cancelled || !_alive) return null;
        if (answer != null) {
          sources = [answer];
          instant = true;
          stage('searchMs');
          state = state.copyWith(notice: _t.noticeWeatherDone(place));
        }
      }
    }
    // News questions: DuckDuckGo's news listing and publisher feeds, in
    // parallel (about a second), instead of a web search that returns
    // front pages and aggregators (report 2026-09-23). The general
    // web search remains the fallback when the briefing comes back empty.
    final newsIntent = plan.mode == RetrievalMode.search && !researchTurn
        ? NewsIntent.of(plan.query)
        : null;
    var newsTurn = false;
    if (newsIntent != null && !_cancelled && !instant) {
      state = state.copyWith(notice: _t.noticeCollectingNews);
      try {
        operationBudget?.useTool();
        final briefing = await ref
            .read(newsDeskProvider)
            .gather(
              newsIntent,
              localeCode: settings.localeCode,
              language: DuckDuckGoScraper.acceptLanguageFor(
                DuckDuckGoScraper.regionFor(settings.localeCode),
              ),
              cancelToken: _retrievalCancel,
              // A phone prefills ~120 and decodes ~25 tokens a second:
              // fewer, better stories and one article keep a briefing
              // under half a minute (a 2.3K-token topic prompt took a
              // minute on the S25+).
              maxItems: settings.usesRemote
                  ? 16
                  : newsIntent.topic == null
                  ? 8
                  : 6,
              maxArticles: settings.usesRemote ? 2 : 1,
              strings: _t,
              progress: (p) {
                if (_alive && !_cancelled) {
                  state = state.copyWith(notice: p);
                }
              },
            );
        if (_cancelled || !_alive) return null;
        if (!briefing.isEmpty) {
          sources = [...briefing.items, ...briefing.articles];
          newsTurn = true;
          final outlets = {
            for (final s in briefing.items)
              (s.outlet ?? s.source ?? '').replaceFirst(
                RegExp(r' \(\+\d+ other outlets?\)$'),
                '',
              ),
          }..remove('');
          state = state.copyWith(
            notice: _t.noticeNewsSummary(
              _t.noticeStoriesCount(briefing.items.length),
              _t.noticeOutletsCount(outlets.length),
              briefing.articles.isEmpty
                  ? ''
                  : ', ${_t.noticeArticlesRead(briefing.articles.length)}',
              (briefing.elapsed.inMilliseconds / 1000).toStringAsFixed(1),
            ),
          );
        }
      } on TurnLimitException {
        rethrow;
      } catch (_) {
        // The general search below still runs.
      }
      stage('newsMs');
    }
    if (plan.mode != RetrievalMode.none &&
        !_cancelled &&
        !instant &&
        !newsTurn) {
      final direct = plan.mode == RetrievalMode.readUrls;
      Future<SearchResult?>? wiki;
      try {
        if (direct) {
          // Pasted links: read them, no search provider involved.
          sources = [
            for (var i = 0; i < plan.urls.length; i++)
              SearchResult(
                title: plan.urls[i].host,
                url: plan.urls[i].toString(),
                snippet: '',
                source: plan.urls[i].host,
                rank: i + 1,
              ),
          ];
        } else {
          // The question itself is searched immediately; a model-written
          // query is prepared at the same time and only used when the first
          // results are thin or when the planner clearly rewrote a
          // conversational question (long input). Overlapping the two
          // saves the planner's ~2 s on most messages.
          state = state.copyWith(
            notice: followUpSearch
                ? _t.noticeFollowUpSearch
                : _t.noticeSearching,
          );
          final wantPlanner =
              operationBudget == null &&
              settings.searchQueryPlanning &&
              (plan.query.split(' ').length > 8 || earlier != null);
          final planned = wantPlanner
              ? _planQueries(
                  engine,
                  model,
                  settings,
                  plan.query,
                  earlier: earlier,
                )
              : Future.value(<String>[plan.query]);
          // A plain local, not `late final`: an uninitialised late local
          // suspended across this await was the prime suspect for the
          // release-only GC crashes of 2026-09-19.
          // Wikipedia's article on the subject is looked up alongside the
          // search and joins the read pages (report 2026-10-04).
          // An imported ZIM answers with no network, even with the online
          // lookup off.
          if (operationBudget == null) {
            wiki = _wikipedia(plan.query, settings);
          }
          List<SearchResult> rawResults = const [];
          try {
            rawResults = await _search(
              [plan.query],
              settings,
              operationBudget: operationBudget,
            );
          } catch (_) {
            // A planner uses the same local engine as the answer. If search
            // fails, cancel and join it before the answer path continues;
            // otherwise an abandoned generation can leave the engine busy.
            if (wantPlanner) {
              engine.cancel();
              await planned;
            }
            rethrow;
          }
          // Results that already cover the question do not wait for the
          // planner: it is cancelled (a hosted model can take seconds to
          // rewrite a query) and joined so the engine is free again.
          if (wantPlanner &&
              rawResults.isNotEmpty &&
              SearchSteps.resultCoverage(plan.query, rawResults) >= 0.6) {
            engine.cancel();
            try {
              await planned;
            } catch (_) {}
            queries = [plan.query];
          } else {
            queries = await planned;
          }
          // A model-written query must not wander to a neighbouring model.
          if (lock != null) {
            queries = [
              for (final q in queries) lock.repair(q, allowed: subjectAllowed),
            ];
          }
          stage('planMs');
          if (_cancelled || !_alive) return null;
          final plannedExtra = queries
              .where((q) => q.toLowerCase() != plan.query.toLowerCase())
              .take(1)
              .toList();
          var extra = <String>[];
          if (plannedExtra.isNotEmpty &&
              (SearchSteps.resultCoverage(plan.query, rawResults) < 0.6 ||
                  SearchSteps.queryTermOverlap(plan.query, plannedExtra.first) <
                      0.5)) {
            extra = plannedExtra;
          }
          // Nothing found and no planner: the question as typed can be a
          // poor query ("What is the …?"); its content terms alone are
          // the second try.
          if (rawResults.isEmpty && extra.isEmpty) {
            final bare = RetrievalPlan.keywords(plan.query);
            if (bare.isNotEmpty &&
                bare.toLowerCase() != plan.query.toLowerCase()) {
              extra = [bare];
            }
          }
          sources = rawResults;
          final primaryExtra = ResearchRecipe.forQuestion(plan.query)
              .primaryQueries(
                plan.query,
                rawResults,
                urlOf: (r) => r.url,
                textOf: (r) => '${r.title} ${r.snippet}',
              );
          extra = {...primaryExtra, ...extra}.take(2).toList();
          if (operationBudget?.remainingTools != null) {
            extra = extra.take(operationBudget!.remainingTools!).toList();
          }
          if (extra.isNotEmpty) {
            sources = await _search(
              [plan.query, ...extra],
              settings,
              seed: rawResults,
              force: true,
              operationBudget: operationBudget,
            );
            queries = [plan.query, ...extra];
          } else {
            queries = [plan.query];
          }
          stage('searchMs');
        }
        if (_cancelled || !_alive) return null;
        if (!direct) {
          sponsoredSources = sources.where((s) => s.sponsored).toList();
          sources = sources.where((s) => !s.sponsored).toList();
          // Best candidates first, so the read budget goes to pages that
          // are about the question and can actually be read.
          sources = EvidenceRanker.rankResults<SearchResult>(
            plan.query,
            sources,
            titleOf: (r) => r.title,
            snippetOf: (r) => r.snippet,
            urlOf: (r) => r.url,
            // Time-sensitive wording: dated, recent results first.
            recent: RetrievalPlan.timeSensitive(plan.query),
          );
          sources = ResearchRecipe.forQuestion(plan.query).order(
            sources,
            plan.query,
            urlOf: (r) => r.url,
            textOf: (r) => '${r.title} ${r.snippet}',
          );
          // The read budget goes to pages about the subject: results about
          // a neighbouring model are dropped, those naming it read first.
          if (lock != null) {
            sources = lock.focus(
              sources,
              textOf,
              allowed: subjectAllowed,
              enough: settings.maxPagesRead + 2,
            );
          }
        }
        sources = await _readPages(
          sources,
          limit: direct ? plan.urls.length : settings.maxPagesRead,
          budget: Duration(seconds: settings.researchTimeBudgetSeconds),
          // Pasted links are read as given; search candidates that fail
          // are skipped for the next one.
          spare: direct ? 0 : 3,
          // Search stops early once two read pages cover the question.
          coverQuery: direct ? null : plan.query,
          language: DuckDuckGoScraper.acceptLanguageFor(
            DuckDuckGoScraper.regionFor(settings.localeCode),
          ),
          operationBudget: operationBudget,
        );
        stage('readMs');
        if (_cancelled || !_alive) return null;
        if (!direct) {
          sources = SearchSteps.withArticle(
            sources,
            await _joinWikipedia(wiki),
          );
          // Search again (report 2026-10-04): when the pages leave
          // words of the question unanswered, one more query for those
          // words and up to two more pages.
          if (settings.searchAgain && operationBudget == null) {
            sources = await _searchAgain(plan.query, sources, settings, lock);
            stage('searchAgainMs');
            if (_cancelled || !_alive) return null;
          }
        }
        // With the pages read: a page about another model goes, and pages
        // that never name the subject go once two pages do.
        if (lock != null && !direct) {
          sources = lock.focus(sources, textOf, allowed: subjectAllowed);
        }
        final read = sources.where((s) => s.pageText != null).length;
        if (direct) {
          // A link that could not be read has nothing to offer the model.
          sources.removeWhere((s) => s.pageText == null);
        }
        state = state.copyWith(
          notice: sources.isEmpty
              ? direct
                    ? _t.noticeLinkUnreadable
                    : _t.noticeNoWebResults
              : direct
              ? _t.noticeLinkedRead(read, plan.urls.length)
              : _t.noticePagesRead(
                  read,
                  sources.length,
                  queries.length > 1 ? _t.noticeQueries(queries.length) : '',
                ),
        );
      } on TurnLimitException {
        rethrow;
      } catch (e) {
        // Both engines failed: Wikipedia's article, when it came back, is
        // still a source.
        final article = direct ? null : await _joinWikipedia(wiki);
        if (_cancelled || !_alive) return null;
        if (article != null) {
          sources = [article];
          state = state.copyWith(notice: _t.noticePagesRead(1, 1, ''));
        } else {
          state = state.copyWith(
            notice: direct
                ? _t.noticeLinkUnreadable
                : AnswerChecks.searchFailureNotice(e, _t),
          );
        }
      }
    } else if (timely && !instant && !newsTurn && !recalledTurn) {
      state = state.copyWith(notice: _t.noticeWebOffUnverified);
    }
    return (
      sources: sources,
      sponsored: sponsoredSources,
      queries: queries,
      newsIntent: newsIntent,
      newsTurn: newsTurn,
    );
  }

  /// The knowledge library's embedding model when it is downloaded.
  TextEmbedder? _webEmbedder() => ref.read(modelManagerProvider).embeddingReady
      ? ref.read(textEmbedderProvider)
      : null;

  /// The source-check model when it is downloaded.
  SupportJudge? _supportJudge() =>
      ref.read(modelManagerProvider).supportCheckReady
      ? ref.read(supportJudgeProvider)
      : null;

  /// Wikipedia's article on [query], or null (off-subject, missing, failed):
  /// from the imported ZIM first, then online when that lookup is on.
  Future<SearchResult?> _wikipedia(String query, InferenceSettings settings) =>
      WikipediaSources.lookup(
        onlineAllowed: settings.wikipediaLookup,
        timely: RetrievalPlan.timeSensitive(query),
        online: () async {
          final client = ref.read(wikipediaClientProvider);
          final language = WikipediaClient.languageFor(
            query,
            settings.localeCode,
          );
          final found = await client.lookup(
            query,
            language: language,
            cancelToken: _retrievalCancel,
          );
          // A request buries the article: "Can you please tell me how old is
          // Justin Bieber" finds none, "old Justin Bieber" finds it (D1
          // benchmark, 2026-10-11).
          final bare = RetrievalPlan.keywords(query);
          if (found != null ||
              bare.isEmpty ||
              bare.toLowerCase() == query.trim().toLowerCase()) {
            return found;
          }
          return client.lookup(
            bare,
            language: language,
            cancelToken: _retrievalCancel,
          );
        },
        offline: () async =>
            (await ref.read(zimWikipediaProvider.future))?.lookup(query),
      );

  /// The imported ZIM's article on [question], or null (no file, no
  /// matching article, a read error).
  Future<SearchResult?> _offlineWikipedia(String question) async {
    try {
      // Opening the archive counts too: a stalled storage lookup must not
      // hold the answer forever.
      final offline = await () async {
        final zim = await ref.read(zimWikipediaProvider.future);
        return zim?.lookup(question);
      }().timeout(const Duration(seconds: 8), onTimeout: () => null);
      return offline?.withPage(stale: RetrievalPlan.timeSensitive(question));
    } catch (_) {
      return null;
    }
  }

  /// Waits a little for a lookup that is still running; a slow Wikipedia
  /// never holds up the answer.
  Future<SearchResult?> _joinWikipedia(Future<SearchResult?>? wiki) async {
    if (wiki == null || _cancelled) return null;
    try {
      return await wiki.timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  /// One more query when the pages read leave words of [question]
  /// unanswered: the subject plus the missing words ("nikon z30" +
  /// "weight"). Nothing is searched when no narrower query can be written.
  /// Up to two new pages are read.
  Future<List<SearchResult>> _searchAgain(
    String question,
    List<SearchResult> sources,
    InferenceSettings settings,
    SubjectTerms? lock,
  ) async {
    final texts = [
      for (final s in sources)
        if (s.pageText != null) s.pageText!,
    ];
    final asked = EvidenceRanker.terms(question).toSet();
    final missing = EvidenceRanker.missingWords(question, texts);
    if (missing.isEmpty || asked.length < 2) return sources;
    final subject = (lock ?? SubjectTerms.of(question)).terms;
    final query =
        PrimaryDiscovery.query(question, missing, subject: subject) ??
        SearchSteps.searchAgainQuery(
          question,
          missing,
          // Without a research lock, the names the question itself uses.
          subject: subject,
        );
    if (query == null) return sources;
    List<SearchResult> found;
    state = state.copyWith(notice: _t.noticeSearchingAgain);
    try {
      found = await ref
          .read(duckDuckGoScraperProvider)
          .search(
            query,
            limit: settings.maxSearchResults,
            cancelToken: _retrievalCancel,
            localeCode: settings.localeCode,
            dateFilter: RetrievalPlan.searchDateFilter(question),
          );
    } catch (_) {
      return sources;
    }
    if (_cancelled || found.isEmpty) return sources;
    final tried = {
      for (final s in sources) ...[
        SearchSteps.urlKey(s.url),
        if (s.finalUrl != null) SearchSteps.urlKey(s.finalUrl!),
      ],
    };
    var fresh = [
      for (final r in found)
        if (!r.sponsored && !tried.contains(SearchSteps.urlKey(r.url))) r,
    ];
    fresh = EvidenceRanker.rankResults<SearchResult>(
      question,
      fresh,
      titleOf: (r) => r.title,
      snippetOf: (r) => r.snippet,
      urlOf: (r) => r.url,
      recent: RetrievalPlan.timeSensitive(question),
    );
    if (lock != null) {
      fresh = lock.focus(fresh, (r) => '${r.title}\n${r.snippet}', enough: 4);
    }
    if (fresh.isEmpty || _cancelled) return sources;
    final more = await _readPages(
      fresh.take(4).toList(),
      limit: 2,
      spare: 2,
      budget: const Duration(seconds: 10),
      language: DuckDuckGoScraper.acceptLanguageFor(
        DuckDuckGoScraper.regionFor(settings.localeCode),
      ),
    );
    // Only pages that answer something the first pages did not.
    final added = [
      for (final r in more)
        if (r.pageText != null &&
            EvidenceRanker.missingWords(missing.join(' '), [
                  r.pageText!,
                ]).length <
                missing.length)
          r,
    ];
    if (added.isEmpty) return sources;
    return SearchSteps.withExtraPages(sources, added);
  }

  /// Puts the evidence into the last message: a comparison's stored
  /// excerpts verbatim, otherwise the passages that best answer the
  /// question, dropped weakest first until the prompt fits the context.
  /// Returns the sources that made it in; null when cancelled.
  Future<List<SearchResult>?> _fitEvidence(
    String input,
    List<Map<String, Object>> messages, {
    required String system,
    required List<SearchResult> sources,
    required RetrievalPlan plan,
    required List<String> queries,
    required InferenceSettings settings,
    required TextEngine engine,
    required ModelInfo model,
    required bool newsTurn,
    required NewsIntent? newsIntent,
    required bool recalledTurn,
    required bool comparison,
    required bool overridden,
    required String prefix,
  }) async {
    sources = List.of(sources);
    final shape = _spoken
        ? AnswerShape.spoken
        : AnswerShapes.of(input, news: newsTurn ? newsIntent : null);
    final local = !settings.usesRemote;
    // On the phone the note goes with the evidence, not into the system
    // prompt: a system prompt that changes for one turn makes the next turn
    // read the whole conversation again (phone, 2026-10-08: 1412 tokens,
    // 16 s before the first word of the turn after a search).
    var noted = '';
    void note(String text) {
      final line = '${TurnPrompts.clockLine()} $text';
      if (local) {
        noted = '$line\n\n';
      } else {
        messages.first['content'] = '${system.toString()}\n$line';
      }
    }

    if (sources.isNotEmpty && comparison) {
      // Comparison: the stored excerpts are the evidence, verbatim.
      note(
        'The user message contains web evidence with retrieval times; answer from it and cite source numbers like [1].',
      );
      messages.last['content'] =
          noted +
          TurnPrompts.evidencePrompt(
            sources,
            messages.last['content'] as String,
            timely: RetrievalPlan.timeSensitive(plan.query),
            shape: AnswerShapes.of(input, news: NewsIntent.of(input)),
            topic: NewsIntent.of(input)?.topic,
            local: local,
          );
    } else if (sources.isNotEmpty && !overridden) {
      // Keep the system prompt short here: some templates (Gemma) have no
      // system role and fold it into the first user turn, far from the
      // evidence. The working instructions travel with the evidence.
      note(
        'The user message contains ${newsTurn ? 'news stories' : 'web evidence'} with retrieval times; answer from it and cite source numbers like [1]. Keep any reasoning brief: pick what answers the question, then answer.',
      );
      final lastTurn = messages.last['content'] as String;
      // A spoken answer from sources reads no earlier answers: Qwen3.5 0.8B
      // answered "how old is Justin Bieber?" with its previous answer word
      // for word, sources and all (tester, 2026-10-09, twice). The earlier
      // question stays as a line, so a follow-up keeps its subject.
      if (_spoken && local) {
        final earlier = ContextUse.dropEarlierExchanges(messages);
        if (earlier != null) {
          // Marked as the user's and as background: the 0.8B answered
          // "how old is Justin Bieber?" with "I am Justin Bieber… I live
          // in London" after the user said they live there (phone probe
          // round 3, 2026-10-18).
          noted =
              '${noted}Earlier in this conversation the user said (their '
              'words, not yours; use them only if this question needs '
              'them): $earlier\n\n';
        }
      }
      // A follow-up about one story ranks that story's article by its
      // headline as well as by the (pronoun-heavy) follow-up itself.
      final rankingQuery = recalledTurn && !sources.first.remembered
          ? '${sources.take(2).map((s) => s.title).join(' ')} $input'
          : plan.query;
      // News stories already carry most of the evidence: articles add a
      // few passages, not a page's worth. A spoken answer is one to three
      // sentences: reading six passages first cost the phone 5 to 11 s
      // before the first word (conversation probe, 2026-10-08).
      final passages = (newsTurn || _spoken) && local
          ? min(3, TurnPolicy.passageBudget(settings))
          : TurnPolicy.passageBudget(settings);
      // News listings are short and were chosen story by story: they go in
      // whole. Pages are cut into passages ranked against the question.
      var selected = await SemanticRerank.rank(
        rankingQuery,
        [
          for (var i = 0; i < sources.length; i++)
            if (sources[i].pageText != null && !sources[i].newsItem)
              ...EvidenceRanker.chunk(sources[i].pageText!, sourceIndex: i),
        ],
        maxChunks: passages,
        perSource: (passages / 3).ceil().clamp(2, 6),
        extraQueries: [
          ...queries.where((q) => q != plan.query),
          // An age question is answered by the passage with the birth
          // date, not by the one that repeats the name most (a Wikipedia
          // controversy paragraph was chosen for "how old is …").
          if (LifeDates.asksAge(input)) 'born birth date birthday age',
        ],
        titles: {for (var i = 0; i < sources.length; i++) i: sources[i].title},
        embedder: _webEmbedder(),
      );
      if (SemanticRerank.trimShare != null) {
        selected = await SemanticRerank.trimSentences(
          rankingQuery,
          selected,
          embedder: _webEmbedder(),
        );
      }
      if (_cancelled || !_alive) return null;
      List<SearchResult> withExcerpts() => [
        for (var i = 0; i < sources.length; i++)
          if (sources[i].pageText == null || sources[i].newsItem)
            sources[i]
          else
            sources[i].withPage(
              text: EvidenceRanker.excerpt(selected, i),
              finalUrl: sources[i].finalUrl,
              fetchedAt: sources[i].fetchedAt,
              error: sources[i].readError,
              publishedAt: sources[i].publishedAt,
              stale: sources[i].stale,
            ),
      ];
      while (sources.isNotEmpty) {
        // Search snippets are discovery hints, not inspected evidence.
        // Once a page was read, only its retained passages may be cited.
        // If every read failed, keep up to three snippets as a clearly
        // labelled fallback rather than claim that nothing was found.
        final excerpts = withExcerpts();
        final readEvidence = excerpts
            .where((s) => s.pageText?.isNotEmpty == true)
            .toList();
        final candidates =
            readEvidence.isNotEmpty || sources.any((s) => s.pageText != null)
            ? readEvidence
            : excerpts.where((s) => s.pageText == null).take(3).toList();
        if (candidates.isEmpty) {
          sources = [];
          break;
        }
        messages.last['content'] =
            noted +
            TurnPrompts.evidencePrompt(
              candidates,
              lastTurn,
              timely: RetrievalPlan.timeSensitive(plan.query),
              shape: shape,
              topic: newsIntent?.topic,
              local: local,
            );
        final budget = await engine.previewPrompt(
          messages: messages,
          fallbackTemplate: model.family.fallbackTemplate,
          settings: settings,
          assistantPrefix: prefix,
        );
        if (_cancelled || !_alive) return null;
        if (budget['fits'] == true) {
          sources = candidates;
          break;
        }
        // Turns older than the last three go first, then the weakest
        // passages down to four, then all but the last exchange, then
        // passages down to two, and only then the last exchange: a
        // follow-up must still know what the conversation is about.
        var omitted = ContextUse.omitOldestExchange(messages, keep: 3);
        if (omitted == 0 && selected.length <= 4) {
          omitted = ContextUse.omitOldestExchange(messages, keep: 1);
        }
        if (omitted == 0 && selected.length <= 2) {
          omitted = ContextUse.omitOldestExchange(messages);
        }
        if (omitted > 0) {
          _fittedOmitted += omitted;
          continue;
        }
        if (selected.isNotEmpty) {
          // Lowest-ranked passage goes first.
          final weakest = selected.reduce((a, b) => b.score < a.score ? b : a);
          selected = selected.where((c) => c != weakest).toList();
        } else {
          // Then the least important story (stories are ranked).
          final lastStory = sources.lastIndexWhere((s) => s.newsItem);
          if (lastStory >= 0) {
            sources.removeAt(lastStory);
          } else {
            sources.removeLast();
          }
        }
      }
      if (sources.isEmpty) {
        messages.last['content'] = lastTurn;
        messages.first['content'] =
            '${system.toString()}\nWeb evidence could not fit in context; current facts are unverified.';
        state = state.copyWith(notice: _t.noticeEvidenceNoFit);
      }
    }
    return sources;
  }

  /// The web judge asks the model the yes/no question at the end of the
  /// real conversation with the real system prompt, so its prompt shares
  /// the resident KV prefix and the answering turn reuses it; a separate
  /// judge prompt evicted the whole chat and cost a second full prefill.
  ///
  /// The verdict has a deadline ([TurnPolicy.judgeDeadline], longer on
  /// the phone: [TurnPolicy.localJudgeDeadline]): a hosted thinking model
  /// that reasons for half a minute before its one word (report,
  /// Gemini) is cancelled and counted as "no"; timely wording still
  /// searches through the keyword rules.
  Future<bool> _needsWeb(
    TextEngine engine,
    ModelInfo model,
    InferenceSettings settings,
    String question, {
    String system = '',
    List<Map<String, Object>> history = const [],
  }) async {
    Future<String>? pending;
    try {
      pending = engine
          .generate(
            messages: [
              {
                'role': 'system',
                'content': system.isEmpty
                    ? 'You decide whether a question needs information from the internet. Answer with exactly one word: yes or no.'
                    : system,
              },
              ...history,
              {
                'role': 'user',
                'content':
                    '$question\n\n(Before answering, decide only this: today is ${TurnPrompts.today()}. Would answering the message above well require looking something up on the internet — because it depends on recent events, a current price, version, schedule or office holder, a specific product, web page or document, or facts you may not know reliably? Answer no for greetings, small talk, general knowledge, definitions, history, science, writing, translation, code and maths. Reply with exactly one word, yes or no.)',
              },
            ],
            fallbackTemplate: model.family.fallbackTemplate,
            settings: settings.copyWith(
              maxTokens: 8,
              temperature: 0,
              thinkingModeEnabled: false,
            ),
          )
          .join();
      final raw = await pending.timeout(
        settings.usesRemote
            ? TurnPolicy.judgeDeadline
            : TurnPolicy.localJudgeDeadline,
      );
      return SearchSteps.parseYes(raw);
    } on TimeoutException {
      // Stop the judge and let it settle so the engine is free for the turn.
      engine.cancel();
      await pending?.catchError((_) => '');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the local model for one or two search-engine queries. Falls back
  /// to the question itself whenever the output is unusable.
  Future<List<String>> _planQueries(
    TextEngine engine,
    ModelInfo model,
    InferenceSettings settings,
    String question, {
    String? earlier,
  }) async {
    try {
      final raw = await engine
          .generate(
            messages: [
              {
                'role': 'system',
                'content':
                    'You turn questions into web search queries. Reply with the queries only, one per line.',
              },
              {
                'role': 'user',
                'content':
                    'Today is ${TurnPrompts.today()}.\n${earlier == null ? '' : 'Earlier in this conversation the user asked: $earlier\nThe new question continues that conversation: each query must name its subject.\n'}Question: $question\n\nWrite 1 or 2 short search-engine queries that would find the answer. One per line. No numbering, no quotes, no explanation.',
              },
            ],
            fallbackTemplate: model.family.fallbackTemplate,
            settings: settings.copyWith(
              maxTokens: 48,
              temperature: 0,
              thinkingModeEnabled: false,
            ),
          )
          .join();
      return SearchSteps.parseQueries(raw, fallback: question);
    } catch (_) {
      return [question];
    }
  }

  /// Runs each query and merges the results by URL, interleaving ranks so
  /// both queries contribute to the top of the list.
  Future<List<SearchResult>> _search(
    List<String> queries,
    InferenceSettings settings, {
    List<SearchResult>? seed,
    bool force = false,
    TurnBudget? operationBudget,
  }) async {
    final scraper = ref.read(duckDuckGoScraperProvider);
    final lists = <List<SearchResult>>[];
    if (seed != null) lists.add(seed);
    for (final q in seed == null ? queries : queries.skip(1)) {
      if (_cancelled) break;
      // A second query only when the first was thin, unless [force]: fewer
      // requests keep the provider from serving a bot check (observed after
      // ~4 quick calls).
      if (!force && lists.isNotEmpty && lists.first.length >= 4) break;
      if (lists.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      if (_cancelled) break;
      operationBudget?.useTool();
      try {
        lists.add(
          await scraper.search(
            q,
            limit: settings.maxSearchResults,
            cancelToken: _retrievalCancel,
            localeCode: settings.localeCode,
            dateFilter: RetrievalPlan.searchDateFilter(q),
          ),
        );
      } catch (e) {
        if (lists.isEmpty && q == queries.last) rethrow;
      }
    }
    // Merge by normalised URL. A sponsored row that unwraps to the same URL
    // as an organic one is never read, so the organic copy wins the slot even
    // when the ad sat higher.
    final slot = <String, int>{};
    final merged = <SearchResult>[];
    final longest = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < longest; i++) {
      for (final l in lists) {
        if (i >= l.length) continue;
        final key = l[i].url
            .replaceFirst(RegExp(r'^https?://(www\.)?'), '')
            .replaceFirst(RegExp(r'/+$'), '')
            .toLowerCase();
        final at = slot[key];
        if (at == null) {
          slot[key] = merged.length;
          merged.add(l[i]);
        } else if (merged[at].sponsored && !l[i].sponsored) {
          merged[at] = l[i];
        }
      }
    }
    return [
      for (var i = 0; i < merged.length; i++)
        SearchResult(
          title: merged[i].title,
          url: merged[i].url,
          snippet: merged[i].snippet,
          source: merged[i].source,
          rank: i + 1,
          sponsored: merged[i].sponsored,
        ),
    ];
  }

  /// Reads candidates three at a time until [limit] pages have yielded text,
  /// trying at most [limit] + [spare] of them, within one wall-clock
  /// [budget] (12 s per page). Failures are recorded per source, not thrown.
  Future<List<SearchResult>> _readPages(
    List<SearchResult> sources, {
    required int limit,
    Duration budget = const Duration(seconds: 25),
    int spare = 3,
    String? coverQuery,
    required String language,
    TurnBudget? operationBudget,
  }) async {
    final sponsored = sources.where((s) => s.sponsored).toList();
    sources = sources.where((s) => !s.sponsored).toList();
    final reader = ref.read(webPageReaderProvider);
    final reading = Stopwatch()..start();
    // Hosts that never yield text to a plain client (bot walls, paywalls,
    // script-only mirrors) keep their snippet but cost no read attempt: a
    // pasted link is still tried, since the user asked for that page.
    final readable = [
      for (var i = 0; i < sources.length; i++)
        if (coverQuery == null || !SourceQuality.unreadable(sources[i].url)) i,
    ];
    final attempts = (limit + spare).clamp(0, readable.length);
    var next = 0, read = 0;
    Future<void> readOne(int slot) async {
      final i = readable[slot];
      if (_cancelled || reading.elapsed >= budget) return;
      if (operationBudget != null && !operationBudget.useRead()) return;
      if (_alive) {
        final host = SourceQuality.hostOf(sources[i].url);
        state = state.copyWith(
          notice: _t.noticeReadingPage(
            min(read + 1, limit),
            limit,
            host.isEmpty ? '' : ' · $host',
          ),
        );
      }
      try {
        final remaining = (budget - reading.elapsed).inMilliseconds.clamp(
          1,
          8000,
        );
        final page = await reader.read(
          Uri.parse(sources[i].url),
          cancelToken: _retrievalCancel,
          timeout: Duration(milliseconds: remaining),
          language: language,
        );
        sources[i] = sources[i].withPage(
          text: page.text,
          finalUrl: page.finalUri.toString(),
          fetchedAt: page.fetchedAt,
          publishedAt: page.publishedAt,
          updatedAt: page.updatedAt,
        );
        read++;
      } catch (e) {
        sources[i] = sources[i].withPage(error: '$e');
      }
    }

    bool covered() =>
        coverQuery != null &&
        read >= 2 &&
        EvidenceRanker.covers(coverQuery, [
          for (final s in sources)
            if (s.pageText != null) s.pageText!,
        ]);

    // Two promising pages get a brief head start. When both return quickly
    // and cover the question, a third fetch and its prompt tokens are saved.
    // Otherwise hedge with page three after 350 ms so a slow site cannot
    // hold up the answer. Pasted URLs still read together as requested.
    const wave = 3;
    while (next < attempts &&
        read < limit &&
        !_cancelled &&
        reading.elapsed < budget) {
      if (covered()) break;
      final batchSize = min(wave, min(limit - read, attempts - next));
      if (next == 0 && coverQuery != null && batchSize == 3) {
        final first = Future.wait([readOne(next), readOne(next + 1)]);
        next += 2;
        final bothFinished = await Future.any([
          first.then((_) => true),
          Future.delayed(const Duration(milliseconds: 350), () => false),
        ]);
        if (bothFinished && covered()) break;
        final third = readOne(next++);
        await Future.wait([first, third]);
        continue;
      }
      final batch = List<int>.generate(batchSize, (offset) => next + offset);
      next += batchSize;
      await Future.wait(batch.map(readOne));
    }
    // Read pages first, then the untried and failed candidates, so the
    // source numbers the model cites start with the pages it was given;
    // within each group the ranked order stands.
    final order = [
      ...sources.where((s) => s.pageText != null),
      ...sources.where((s) => s.pageText == null),
    ];
    return [...order, ...sponsored];
  }

  /// Evidence for a follow-up from what this chat already read: the story
  /// or source it points at ("the second story" → that story's article,
  /// read now when only its listing was seen), or the earlier pages whose
  /// passages match it ("why?" and "tell me more" get the same evidence
  /// again). Pages still in the reader's memory come back whole; older
  /// ones as the excerpts stored with the answer. Empty when nothing
  /// earlier fits, and the turn searches as usual.
  Future<List<SearchResult>> _recall(
    String input, {
    required String previousQuestion,
    required InferenceSettings settings,
    required bool webAllowed,
    TurnBudget? operationBudget,
  }) async {
    var earlier = const <SearchResult>[];
    for (final a
        in state.messages
            .where(
              (m) => m.role == ChatRole.assistant && ChatNotifier.isLive(m),
            )
            .toList()
            .reversed) {
      try {
        final list = SearchSteps.sourcesFromJson(
          a.sourcesJson,
        ).where((s) => !s.sponsored).toList();
        if (list.isNotEmpty) {
          earlier = list;
          break;
        }
      } catch (_) {}
    }
    if (earlier.isEmpty) return const [];
    final reader = ref.read(webPageReaderProvider);
    SearchResult whole(SearchResult s) {
      if (s.newsItem) return s.withPage(remembered: true);
      WebPage? page;
      for (final url in [s.finalUrl, s.url]) {
        final uri = url == null ? null : Uri.tryParse(url);
        if (uri != null && uri.hasScheme) page ??= reader.remembered(uri);
      }
      return page == null
          ? s.withPage(remembered: true)
          : s.withPage(
              text: page.text,
              fetchedAt: page.fetchedAt,
              remembered: true,
            );
    }

    final pointed = RetrievalPlan.referencedItem(input);
    if (pointed != null) {
      final index = pointed == -1 ? earlier.length - 1 : pointed - 1;
      if (index < 0 || index >= earlier.length) return const [];
      final focus = earlier[index];
      if (!focus.newsItem) return [whole(focus)];
      // A story seen only as a listing: its article is what "more" means.
      if (!webAllowed) return [whole(focus)];
      if (_alive) state = state.copyWith(notice: _t.noticeOpeningStory);
      final article = await _articleFor(
        focus,
        settings,
        operationBudget: operationBudget,
      );
      // Opened from its own link, the article replaces the listing.
      return [
        ?article,
        if (article == null ||
            SourceQuality.hostOf(article.url) + Uri.parse(article.url).path !=
                SourceQuality.hostOf(focus.url) + Uri.parse(focus.url).path)
          whole(focus),
      ];
    }
    final pages = [
      for (final s in earlier) whole(s),
    ].where((s) => (s.pageText ?? '').isNotEmpty).toList();
    if (pages.isEmpty) return const [];
    final asks = EvidenceRanker.terms(input).toSet();
    if (asks.isEmpty) return pages.take(6).toList();
    final chunks = [
      for (var i = 0; i < pages.length; i++)
        ...EvidenceRanker.chunk(pages[i].pageText!, sourceIndex: i),
    ];
    final ranked = EvidenceRanker.rank(
      '$input ${RetrievalPlan.keywords(previousQuestion)}',
      chunks,
      perSource: 3,
      maxChunks: 8,
    );
    // Only pages with a passage that has the follow-up's own words: one
    // word in common is not enough ("how many shots does its battery last?"
    // matched a page about battery and recording time, and the answer said
    // the sources had no shot count). Otherwise the turn searches again.
    final need = asks.difference(_vagueTerms);
    final key = need.isEmpty ? asks : need;
    final enough = key.length <= 2 ? key.length : (key.length * 2 / 3).ceil();
    final hits = {
      for (final c in ranked)
        if (c.score > 0 &&
            EvidenceRanker.terms(c.text).toSet().intersection(key).length >=
                enough)
          c.sourceIndex,
    };
    return [
      for (var i = 0; i < pages.length; i++)
        if (hits.contains(i)) pages[i],
    ];
  }

  /// The readable article behind a news story: the story's own link when
  /// the publisher's page can be read, otherwise the best readable search
  /// result for its headline (syndication mirrors are script shells).
  Future<SearchResult?> _articleFor(
    SearchResult story,
    InferenceSettings settings, {
    TurnBudget? operationBudget,
  }) async {
    final reader = ref.read(webPageReaderProvider);
    final language = DuckDuckGoScraper.acceptLanguageFor(
      DuckDuckGoScraper.regionFor(settings.localeCode),
    );
    Future<SearchResult?> open(String url, {String? title}) async {
      if (operationBudget != null && !operationBudget.useRead()) return null;
      try {
        final page = await reader.read(
          Uri.parse(url),
          cancelToken: _retrievalCancel,
          timeout: const Duration(seconds: 6),
          language: language,
        );
        return SearchResult(
          title: page.title.isEmpty ? (title ?? story.title) : page.title,
          url: url,
          snippet: story.snippet,
          source: Uri.tryParse(url)?.host,
          rank: 0,
          pageText: page.text,
          finalUrl: page.finalUri.toString(),
          fetchedAt: page.fetchedAt,
          publishedAt: page.publishedAt ?? story.publishedAt,
          updatedAt: page.updatedAt,
          outlet: SourceQuality.outletOf(url)?.name,
        );
      } catch (_) {
        return null;
      }
    }

    if (!SourceQuality.unreadable(story.url)) {
      final direct = await open(story.url);
      if (direct != null) return direct;
    }
    try {
      operationBudget?.useTool();
      final found = await ref
          .read(duckDuckGoScraperProvider)
          .search(
            story.title,
            limit: 6,
            cancelToken: _retrievalCancel,
            localeCode: settings.localeCode,
            dateFilter: 'w',
          );
      final ranked = EvidenceRanker.rankResults<SearchResult>(
        story.title,
        found
            .where(
              (r) =>
                  !r.sponsored &&
                  !SourceQuality.unreadable(r.url) &&
                  !SourceQuality.lowValue(r.url),
            )
            .toList(),
        titleOf: (r) => r.title,
        snippetOf: (r) => r.snippet,
        urlOf: (r) => r.url,
        recent: true,
      );
      for (final r in ranked.take(2)) {
        final page = await open(r.url, title: r.title);
        if (page != null) return page;
      }
    } on TurnLimitException {
      rethrow;
    } catch (_) {}
    return null;
  }
}
