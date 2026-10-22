part of 'goals_page.dart';

// Watched goals, past goals and the full history page.

/// The watched goals above the past ones: what each daily check found.
class _Watches extends ConsumerWidget {
  final void Function(String objective) onRunAgain;
  const _Watches({required this.onRunAgain});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watches = ref.watch(goalWatchProvider);
    if (watches.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(goalWatchProvider.notifier);
    final t = context.l10n;
    final c = context.colors;
    String when(DateTime d) =>
        '${MaterialLocalizations.of(context).formatShortMonthDay(d)} '
        '${TimeOfDay.fromDateTime(d).format(context)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppDesign.xl),
        Text(t.goalWatchesTitle, style: context.text.title),
        const SizedBox(height: AppDesign.sm),
        for (final w in watches)
          Builder(
            builder: (context) {
              final change = w.lastChange;
              final checking = notifier.isChecking(w.id);
              final status = checking
                  ? t.goalWatchChecking
                  : w.lastError != null
                  ? switch (w.lastError) {
                      'webOff' => t.goalWatchWebOff,
                      'noResults' => t.goalWatchNoResults,
                      _ => t.goalWatchOffline,
                    }
                  : w.lastCheckedAt == null
                  ? t.goalWatchNotYet
                  : change == null
                  ? t.goalWatchBaseline(when(w.lastCheckedAt!))
                  : change.isEmpty
                  ? t.goalWatchNoChange(when(w.lastCheckedAt!))
                  : t.goalWatchChanged(
                      change.fresh.length,
                      change.figures.length,
                      when(w.lastCheckedAt!),
                    );
              return ExpansionTile(
                key: Key('goal-watch-${w.id}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: AppDesign.md),
                leading: Icon(
                  change != null && !change.isEmpty
                      ? Icons.notifications_active
                      : Icons.visibility_outlined,
                  color: change != null && !change.isEmpty
                      ? c.accent
                      : c.textMuted,
                ),
                title: Text(
                  w.objective,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '$status · ${t.goalWatchDailyAt(TimeOfDay(hour: w.hour, minute: w.minute).format(context))}',
                  style: context.text.small,
                ),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (change != null)
                    for (final f in change.fresh)
                      Text(
                        '• ${t.goalWatchNewResult(f.title.isEmpty ? f.url : f.title)}',
                        style: context.text.bodyMuted,
                      ),
                  if (change != null)
                    for (final f in change.figures)
                      Text(
                        '• ${f.item.title}: ${f.before.join(', ')} → ${f.after.join(', ')}',
                        style: context.text.bodyMuted,
                      ),
                  const SizedBox(height: AppDesign.sm),
                  Wrap(
                    spacing: AppDesign.sm,
                    runSpacing: AppDesign.sm,
                    children: [
                      OutlinedButton.icon(
                        key: Key('goal-watch-check-${w.id}'),
                        onPressed: checking
                            ? null
                            : () => unawaited(notifier.check(w.id)),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(t.goalWatchCheckNow),
                      ),
                      OutlinedButton.icon(
                        key: Key('goal-watch-run-${w.id}'),
                        onPressed: () => onRunAgain(w.objective),
                        icon: const Icon(Icons.flag_outlined, size: 18),
                        label: Text(t.goalWatchRunAgain),
                      ),
                      TextButton.icon(
                        key: Key('goal-watch-stop-${w.id}'),
                        onPressed: () async {
                          await notifier.remove(w.id);
                          try {
                            final items = [...await ScheduleStore.list()];
                            items.removeWhere((p) => p.id == w.id);
                            await ScheduleStore.save(items);
                          } catch (_) {}
                        },
                        icon: const Icon(
                          Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        label: Text(t.goalWatchStop),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// The past goals under the new-goal form, newest first.
class _PastGoals extends ConsumerWidget {
  const _PastGoals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(goalHistoryProvider);
    if (history.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final t = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppDesign.xl),
        Text(t.goalPastTitle, style: context.text.title),
        const SizedBox(height: AppDesign.sm),
        for (final e in history)
          ListTile(
            key: Key('goal-past-${e.id}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              e.goal.status == GoalStatus.completed
                  ? Icons.flag
                  : Icons.outlined_flag,
              color: e.goal.status == GoalStatus.completed
                  ? c.accent
                  : c.textMuted,
            ),
            title: Text(
              e.goal.spec.objective,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_pastStatus(t, e.goal.status)} · '
              '${MaterialLocalizations.of(context).formatMediumDate(e.finishedAt)} · '
              '${t.goalSources(e.goal.sources.length)}',
              style: context.text.small,
            ),
            trailing: Icon(Icons.chevron_right, color: c.textFaint),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => GoalHistoryPage(entry: e),
              ),
            ),
          ),
      ],
    );
  }
}

String _pastStatus(AppLocalizations t, GoalStatus s) => switch (s) {
  GoalStatus.completed => t.goalCompleted,
  GoalStatus.partial => t.goalPartial,
  GoalStatus.stopped => t.goalStopped,
  GoalStatus.failed => t.goalFailed,
  GoalStatus.paused => t.goalPaused,
  GoalStatus.running => t.goalPhaseResearching,
  GoalStatus.ready => t.goalReady,
};

/// A past goal, read only: its report first, then how it was made. It can
/// be made the current goal again (to refine or continue), opened as a
/// chat, or deleted.
class GoalHistoryPage extends ConsumerWidget {
  final GoalHistoryEntry entry;
  const GoalHistoryPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = entry.goal;
    final t = context.l10n;
    final c = context.colors;
    final current = ref.watch(goalProvider);
    final busy = current != null && !GoalNotifier.isFinished(current);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.goalsTitle),
        actions: [
          IconButton(
            key: const Key('goal-past-delete'),
            tooltip: t.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ref.read(goalHistoryProvider.notifier).remove(entry.id);
              navigator.pop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDesign.xl),
          children: [
            ..._headerBlocks(context, goal, compact: true),
            const SizedBox(height: AppDesign.sm),
            _statusRow(context, goal),
            ..._reportBlocks(context, goal, running: false),
            ..._actionBlocks(context, goal),
            const SizedBox(height: AppDesign.lg),
            Wrap(
              spacing: AppDesign.sm,
              runSpacing: AppDesign.sm,
              children: [
                if (entry.chatId != null)
                  OutlinedButton.icon(
                    key: const Key('goal-past-chat'),
                    onPressed:
                        ref.watch(chatProvider.select((s) => s.isGenerating))
                        ? null
                        : () async {
                            final navigator = Navigator.of(context);
                            await ref
                                .read(chatProvider.notifier)
                                .openChat(entry.chatId!);
                            if (ref.read(chatProvider).chatId == entry.chatId) {
                              navigator.popUntil((r) => r.isFirst);
                            }
                          },
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(t.goalOpenChat),
                  ),
                OutlinedButton.icon(
                  key: const Key('goal-past-reopen'),
                  onPressed: busy
                      ? null
                      : () async {
                          final navigator = Navigator.of(context);
                          if (await ref
                              .read(goalProvider.notifier)
                              .reopen(entry)) {
                            navigator.pop();
                          }
                        },
                  icon: const Icon(Icons.tune),
                  label: Text(t.goalPastReopen),
                ),
              ],
            ),
            const SizedBox(height: AppDesign.xl),
            Divider(color: c.hairline),
            const SizedBox(height: AppDesign.sm),
            Text(t.goalHowMade, style: context.text.title),
            const SizedBox(height: AppDesign.sm),
            ..._statsBlocks(context, goal),
            ..._criteriaBlocks(context, goal),
            ..._detailBlocks(context, goal, running: false),
          ],
        ),
      ),
    );
  }
}
