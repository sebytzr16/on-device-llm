part of 'chat_provider.dart';

extension _ChatRounds on ChatNotifier {
  /// Generation rounds: the model may end a round with tool calls; the
  /// host runs them, appends the results and asks again, at most
  /// toolMaxRounds times. Each round's text moves into the reasoning
  /// channel as a step so the final answer stays clean. A copied prompt, a
  /// denied figure and an unchecked live figure are each asked again once.
  Future<void> _runRounds(_Turn t, _Prompt prompt) async {
    final input = t.input;
    final settings = t.settings!;
    final engine = t.engine;
    final model = t.model!;
    final budget = t.budget;
    final runner = t.runner;
    final messages = prompt.messages;
    final tools = prompt.tools;
    final nativeTools = prompt.nativeTools;
    final local = engine is! RemoteEngine;
    final answer = t.answer, thinking = t.thinking;
    final toolMessages = <Map<String, Object>>[];
    final pendingHelpers = <({ToolCall call, Future<ToolResult> reply})>[];
    t.holdAnswer =
        HelperRequest.wanted(input) &&
        tools.any((tool) => tool.name == 'ask_helper');
    final helperSlots = Map<ToolCall, Map<String, Object>>.identity();
    var helperCount = 0;
    Future<void> collectHelpers() async {
      // Keep native tool-call pairs valid by replacing their start acknowledgements (owner, 2026-11-02).
      final waiting = Stopwatch()..start();
      var remaining = pendingHelpers.length;
      void update() {
        if (_alive && !_cancelled) {
          _chatState = _chatState.copyWith(
            notice: _t.helpersWaiting(remaining, waiting.elapsed.inSeconds),
          );
        }
      }

      update();
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => update());
      late List<ToolResult> results;
      try {
        results = await Future.wait(
          pendingHelpers.map(
            (job) => job.reply.then((reply) {
              remaining--;
              return reply;
            }),
          ),
        );
      } finally {
        timer.cancel();
        if (_alive && !_cancelled)
          _chatState = _chatState.copyWith(clearNotice: true);
      }
      if (_cancelled || !_alive) return;
      for (var i = 0; i < results.length; i++) {
        final result = results[i];
        final call = pendingHelpers[i].call;
        // Text-parsed calls all have an empty id, so the start
        // acknowledgement is found by identity, not by tool_call_id.
        final slot = helperSlots.remove(call);
        final index = slot == null
            ? -1
            : toolMessages.indexWhere((m) => identical(m, slot));
        final reply = {
          'role': 'tool',
          'tool_call_id': call.id,
          'name': call.name,
          'content': result.output,
        };
        if (index < 0) {
          toolMessages.add(reply);
        } else {
          toolMessages[index] = reply;
        }
        thinking.write(
          '\n▸ ${call.name}${ChatNotifier._argSummary(call)} → ${result.ok ? '' : 'error: '}'
          '${result.output.length > 160 ? '${result.output.substring(0, 160)}…' : result.output}\n',
        );
        if (result.ok) {
          _chatRef
              .read(helperJobsProvider.notifier)
              .report(
                t.assistantId,
                '${call.args['task']}'.trim(),
                model.displayName,
              );
        }
      }
      pendingHelpers.clear();
    }

    var rounds = 0;
    // A model restating its whole answer is stopped at the repeat.
    var repeatStopped = false;
    // The model copied its prompt instead of answering; asked again once.
    var echoed = false;
    var echoRetried = false;
    // The answer said the figure asked for is unknown; asked once more.
    var denialRetried = false;
    // The answer gave a "next" date that has passed; asked once more.
    var pastRetried = false;
    Object? echoPrompt;
    var pieces = 0;
    final canvasSub = engine is DiffusionGemmaEngine
        ? engine.canvasChanges.listen((event) {
            if (_alive && !_cancelled && event['canvas'] is String) {
              _chatState = _chatState.copyWith(
                partialAnswer: t.holdAnswer
                    ? ''
                    : '${event['committed'] ?? ''}${event['canvas']}',
                metrics: engine.metrics,
              );
            }
          })
        : null;
    // The turn owns the preview subscription, including errors/cancellation.
    t.canvasSub = canvasSub;
    // Out of tool rounds with calls still coming: one last round without
    // tools, answering from what was gathered (the call itself used to end
    // up as the answer).
    var lastRound = false;
    var emptyRetried = false;
    // The remote model offered to read on instead of reading; told yes
    // once.
    var toldToRead = false;
    var sent = false;
    final helpers = tools.any((tool) => tool.name == 'ask_helper')
        ? _chatRef.read(helperRunnerProvider)
        : null;
    helpers?.beginTurn();
    try {
      while (true) {
        if (_cancelled) break;
        // All independent jobs have started. Wait before generating any
        // more answer tokens, including an acknowledgement or outline.
        if (pendingHelpers.isNotEmpty) {
          t.clearAnswer();
          _chatState = _chatState.copyWith(partialAnswer: '');
          await collectHelpers();
          if (_cancelled || !_alive) break;
          t.holdAnswer = false;
          lastRound = true;
          toolMessages.add({
            'role': 'user',
            'content':
                'All helper replies are now available above. ${HelperRequest.mergeInstruction} '
                'No more tools are available; write the final answer now.',
          });
        }
        budget?.check();
        if (toolMessages.isNotEmpty) {
          // Tool results can outgrow the context (nine pages plus thinking did
          // on the phone); the bridge would then drop the question itself.
          // Shorten the largest results until the prompt fits.
          final roundPrompt = [...messages, ...toolMessages];
          final cut = await fitToolResults(
            engine,
            roundPrompt,
            toolMessages,
            settings,
            model,
            tools: nativeTools ? tools : const [],
          );
          messages.removeWhere((m) => !roundPrompt.contains(m));
          if (cut != null) thinking.write('\n$cut\n');
        }
        // A spoken phone answer gets the same cap: at the card's 1.0 the 0.8B
        // put Canberra "in New Zealand's northern island" and answered "¿qué
        // tal?" with nonsense (Conversation probe round 7, 2026-10-18).
        var roundSettings = TurnPolicy.groundedSettings(
          settings,
          grounded: t.sources.isNotEmpty || (t.spoken && local),
        );
        if (budget != null) {
          final preview = await engine.previewPrompt(
            messages: [...messages, ...toolMessages],
            fallbackTemplate: model.family.fallbackTemplate,
            settings: roundSettings,
            tools: nativeTools ? tools : const [],
          );
          final allowed = budget.outputAllowance(
            (preview['promptTokens'] as num?)?.toInt() ?? 0,
            roundSettings.outputCeiling,
          );
          roundSettings = roundSettings.withinOutput(allowed);
        }
        // Memory sharing turned off mid-turn: the next request would carry
        // the notes already in this prompt (system notes, recall results).
        // Checked after the awaits above, right before sending; the turn ends
        // with what it has (audit P2-15).
        if (sent &&
            !local &&
            (t.memoryFacts.isNotEmpty ||
                (runner?.trace.any((r) => r.call.name == 'recall') ?? false)) &&
            !_remoteMemoryShared(settings)) {
          break;
        }
        sent = true;
        try {
          await for (final event in _turns.stream(
            t.lease,
            () => engine.generate(
              messages: [...messages, ...toolMessages],
              fallbackTemplate: model.family.fallbackTemplate,
              settings: roundSettings,
              assistantPrefix: t.resume?.content ?? '',
              tools: nativeTools ? tools : const [],
              // Required applies to the first round only; once a result is in,
              // the model must be free to answer. An outright action request
              // must prepare its card, not promise to.
              toolChoice:
                  (lastRound || (nativeTools && RetrievalPlan.smallTalk(input)))
                  ? 'none'
                  : nativeTools &&
                        rounds == 0 &&
                        (prompt.researchTurn ||
                            (t.remoteBrain &&
                                settings.webMode == WebMode.always &&
                                !RetrievalPlan.greetingOnly(input)) ||
                            (HelperRequest.wanted(input) &&
                                tools.any((t) => t.name == 'ask_helper')) ||
                            settings.toolChoice == ToolChoice.required ||
                            (PhoneActions.command(input) &&
                                tools.any(
                                  (s) => PhoneActions.kinds.contains(s.name),
                                )))
                  ? 'required'
                  : 'auto',
            ),
          )) {
            if (event is! TextDelta) continue;
            t.parser!.add(event.text);
            if (_cancelled) engine.cancel();
            if (++pieces % 24 == 0 &&
                !repeatStopped &&
                AnswerCleanup.isRepeating(answer.toString())) {
              repeatStopped = true;
              engine.cancel();
            }
            // The model narrates the request on a new line: the answer is
            // over (stopped before the voice reaches that line).
            if (!repeatStopped && event.text.isNotEmpty && t.tail.narrating) {
              repeatStopped = true;
              engine.cancel();
            }
            // Checked while the answer's opening is being written, on a turn
            // with sources: their prompt opens with the app's own paragraphs,
            // while a chat turn's may be the user's text, which a corrected
            // copy starts with.
            // The second try is checked against the same sources turn.
            final asked = echoPrompt ??= messages.last['content'];
            if (!echoed &&
                !t.echoStopped &&
                t.resume == null &&
                t.sources.isNotEmpty &&
                answer.length >= 60 &&
                answer.length < 400 &&
                asked is String &&
                AnswerCleanup.echoes(answer.toString(), asked)) {
              if (echoRetried) {
                t.echoStopped = true;
              } else {
                echoed = true;
              }
              engine.cancel();
            }
          }
        } finally {
          final prompt = (engine.metrics['promptTokens'] as num?)?.toInt() ?? 0;
          final generated = (engine.metrics['tokens'] as num?)?.toInt() ?? 0;
          budget?.charge(prompt, generated);
          t.promptTokens += prompt;
          t.generatedTokens += generated;
          t.generationRounds++;
          t.nativeOmitted = max(
            t.nativeOmitted,
            (engine.metrics['trimmedMessages'] as num?)?.toInt() ?? 0,
          );
          t.metrics = {
            ...engine.metrics,
            'promptTokens': t.promptTokens,
            'tokens': t.generatedTokens,
            'generationRounds': t.generationRounds,
            'trimmedMessages': _fittedOmitted + t.nativeOmitted,
          };
        }
        // A copy of the prompt is no answer: once, ask again in a short turn
        // of its own after the cached prompt. The same order appended to the
        // end of the sources turn was copied too (frozen-web benchmark,
        // 2026-10-11: 3 of 3 on the weather tables).
        if (echoed && !echoRetried && !_cancelled && _alive) {
          echoRetried = true;
          echoed = false;
          t.parser!.close();
          final copied = answer.toString().trim().split('\n').first;
          t.clearAnswer();
          thinking.write('\n(The answer copied the prompt; asked again.)\n');
          final question = input.isEmpty ? 'the question above' : input;
          (toolMessages.isEmpty ? messages : toolMessages).addAll([
            {'role': 'assistant', 'content': copied},
            {
              'role': 'user',
              'content':
                  'That copies the prompt. Answer in your own words, from '
                  'the sources above, citing them like [1]: $question',
            },
          ]);
          t.newParser();
          continue;
        }
        // The phone's model says the figure is unknown while its pages give
        // one: once, ask again for it from them. Qwen3.5 0.8B said "There is
        // no current record of how many people live in Ottawa" (phone probe
        // round 6, 2026-10-18).
        if (!denialRetried &&
            !_cancelled &&
            _alive &&
            !repeatStopped &&
            !t.echoStopped &&
            t.resume == null &&
            local &&
            t.sources.isNotEmpty &&
            // A recalled page that lacks it: the turn searches instead
            // ([_searchAfterRecall]).
            !t.searchIfLacking &&
            AnswerCleanup.deniesFigure(answer.toString(), input) &&
            t.sources.any(
              (s) => RegExp(r'\d').hasMatch('${s.snippet} ${s.pageText ?? ''}'),
            )) {
          denialRetried = true;
          t.parser!.close();
          final denied = answer.toString().trim();
          t.clearAnswer();
          thinking.write(
            '\n(The answer said the figure is unknown; asked again.)\n',
          );
          (toolMessages.isEmpty ? messages : toolMessages).addAll([
            {'role': 'assistant', 'content': denied},
            {
              'role': 'user',
              'content':
                  'The sources above do give a figure for this. Answer '
                  'with it, citing them like [1]: $input',
            },
          ]);
          t.newParser();
          continue;
        }
        // "The next eclipse is on August 12, 2026" asked on October 20,
        // 2026: once, ask for the first date after today. Qwen3.5 0.8B took
        // the page's most recent date (speed set, 2026-10-20). The parser
        // holds back the answer's last characters until it is closed, and
        // every path from here closes it anyway.
        t.parser!.close();
        if (!pastRetried &&
            !_cancelled &&
            _alive &&
            !repeatStopped &&
            !t.echoStopped &&
            t.resume == null &&
            local &&
            t.sources.isNotEmpty &&
            DateCheck.passedNext(answer.toString(), input, DateTime.now())) {
          pastRetried = true;
          final dated = answer.toString().trim();
          t.clearAnswer();
          thinking.write(
            '\n(The answer gave a date already past; asked again.)\n',
          );
          final now = DateTime.now();
          final today =
              '${now.year}-${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')}';
          (toolMessages.isEmpty ? messages : toolMessages).addAll([
            {'role': 'assistant', 'content': dated},
            {
              'role': 'user',
              'content':
                  'That date has already passed: today is $today. Answer with '
                  'the first date after today that the sources give, citing '
                  'them like [1], or say they give none: $input',
            },
          ]);
          t.newParser();
          continue;
        }
        if (_cancelled || repeatStopped || t.echoStopped || !_alive) {
          break;
        }
        // Flush the parser so the round's text is complete before reading it.
        t.parser!.close();
        final roundText = answer.toString();
        var calls =
            runner == null ||
                tools.isEmpty ||
                lastRound ||
                (nativeTools && RetrievalPlan.smallTalk(input))
            ? const <ToolCall>[]
            : nativeTools
            ? TextEngine.toolCallsOf(engine.metrics)
            : TextToolProtocol.parse(
                roundText,
                counter: rounds + 1,
                maxCalls: settings.agentMaxConcurrent.clamp(3, 4),
              );
        // An explicit delegation should not end at a promise to call (owner, 2026-11-02).
        var appCall = false;
        // A model that searched instead of delegating still gets the agents
        // the user asked for ("latest news, use four agents": LFM3 called only
        // search_news, 2026-11-08).
        final helperCalls = HelperRequest.fallbackCalls(
          input,
          offered: tools.any((s) => s.name == 'ask_helper'),
          round: rounds,
          lastRound: lastRound,
          completed: calls.where((c) => c.name == 'ask_helper').length,
        );
        if (helperCalls.isNotEmpty) {
          appCall = calls.isEmpty;
          calls = [...calls, ...helperCalls];
        }
        // A plain timer request the phone's model answered with chat instead
        // of the required call is prepared from its own words.
        if (calls.isEmpty &&
            rounds == 0 &&
            !lastRound &&
            local &&
            PhoneActions.command(input) &&
            tools.any((s) => s.name == 'set_timer')) {
          final timer = PhoneActions.plainTimer(input);
          if (timer != null) {
            calls = [
              ToolCall(
                id: 'app_timer',
                name: 'set_timer',
                arguments: jsonEncode(timer),
              ),
            ];
            appCall = true;
          }
        }
        // The round's words without any tool-call markup: the parser's own
        // split when the native library reports calls, else the known markers
        // (the text protocol only drops blocks that are calls).
        final stripped = TextToolProtocol.strip(
          nativeTools ? ToolMarkup.strip(roundText) : roundText,
        );
        final said = appCall
            ? ''
            : calls.isNotEmpty &&
                  nativeTools &&
                  engine.metrics['toolContent'] is String
            ? (engine.metrics['toolContent'] as String).trim()
            : stripped;
        // A changing figure with nothing looked up this turn: "tomorrow in
        // Rome… twenty-eight degrees" from no page (round 5).
        // Only when the question asks for one: an explanation that names a
        // cost or a forecast was moved to the thinking pop-up and asked again,
        // and the second, shorter answer was the one shown (tester,
        // 2026-10-20: "it answered twice").
        final unchecked =
            rounds == 0 &&
            t.appAnswer == null &&
            prompt.sum == null &&
            t.sources.isEmpty &&
            (RetrievalPlan.timeSensitive(input) ||
                RetrievalPlan.productSpec(input)) &&
            AnswerCleanup.statesLiveFigure(said);
        // An age "as of" an earlier year, copied from a dated snippet.
        final dated =
            rounds > 0 && AnswerCleanup.staleAge(input, said, DateTime.now());
        if (calls.isEmpty &&
            t.remoteBrain &&
            !toldToRead &&
            !lastRound &&
            rounds < settings.toolMaxRounds &&
            (unchecked ||
                dated ||
                // A full answer that ends by pointing at a site is kept.
                (rounds > 0 &&
                    said.length < 600 &&
                    (AnswerCleanup.offersToLookFurther(said) ||
                        AnswerCleanup.defersToSources(said))))) {
          // "Would you like the specific details from Environment Canada?"
          // after a search (LM Studio Gemma 4 E4B, conversation probe
          // 2026-10-18), although it was told to read on rather than ask; or
          // "you can check Environment Canada for detailed hourly forecasts"
          // with no figure (round 4).
          final offered = AnswerCleanup.offersToLookFurther(said);
          toldToRead = true;
          t.clearAnswer();
          if (said.isNotEmpty) thinking.write('\n$said\n');
          toolMessages.addAll([
            {'role': 'assistant', 'content': said},
            {
              'role': 'user',
              'content': unchecked
                  ? 'Search first: that figure changes, so look it up now '
                        'and answer my question from what you find.'
                  : dated
                  ? 'Today is ${DateTime.now().toIso8601String().substring(0, 10)}. '
                        'Give the age as of today, worked out from the birth '
                        'date in the sources.'
                  : offered
                  ? 'Yes. Read the best source now and answer my question '
                        'from what it says.'
                  : 'Read the best page now with read_url and answer my '
                        'question with the figures it gives.',
            },
          ]);
          t.newParser();
          continue;
        }
        if (calls.isEmpty) {
          if (said.trim().isEmpty &&
              !emptyRetried &&
              (t.sources.isNotEmpty || (runner?.trace.isNotEmpty ?? false))) {
            emptyRetried = true;
            lastRound = true;
            t.clearAnswer();
            toolMessages.add({
              'role': 'user',
              'content':
                  'Your last reply contained no answer. Write a plain-text answer now '
                  'using the supplied sources and helper results, citing source numbers. '
                  'Do not think aloud or call tools.',
            });
            t.newParser();
            continue;
          }
          if (rounds == 0 && prompt.researchTurn) t.researchSkipped = true;
          // A stray block the model wrote without stopping is not shown.
          if (said != roundText.trim()) t.replaceAnswer(said);
          break;
        }
        if (runner == null) break;
        if (rounds >= settings.toolMaxRounds) {
          lastRound = true;
          t.clearAnswer();
          toolMessages.add({
            'role': 'user',
            'content':
                '(No more tool calls are available. Answer my question now from the tool results above, citing their source numbers.)',
          });
          t.newParser();
          continue;
        }
        rounds++;
        t.clearAnswer();
        if (said.isNotEmpty) thinking.write('\n$said\n');
        toolMessages.add({
          'role': 'assistant',
          // Native turns carry their calls structurally; repeating the markup
          // in the text made the template render every call twice.
          'content': nativeTools ? said : roundText,
          if (nativeTools)
            'tool_calls': [
              for (final c in calls)
                {...c.toJson(), 'arguments': c.jsonArguments},
            ],
        });
        if (calls.any((c) => c.name == 'ask_helper')) t.holdAnswer = true;
        // Start every helper before awaiting other tools.
        if (!_cancelled) {
          for (final call in calls.where((c) => c.name == 'ask_helper')) {
            pendingHelpers.add((call: call, reply: runner.run(call)));
          }
        }
        var repeated = false;
        for (final call in calls) {
          if (_cancelled) break;
          // The same phone action again (Qwen3.5 0.8B prepared one timer four
          // times, 2026-10-08): not prepared twice; the model answers. On the
          // phone any second one of the same kind counts: after a five-minute
          // timer the 0.8B prepared two "0 minute" timers (Conversation probe
          // round 7, 2026-10-18).
          if (PhoneActions.kinds.contains(call.name) &&
              runner.trace.any(
                (r) =>
                    r.ok &&
                    r.call.name == call.name &&
                    (local ||
                        PhoneAction(r.call.name, r.call.args).detail ==
                            PhoneAction(call.name, call.args).detail),
              )) {
            repeated = true;
            toolMessages.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'name': call.name,
              'content':
                  'Already prepared: the card is shown under your answer. '
                  'Do not prepare it again; answer the user now.',
            });
            continue;
          }
          t.lease.transition(TurnStage.tools);
          budget?.useTool();
          _chatState = _chatState.copyWith(
            notice: call.name == 'ask_helper'
                ? _t.helperWorking
                : _t.noticeUsingTool(call.name, ChatNotifier._argSummary(call)),
          );
          final ToolResult result;
          if (call.name == 'ask_helper') {
            final helperName = await _chatRef
                .read(helperRunnerProvider)
                .modelNameFor(settings.helperModelId, agentSettings: settings);
            result = ToolResult(
              call: call,
              ok: true,
              elapsedMs: 0,
              output:
                  'Helper job ${++helperCount} started on $helperName: ${call.args['task']}. '
                  'Its reply will be added before you write the final answer.',
            );
          } else {
            result = await runner.run(call);
          }
          thinking.write(
            '\n▸ ${call.name}${ChatNotifier._argSummary(call)} → ${result.ok ? '' : 'error: '}'
            '${result.output.length > 160 ? '${result.output.substring(0, 160)}…' : result.output}\n',
          );
          final message = <String, Object>{
            'role': 'tool',
            'tool_call_id': call.id,
            'name': call.name,
            'content': result.output,
          };
          if (call.name == 'ask_helper') helperSlots[call] = message;
          toolMessages.add(message);
        }
        if (repeated) lastRound = true;
        t.stage('tools${rounds}Ms');
        // Pages the tools read become this answer's sources, numbered as the
        // tool results numbered them (the runner was seeded with the evidence
        // already in the prompt).
        t.sources = List.of(runner.sources);
        for (final s in runner.sponsored) {
          if (!t.sponsored.any((x) => x.url == s.url)) t.sponsored.add(s);
        }
        t.newParser();
      }
    } finally {
      // Stop/error paths must settle jobs before saving their trace or starting another turn (owner, 2026-11-02).
      if (pendingHelpers.isNotEmpty) {
        t.lease.retrieval.cancel('helper turn ended');
        await Future.wait(pendingHelpers.map((job) => job.reply));
      }
      helpers?.endTurn();
    }
  }
}
