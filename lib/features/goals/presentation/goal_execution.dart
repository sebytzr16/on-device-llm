part of 'goal_provider.dart';

/// Runner wiring; ownership and lifetime remain with GoalNotifier.
extension _GoalExecution on GoalNotifier {
  /// Refuses a goal whose chat the user turned local: every step researches,
  /// so after "Stay local" on the new-chat consent it would spend its budget
  /// on sourceless answers. The cascade follows the open
  /// chat, so the goal's own chat is opened first (a step does the same);
  /// the start and Continue are refused the same way (review 2026-11-20
  /// finding 2 and P2-2). Null when the goal may run.
  Future<GoalProgress?> _webOffRefusal(
    GoalSpec spec,
    GoalProgress? resume,
  ) async {
    final goalChat = _goalChatId;
    if (goalChat != null && _goalRef.read(chatProvider).chatId != goalChat) {
      await _goalRef.read(chatProvider.notifier).openChat(goalChat);
    }
    if (_goalRef.read(chatProvider).chatId != goalChat) {
      // The goal's chat could not be opened: the run reports that itself.
      return null;
    }
    // Only a chat the user turned local ("Stay local") is refused: web
    // research is off by default, and a goal without it still runs.
    if (_goalRef.read(chatOverridesProvider)['webMode'] != 'off') return null;
    final current =
        resume ??
        GoalProgress(
          spec: spec,
          status: GoalStatus.failed,
          steps: 0,
          startedAt: DateTime.now(),
        );
    return current.copyWith(
      status: GoalStatus.failed,
      clearAwaitingInput: true,
      error: stringsFor(_goalRef.read(settingsProvider).localeCode).goalWebOff,
    );
  }

  Future<void> _run(GoalSpec spec, {GoalProgress? resume}) async {
    if (_runner != null) return;
    final refused = await _webOffRefusal(spec, resume);
    if (refused != null) return _save(refused);
    final runner = GoalRunner(
      clarify: _clarify,
      research: _research,
      plan: _plan,
      evaluate: _evaluate,
      write: _write,
      verify: _verify,
      deliver: _deliver,
      checkpoint: _save,
      overheadUsage: () {
        final u = _overhead;
        _overhead = const GoalUsage();
        return u;
      },
      modelName: _modelName,
    );
    _runner = runner;
    _stopping = false;
    _dismissWhenDone = false;
    // Usage left from an earlier goal's calls is not this goal's.
    _overhead = const GoalUsage();
    final done = Completer<void>();
    _runDone = done.future;
    try {
      final ram =
          (await _goalRef.read(deviceMemoryProvider.future))?.totalGb ?? 0;
      _goalContext = ram >= 8 ? 16384 : 8192;
    } catch (_) {
      _goalContext = 8192;
    }
    final deadline = spec.maxDuration == null
        ? null
        : (resume?.startedAt ?? DateTime.now()).add(spec.maxDuration!);
    final remaining = deadline?.difference(DateTime.now());
    final timer = remaining == null
        ? null
        : Timer(
            remaining < Duration.zero ? Duration.zero : remaining,
            _cancelOwned,
          );
    try {
      await runner.run(spec, resume: resume);
    } finally {
      timer?.cancel();
      _runner = null;
      done.complete();
      if (_dismissWhenDone) {
        _dismissWhenDone = false;
        unawaited(dismissFinished());
      }
    }
  }
}
