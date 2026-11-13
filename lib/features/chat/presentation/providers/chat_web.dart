part of 'chat_provider.dart';

/// Web retrieval for a turn: instant answers, news desk, search, page reads, recall of earlier pages and the evidence budget.
// Question words a follow-up's evidence need not contain ("how many",
// "combien", "cuántos"): the page that answers says "330 shots".
const _vagueTerms = {
  'many', 'much', 'long', 'often', 'last', 'time', 'combien', 'temp', 'dure', //
  'cuánto', 'cuánta', 'cuántos', 'cuántas', 'dura', 'tiempo',
};

extension _ChatWeb on ChatNotifier {
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
        _chatState = _chatState.copyWith(
          notice: _t.noticeWeatherLoading(place),
        );
        final answer = await _chatRef
            .read(instantAnswersProvider)
            .weather(place, cancelToken: _retrievalCancel);
        if (_cancelled || !_alive) return null;
        if (answer != null) {
          sources = [answer];
          instant = true;
          stage('searchMs');
          _chatState = _chatState.copyWith(notice: _t.noticeWeatherDone(place));
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
      _chatState = _chatState.copyWith(notice: _t.noticeCollectingNews);
      try {
        operationBudget?.useTool();
        final briefing = await _chatRef
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
                  _chatState = _chatState.copyWith(notice: p);
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
          _chatState = _chatState.copyWith(
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
          _chatState = _chatState.copyWith(
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
            } catch (e, st) {
              quietFailure('chat_web:219', e, st);
            }
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
        _chatState = _chatState.copyWith(
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
          _chatState = _chatState.copyWith(
            notice: _t.noticePagesRead(1, 1, ''),
          );
        } else {
          _chatState = _chatState.copyWith(
            notice: direct
                ? _t.noticeLinkUnreadable
                : AnswerChecks.searchFailureNotice(e, _t),
          );
        }
      }
    } else if (timely && !instant && !newsTurn && !recalledTurn) {
      _chatState = _chatState.copyWith(notice: _t.noticeWebOffUnverified);
    }
    return (
      sources: sources,
      sponsored: sponsoredSources,
      queries: queries,
      newsIntent: newsIntent,
      newsTurn: newsTurn,
    );
  }
}
