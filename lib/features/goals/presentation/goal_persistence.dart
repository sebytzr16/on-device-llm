part of 'goal_provider.dart';

/// Serialization and active-goal checkpoints.
class _GoalPersistenceCodec {
  /// A saved goal; a goal that was running when the app stopped comes back
  /// paused, to be continued by hand.
  static GoalProgress decode(Map<String, dynamic> map) {
    final allowance = map['initialAllowance'];
    final spec = GoalSpec(
      objective: map['objective'] as String,
      successCriteria: map['criteria'] as String? ?? '',
      maxSteps: map['maxSteps'] as int?,
      maxTokens: map['maxTokens'] as int?,
      maxToolCalls: map['maxToolCalls'] as int?,
      maxDuration: map['maxDurationMs'] is int
          ? Duration(milliseconds: map['maxDurationMs'] as int)
          : map['maxMinutes'] == null
          ? null
          : Duration(minutes: map['maxMinutes'] as int),
      initialAllowance: allowance is Map
          ? GoalSpec(
              objective: map['objective'] as String,
              successCriteria: map['criteria'] as String? ?? '',
              maxSteps: allowance['maxSteps'] as int?,
              maxTokens: allowance['maxTokens'] as int?,
              maxToolCalls: allowance['maxToolCalls'] as int?,
              maxDuration: allowance['maxDurationMs'] is int
                  ? Duration(milliseconds: allowance['maxDurationMs'] as int)
                  : null,
            )
          : null,
      specialization: GoalSpecialization.byName(
        map['specialization'] as String?,
      ),
      terms: [
        for (final t in (map['terms'] as List?) ?? const [])
          if (t is String) t,
      ],
      rules: map['rules'] as String? ?? '',
      completionTarget: (map['completionTarget'] as num?)?.toDouble() ?? 0.85,
      searchGuidance: map['searchGuidance'] as String? ?? '',
      clarifications: GoalClarification.parse(map['clarifications']),
    );
    final saved = GoalStatus.values.byName(
      map['status'] as String? ?? 'paused',
    );
    return GoalProgress(
      spec: spec,
      status: saved == GoalStatus.running ? GoalStatus.paused : saved,
      phase:
          GoalPhase.values.asNameMap()[map['phase']] ?? GoalPhase.researching,
      steps: map['steps'] as int? ?? 0,
      usedTokens: map['usedTokens'] as int? ?? 0,
      usedToolCalls: map['usedToolCalls'] as int? ?? 0,
      startedAt: DateTime.parse(map['startedAt'] as String),
      tasks: [
        for (final t in (map['tasks'] as List?) ?? const [])
          GoalTask.fromJson(Map<String, dynamic>.from(t as Map)),
      ],
      sources: [
        for (final s in (map['sources'] as List?) ?? const [])
          GoalSource.fromJson(Map<String, dynamic>.from(s as Map)),
      ],
      reviews: map['reviews'] as int? ?? 0,
      reviewedSteps: map['reviewedSteps'] as int? ?? 0,
      gapRounds: map['gapRounds'] as int? ?? 0,
      models: [
        for (final m in (map['models'] as List?) ?? const [])
          if (m is String) m,
      ],
      report: map['report'] as String? ?? '',
      latestAnswer: map['latestAnswer'] as String? ?? '',
      nextStep: map['nextStep'] as String? ?? spec.objective,
      missing: (map['missing'] as List?)?.cast<String>() ?? const [],
      error: map['error'] as String?,
      reportChecks: GoalCheck.listFromJson(map['reportChecks']),
      planNotes: map['planNotes'] as String? ?? '',
      reviewNotes: map['reviewNotes'] as String? ?? '',
      criteriaSatisfied: map['criteriaSatisfied'] == true,
      clarificationChecked: map['clarificationChecked'] == true,
      awaitingInputSince: DateTime.tryParse(
        map['awaitingInputSince'] as String? ?? '',
      ),
      criteria: [
        for (final c in map['criterionAssessments'] as List? ?? const [])
          if (c is Map) GoalCriterion.fromJson(Map<String, dynamic>.from(c)),
      ],
      actions: [
        for (final a in map['actions'] as List? ?? const [])
          ?PhoneAction.fromJson(a),
      ],
      actionOutcomes: {
        for (final e in (map['actionOutcomes'] as Map? ?? const {}).entries)
          if (int.tryParse('${e.key}') != null &&
              GoalActionOutcome.fromJson(e.value) != null)
            int.parse('${e.key}'): GoalActionOutcome.fromJson(e.value)!,
      },
    );
  }

  static Map<String, dynamic> encode(GoalProgress p, {String? chatId}) => {
    'objective': p.spec.objective,
    'criteria': p.spec.successCriteria,
    'maxSteps': p.spec.maxSteps,
    'maxTokens': p.spec.maxTokens,
    'maxToolCalls': p.spec.maxToolCalls,
    'maxMinutes': p.spec.maxDuration?.inMinutes,
    'maxDurationMs': p.spec.maxDuration?.inMilliseconds,
    if (p.spec.initialAllowance case final allowance?)
      'initialAllowance': {
        'maxSteps': allowance.maxSteps,
        'maxTokens': allowance.maxTokens,
        'maxToolCalls': allowance.maxToolCalls,
        'maxDurationMs': allowance.maxDuration?.inMilliseconds,
      },
    'specialization': p.spec.specialization.name,
    'terms': p.spec.terms,
    'rules': p.spec.rules,
    'completionTarget': p.spec.completionTarget,
    'searchGuidance': p.spec.searchGuidance,
    'clarifications': [for (final q in p.spec.clarifications) q.toJson()],
    'clarificationChecked': p.clarificationChecked,
    'awaitingInputSince': p.awaitingInputSince?.toIso8601String(),
    'usedTokens': p.usedTokens,
    'usedToolCalls': p.usedToolCalls,
    'steps': p.steps,
    'startedAt': p.startedAt.toIso8601String(),
    'phase': p.phase.name,
    'tasks': [for (final t in p.tasks) t.toJson()],
    'sources': [for (final s in p.sources) s.toJson()],
    'reviews': p.reviews,
    'reviewedSteps': p.reviewedSteps,
    'gapRounds': p.gapRounds,
    'models': p.models,
    'report': p.report,
    'latestAnswer': p.latestAnswer,
    'nextStep': p.nextStep,
    'missing': p.missing,
    'status': p.status.name,
    'error': p.error,
    'reportChecks': [for (final c in p.reportChecks) c.toJson()],
    'planNotes': p.planNotes,
    'reviewNotes': p.reviewNotes,
    'criteriaSatisfied': p.criteriaSatisfied,
    'criterionAssessments': [for (final c in p.criteria) c.toJson()],
    'actions': [for (final a in p.actions) a.toJson()],
    'actionOutcomes': {
      for (final e in p.actionOutcomes.entries) '${e.key}': e.value.toJson(),
    },
    'chatId': chatId,
  };
}

extension _GoalPersistence on GoalNotifier {
  Future<void> _restore() async {
    // Retain legacy state until an explicit migration/deletion.
    final raw = await DeviceEncryption.instance.readGoal(GoalNotifier._key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (_goalState != null || _runner != null) return;
      _goalChatId = map['chatId'] as String?;
      _goalState = GoalNotifier.decode(map);
      if (GoalNotifier.isFinished(_goalState!)) {
        _archivedId = GoalHistoryNotifier.idOf(_goalState!);
      }
    } catch (_) {
      await DeviceEncryption.instance.removeGoal(GoalNotifier._key);
    }
  }

  Future<void> _save(GoalProgress progress) async {
    _goalState = progress;
    final saved = await DeviceEncryption.instance.writeGoal(
      GoalNotifier._key,
      jsonEncode(GoalNotifier.encode(progress, chatId: _goalChatId)),
    );
    if (!saved) throw StateError('Goal progress could not be saved.');
    if (GoalNotifier.isFinished(progress) &&
        GoalHistoryNotifier.worthKeeping(progress)) {
      final id = GoalHistoryNotifier.idOf(progress);
      final history = _goalRef.read(goalHistoryProvider.notifier);
      await history.put(progress, chatId: _goalChatId);
      if (_archivedId != null && _archivedId != id) {
        await history.remove(_archivedId!);
      }
      _archivedId = id;
    }
  }
}

/// A finished goal kept for the Goals hub, newest first.
class GoalHistoryEntry {
  final String id;
  final String? chatId;
  final DateTime finishedAt;
  final GoalProgress goal;
  const GoalHistoryEntry({
    required this.id,
    required this.chatId,
    required this.finishedAt,
    required this.goal,
  });
}

/// Every finished goal (request 2026-10-08): Goals opens on a new
/// goal, and the past ones are listed under it to read again, continue or
/// delete. Kept on the device with the other goal state.
class GoalHistoryNotifier extends Notifier<List<GoalHistoryEntry>> {
  static const _key = 'goal_history_v1';
  static const limit = 60;
  late Future<void> ready;
  Future<void> _writes = Future.value();

  @override
  List<GoalHistoryEntry> build() {
    ready = _load();
    return const [];
  }

  /// A goal is known by when it started (a refined or continued goal gets
  /// a new start).
  static String idOf(GoalProgress g) => '${g.startedAt.microsecondsSinceEpoch}';

  /// Worth listing: it found or wrote something (a goal refused before it
  /// started is not).
  static bool worthKeeping(GoalProgress g) =>
      g.report.trim().isNotEmpty || g.sources.isNotEmpty || g.tasks.isNotEmpty;

  Future<void> _load() async {
    final raw = await DeviceEncryption.instance.readGoal(_key);
    if (raw == null) return;
    final entries = <GoalHistoryEntry>[];
    try {
      for (final e in jsonDecode(raw) as List) {
        try {
          final map = Map<String, dynamic>.from(e as Map);
          entries.add(
            GoalHistoryEntry(
              id: map['id'] as String,
              chatId: map['chatId'] as String?,
              finishedAt: DateTime.parse(map['finishedAt'] as String),
              goal: GoalNotifier.decode(
                Map<String, dynamic>.from(map['goal'] as Map),
              ),
            ),
          );
        } catch (_) {
          // One unreadable entry does not hide the others.
        }
      }
    } catch (_) {
      return;
    }
    // Entries put while loading come first.
    final known = {for (final e in state) e.id};
    state = [...state, ...entries.where((e) => !known.contains(e.id))];
  }

  Future<void> _persist() {
    final data = jsonEncode([
      for (final e in state)
        {
          'id': e.id,
          'chatId': e.chatId,
          'finishedAt': e.finishedAt.toIso8601String(),
          'goal': GoalNotifier.encode(e.goal, chatId: e.chatId),
        },
    ]);
    final write = _writes.then((_) async {
      await DeviceEncryption.instance.writeGoal(_key, data);
    });
    _writes = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<void> put(GoalProgress goal, {String? chatId}) async {
    await ready;
    final id = idOf(goal);
    final old = state.where((e) => e.id == id).firstOrNull;
    final entry = GoalHistoryEntry(
      id: id,
      chatId: chatId ?? old?.chatId,
      finishedAt: old?.finishedAt ?? DateTime.now(),
      goal: goal,
    );
    state = [entry, ...state.where((e) => e.id != id)].take(limit).toList();
    await _persist();
  }

  /// Replaces a listed goal (an action outcome recorded on a past goal).
  Future<void> update(GoalProgress goal) async {
    await ready;
    final id = idOf(goal);
    if (!state.any((e) => e.id == id)) return;
    state = [
      for (final e in state)
        e.id == id
            ? GoalHistoryEntry(
                id: e.id,
                chatId: e.chatId,
                finishedAt: e.finishedAt,
                goal: goal,
              )
            : e,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    await ready;
    if (!state.any((e) => e.id == id)) return;
    state = [...state.where((e) => e.id != id)];
    await _persist();
  }
}

final goalHistoryProvider =
    NotifierProvider<GoalHistoryNotifier, List<GoalHistoryEntry>>(
      GoalHistoryNotifier.new,
    );
