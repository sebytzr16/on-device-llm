part of 'goals_page.dart';

// The Goals page's small widgets: the model line, step tiles, checks, notes.

/// The model a goal will run with; for a goal that ran, the models its
/// steps used ([used]), which later settings do not change.
class _GoalModelIndicator extends ConsumerWidget {
  final List<String> used;
  const _GoalModelIndicator({this.used = const []});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (used.isNotEmpty) {
      return Text(
        key: const Key('goal-active-model'),
        '${context.l10n.goalModelLabel}: ${used.join(', ')}',
        style: context.text.small.copyWith(height: 1.4),
      );
    }
    final settings = ref.watch(settingsProvider);
    final models = ref.watch(modelManagerProvider);
    final candidate =
        models.loadedModel ??
        models.catalog.where((m) => m.isDownloaded).firstOrNull;
    final name = settings.usesRemote
        ? (settings.remoteModel.isEmpty
              ? context.l10n.remoteDefaultModel
              : settings.remoteModel)
        : candidate?.displayName ?? context.l10n.goalModelNone;
    return Text(
      key: const Key('goal-active-model'),
      '${context.l10n.goalModelLabel}: $name'
      '${!settings.usesRemote && models.loadedModel == null && candidate != null ? ' · ${context.l10n.goalModelOnStart}' : ''}',
      style: context.text.small.copyWith(height: 1.4),
    );
  }
}

class _GoalActions extends StatelessWidget {
  final List<Widget> children;
  const _GoalActions({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final height =
          64 +
          (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 60) * 2;
      return Wrap(
        spacing: AppDesign.sm,
        runSpacing: AppDesign.sm,
        children: [
          for (final button in children)
            SizedBox(
              width: (bounds.maxWidth - AppDesign.sm) / 2,
              height: height.toDouble(),
              child: button,
            ),
        ],
      );
    },
  );
}

class _TaskTile extends StatelessWidget {
  final int index;
  final GoalTask task;
  final List<GoalSource> sources;
  final bool active;
  const _TaskTile({
    required this.index,
    required this.task,
    required this.sources,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    final warn = task.checks.any((x) => x.excludes);
    final icon = switch (task.status) {
      GoalTaskStatus.done when warn => Icon(
        Icons.report_gmailerrorred,
        size: 18,
        color: c.warning,
      ),
      GoalTaskStatus.done => Icon(
        Icons.check_circle,
        size: 18,
        color: c.accent,
      ),
      GoalTaskStatus.failed => Icon(
        Icons.error_outline,
        size: 18,
        color: c.danger,
      ),
      GoalTaskStatus.pending when active => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      GoalTaskStatus.pending => Icon(
        Icons.radio_button_unchecked,
        size: 18,
        color: c.textFaint,
      ),
    };
    final trace = task.trace;
    final hasDetail =
        task.findings.isNotEmpty ||
        (task.error?.isNotEmpty ?? false) ||
        trace != null;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: AppDesign.md, bottom: AppDesign.xs),
      child: Text(text, style: context.text.label.copyWith(color: c.textMuted)),
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: Key('goal-task-$index'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(
          left: AppDesign.xxl,
          bottom: AppDesign.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: icon,
        enabled: hasDetail,
        title: Text('$index. ${task.question}', style: context.text.body),
        subtitle: trace == null
            ? null
            : Text(
                [
                  if (trace.queries.isNotEmpty)
                    t.goalStepSearchCount(trace.queries.length),
                  if (trace.tools.isNotEmpty)
                    t.goalStepToolCount(trace.tools.length),
                  if (trace.sources.isNotEmpty)
                    t.goalSources(trace.sources.length),
                  if (trace.ms > 0) '${(trace.ms / 1000).toStringAsFixed(0)} s',
                ].join(' · '),
                style: context.text.mono.copyWith(color: c.textFaint),
              ),
        children: [
          if (task.checks.isNotEmpty) _ChecksLine(checks: task.checks),
          if (task.findings.isNotEmpty)
            MarkdownBody(
              inlineSyntaxes: [MathSyntax()],
              builders: {'math': MathBuilder()},
              data: task.findings,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                tableColumnWidth: markdownTableColumns(context),
              ),
            )
          else if (task.error != null)
            Text(task.error!, style: context.text.bodyMuted),
          if (trace != null && trace.queries.isNotEmpty) ...[
            label(t.goalStepSearched),
            for (final q in trace.queries)
              Text('“$q”', style: context.text.mono),
          ],
          if (trace != null && trace.tools.isNotEmpty) ...[
            label(t.goalStepTools),
            for (final tool in trace.tools)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDesign.xs),
                child: Text(
                  '${tool['ok'] == false ? '✗' : '▸'} ${tool['name']}'
                  '${(tool['args'] as String?)?.isNotEmpty == true ? ' ${tool['args']}' : ''}'
                  '${(tool['output'] as String?)?.isNotEmpty == true ? '\n   → ${tool['output']}' : ''}',
                  style: context.text.mono,
                ),
              ),
          ],
          if (trace != null && trace.sources.isNotEmpty) ...[
            label(t.goalStepSources),
            for (final n in trace.sources)
              if (n >= 1 && n <= sources.length)
                InkWell(
                  onTap: () async {
                    try {
                      await openExternalLink(sources[n - 1].url);
                    } catch (_) {}
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '[$n] ${sources[n - 1].title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.small.copyWith(color: c.accent),
                    ),
                  ),
                ),
          ],
          if (trace != null && trace.reasoning.isNotEmpty)
            _Notes(title: t.goalStepReasoning, text: trace.reasoning),
          if (trace != null && (trace.tokens > 0 || trace.ms > 0))
            Padding(
              padding: const EdgeInsets.only(top: AppDesign.sm),
              child: Text(
                t.goalStepStats(
                  trace.promptTokens,
                  trace.tokens,
                  (trace.ms / 1000).toStringAsFixed(0),
                  trace.tokensPerSecond.toStringAsFixed(1),
                ),
                style: context.text.mono.copyWith(color: c.textFaint),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the checker found, in words; for the report an empty list reads
/// as passed.
class _ChecksLine extends StatelessWidget {
  final List<GoalCheck> checks;
  final bool report;
  const _ChecksLine({required this.checks, this.report = false});

  /// What was done about a problem rather than a problem left.
  static const _notes = {
    GoalCheckKind.retried,
    GoalCheckKind.revised,
    GoalCheckKind.droppedFigures,
  };

  static String describe(AppLocalizations t, GoalCheck c) => switch (c.kind) {
    GoalCheckKind.drift => t.goalCheckDrift(c.detail),
    GoalCheckKind.offTarget => t.goalCheckOffTarget(c.detail),
    GoalCheckKind.noSources => t.goalCheckNoSources,
    GoalCheckKind.noCitations => t.goalCheckNoCitations,
    GoalCheckKind.badCitations => t.goalCheckBadCitations(c.detail),
    GoalCheckKind.figures => t.goalCheckFigures(c.detail),
    GoalCheckKind.unsupportedClaims => '${t.goalCheckNoSources}: ${c.detail}',
    GoalCheckKind.droppedFigures => t.goalCheckDroppedFigures(c.detail),
    GoalCheckKind.askedUser => t.goalCheckAskedUser,
    GoalCheckKind.leak => t.goalCheckLeak,
    GoalCheckKind.retried => t.goalCheckRetried,
    GoalCheckKind.revised => t.goalCheckRevised,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    final problems = [
      for (final x in checks)
        if (!_notes.contains(x.kind)) x,
    ];
    final notes = [
      for (final x in checks)
        if (_notes.contains(x.kind)) x,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report && problems.isEmpty)
            _line(
              context,
              Icons.verified_outlined,
              c.success,
              t.goalReportChecked,
            ),
          for (final x in problems)
            _line(
              context,
              x.excludes ? Icons.block : Icons.warning_amber_rounded,
              x.excludes ? c.danger : c.warning,
              describe(t, x),
            ),
          for (final x in notes)
            _line(
              context,
              x.kind == GoalCheckKind.droppedFigures
                  ? Icons.content_cut
                  : Icons.replay,
              c.textMuted,
              describe(t, x),
            ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, Color color, String text) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: AppDesign.xs),
            Expanded(
              child: Text(
                text,
                style: context.text.small.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
}

/// A collapsed block of the model's reasoning.
class _Notes extends StatelessWidget {
  final String title, text;
  const _Notes({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(Icons.psychology_outlined, size: 18, color: c.reasoning),
        title: Text(
          title,
          style: context.text.label.copyWith(color: c.textMuted),
        ),
        childrenPadding: const EdgeInsets.only(bottom: AppDesign.sm),
        children: [SelectableText(text, style: context.text.small)],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppDesign.sm, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: AppDesign.radius(AppDesign.rSm),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(text, style: context.text.label.copyWith(color: color)),
  );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Banner({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppDesign.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.4)),
      borderRadius: AppDesign.radius(AppDesign.rMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppDesign.sm),
        Expanded(child: Text(text, style: context.text.body)),
      ],
    ),
  );
}
