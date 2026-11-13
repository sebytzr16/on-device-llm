part of 'chat_provider.dart';

extension _ChatWebEvidence on ChatNotifier {
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
        _chatState = _chatState.copyWith(notice: _t.noticeEvidenceNoFit);
      }
    }
    return sources;
  }
}
