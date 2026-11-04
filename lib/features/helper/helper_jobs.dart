import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'helper_runner.dart' show HelperReply;

enum HelperPhase {
  queued,
  loadingModel,
  prefill,
  generating,
  done,
  failed,
  cancelled,
  timedOut,
}

class HelperJob {
  final String id, task, inputPreview, modelName;
  final String? messageId, reason, reportedTo;
  final HelperPhase phase;
  final String output, thinking;
  final Duration elapsed;
  final Duration? firstToken, prefill;
  final Map<String, dynamic> metrics;
  final HelperReply? reply;
  const HelperJob({
    required this.id,
    required this.task,
    required this.inputPreview,
    required this.modelName,
    this.messageId,
    this.reportedTo,
    this.reason,
    this.phase = HelperPhase.queued,
    this.output = '',
    this.thinking = '',
    this.elapsed = Duration.zero,
    this.firstToken,
    this.prefill,
    this.metrics = const {},
    this.reply,
  });

  HelperJob reported(String model) => HelperJob(
    id: id,
    task: task,
    inputPreview: inputPreview,
    modelName: modelName,
    messageId: messageId,
    reason: reason,
    reportedTo: model,
    phase: phase,
    output: output,
    thinking: thinking,
    elapsed: elapsed,
    firstToken: firstToken,
    prefill: prefill,
    metrics: metrics,
    reply: reply,
  );

  HelperJob ended(HelperPhase end, String why) => HelperJob(
    id: id,
    task: task,
    inputPreview: inputPreview,
    modelName: modelName,
    messageId: messageId,
    reportedTo: reportedTo,
    reason: why,
    phase: end,
    output: output,
    thinking: thinking,
    elapsed: elapsed,
    firstToken: firstToken,
    prefill: prefill,
    metrics: metrics,
    reply: reply,
  );

  bool get terminal => switch (phase) {
    HelperPhase.done ||
    HelperPhase.failed ||
    HelperPhase.cancelled ||
    HelperPhase.timedOut => true,
    _ => false,
  };
  int? get tokens => (metrics['tokens'] as num?)?.toInt();
  int? get promptTokens => (metrics['promptTokens'] as num?)?.toInt();
  double? get tokensPerSecond {
    final measured = (metrics['tokensPerSecond'] as num?)?.toDouble();
    if (measured != null && measured.isFinite && measured >= 0) return measured;
    final first = firstToken;
    final count = tokens;
    if (first == null || count == null) return null;
    final generationMs = metrics['generationElapsedMs'];
    final generation = generationMs is num
        ? Duration(milliseconds: generationMs.toInt())
        : elapsed;
    return rate(count, generation - first);
  }

  // The first token has no inter-token interval (owner, 2026-11-02).
  static double rate(int tokens, Duration generation) =>
      tokens > 1 && generation.inMicroseconds > 0
      ? (tokens - 1) *
            Duration.microsecondsPerSecond /
            generation.inMicroseconds
      : 0;
}

class HelperJobsState {
  final List<HelperJob> jobs;
  final Set<String> visible;
  final bool expanded;
  const HelperJobsState({
    this.jobs = const [],
    this.visible = const {},
    this.expanded = false,
  });
}

class HelperJobs extends Notifier<HelperJobsState> {
  @override
  HelperJobsState build() => const HelperJobsState();

  void publish(HelperJob job) {
    final isNew = !state.jobs.any((j) => j.id == job.id);
    final jobs = [
      for (final j in state.jobs) j.id == job.id ? job : j,
      if (isNew) job,
    ];
    final visible = isNew ? {...state.visible, job.id} : state.visible;
    final wasRunning = state.jobs.any(
      (j) => state.visible.contains(j.id) && !j.terminal,
    );
    final allDone = jobs
        .where((j) => visible.contains(j.id))
        .every((j) => j.terminal);
    state = HelperJobsState(
      jobs: jobs,
      visible: visible,
      // Collapse once on completion; later report updates preserve manual expansion (owner, 2026-11-02).
      expanded: wasRunning && allDone
          ? false
          : isNew && state.visible.isEmpty
          ? true
          : state.expanded,
    );
  }

  void report(String messageId, String task, String model) {
    final job = state.jobs
        .where(
          (j) =>
              j.messageId == messageId &&
              j.task == task &&
              j.phase == HelperPhase.done &&
              j.reportedTo == null,
        )
        .firstOrNull;
    if (job != null) publish(job.reported(model));
  }

  void dismiss() => state = HelperJobsState(jobs: state.jobs);
  void toggle() => state = HelperJobsState(
    jobs: state.jobs,
    visible: state.visible,
    expanded: !state.expanded,
  );
  void reopen(Iterable<String> ids) => state = HelperJobsState(
    jobs: state.jobs,
    visible: ids.toSet(),
    expanded: true,
  );
}

final helperJobsProvider = NotifierProvider<HelperJobs, HelperJobsState>(
  HelperJobs.new,
);
