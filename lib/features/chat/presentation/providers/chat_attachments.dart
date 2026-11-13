part of 'chat_provider.dart';

extension _ChatAttachments on ChatNotifier {
  /// Shortens the largest tool results (in place, keeping their beginning)
  /// until the prompt fits. Returns a notice when something was cut.
  Future<String?> _fitToolResults(
    TextEngine engine,
    List<Map<String, Object>> messages,
    List<Map<String, Object>> toolMessages,
    InferenceSettings settings,
    ModelInfo model, {
    List<ToolSpec> tools = const [],
  }) async {
    var cuts = 0;
    var rounds = 0;
    while (rounds++ < 12) {
      final budget = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: model.family.fallbackTemplate,
        settings: settings,
        assistantPrefix: '',
        tools: tools,
      );
      if (budget['fits'] == true || _cancelled) break;
      Map<String, Object>? biggest;
      for (final m in toolMessages) {
        if (m['role'] != 'tool') continue;
        if (biggest == null ||
            (m['content'] as String).length >
                (biggest['content'] as String).length) {
          biggest = m;
        }
      }
      // Older turns first, then long results, then the last exchanges
      // (see [ContextUse.omitOldestExchange]).
      final longResult =
          biggest != null && (biggest['content'] as String).length >= 4000;
      final available = (budget['availableTokens'] as num?)?.toInt();
      // Estimate each exchange's tokens from the counts this preview already
      // returned instead of rendering every dropped exchange on its own:
      // several are dropped per round and the preview at the top of the next
      // round confirms the result once (audit N23: a full re-render per
      // dropped message is quadratic on long chats).
      final prompt = (budget['promptTokens'] as num?)?.toInt() ?? 0;
      final chars = messages.fold<int>(
        0,
        (n, m) => n + '${m['content'] ?? ''}'.length,
      );
      final charsPerToken = prompt > 0 && chars > 0 ? chars / prompt : 4.0;
      final omitted = await ContextUse.omitToFit(
        messages,
        deficit: available == null ? 1 : max(1, -available),
        keep: longResult ? 2 : 0,
        cancelled: () => _cancelled,
        count: (exchange) async => max(
          1,
          (exchange.fold<int>(0, (n, m) => n + '${m['content'] ?? ''}'.length) /
                  charsPerToken)
              .ceil(),
        ),
      );
      if (omitted > 0) {
        _fittedOmitted += omitted;
        // Omit rounds count toward the 12-round cap: each one still costs a
        // full-prompt preview at the top of the loop.
        continue;
      }
      if (biggest == null) break;
      final text = biggest['content'] as String;
      if (text.length < 1000) break;
      final kept = cutMiddle(
        text,
        text.runes.length ~/ 2,
        marker: _t.toolCutMiddleMarker,
      );
      final at = messages.indexOf(biggest);
      final shortened = {...biggest, 'content': kept};
      toolMessages[toolMessages.indexOf(biggest)] = shortened;
      if (at >= 0) messages[at] = shortened;
      cuts++;
    }
    return cuts == 0 ? null : _t.noticeToolCut(cuts);
  }

  /// Shortens attached document text in the last user turn until the prompt
  /// fits (the largest file each round, keeping its passages closest to the
  /// request). Returns a notice when something was left out.
  ///
  /// [fullTexts] provides the complete extracted text for each attachment by
  /// filename, so semantic fitting can rank from the original document instead
  /// of the already-lexically-filtered prompt text (audit A03).
  Future<String?> _fitDocuments(
    TextEngine engine,
    List<Map<String, Object>> messages,
    InferenceSettings settings,
    ModelInfo model, {
    Map<String, String>? fullTexts,
  }) async {
    final last = messages.last;
    if (last['role'] != 'user' ||
        !(last['content'] as String).contains('[File: ')) {
      return null;
    }
    final original = last['content'] as String;
    var content = original;
    final whole = <String, String>{};
    int? target;
    (int, int)? passages;
    var rounds = 0;
    while (rounds++ < 12) {
      final budget = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: model.family.fallbackTemplate,
        settings: settings,
        assistantPrefix: '',
      );
      if (budget['fits'] == true || _cancelled) break;
      final blocks = RegExp(
        r'\[File: ([^\]]+)\]\n([\s\S]*?)\n\[End of file: \1\]',
      ).allMatches(content).toList();
      final biggest = blocks.isEmpty
          ? null
          : blocks.reduce(
              (a, b) => b.group(2)!.length > a.group(2)!.length ? b : a,
            );
      // Older turns first, then the long file, then the last exchange
      // (see [ContextUse.omitOldestExchange]).
      var omitted = ContextUse.omitOldestExchange(messages, keep: 1);
      if (omitted == 0 &&
          (biggest == null || biggest.group(2)!.length < 8000)) {
        omitted = ContextUse.omitOldestExchange(messages);
      }
      if (omitted > 0) {
        _fittedOmitted += omitted;
        rounds--;
        continue;
      }
      // Largest file block first: the passages closest to the request
      // (EmbeddingGemma when downloaded), not its beginning. Halving kept
      // only the first 25% of a long file (owner, 2026-11-01).
      if (biggest == null) break;
      final name = biggest.group(1)!;
      // Use the full original text for semantic ranking, not the already-
      // filtered prompt text (audit A03).
      final full = whole[name] ??= fullTexts?[name] ?? biggest.group(2)!;
      if (full.length < 2000) break;
      final prompt = (budget['promptTokens'] as num?)?.toInt() ?? 0;
      final over =
          prompt +
          ((budget['reservedTokens'] as num?)?.toInt() ?? 0) -
          ((budget['contextSize'] as num?)?.toInt() ?? 0);
      final perToken = prompt > 0 ? content.length / prompt : 4.0;
      final current = biggest.group(2)!.length;
      target = max(
        1500,
        min(
          (target ?? current) * (target == null ? 1 : 0.85),
          current - over * perToken * 1.1 - 200,
        ).floor(),
      );
      final request = content
          .substring(content.lastIndexOf('[End of file: ') + 1)
          .replaceFirst(RegExp(r'^[^\]]*\]'), '')
          .trim();
      final fitted = await DocumentPassages.fit(
        full,
        request,
        target,
        embedder: _webEmbedder(),
        owner: DocumentPassages.cacheOwner(_chatState.chatId),
        // A temporary chat must not persist vectors about its files (S15).
        persistVectors: !_chatState.temporary,
      );
      passages = (fitted.kept, fitted.total);
      content = content.replaceRange(
        biggest.start,
        biggest.end,
        '[File: $name]\n${fitted.text}\n[End of file: $name]',
      );
      messages.last = {...last, 'content': content};
      if (target <= 1500) break;
    }
    if (content == original) return null;
    final (kept, total) = passages ?? (1, 1);
    return _t.noticeDocPassages(kept, total);
  }
}
