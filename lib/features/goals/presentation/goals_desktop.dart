part of 'goals_page.dart';

extension _DesktopGoals on _GoalsPageState {
  Widget _desktop(BuildContext context, GoalProgress? goal) {
    final t = context.l10n;
    final c = context.colors;
    final history = ref.watch(goalHistoryProvider);
    final selected = history.where((e) => e.id == _selectedHistory).firstOrNull;
    final navigation = ListView(
      key: const Key('desktop-goals-history'),
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          key: const Key('desktop-goals-current'),
          selected: selected == null,
          leading: const Icon(Icons.flag_outlined),
          title: Text(
            goal?.spec.objective ?? t.goalNew,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: goal == null ? null : Text(_pastStatus(t, goal.status)),
          onTap: () => _selectHistory(null),
        ),
        const Divider(),
        Text(t.goalPastTitle, style: context.text.label),
        const SizedBox(height: 12),
        for (final entry in history)
          ListTile(
            key: Key('desktop-goal-history-${entry.id}'),
            selected: entry.id == selected?.id,
            leading: const Icon(Icons.history, size: 18),
            title: Text(
              entry.goal.spec.objective,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_pastStatus(t, entry.goal.status)} \u00b7 '
              '${MaterialLocalizations.of(context).formatMediumDate(entry.finishedAt)}',
            ),
            onTap: () => _selectHistory(entry.id),
          ),
        _Watches(
          onRunAgain: (objective) {
            _selectHistory(null);
            _objective.text = objective;
            if (_setupScroll.hasClients) {
              _setupScroll.glideTo(0, context.motion);
            }
          },
        ),
      ],
    );
    final detail = KeyedSubtree(
      key: ValueKey(selected?.id ?? 'current-goal'),
      child: selected != null
          ? GoalHistoryPage(
              entry: selected,
              embedded: true,
              onClose: () => _selectHistory(null),
            )
          : goal == null
          ? _setup(context)
          : _progress(context, goal),
    );
    return Material(
      color: DesktopTheme.contentLayer(c),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.desktopPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeveloperPageHeader(title: t.goalsTitle),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Compact desktop windows retain both independently scrollable
                  // panes vertically; phone pages never enter this branch.
                  final wide = constraints.maxWidth >= 760;
                  Widget panel(Widget child) => Material(
                    clipBehavior: Clip.antiAlias,
                    color: c.surface,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: c.hairline),
                      borderRadius: AppDesign.radius(AppDesign.rMd),
                    ),
                    child: child,
                  );
                  return Flex(
                    key: const Key('desktop-goals-workspace'),
                    direction: wide ? Axis.horizontal : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: wide ? 300 : null,
                        height: wide ? null : 180,
                        child: panel(navigation),
                      ),
                      SizedBox(width: wide ? 20 : 0, height: wide ? 0 : 16),
                      Expanded(child: panel(detail)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
