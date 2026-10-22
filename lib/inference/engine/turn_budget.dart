import 'dart:math';

class TurnLimitException implements Exception {
  final String reason;
  const TurnLimitException(this.reason);
  @override
  String toString() => reason;
}

/// Shared allowance for all generations and tool rounds in one operation.
/// Prompt tokens count on every request, as they do in Goal usage records.
class TurnBudget {
  final int? maxTokens, maxToolCalls;

  /// Pages the operation may read, counted apart from [maxToolCalls]
  /// (searches and the model's tool calls). When reads shared the tool
  /// calls, three steps of the tester's camera Goal spent 32 of 36 calls,
  /// mostly on reads, and the later steps read almost nothing (tester
  /// review, 2026-09-28). Null: no read limit here (a chat turn reads its
  /// "Pages to read" setting).
  final int? maxReads;
  final DateTime? deadline;
  final DateTime Function() now;
  int usedTokens = 0, usedToolCalls = 0, usedReads = 0;
  TurnBudget({
    this.maxTokens,
    this.maxToolCalls,
    this.maxReads,
    this.deadline,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Duration? get remainingTime => deadline?.difference(now());
  int? get remainingTokens =>
      maxTokens == null ? null : max(0, maxTokens! - usedTokens);
  int? get remainingTools =>
      maxToolCalls == null ? null : max(0, maxToolCalls! - usedToolCalls);
  int? get remainingReads =>
      maxReads == null ? null : max(0, maxReads! - usedReads);
  void check() {
    if (remainingTime != null && remainingTime! <= Duration.zero) {
      throw const TurnLimitException('The time budget was reached.');
    }
    if (remainingTokens == 0) {
      throw const TurnLimitException('The token budget was reached.');
    }
  }

  int outputAllowance(int promptTokens, int requested) {
    check();
    if (remainingTokens == null) return requested;
    final room = remainingTokens! - promptTokens;
    if (room <= 0) {
      throw const TurnLimitException(
        'The remaining token budget cannot fit this prompt.',
      );
    }
    return min(requested, room);
  }

  void charge(int promptTokens, int generatedTokens) {
    usedTokens += max(0, promptTokens) + max(0, generatedTokens);
  }

  void useTool() {
    check();
    if (remainingTools == 0) {
      throw const TurnLimitException('The tool-call budget was reached.');
    }
    usedToolCalls++;
  }

  /// Counts one page read. False when the read allowance is spent: the
  /// page is skipped and the turn goes on with what it has.
  bool useRead() {
    check();
    if (remainingReads == 0) return false;
    usedReads++;
    return true;
  }
}
