part of 'goal_provider.dart';

class _GoalActions {
  /// The actions prompt: the goal, the report, the local date and time, and
  /// the action kinds with their fields.
  /// A long report keeps its head and its end (where the dates, the
  /// verdict and what is missing usually are), not only its head.
  static String actionsPrompt(
    String objective,
    String report,
    DateTime now, {
    Set<String>? kinds,
  }) {
    final cut = report.length > 12000
        ? '${report.substring(0, 5000)}\n…\n${report.substring(report.length - 4000)}'
        : report;
    bool has(String k) => kinds == null || kinds.contains(k);
    final weekday = const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][now.weekday - 1];
    final local = now.toIso8601String().substring(0, 16);
    return 'Goal: $objective\n\n'
        'Now (local time): $weekday $local\n\n'
        'Report:\n$cut\n\n'
        'List only the actions the goal asks for, using facts from the report '
        '(exact dates, times, names, places). Kinds and fields:\n'
        '${has('create_event') ? '- create_event: title, start (YYYY-MM-DDTHH:MM), end (optional), location (optional), notes (optional), all_day (optional true)\n' : ''}'
        '${has('set_reminder') ? '- set_reminder: text, when (YYYY-MM-DDTHH:MM)\n' : ''}'
        '${has('set_alarm') ? '- set_alarm: time (HH:MM), label (optional), days (optional list like ["mon","fri"])\n' : ''}'
        '${has('set_timer') ? '- set_timer: minutes, seconds (optional), label (optional)\n' : ''}'
        '${has('draft_message') ? '- draft_message: channel ("email", "sms" or "any"), to (optional), subject (optional), body\n' : ''}'
        '${has('save_file') ? '- save_file: name, format ("md", "txt", "csv", "html" or "json"), content\n' : ''}'
        'At most $maxActions actions. When the goal asks for none of these, reply {"actions": []}.\n'
        'Reply as {"actions": [{"kind": "...", "args": {...}}]}';
  }

  static const maxActions = 6;

  /// The valid actions in the model's reply; invalid ones are dropped, and
  /// [rejected] gets each dropped kind's problem.
  static List<PhoneAction> actionsFrom(
    Map<String, dynamic>? reply, {
    Map<String, String>? rejected,
  }) {
    final raw = reply?['actions'];
    if (raw is! List) return const [];
    final out = <PhoneAction>[];
    for (final a in raw) {
      if (a is! Map) continue;
      final kind = a['kind'];
      if (kind is! String || !PhoneActions.kinds.contains(kind)) continue;
      // Some models put the fields beside the kind.
      final args = a['args'] is Map
          ? Map<String, dynamic>.from(a['args'] as Map)
          : <String, dynamic>{
              for (final e in a.entries)
                if (e.key != 'kind') '${e.key}': e.value,
            };
      final action = PhoneAction(kind, args);
      final problem = action.problem;
      if (problem != null) {
        rejected?.putIfAbsent(kind, () => problem);
      } else if (out.length < maxActions) {
        out.add(action);
      }
    }
    return out;
  }
}

/// Preparing deliverables and recording action outcomes.
extension _GoalDelivery on GoalNotifier {
  /// The delivery phase (audit G1/G3/G5): what the goal asked to have made
  /// from the finished report. A requested file is the full report and its
  /// sources, made by the app (never retyped by the model, so nothing is
  /// cut); events, reminders, alarms, timers and messages are proposed by
  /// the model within the goal's budget. Nothing is done here: each becomes
  /// a card the user confirms in the phone's own app. What could not be
  /// prepared is named, and the goal is then not complete.
  Future<GoalDelivery> _deliver(GoalSpec spec, GoalProgress progress) async {
    final wanted = spec.deliverables;
    final actions = <PhoneAction>[];
    final reasons = <String, String>{};
    for (final w in wanted) {
      if (w.kind != GoalDeliverableKind.file) continue;
      final file = GoalDeliverables.reportFile(
        spec.objective,
        progress.report,
        progress.sources,
        format: w.format,
      );
      if (file == null) {
        reasons[w.actionKind] = 'tooLong';
      } else {
        actions.add(file);
      }
    }
    final kinds = {
      for (final w in wanted)
        if (w.kind != GoalDeliverableKind.file) w.actionKind,
    };
    // A continuation records completed actions; it never proposes another
    // copy of an event/message the user already confirmed. Keep the other
    // prepared cards, and refresh report files from the complete new report.
    if (progress.actionOutcomes.values.any((o) => o.confirmed)) {
      final outcomes = <int, GoalActionOutcome>{};
      for (final (oldIndex, action) in progress.actions.indexed) {
        if (!kinds.contains(action.kind)) continue;
        final index = actions.length;
        actions.add(action);
        final outcome = progress.actionOutcomes[oldIndex];
        if (outcome != null) outcomes[index] = outcome;
      }
      return GoalDelivery(
        actions: actions,
        outcomes: outcomes,
        missing: GoalDeliverables.missing(wanted, actions, reasons: reasons),
      );
    }
    if (kinds.isNotEmpty) {
      try {
        final (reply, _) = await _json(
          'You turn a finished research report into actions on the user\'s '
          'phone. You only prepare them; the user confirms each one. Reply '
          'with JSON only.',
          GoalNotifier.actionsPrompt(
            spec.objective,
            progress.report,
            DateTime.now(),
            kinds: kinds,
          ),
          maxTokens: 900,
          budgetSpec: spec,
        );
        if (reply == null) {
          for (final k in kinds) {
            reasons[k] = 'unreadable';
          }
        }
        final rejected = <String, String>{};
        for (final a in GoalNotifier.actionsFrom(reply, rejected: rejected)) {
          if (kinds.contains(a.kind)) actions.add(a);
        }
        for (final e in rejected.entries) {
          reasons.putIfAbsent(e.key, () => 'invalid: ${e.value}');
        }
      } on TurnLimitException {
        for (final k in kinds) {
          reasons[k] = 'budget';
        }
      } catch (_) {
        for (final k in kinds) {
          reasons[k] = _stopping ? 'stopped' : 'unreadable';
        }
      }
    }
    return GoalDelivery(
      actions: actions,
      missing: GoalDeliverables.missing(wanted, actions, reasons: reasons),
    );
  }

  Future<void> _recordAction(
    GoalProgress goal,
    int index,
    GoalActionOutcome outcome,
  ) async {
    final current = _goalState;
    if (current != null && current.startedAt == goal.startedAt) {
      await _save(
        current.copyWith(
          actionOutcomes: {...current.actionOutcomes, index: outcome},
        ),
      );
      return;
    }
    await _goalRef
        .read(goalHistoryProvider.notifier)
        .update(
          goal.copyWith(
            actionOutcomes: {...goal.actionOutcomes, index: outcome},
          ),
        );
  }
}
