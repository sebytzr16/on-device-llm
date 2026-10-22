part of 'goals_page.dart';

// The blocks a goal's card is built from: header, status, stats, criteria,
// report, actions and details.

/// Line icons matching the rest of the app (the kinds used colour emoji).
IconData _kindIcon(GoalSpecialization k) => switch (k) {
  GoalSpecialization.general => Icons.explore_outlined,
  GoalSpecialization.code => Icons.code,
  GoalSpecialization.science => Icons.science_outlined,
  GoalSpecialization.math => Icons.calculate_outlined,
  GoalSpecialization.news => Icons.newspaper_outlined,
  GoalSpecialization.product => Icons.balance_outlined,
};

/// The goal itself: its kind, objective, criteria, answers to its
/// questions and the names and rules it stays on. [compact] for a finished
/// goal, whose report comes right after.
List<Widget> _headerBlocks(
  BuildContext context,
  GoalProgress goal, {
  bool compact = false,
}) {
  final c = context.colors;
  final t = context.l10n;
  return [
    if (goal.spec.specialization != GoalSpecialization.general)
      Row(
        children: [
          Icon(_kindIcon(goal.spec.specialization), size: 16, color: c.accent),
          const SizedBox(width: AppDesign.xs),
          Text(
            goal.spec.specialization.labelIn(t),
            style: context.text.label.copyWith(color: c.accent),
          ),
        ],
      ),
    Text(
      goal.spec.objective,
      style: compact ? context.text.title : context.text.headline,
    ),
    if (!compact && goal.spec.successCriteria.trim().isNotEmpty) ...[
      const SizedBox(height: AppDesign.xs),
      Text(goal.spec.successCriteria, style: context.text.bodyMuted),
    ],
    if (!compact &&
        goal.spec.clarifications.isNotEmpty &&
        goal.awaitingInputSince == null) ...[
      const SizedBox(height: AppDesign.sm),
      Text(t.goalClarificationAnswers, style: context.text.label),
      for (final q in goal.spec.clarifications)
        Text(
          '${q.question}\n${q.answer.isEmpty ? t.goalAssumptionsAllowed : q.answer}',
          style: context.text.bodyMuted,
        ),
    ],
    if (goal.spec.subject.isNotEmpty || goal.spec.rules.trim().isNotEmpty) ...[
      const SizedBox(height: AppDesign.sm),
      Wrap(
        spacing: AppDesign.xs,
        runSpacing: AppDesign.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: c.accent),
          for (final n in goal.spec.subject.terms) _Pill(n, color: c.accent),
          for (final r in GoalRules.userLines(goal.spec.rules))
            _Pill(r, color: c.textMuted),
        ],
      ),
    ],
  ];
}

double? _fraction(GoalProgress goal) {
  final total = goal.tasks.length;
  if (goal.status == GoalStatus.completed) return 1.0;
  if (total == 0) return goal.status == GoalStatus.running ? null : 0.0;
  return (goal.done / (total + 1)).clamp(0.02, 0.95);
}

/// What the goal is doing, or how it ended.
Widget _statusRow(BuildContext context, GoalProgress goal) {
  final t = context.l10n;
  final phase = switch (goal.phase) {
    GoalPhase.clarifying => t.goalPhaseClarifying,
    GoalPhase.planning => t.goalPhasePlanning,
    GoalPhase.researching =>
      '${t.goalPhaseResearching}${goal.nextTask == null ? '' : ': ${goal.nextTask!.question}'}',
    GoalPhase.checking => t.goalPhaseChecking,
    GoalPhase.writing => t.goalPhaseWriting,
    GoalPhase.verifying => t.goalPhaseVerifying,
    GoalPhase.delivering => t.goalPhaseDelivering,
    GoalPhase.confirming => t.goalAwaitingActions,
    GoalPhase.done => t.goalPhaseDone,
  };
  final status = switch (goal.status) {
    GoalStatus.running => phase,
    GoalStatus.paused =>
      goal.awaitingInputSince != null
          ? t.goalWaitingAnswers
          : _GoalsPageState._limitHit(goal)
          ? t.goalPausedBudget
          : t.goalPaused,
    GoalStatus.completed => t.goalCompleted,
    GoalStatus.partial =>
      goal.phase == GoalPhase.confirming
          ? t.goalAwaitingActions
          : t.goalPartial,
    GoalStatus.stopped => t.goalStopped,
    GoalStatus.failed => t.goalFailed,
    GoalStatus.ready => t.goalReady,
  };
  return Row(
    children: [
      if (goal.status == GoalStatus.running)
        const Padding(
          padding: EdgeInsets.only(right: AppDesign.sm),
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      Expanded(child: Text(status, style: context.text.title)),
    ],
  );
}

/// Steps, sources, tokens and tool calls; the models; an error.
List<Widget> _statsBlocks(BuildContext context, GoalProgress goal) {
  final c = context.colors;
  final t = context.l10n;
  return [
    Text(
      '${t.goalStepsOf(goal.done, goal.tasks.length)} · '
      '${t.goalSources(goal.sources.length)} · '
      '${goal.usedTokens}${goal.spec.maxTokens == null ? '' : ' / ${goal.spec.maxTokens}'} ${t.goalTokensWord} · '
      '${goal.usedToolCalls}${goal.spec.maxToolCalls == null ? '' : ' / ${goal.spec.maxToolCalls}'} ${t.goalToolCallsWord}',
      style: context.text.mono.copyWith(color: c.textFaint),
    ),
    const SizedBox(height: AppDesign.xs),
    _GoalModelIndicator(used: goal.models),
    if (goal.error != null) ...[
      const SizedBox(height: AppDesign.md),
      _Banner(icon: Icons.error_outline, text: goal.error!, color: c.danger),
    ],
  ];
}

/// How well the findings meet each success criterion.
List<Widget> _criteriaBlocks(
  BuildContext context,
  GoalProgress goal, {
  void Function(String criterion)? onTap,
}) {
  if (goal.criteria.isEmpty) return const [];
  final c = context.colors;
  final t = context.l10n;
  return [
    const SizedBox(height: AppDesign.md),
    Text(
      t.goalCoverage(
        (goal.spec.coverage(goal.criteria) * 100).round(),
        (goal.spec.completionTarget * 100).round(),
      ),
      style: context.text.label,
    ),
    Text(t.goalCriteriaReview, style: context.text.title),
    for (final criterion in goal.criteria)
      ListTile(
        onTap: onTap == null ? null : () => onTap(criterion.text),
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          criterion.satisfied ? Icons.check_circle_outline : Icons.help_outline,
          color: criterion.satisfied ? c.accent : c.textMuted,
        ),
        title: Text(criterion.text),
        subtitle: Text(
          [
            criterion.explanation,
            if (criterion.quotes.isNotEmpty)
              for (final quote in criterion.quotes) '“${quote.quote}”'
            else if (criterion.quote.isNotEmpty)
              '“${criterion.quote}”',
            for (final item in criterion.evidence)
              '[${item.source}] “${item.quote}”',
            if (criterion.steps.isNotEmpty)
              t.goalEvidenceSteps(criterion.steps.join(', ')),
          ].where((s) => s.isNotEmpty).join('\n'),
        ),
      ),
  ];
}

/// The report with copy, save and daily-reminder controls.
List<Widget> _reportBlocks(
  BuildContext context,
  GoalProgress goal, {
  required bool running,
}) {
  if (goal.report.isEmpty) return const [];
  final c = context.colors;
  final t = context.l10n;
  return [
    const SizedBox(height: AppDesign.lg),
    Row(
      children: [
        Expanded(
          child: Text(
            goal.status == GoalStatus.paused
                ? t.goalInterimReport
                : t.goalReport,
            style: context.text.title,
          ),
        ),
        IconButton(
          tooltip: t.goalCopyReport,
          icon: const Icon(Icons.copy_outlined, size: 18),
          onPressed: () {
            Clipboard.setData(
              ClipboardData(
                text: _GoalsPageState._withSources(goal.report, goal.sources),
              ),
            );
            showIslandToast(context, t.goalReportCopied, tone: IslandTone.done);
          },
        ),
      ],
    ),
    Container(
      key: const Key('goal-report'),
      padding: const EdgeInsets.all(AppDesign.lg),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border.all(color: c.hairline),
        borderRadius: AppDesign.radius(AppDesign.rMd),
      ),
      child: MarkdownBody(
        inlineSyntaxes: [MathSyntax()],
        builders: {'math': MathBuilder()},
        data: goal.report,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          tableColumnWidth: markdownTableColumns(context),
        ),
      ),
    ),
    if (goal.phase == GoalPhase.done || goal.status == GoalStatus.paused) ...[
      const SizedBox(height: AppDesign.sm),
      _ChecksLine(checks: goal.reportChecks, report: true),
    ],
    if (!running) ...[
      const SizedBox(height: AppDesign.sm),
      Wrap(
        spacing: AppDesign.sm,
        runSpacing: AppDesign.sm,
        children: [
          OutlinedButton.icon(
            key: const Key('goal-save-report'),
            onPressed: () =>
                unawaited(_GoalsPageState._saveReport(context, goal)),
            icon: const Icon(Icons.save_alt_outlined, size: 18),
            label: Text(t.goalSaveReport),
          ),
          OutlinedButton.icon(
            key: const Key('goal-watch'),
            onPressed: () => unawaited(_GoalsPageState._watch(context, goal)),
            icon: const Icon(Icons.update, size: 18),
            label: Text(t.goalWatch),
          ),
        ],
      ),
    ],
  ];
}

/// The phone actions prepared from the report, or a note while they are.
List<Widget> _actionBlocks(BuildContext context, GoalProgress goal) {
  final t = context.l10n;
  return [
    if (goal.preparingActions ||
        (goal.phase == GoalPhase.delivering &&
            goal.status == GoalStatus.running)) ...[
      const SizedBox(height: AppDesign.xl),
      Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppDesign.sm),
          Text(t.goalPreparingActions, style: context.text.bodyMuted),
        ],
      ),
    ],
    if (goal.actions.isNotEmpty) ...[
      const SizedBox(height: AppDesign.xl),
      Text(t.goalActionsTitle, style: context.text.title),
      const SizedBox(height: AppDesign.sm),
      Consumer(
        builder: (context, ref, _) => PhoneActionCards(
          actions: goal.actions,
          opened: {
            for (final e in goal.actionOutcomes.entries)
              if (e.value.opened) e.key: e.value.at,
          },
          confirmed: {
            for (final e in goal.actionOutcomes.entries)
              if (e.value.confirmed) e.key: e.value.at,
          },
          onConfirmed: (i) =>
              unawaited(ref.read(goalProvider.notifier).confirmAction(goal, i)),
          onLaunched: (i, opened) => unawaited(
            ref
                .read(goalProvider.notifier)
                .recordActionOutcome(goal, i, opened),
          ),
        ),
      ),
    ],
  ];
}

/// A [GoalProgress.missing] line; a deliverable left out is said in the
/// user's language.
String _gapText(BuildContext context, String gap) {
  final parsed = GoalDeliverables.parseMissing(gap);
  if (parsed == null) return gap;
  final t = context.l10n;
  final (d, reason) = parsed;
  final item = switch (d.kind) {
    GoalDeliverableKind.file => t.goalDeliverableFile(d.format.toUpperCase()),
    GoalDeliverableKind.event => t.goalDeliverableEvent,
    GoalDeliverableKind.reminder => t.goalDeliverableReminder,
    GoalDeliverableKind.alarm => t.goalDeliverableAlarm,
    GoalDeliverableKind.timer => t.goalDeliverableTimer,
    GoalDeliverableKind.message => t.goalDeliverableMessage,
  };
  final why = switch (reason) {
    'stopped' => t.goalNotPreparedStopped,
    'budget' => t.goalNotPreparedBudget,
    'unreadable' => t.goalNotPreparedUnreadable,
    'tooLong' => t.goalNotPreparedTooLong,
    'none' => t.goalNotPreparedNone,
    _ when reason.startsWith('invalid: ') => t.goalNotPreparedInvalid(
      reason.substring('invalid: '.length),
    ),
    _ => reason,
  };
  return t.goalNotPrepared(item, why);
}

/// The plan's steps, what is still missing, the review notes and the
/// sources.
List<Widget> _detailBlocks(
  BuildContext context,
  GoalProgress goal, {
  required bool running,
}) {
  final t = context.l10n;
  return [
    if (goal.tasks.isNotEmpty) ...[
      const SizedBox(height: AppDesign.xl),
      Text(t.goalPlan, style: context.text.title),
      if (goal.planNotes.isNotEmpty)
        _Notes(title: t.goalPlanNotes, text: goal.planNotes),
      const SizedBox(height: AppDesign.xs),
      // Steps spring in as the plan fills in (a cascade when a finished
      // goal opens).
      for (var i = 0; i < goal.tasks.length; i++)
        SpringEntrance(
          key: ValueKey('task-$i'),
          delay: SpringEntrance.cascade(i, stepMs: 45),
          child: _TaskTile(
            index: i + 1,
            task: goal.tasks[i],
            sources: goal.sources,
            active:
                running &&
                goal.phase == GoalPhase.researching &&
                identical(goal.tasks[i], goal.nextTask),
          ),
        ),
    ],
    // A finished report can still have gaps the last review named.
    if (goal.missing.isNotEmpty) ...[
      const SizedBox(height: AppDesign.lg),
      Text(
        goal.status == GoalStatus.completed
            ? t.goalNotCovered
            : t.goalStillMissing,
        style: context.text.title,
      ),
      for (final gap in goal.missing)
        Text('• ${_gapText(context, gap)}', style: context.text.bodyMuted),
    ],
    if (goal.reviewNotes.isNotEmpty)
      _Notes(title: t.goalReviewNotes, text: goal.reviewNotes),
    if (goal.sources.isNotEmpty) ...[
      const SizedBox(height: AppDesign.xl),
      Text(t.goalSourcesTitle, style: context.text.title),
      for (var i = 0; i < goal.sources.length; i++)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            '[${i + 1}] ${goal.sources[i].title}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            goal.sources[i].outlet ??
                Uri.tryParse(goal.sources[i].url)?.host ??
                '',
          ),
          trailing: const Icon(Icons.open_in_new, size: 16),
          onTap: () async {
            try {
              await openExternalLink(goal.sources[i].url);
            } catch (_) {}
          },
        ),
    ],
  ];
}
