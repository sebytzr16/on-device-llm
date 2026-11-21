part of 'goal_provider.dart';

/// Serialization and active-goal checkpoints.
class _GoalPersistenceCodec {
  /// What a cap this build cannot read falls back to: the goal's own
  /// defaults, so a corrupt number never makes a goal uncapped.
  static const _specDefaults = GoalSpec(objective: '', successCriteria: '');

  /// A stored text; a value of another type reads as [fallback] (audit
  /// 05a-4: one unreadable field must not lose the whole goal).
  static String _text(Object? v, [String fallback = '']) =>
      v is String ? v : fallback;

  static String? _textOrNull(Object? v) => v is String ? v : null;

  /// A stored count: a number or a text of digits reads as the int it
  /// names; anything else as [fallback].
  static int _count(Object? v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  /// A stored cap: absent (or null) stays "no cap"; a value this build
  /// cannot read falls back instead of uncapping the goal.
  static int? _cap(Object? v, int fallback) =>
      v == null ? null : _count(v, fallback);

  /// The share of the criteria a review must find met. A value outside
  /// (0, 1] falls back to the default; the spec refuses to hold another.
  static double _target(Object? v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    return n != null && n > 0 && n <= 1 ? n : 0.85;
  }

  /// A stored duration, in milliseconds or minutes; a text of digits reads
  /// as the number it names.
  static Duration? _duration(Object? ms, Object? minutes) {
    final millis = ms is int
        ? ms
        : ms is num
        ? ms.toInt()
        : int.tryParse(_text(ms).trim());
    if (millis != null) return Duration(milliseconds: millis);
    return minutes == null ? null : Duration(minutes: _count(minutes, 30));
  }

  static List<Object?> _list(Object? v) => v is List ? v : const [];

  static List<String> _texts(Object? v) => [
    for (final s in _list(v))
      if (s is String) s,
  ];

  /// One stored item this build cannot read is dropped, so it never takes
  /// the whole goal with it (audit 05a-4).
  static T? _item<T>(
    Object? raw,
    T? Function(Map<String, dynamic>) read,
    String name,
  ) {
    if (raw is! Map) return null;
    try {
      return read(Map<String, dynamic>.from(raw));
    } catch (e, st) {
      quietFailure('goal_persistence:$name', e, st);
      return null;
    }
  }

  /// The recorded action outcomes by index; a key or an entry this build
  /// cannot read is left out.
  static Map<int, GoalActionOutcome> _outcomes(Object? raw) {
    final out = <int, GoalActionOutcome>{};
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      final index = int.tryParse('${e.key}');
      final outcome = _item(
        e.value,
        (m) => GoalActionOutcome.fromJson(m),
        'outcome',
      );
      if (index != null && outcome != null) out[index] = outcome;
    }
    return out;
  }

  /// A saved goal; a goal that was running when the app stopped comes back
  /// paused, to be continued by hand.
  static GoalProgress decode(Map<String, dynamic> map) {
    // A value a newer build wrote differently must not lose the whole goal
    // (audit 05a-4): every field reads what it can and falls back.
    final objective = _text(map['objective']);
    // The start time is the goal's identity ([GoalHistoryNotifier.idOf]) and
    // the base of its age: a record without a readable one is dropped
    // rather than restored under a new identity (audit 05a-4).
    final startedAt = DateTime.tryParse(_text(map['startedAt']));
    if (startedAt == null) {
      throw const FormatException('The saved goal has no start time.');
    }
    final allowance = map['initialAllowance'];
    final criteria = _text(map['criteria']);
    final spec = GoalSpec(
      objective: objective,
      successCriteria: criteria,
      maxSteps: _cap(map['maxSteps'], _specDefaults.maxSteps!),
      maxTokens: _cap(map['maxTokens'], _specDefaults.maxTokens!),
      maxToolCalls: _cap(map['maxToolCalls'], _specDefaults.maxToolCalls!),
      maxDuration: _duration(map['maxDurationMs'], map['maxMinutes']),
      initialAllowance: allowance is Map
          ? GoalSpec(
              objective: objective,
              successCriteria: criteria,
              maxSteps: _cap(allowance['maxSteps'], _specDefaults.maxSteps!),
              maxTokens: _cap(allowance['maxTokens'], _specDefaults.maxTokens!),
              maxToolCalls: _cap(
                allowance['maxToolCalls'],
                _specDefaults.maxToolCalls!,
              ),
              maxDuration: _duration(allowance['maxDurationMs'], null),
            )
          : null,
      specialization: GoalSpecialization.byName(
        _textOrNull(map['specialization']),
      ),
      terms: _texts(map['terms']),
      rules: _text(map['rules']),
      completionTarget: _target(map['completionTarget']),
      searchGuidance: _text(map['searchGuidance']),
      clarifications: GoalClarification.parse(map['clarifications']),
    );
    final saved =
        GoalStatus.values.asNameMap()[map['status']] ?? GoalStatus.paused;
    return GoalProgress(
      spec: spec,
      status: saved == GoalStatus.running ? GoalStatus.paused : saved,
      phase:
          GoalPhase.values.asNameMap()[map['phase']] ?? GoalPhase.researching,
      steps: _count(map['steps']),
      usedTokens: _count(map['usedTokens']),
      usedToolCalls: _count(map['usedToolCalls']),
      startedAt: startedAt,
      tasks: [
        for (final t in _list(map['tasks']))
          ?_item(t, GoalTask.fromJson, 'task'),
      ],
      sources: [
        for (final s in _list(map['sources']))
          ?_item(s, GoalSource.fromJson, 'source'),
      ],
      reviews: _count(map['reviews']),
      reviewedSteps: _count(map['reviewedSteps']),
      gapRounds: _count(map['gapRounds']),
      models: _texts(map['models']),
      report: _text(map['report']),
      latestAnswer: _text(map['latestAnswer']),
      nextStep: _text(map['nextStep'], objective),
      missing: _texts(map['missing']),
      error: _textOrNull(map['error']),
      reportChecks: [
        for (final c in _list(map['reportChecks']))
          ?_item(c, (m) => GoalCheck.fromJson(m), 'check'),
      ],
      planNotes: _text(map['planNotes']),
      reviewNotes: _text(map['reviewNotes']),
      criteriaSatisfied: map['criteriaSatisfied'] == true,
      clarificationChecked: map['clarificationChecked'] == true,
      awaitingInputSince: DateTime.tryParse(_text(map['awaitingInputSince'])),
      criteria: [
        for (final c in _list(map['criterionAssessments']))
          ?_item(c, GoalCriterion.fromJson, 'criterion'),
      ],
      actions: [
        for (final a in _list(map['actions']))
          ?_item(a, PhoneAction.fromJson, 'action'),
      ],
      actionOutcomes: _outcomes(map['actionOutcomes']),
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
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e, st) {
      // Not JSON at all: nothing in it can be read again.
      quietFailure('goal_persistence:156', e, st);
      await DeviceEncryption.instance.removeGoal(GoalNotifier._key);
      return;
    }
    if (decoded is! Map) {
      await DeviceEncryption.instance.removeGoal(GoalNotifier._key);
      return;
    }
    if (_goalState != null || _runner != null) return;
    try {
      final map = Map<String, dynamic>.from(decoded);
      _goalChatId = map['chatId'] is String ? map['chatId'] as String : null;
      final goal = GoalNotifier.decode(map);
      _goalState = goal;
      if (GoalNotifier.isFinished(goal)) {
        _archivedId = GoalHistoryNotifier.idOf(goal);
      }
    } catch (e, st) {
      // A saved goal this build cannot read at all is kept on the device
      // instead of deleted (audit 05a-4); the next save replaces it.
      quietFailure('goal_persistence:decode', e, st);
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
