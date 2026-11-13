part of 'goal_provider.dart';

/// Goal-owned model exchanges and prompt budgets.
extension _GoalModelExchange on GoalNotifier {
  /// Research steps and the report answer without thinking, with room for
  /// the answer only; on the phone the context grows to fit a page of
  /// evidence plus the answer (16K on 8 GB+ phones; the model reloads once
  /// for the goal).
  Map<String, dynamic> _turn(GoalSpec spec, GoalRulePhase phase) {
    final s = _goalRef.read(settingsProvider);
    final answer = phase == GoalRulePhase.report
        ? (_local ? 3072 : 8192)
        : (_local ? 1536 : 4096);
    final context = _goalContext;
    return {
      ...spec.specialization.turnOverrides,
      'thinkingModeEnabled': false,
      'maxTokens': min(answer, spec.maxTokens ?? answer),
      if (_local && s.contextSize < context) 'contextSize': context,
    };
  }

  ({TextEngine engine, String fallback, InferenceSettings settings}) _model() {
    final settings = _goalRef.read(settingsProvider);
    final TextEngine engine = settings.usesRemote
        ? _goalRef.read(remoteEngineProvider)
        : _goalRef.read(llamaEngineProvider);
    final model = _goalRef.read(modelManagerProvider).loadedModel;
    return (
      engine: engine,
      fallback: model == null ? '' : model.family.fallbackTemplate,
      settings: settings,
    );
  }

  /// A short JSON exchange with the loaded model (planner, reviewer). The
  /// model thinks first ([thinkBudget] tokens; a JSON grammar would forbid
  /// the reasoning block, so the reply is read leniently), and when that
  /// reply holds no JSON the question is asked again under the grammar
  /// without thinking. Returns the object and the reasoning.
  Future<(Map<String, dynamic>?, String)> _json(
    String system,
    String prompt, {
    int maxTokens = 400,
    int thinkBudget = 0,
    GoalSpec? budgetSpec,
    String Function(int maxCharacters)? promptForLimit,
  }) async {
    // Claimed before any await, so a chat sent meanwhile is refused instead
    // of failing with "engine busy" (audit P1-17).
    if (_goalRef.read(chatProvider).isGenerating ||
        _goalRef.read(sessionBusyProvider)) {
      throw StateError('The chat is busy.');
    }
    final busy = _goalRef.read(sessionBusyProvider.notifier);
    busy.state = true;
    _ownsEngine = true;
    try {
      return await _jsonHeld(
        system,
        prompt,
        maxTokens: maxTokens,
        thinkBudget: thinkBudget,
        budgetSpec: budgetSpec,
        promptForLimit: promptForLimit,
      );
    } finally {
      _ownsEngine = false;
      if (_goalRef.mounted) busy.state = false;
    }
  }

  Future<(Map<String, dynamic>?, String)> _jsonHeld(
    String system,
    String prompt, {
    required int maxTokens,
    required int thinkBudget,
    GoalSpec? budgetSpec,
    String Function(int maxCharacters)? promptForLimit,
  }) async {
    final budget = budgetSpec == null ? TurnBudget() : _budget(budgetSpec);
    final m = _model();
    // A remote model is used as configured; a local one must be loaded.
    if (!m.settings.usesRemote &&
        _goalRef.read(modelManagerProvider).loadedModel == null) {
      final library = _goalRef.read(modelManagerProvider);
      final candidate = library.catalog
          .where((x) => x.isDownloaded)
          .firstOrNull;
      if (candidate == null) throw StateError('Add a model first.');
      await _goalRef
          .read(modelManagerProvider.notifier)
          .loadModel(candidate, forChat: true);
    }
    Future<String> ask(InferenceSettings settings) async {
      if (_stopping) throw StateError('The Goal was stopped.');
      if (_local && settings.contextSize < _goalContext) {
        settings = settings.copyWith(contextSize: _goalContext);
      }
      budget.check();
      var fittedPrompt = prompt;
      var messages = <Map<String, Object>>[
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': fittedPrompt},
      ];
      var preview = await m.engine.previewPrompt(
        messages: messages,
        fallbackTemplate: _model().fallback,
        settings: settings,
      );
      for (
        var attempt = 0;
        preview['fits'] == false && promptForLimit != null && attempt < 6;
        attempt++
      ) {
        final tokens = (preview['promptTokens'] as num?)?.toInt() ?? 1;
        final window =
            (preview['contextSize'] as num?)?.toInt() ?? settings.contextSize;
        final reserve =
            (preview['reservedTokens'] as num?)?.toInt() ?? settings.maxTokens;
        final limit =
            (fittedPrompt.length *
                    max(0, window - reserve) /
                    max(1, tokens) *
                    0.85)
                .floor();
        fittedPrompt = promptForLimit(limit);
        messages = [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': fittedPrompt},
        ];
        preview = await m.engine.previewPrompt(
          messages: messages,
          fallbackTemplate: _model().fallback,
          settings: settings,
        );
      }
      if (preview['fits'] == false) {
        throw const TurnLimitException(
          'The Goal review does not fit the model context. Increase the context size or use a model with a larger context.',
        );
      }
      final allowed = budget.outputAllowance(
        (preview['promptTokens'] as num?)?.toInt() ?? 0,
        settings.outputCeiling,
      );
      settings = settings.withinOutput(allowed);
      final timer = budget.remainingTime == null
          ? null
          : Timer(budget.remainingTime!, m.engine.cancel);
      String raw;
      try {
        raw = await m.engine
            .generate(
              messages: messages,
              fallbackTemplate: _model().fallback,
              settings: settings,
            )
            .join();
      } finally {
        timer?.cancel();
        final metrics = m.engine.metrics;
        final promptTokens = (metrics['promptTokens'] as num?)?.toInt() ?? 0;
        final generated = (metrics['tokens'] as num?)?.toInt() ?? 0;
        budget.charge(promptTokens, generated);
        _overhead = GoalUsage(
          tokens: _overhead.tokens + promptTokens + generated,
          toolCalls: _overhead.toolCalls,
        );
      }
      if (_stopping) throw StateError('The Goal was stopped.');
      if (budget.remainingTime != null &&
          budget.remainingTime! <= Duration.zero) {
        throw const TurnLimitException('The time budget was reached.');
      }
      return raw;
    }

    var notes = '';
    if (thinkBudget > 0) {
      final raw = await ask(
        m.settings.copyWith(
          temperature: 0.3,
          maxTokens: maxTokens,
          thinkingModeEnabled: true,
          thinkingBudgetTokens: thinkBudget,
          responseFormat: ResponseFormat.text,
          toolsEnabled: false,
        ),
      );
      final split = GoalNotifier.splitThinking(raw);
      notes = split.$1;
      final parsed = GoalNotifier.parseJsonObject(split.$2);
      if (parsed != null) return (parsed, notes);
    }
    final raw = await ask(
      m.settings.copyWith(
        temperature: 0.2,
        maxTokens: maxTokens,
        thinkingModeEnabled: false,
        responseFormat: ResponseFormat.json,
        toolsEnabled: false,
      ),
    );
    return (
      GoalNotifier.parseJsonObject(GoalNotifier.splitThinking(raw).$2),
      notes,
    );
  }

  Future<List<GoalClarification>> _clarify(GoalSpec spec) async {
    if (spec.quick ||
        !GoalClarification.preferencesMayMatter(
          spec.objective,
          spec.criteria,
        )) {
      return const [];
    }
    final (reply, _) = await _json(
      'Help the user clarify a research goal before planning it. Ask only about missing personal preferences that materially change the answer. Reply with JSON only.',
      'Goal: ${spec.objective}\nSuccess criteria: ${spec.criteria}\nUser rules and search guidance: ${spec.effectiveRules}\n'
          'Return zero to three concise questions, written in ${GoalNotifier._language(spec)}. For a recommendation, intended use, budget or priorities may matter. '
          'Do not ask for information already given, publicly researchable facts, sources, permission to research, or an exhaustive list of preferences. '
          'If the request is already clear or no personal preference affects the result, return an empty list. '
          'Each question may have two or three short suggested answers; the user can also type their own or skip. '
          'Return: {"questions": [{"question": "What matters most to you?", "options": ["First priority", "Second priority"]}]}',
      maxTokens: 1000,
      budgetSpec: spec,
    );
    // Questions are model proposals, never prefilled user answers.
    return [
      for (final q in GoalClarification.parse(reply?['questions']))
        q.answered(''),
    ];
  }

  Future<GoalPlan> _plan(GoalSpec spec) async {
    final subject = spec.subject;
    final (reply, notes) = await _json(
      'You plan research. Break a goal into a few specific questions that a '
          'web search can answer, covering everything the success criteria ask '
          'for. Think it through first, then reply with JSON only.',
      'Goal: ${spec.objective}\nSuccess criteria: ${spec.criteria}\n\n'
          '${GoalRules.block(terms: subject.terms, userRules: spec.effectiveRules, today: GoalNotifier._today(), kind: spec.specialization, phase: GoalRulePhase.plan)}\n\n'
          'Write 3 to 6 research questions, in the order they should be researched. '
          'Each must be a complete, specific question that stands on its own (name the subject exactly; no "it", "this" or "each camera"), '
          'asks one thing, and is written in ${GoalNotifier._language(spec)}. '
          'Keep every question within the success criteria. Do not add unrequested measurements or topics; a simple goal may need only one or two questions. '
          '${_goalState?.tasks.isNotEmpty == true ? 'This is a follow-up to existing research. Focus new questions on the edited requirements and latest search guidance; retain useful existing evidence. ' : ''}'
          '${spec.specialization.planHint.isEmpty ? '' : '${spec.specialization.planHint} '}'
          '${spec.deliverables.isEmpty ? '' : 'The app makes the requested ${spec.deliverables.join(', ')} from the report itself: plan only the research, no step about making or formatting it. '}'
          'Return: {"steps": ["question 1", "question 2", ...]}',
      maxTokens: 500,
      thinkBudget: GoalNotifier._reviewThinking,
      budgetSpec: spec,
    );
    return GoalPlan(
      GoalNotifier._strings(reply?['steps'] ?? reply?['questions']),
      notes: GoalNotifier._clip(notes),
    );
  }
}
