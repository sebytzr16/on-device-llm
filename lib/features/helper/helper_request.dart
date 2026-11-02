import 'dart:convert';

import '../tools/domain/tool_spec.dart';

/// Explicit delegation must survive greeting and retrieval gates (owner, 2026-11-02).
abstract final class HelperRequest {
  static const contentBudget = 4800;
  static const _cut = '\n[Excerpt cut to helper budget]\n';

  // Bound both fields at the final prompt boundary, including direct callers (owner, 2026-11-02).
  static String content(
    String task,
    String input, {
    int budget = contentBudget,
  }) {
    budget = budget.clamp(256, 65536);
    final taskLimit = budget.clamp(256, 1200);
    final instruction = task.length > taskLimit
        ? '${_slice(task, 0, taskLimit - _cut.length)}$_cut'
        : task;
    if (input.isEmpty) return instruction;
    // CJK and emoji cost about a token per character, so halve the budget to
    // stay inside the helper's per-sequence context (review, 2026-11-02).
    final dense = RegExp(r'[⺀-￿]').allMatches(input).length > input.length ~/ 5;
    final available = (dense ? budget ~/ 2 : budget) - instruction.length - 6;
    if (available <= _cut.length + 16) return _slice(instruction, 0, budget);
    if (input.length <= available) return '$instruction\n\n---\n$input';
    final head = _slice(input, 0, (available ~/ 3).clamp(1, 1000));
    final remaining = available - head.length - _cut.length;
    final words = RegExp(
      r'[a-zA-Z]{4,}',
    ).allMatches(task.toLowerCase()).map((m) => m[0]!).toSet();
    // Without task words in the page, keep its full-length tail (review, 2026-11-02).
    var best = input.length - remaining, score = 0;
    for (var start = head.length; start < input.length; start += 512) {
      final passage = _slice(input, start, remaining).toLowerCase();
      final hits = words.where(passage.contains).length;
      if (hits > score) {
        score = hits;
        best = start < input.length - remaining
            ? start
            : input.length - remaining;
      }
    }
    return '$instruction\n\n---\n$head$_cut${_slice(input, best, remaining)}';
  }

  // Avoid splitting a UTF-16 surrogate pair at excerpt boundaries (owner, 2026-11-02).
  static String _slice(String text, int start, int length) {
    var end = (start + length).clamp(0, text.length);
    if (start > 0 && _low(text.codeUnitAt(start))) start++;
    if (end < text.length && end > start && _low(text.codeUnitAt(end))) end--;
    return text.substring(start, end);
  }

  static bool _low(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

  static bool wanted(String input) =>
      !RegExp(
        r"\b(don't|do not|never|without|no uses)\b|n'utilise pas",
        caseSensitive: false,
      ).hasMatch(input) &&
      !RegExp(
        r'^(how (do|can)|comment|c[oó]mo)\b',
        caseSensitive: false,
      ).hasMatch(input.trim()) &&
      RegExp(
        r'\b(use|ask|call|delegate|invoke|launch|fire|utilise|demande|appelle|usa|utiliza|delega)\b',
        caseSensitive: false,
      ).hasMatch(input) &&
      RegExp(
        r'\b(helpers?|sub[ -]?agents?|assistant auxiliaire|ayudante|subagente)\b',
        caseSensitive: false,
      ).hasMatch(input);

  // Small models sometimes promise a call instead of emitting one (owner, 2026-11-02).
  static ToolCall? fallback(
    String input, {
    required bool offered,
    required int round,
    required bool lastRound,
  }) => offered && round == 0 && !lastRound && wanted(input)
      ? ToolCall(
          id: 'explicit_helper',
          name: 'ask_helper',
          arguments: _arguments(input),
        )
      : null;

  static String _arguments(String input) => jsonEncode({
    'task':
        'Carry out the task requested in the supplied user message. Return your result to the main assistant.',
    'input': input,
  });
}
