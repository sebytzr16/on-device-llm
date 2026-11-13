part of 'goal_provider.dart';

/// Runner wiring; ownership and lifetime remain with GoalNotifier.
extension _GoalExecution on GoalNotifier {
  Future<void> _run(GoalSpec spec, {GoalProgress? resume}) async {
    if (_runner != null) return;
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
