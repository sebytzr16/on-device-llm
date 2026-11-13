part of 'chat_provider.dart';

extension _ChatWebSources on ChatNotifier {
  /// The knowledge library's embedding model when it is downloaded.
  TextEmbedder? _webEmbedder() =>
      _chatRef.read(modelManagerProvider).embeddingReady
      ? _chatRef.read(textEmbedderProvider)
      : null;

  /// The source-check model when it is downloaded.
  SupportJudge? _supportJudge() =>
      _chatRef.read(modelManagerProvider).supportCheckReady
      ? _chatRef.read(supportJudgeProvider)
      : null;

  /// Wikipedia's article on [query], or null (off-subject, missing, failed):
  /// from the imported ZIM first, then online when that lookup is on.
  Future<SearchResult?> _wikipedia(String query, InferenceSettings settings) =>
      WikipediaSources.lookup(
        onlineAllowed: settings.wikipediaLookup,
        timely: RetrievalPlan.timeSensitive(query),
        online: () async {
          final client = _chatRef.read(wikipediaClientProvider);
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
            (await _chatRef.read(zimWikipediaProvider.future))?.lookup(query),
      );

  /// The imported ZIM's article on [question], or null (no file, no
  /// matching article, a read error).
  Future<SearchResult?> _offlineWikipedia(String question) async {
    try {
      // Opening the archive counts too: a stalled storage lookup must not
      // hold the answer forever.
      final offline = await () async {
        final zim = await _chatRef.read(zimWikipediaProvider.future);
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
    _chatState = _chatState.copyWith(notice: _t.noticeSearchingAgain);
    try {
      found = await _chatRef
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
    final scraper = _chatRef.read(duckDuckGoScraperProvider);
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
    final reader = _chatRef.read(webPageReaderProvider);
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
        _chatState = _chatState.copyWith(
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
        in _chatState.messages
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
      } catch (e, st) {
        quietFailure('chat_web:1079', e, st);
      }
    }
    if (earlier.isEmpty) return const [];
    final reader = _chatRef.read(webPageReaderProvider);
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
      if (_alive) {
        _chatState = _chatState.copyWith(notice: _t.noticeOpeningStory);
      }
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
    final reader = _chatRef.read(webPageReaderProvider);
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
      final found = await _chatRef
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
    } catch (e, st) {
      quietFailure('chat_web:1233', e, st);
    }
    return null;
  }
}
