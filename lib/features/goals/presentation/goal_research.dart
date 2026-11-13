part of 'goal_provider.dart';

/// Research turns and their evidence checks.
extension _GoalResearch on GoalNotifier {
  /// One research step: the step's question goes to the chat as it is (a
  /// clean search query), researched even when Auto would not search, with
  /// the goal and its rules as a hidden instruction and without the earlier
  /// steps in the prompt. The answer is checked (subject, citations,
  /// figures, requests to the user); one that researched another model or
  /// asked the user is researched once more with what to fix.
  Future<GoalStepResult> _research(
    GoalSpec spec,
    GoalTask task,
    GoalProgress progress,
  ) async {
    final number = progress.tasks.indexOf(task) + 1;
    final subject = spec.subject;
    GoalStepResult? first;
    var tokens = 0, calls = 0;
    final elapsed = Stopwatch()..start();
    for (var attempt = 1; attempt <= 2; attempt++) {
      if ((spec.maxTokens != null && tokens >= spec.maxTokens!) ||
          (spec.maxDuration != null && elapsed.elapsed >= spec.maxDuration!)) {
        throw const TurnLimitException('The research allowance was reached.');
      }
      final GoalStepResult result;
      try {
        result = await _researchOnce(
          spec.copyWith(
            maxTokens: spec.maxTokens == null
                ? null
                : max(0, spec.maxTokens! - tokens),
            maxToolCalls: spec.maxToolCalls == null
                ? null
                : max(0, spec.maxToolCalls! - calls),
            maxDuration: spec.maxDuration == null
                ? null
                : spec.maxDuration! - elapsed.elapsed,
          ),
          task,
          number: number,
          total: progress.tasks.length,
          subject: subject,
          fixes: first == null
              ? ''
              : first.answer.isEmpty &&
                    !first.checks.any(
                      (c) => c.kind == GoalCheckKind.droppedFigures,
                    )
              ? '- It gave no answer (only a tool call or nothing). Answer the question from the sources given, with citations.'
              : GoalChecker.fixes(first.checks, subject),
          attempt: attempt,
        );
      } on TurnLimitException {
        rethrow;
      } catch (_) {
        // The retry failed: the first answer, flagged, beats none.
        if (first == null || first.answer.isEmpty) rethrow;
        return GoalStepResult(
          answer: first.answer,
          sources: first.sources,
          tokens: tokens,
          toolCalls: calls,
          checks: first.checks,
          trace: first.trace,
        );
      }
      tokens += result.tokens;
      calls += result.toolCalls;
      // Researched another model, asked the user, or said nothing (a
      // bare tool call cleaned away): once more, with what to fix.
      final retry =
          result.answer.isEmpty ||
          result.checks.any(
            (c) =>
                c.excludes ||
                (c.kind == GoalCheckKind.leak && result.answer.length < 200),
          );
      if (attempt == 1 &&
          retry &&
          (spec.maxTokens == null || tokens < spec.maxTokens!)) {
        first = result;
        continue;
      }
      // The second answer is kept unless it is worse than the first.
      final kept =
          first != null &&
              result.checks.where((c) => c.excludes).length >
                  first.checks.where((c) => c.excludes).length
          ? first
          : result;
      return GoalStepResult(
        answer: kept.answer,
        sources: kept.sources,
        tokens: tokens,
        toolCalls: calls,
        checks: [
          ...kept.checks,
          if (first != null) const GoalCheck(GoalCheckKind.retried),
        ],
        trace: kept.trace == null
            ? null
            : GoalTrace(
                queries: kept.trace!.queries,
                tools: kept.trace!.tools,
                reasoning: kept.trace!.reasoning,
                promptTokens: kept.trace!.promptTokens,
                tokens: kept.trace!.tokens,
                ms: kept.trace!.ms,
                attempts: attempt,
                tokensPerSecond: kept.trace!.tokensPerSecond,
              ),
      );
    }
    throw StateError('unreachable');
  }

  /// Pages one step may read: its search's pages with the spare tries for
  /// pages that fail, and a couple more for a search of its own. Reads no
  /// longer spend the goal's tool calls (review, 2026-09-28: three
  /// steps spent 32 of 36 calls, mostly on reads, and the rest read almost
  /// nothing).
  int get _stepReads => _goalRef.read(settingsProvider).maxPagesRead + 5;

  Future<GoalStepResult> _researchOnce(
    GoalSpec spec,
    GoalTask task, {
    required int number,
    required int total,
    required SubjectTerms subject,
    required String fixes,
    required int attempt,
  }) async {
    await _useGoalChat();
    final budget = _budget(spec, maxReads: _stepReads);
    final kind = spec.specialization;
    final clock = Stopwatch()..start();
    final accepted = await _goalRef
        .read(chatProvider.notifier)
        .send(
          task.question,
          owner: this,
          forceResearch: true,
          budget: budget,
          learn: false,
          isolated: true,
          // The step's own names count as on-topic too: in "EVs in Canada",
          // a page about the Tesla Model Y answers "range of the Model Y"
          // without naming Canada.
          subject: SubjectTerms(
            {
              ...subject.terms,
              ...SubjectTerms.of(task.question).terms,
            }.toList(),
          ),
          subjectAllowed: '${spec.allowed}\n${task.question}',
          turnOverrides: _turn(spec, GoalRulePhase.step),
          // What is the same for every step comes first, so the engine's
          // prompt cache keeps it from one step to the next; the step's
          // number and any fixes come last.
          extraSystem:
              'You are researching one step of this goal: ${spec.objective}\n'
              'Answer only the step\'s question, factually, with the key facts, figures, names and dates from the sources, each cited like [1]. Your answer becomes part of a report.\n'
              '${GoalRules.block(terms: subject.terms, userRules: spec.effectiveRules, today: GoalNotifier._today(), kind: kind)}'
              '${kind.stepInstruction.isEmpty ? '' : '\n${kind.stepInstruction}'}'
              '\nThis is step $number of $total.'
              '${fixes.isEmpty ? '' : '\nAn earlier answer to this step was rejected. Fix this:\n$fixes'}',
        );
    _goalChatId ??= _goalRef.read(chatProvider).chatId;
    final chat = _goalRef.read(chatProvider);
    if (!accepted ||
        chat.error != null ||
        (budget.remainingTime != null &&
            budget.remainingTime! <= Duration.zero)) {
      _overhead = GoalUsage(
        tokens: _overhead.tokens + budget.usedTokens,
        toolCalls: _overhead.toolCalls + budget.usedToolCalls,
      );
      if (budget.remainingTime != null &&
          budget.remainingTime! <= Duration.zero) {
        throw const TurnLimitException('The time budget was reached.');
      }
      if ((chat.error ?? '').contains('budget')) {
        throw TurnLimitException(chat.error!);
      }
      throw StateError(chat.error ?? 'The chat could not start the step.');
    }
    final answer = chat.messages
        .where((m) => m.role == ChatRole.assistant && ChatNotifier.isLive(m))
        .lastOrNull;
    if (answer == null || answer.content.trim().isEmpty) {
      _overhead = GoalUsage(
        tokens: _overhead.tokens + budget.usedTokens,
        toolCalls: _overhead.toolCalls + budget.usedToolCalls,
      );
      throw StateError(chat.error ?? 'The model returned no answer.');
    }
    final run = TurnRun.decode(answer.runJson);
    final metrics = run?.metrics ?? const <String, dynamic>{};
    final sources = <GoalSource>[];
    final evidence = <String>[];
    try {
      for (final s in SearchSteps.sourcesFromJson(answer.sourcesJson)) {
        if (s.sponsored) continue;
        sources.add(
          GoalSource(
            title: s.title,
            url: s.finalUrl ?? s.url,
            outlet: s.outlet,
            evidence: '${s.title}\n${s.snippet}\n${s.pageText ?? ''}',
            publishedAt: s.publishedAt,
            retrievedAt: s.fetchedAt,
          ),
        );
        evidence.add('${s.title}\n${s.snippet}\n${s.pageText ?? ''}');
      }
    } catch (e, st) {
      quietFailure('goal_provider:1157', e, st);
    }
    // Figures no source states are left out with their sentence or table
    // cell, and the step keeps its other facts.
    final math = spec.specialization == GoalSpecialization.math;
    final (text, found) = GoalChecker.findings(
      GoalChecker.clean(answer.content.trim()),
      subject: subject,
      allowed: spec.allowed,
      evidence: evidence,
      requireSources: !math,
      dropUnsupported: !math,
    );
    final checks = [
      ...found,
      if (GoalChecker.leaked(answer.content))
        const GoalCheck(GoalCheckKind.leak),
    ];
    final reasoning = (answer.reasoning ?? '').trim();
    final queries = chat.metrics['queries'];
    final tokens = budget.usedTokens;
    return GoalStepResult(
      answer: text,
      sources: sources,
      tokens: tokens,
      toolCalls: budget.usedToolCalls,
      checks: checks,
      trace: GoalTrace(
        queries: [
          if (queries is List)
            for (final q in queries)
              if (q is String) q,
        ],
        tools: [
          for (final t in run?.toolTrace ?? const <Map<String, dynamic>>[])
            GoalNotifier._toolLine(t),
        ],
        reasoning: reasoning.length <= GoalTrace.maxReasoning
            ? reasoning
            : '${reasoning.substring(0, GoalTrace.maxReasoning)}…',
        promptTokens: (metrics['promptTokens'] as num?)?.toInt() ?? 0,
        tokens: (metrics['tokens'] as num?)?.toInt() ?? 0,
        ms: clock.elapsedMilliseconds,
        attempts: attempt,
        tokensPerSecond: (metrics['tokensPerSecond'] as num?)?.toDouble() ?? 0,
      ),
    );
  }
}
