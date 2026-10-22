import 'dart:math';

import '../../settings/domain/entities/inference_settings.dart';

/// Sampling and timing rules for a turn: how much evidence it gets,
/// how grounded answers sample, how long the web judge may take.
class TurnPolicy {
  const TurnPolicy._();

  /// Passages given to the model: the user's setting on the phone, where
  /// every passage costs prefill time; hosted models read tens of thousands
  /// of tokens in a second, so a remote turn gets at least twelve.
  static int passageBudget(InferenceSettings s) =>
      s.usesRemote ? max(s.evidencePassages, 12) : s.evidencePassages;

  /// A grounded (web/document evidence) answer keeps the user's sampling but
  /// caps unlimited thinking: with a page of evidence in the prompt, small
  /// models otherwise reason for a minute before the first answer token.
  /// The Think chip decides: with thinking off, a searched answer does not
  /// think either (tester, 2026-10-08; it used to think up to the grounded
  /// budget, "Think before answering from sources", 2026-10-04).
  ///
  /// Sampling is capped at [groundedTemperature] and [groundedTopP]: with
  /// the Qwen3.5 card's 1.0/1.0, Qwen3.5 0.8B answered Toronto's weather
  /// without a figure in 2 of 6 replays and invented "14 °F, rained
  /// yesterday"; at 0.7/0.8 all 6 quoted the source (phone, 2026-10-08,
  /// tester: "he got all the answers wrong"). Lower settings are kept.
  static InferenceSettings groundedSettings(
    InferenceSettings s, {
    required bool grounded,
  }) {
    if (!grounded) return s;
    // A remote model on its own settings keeps them (tester, 2026-10-18):
    // the cap was measured on the phone's 0.8B.
    if (!s.serverSampling &&
        (s.temperature > groundedTemperature || s.topP > groundedTopP)) {
      s = s.copyWith(
        temperature: s.temperature > groundedTemperature
            ? groundedTemperature
            : s.temperature,
        topP: s.topP > groundedTopP ? groundedTopP : s.topP,
      );
    }
    if (!s.thinkingModeEnabled || s.thinkingBudgetTokens > 0) return s;
    return s.copyWith(thinkingBudgetTokens: groundedThinkingBudget);
  }

  /// The most randomness an answer from sources gets (see
  /// [groundedSettings]).
  static const groundedTemperature = 0.7;
  static const groundedTopP = 0.8;

  /// Reasoning room for an answer from sources: enough to pick the passage
  /// that answers and check its figures (decision 2026-10-04; it was
  /// 256, which cut Gemma 4's reasoning mid-sentence).
  static const groundedThinkingBudget = 1024;

  /// How long the web judge may take before the turn proceeds without it:
  /// a hosted model answers in well under a second unless it thinks.
  static const judgeDeadline = Duration(milliseconds: 2500);

  /// The same for a model on the phone. Its judge first prefills the
  /// chat's system prompt (reused by the answer), which took longer than
  /// 2.5 s on the S25+ CPU: all 30 judged questions of the 2026-09-24 eval
  /// timed out and none was ever searched.
  /// Tests shorten it.
  static Duration localJudgeDeadline = const Duration(seconds: 15);

  /// Whether a model on the phone judges Auto-mode questions. Off: on the
  /// S25+ (Qwen3.5 2B, 2026-09-24 eval) the judge took ~7.7 s and said yes
  /// to 35 of 38 questions (capital of Australia, the SSH port…), for +2
  /// correct answers at 3x the time; with 2.5 s it always timed out and
  /// cost ~6 s for nothing. Keywords decide on the phone. Tests turn it on
  /// to exercise the judge with the fake local engine.
  static bool judgeLocalModels = false;
}
