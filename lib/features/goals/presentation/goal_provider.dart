import 'dart:async';
import '../../../core/storage/device_encryption.dart';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/device_info.dart';
import '../../../core/providers/shared_providers.dart';
import '../../../data/network/web_search/search_models.dart';
import '../../../inference/engine/text_engine.dart';
import '../../../inference/engine/turn_budget.dart';
import '../../chat/domain/entities/chat_message.dart';
import '../../chat/domain/entities/turn_run.dart';
import '../../chat/domain/research_recipes.dart';
import '../../chat/presentation/providers/chat_provider.dart';
import '../../models/domain/entities/model_info.dart';
import '../../models/presentation/providers/model_manager_provider.dart';
import '../../retrieval/domain/subject_terms.dart';
import '../../retrieval/domain/evidence.dart';
import '../../settings/domain/entities/inference_settings.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import '../../tools/domain/tool_spec.dart';
import '../../tools/phone_actions.dart';
import '../goal_deliverables.dart';
import '../goal_runner.dart';
import '../../chat/domain/search_steps.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

part 'goal_persistence.dart';
part 'goal_execution.dart';
part 'goal_delivery.dart';
part 'goal_research.dart';
part 'goal_model_exchange.dart';
part 'goal_review.dart';
part 'goal_reports.dart';

class GoalNotifier extends Notifier<GoalProgress?> {
  static const _key = 'active_goal_v2';
  GoalRunner? _runner;
  String? _goalChatId;
  GoalUsage _overhead = const GoalUsage();
  Future<void> _runDone = Future.value();

  /// The goal's context window, decided once when it starts, so research
  /// turns and reviews do not reload the model at another size.
  int _goalContext = 8192;
  bool _stopping = false;

  /// A planner or reviewer call holds the engine (audit P1-17).
  bool _ownsEngine = false;

  /// The history entry this goal was last kept under (a continued or
  /// refined goal replaces it when it finishes again).
  String? _archivedId;

  /// Left while its phone actions were still being prepared: put away when
  /// they are.
  bool _dismissWhenDone = false;
  late Future<void> ready;

  /// The chat the goal's steps and report are written to.
  String? get chatId => _goalChatId;

  // Riverpod stays the composition and lifecycle boundary for the parts.
  Ref get _goalRef => ref;
  GoalProgress? get _goalState => state;
  set _goalState(GoalProgress? value) => state = value;

  @override
  GoalProgress? build() {
    ready = _restore();
    ref.onDispose(() => _runner?.pause());
    return null;
  }

  /// A saved goal; running goals restore paused.
  static GoalProgress decode(Map<String, dynamic> map) =>
      _GoalPersistenceCodec.decode(map);

  static Map<String, dynamic> encode(GoalProgress p, {String? chatId}) =>
      _GoalPersistenceCodec.encode(p, chatId: chatId);

  /// Done with: nothing left to run or answer (a paused goal is not).
  static bool isFinished(GoalProgress g) =>
      g.awaitingInputSince == null &&
      const {
        GoalStatus.completed,
        GoalStatus.partial,
        GoalStatus.stopped,
        GoalStatus.failed,
      }.contains(g.status);

  /// Leaving a finished goal puts it away: it stays in the history, and
  /// Goals opens on a new goal next time (request 2026-10-08: "if I
  /// start another goal, it has to start anew").
  Future<void> dismissFinished() async {
    final g = state;
    if (g == null || !isFinished(g)) return;
    if (_runner != null) {
      _dismissWhenDone = true; // its phone actions are still being prepared
      return;
    }
    // A goal finished by an older build was never filed: file it now.
    if (GoalHistoryNotifier.worthKeeping(g)) {
      final history = ref.read(goalHistoryProvider.notifier);
      await history.ready;
      final id = GoalHistoryNotifier.idOf(g);
      if (!ref.read(goalHistoryProvider).any((e) => e.id == id)) {
        await history.put(g, chatId: _goalChatId);
      }
    }
    if (!identical(state, g)) return; // replaced while filing
    await clear();
  }

  /// Makes a goal from the history the current one again, to continue or
  /// refine it. False while another goal is running.
  Future<bool> reopen(GoalHistoryEntry entry) async {
    if (_runner != null) return false;
    final current = state;
    if (current != null && !isFinished(current)) return false;
    _goalChatId = entry.chatId;
    _archivedId = entry.id;
    _dismissWhenDone = false;
    await _save(entry.goal);
    return true;
  }

  Future<void> start(GoalSpec spec) {
    if (ref.read(chatProvider).isGenerating || _runner != null) {
      return _save(
        GoalProgress(
          spec: spec,
          status: GoalStatus.failed,
          steps: 0,
          startedAt: DateTime.now(),
          error: 'Stop the current chat response before starting a Goal.',
        ),
      );
    }
    _goalChatId = null;
    _archivedId = null;
    ref.read(chatProvider.notifier).newChat();
    // The names are fixed when the goal starts, so a resumed goal keeps
    // the same subject lock.
    return _run(
      spec.terms.isEmpty
          ? spec.copyWith(terms: SubjectTerms.of(spec.objective).terms)
          : spec,
    );
  }

  /// Continues a paused, stopped or failed goal. A goal that ran out of
  /// budget gets a fresh allowance of the same size.
  Future<void> continueGoal() async {
    final current = state;
    if (current == null ||
        current.status == GoalStatus.running ||
        current.awaitingInputSince != null) {
      return;
    }
    final extended = continuationSpec(current, DateTime.now());
    await _run(extended, resume: continuedProgress(current, extended));
  }

  /// What Continue resumes: the goal as it stands, with the steps that
  /// failed (an error, not a finding) asked again. The reviews, the extra
  /// round and the last verdict stay: the same findings are not reviewed
  /// again, and a step whose findings were rejected is not researched
  /// again the same way (review, 2026-09-28: Continue reset them and
  /// the goal went round in circles).
  static GoalProgress continuedProgress(
    GoalProgress current,
    GoalSpec spec,
  ) => current.copyWith(
    spec: spec,
    status: GoalStatus.paused,
    clearError: true,
    phase: current.actionOutcomes.values.any((o) => o.confirmed && !o.included)
        ? GoalPhase.checking
        : current.phase,
    reviewedSteps:
        current.actionOutcomes.values.any((o) => o.confirmed && !o.included)
        ? -1
        : current.reviewedSteps,
    actionOutcomes: {
      for (final e in current.actionOutcomes.entries)
        e.key: GoalActionOutcome(
          opened: e.value.opened,
          confirmed: e.value.confirmed,
          included: e.value.included || e.value.confirmed,
          at: e.value.at,
        ),
    },
    tasks: [
      for (final t in current.tasks)
        t.status == GoalTaskStatus.failed ? GoalTask(t.question) : t,
      for (final e in current.actionOutcomes.entries)
        if (e.value.confirmed &&
            !e.value.included &&
            e.key < current.actions.length)
          GoalTask(
            'Record the confirmed phone action',
            kind: GoalTaskKind.recordOutcome,
            status: GoalTaskStatus.done,
            findings:
                'The user confirmed completion of '
                '${current.actions[e.key].kind}: ${current.actions[e.key].title}. '
                '${current.actions[e.key].detail}\nConfirmed at ${e.value.at.toIso8601String()}. '
                'Do not create this action again.',
          ),
    ],
  );

  /// Whether Continue has something to do for [goal]: research left,
  /// findings not reviewed yet, or steps that failed. A finished goal
  /// whose findings were reviewed would only write the same report again.
  static bool canContinue(GoalProgress goal) {
    if (goal.status != GoalStatus.running &&
        goal.actionOutcomes.values.any((o) => o.confirmed && !o.included)) {
      return true;
    }
    if (goal.status == GoalStatus.running ||
        goal.status == GoalStatus.completed ||
        goal.status == GoalStatus.ready) {
      return false;
    }
    if (goal.status != GoalStatus.partial) return true;
    return goal.steps > goal.reviewedSteps ||
        goal.tasks.any((t) => t.status != GoalTaskStatus.done);
  }

  static GoalSpec continuationSpec(GoalProgress current, DateTime now) {
    final old = current.spec;
    final allowance = old.initialAllowance ?? old;
    return old.copyWith(
      initialAllowance: allowance,
      maxSteps: old.maxSteps == null
          ? null
          : current.steps + allowance.maxSteps!,
      unlimitedSteps: old.maxSteps == null,
      maxTokens: old.maxTokens == null
          ? null
          : current.usedTokens + allowance.maxTokens!,
      unlimitedTokens: old.maxTokens == null,
      maxToolCalls: old.maxToolCalls == null
          ? null
          : current.usedToolCalls + allowance.maxToolCalls!,
      unlimitedToolCalls: old.maxToolCalls == null,
      maxDuration: old.maxDuration == null
          ? null
          : now.difference(current.startedAt) + allowance.maxDuration!,
      unlimitedDuration: old.maxDuration == null,
    );
  }

  /// Kept for older callers: same as [continueGoal].
  Future<void> resume() => continueGoal();

  /// Revise a paused or finished goal while retaining its researched evidence.
  static GoalProgress refinedProgress(GoalProgress current, GoalSpec spec) =>
      current.copyWith(
        spec: spec,
        status: GoalStatus.paused,
        phase:
            spec.objective != current.spec.objective ||
                spec.successCriteria != current.spec.successCriteria ||
                spec.searchGuidance != current.spec.searchGuidance
            ? GoalPhase.planning
            : GoalPhase.checking,
        tasks: [
          for (final task in current.tasks)
            if (task.status != GoalTaskStatus.pending) task,
        ],
        reviews: 0,
        reviewedSteps: 0,
        gapRounds: 0,
        criteria: const [],
        criteriaSatisfied: false,
        missing: const [],
        nextStep: '',
        reviewNotes: '',
        reportChecks: const [],
        clearError: true,
      );

  Future<void> refine(GoalSpec spec, {bool run = false}) async {
    final current = state;
    if (current == null ||
        _runner != null ||
        current.awaitingInputSince != null) {
      return;
    }
    final revised = refinedProgress(current, spec);
    await _save(revised);
    if (run) await continueGoal();
  }

  /// Human waiting time is excluded from the duration budget. Answering
  /// questions resumes the original allowance rather than granting a new one.
  static GoalProgress withClarificationAnswers(
    GoalProgress current,
    Map<String, String> answers,
    DateTime now,
  ) => current.copyWith(
    spec: current.spec.copyWith(
      clarifications: [
        for (final q in current.spec.clarifications)
          q.answered(answers[q.id] ?? ''),
      ],
    ),
    startedAt: current.startedAt.add(
      current.awaitingInputSince == null
          ? Duration.zero
          : now.difference(current.awaitingInputSince!),
    ),
    phase: GoalPhase.planning,
    clarificationChecked: true,
    clearAwaitingInput: true,
  );

  Future<void> answerClarifications(Map<String, String> answers) async {
    final current = state;
    if (current == null ||
        current.awaitingInputSince == null ||
        _runner != null) {
      return;
    }
    final answered = withClarificationAnswers(current, answers, DateTime.now());
    await _save(answered);
    await _run(answered.spec, resume: answered);
  }

  /// The actions prompt: the goal, report, local date/time, and action fields.
  static String actionsPrompt(
    String objective,
    String report,
    DateTime now, {
    Set<String>? kinds,
  }) => _GoalActions.actionsPrompt(objective, report, now, kinds: kinds);

  static const maxActions = _GoalActions.maxActions;

  /// The valid actions in a model reply, with dropped kinds in [rejected].
  static List<PhoneAction> actionsFrom(
    Map<String, dynamic>? reply, {
    Map<String, String>? rejected,
  }) => _GoalActions.actionsFrom(reply, rejected: rejected);

  /// The model answering the goal now: the remote model, or the remote
  /// connection's name when it uses the server's default model, or the
  /// loaded model.
  String _modelName() {
    final s = ref.read(settingsProvider);
    if (s.usesRemote) {
      final model = s.remoteModel.trim();
      return model.isNotEmpty ? model : s.activeRemoteProfile?.name ?? '';
    }
    return ref.read(modelManagerProvider).loadedModel?.displayName ?? '';
  }

  /// Records that the user opened action [index] of the current goal (or
  /// that no app could take it); a past goal's is recorded in its history.
  Future<void> recordActionOutcome(
    GoalProgress goal,
    int index,
    bool opened,
  ) async {
    if (index < 0 || index >= goal.actions.length) return;
    final outcome = GoalActionOutcome(
      opened: opened,
      at: DateTime.now(),
      confirmed: opened && goal.actions[index].kind == 'save_file',
      included: goal.actions[index].kind == 'save_file',
    );
    await _recordAction(goal, index, outcome);
  }

  /// The tester's explicit confirmation, separately from opening an intent.
  Future<void> confirmAction(GoalProgress goal, int index) async {
    if (index < 0 || index >= goal.actions.length) return;
    final current = state;
    final actual = current?.startedAt == goal.startedAt ? current! : goal;
    if (actual.actionOutcomes[index]?.opened != true) return;
    await _recordAction(
      actual,
      index,
      GoalActionOutcome(opened: true, confirmed: true, at: DateTime.now()),
    );
  }

  void pause() => _runner?.pause();

  /// Stops only work this goal started: its chat turn or its own engine
  /// call, never a chat the user sent meanwhile (audit P1-17).
  void _cancelOwned() {
    if (_ownsEngine) _model().engine.cancel();
    ref.read(chatProvider.notifier).cancelOwned(this);
  }

  void stop() {
    _stopping = true;
    _runner?.stop();
    _cancelOwned();
  }

  Future<void> clear() async {
    // The finished goal's delivery is stopped, and its end awaited so it
    // cannot save into the next goal.
    if (_runner != null &&
        (state?.preparingActions == true ||
            state?.phase == GoalPhase.delivering)) {
      stop();
      await _runDone;
    }
    if (_runner != null) {
      throw StateError('Stop the current goal first.');
    }
    state = null;
    _goalChatId = null;
    _archivedId = null;
    await DeviceEncryption.instance.removeGoal(_key);
  }

  /// Opens the goal's chat (steps, sources and report) in the chat screen.
  Future<bool> openChat() async {
    final id = _goalChatId;
    if (id == null || ref.read(chatProvider).isGenerating) return false;
    await ref.read(chatProvider.notifier).openChat(id);
    return ref.read(chatProvider).chatId == id;
  }

  Future<void> _useGoalChat() async {
    final chat = ref.read(chatProvider);
    if (_goalChatId != null && chat.chatId != _goalChatId) {
      await ref.read(chatProvider.notifier).openChat(_goalChatId!);
      if (ref.read(chatProvider).chatId != _goalChatId) {
        throw StateError('The Goal conversation could not be opened.');
      }
    }
  }

  /// The goal's language, named for the model: small models asked for "the
  /// language of the goal" sometimes picked another one (an English goal
  /// got Spanish questions on LM Studio, 2026-09-28). Counts common words;
  /// English when unsure.
  static String _language(GoalSpec spec) {
    final words = RegExp(r"[a-zà-ÿ']+")
        .allMatches('${spec.objective} ${spec.criteria}'.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    int count(Set<String> set) => words.where(set.contains).length;
    final fr = count(const {
      'le',
      'la',
      'les',
      'des',
      'du',
      'est',
      'et',
      'pour',
      'dans',
      'une',
      'sur',
      'avec',
      'quel',
      'quels',
      'quelle',
      'meilleur',
      'pas',
      'qui',
      'au',
      'aux',
    });
    final es = count(const {
      'el',
      'los',
      'las',
      'del',
      'es',
      'y',
      'para',
      'en',
      'una',
      'con',
      'por',
      'cuál',
      'cuáles',
      'mejor',
      'qué',
      'como',
      'cómo',
      'que',
      'al',
    });
    final en = count(const {
      'the',
      'and',
      'of',
      'for',
      'to',
      'in',
      'is',
      'what',
      'which',
      'best',
      'how',
      'with',
      'on',
      'a',
      'an',
      'my',
      'are',
      'vs',
      'compare',
    });
    if (fr > en && fr > es) return 'French';
    if (es > en && es > fr) return 'Spanish';
    return 'English';
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  bool get _local => !ref.read(settingsProvider).usesRemote;

  /// The plan and the evidence review think at Low (review,
  /// 2026-09-28): a short reasoning pass makes a better plan and a fairer
  /// verdict, while longer ones only made a run slower.
  static final int _reviewThinking = ThinkingLevel.low.budget;

  TurnBudget _budget(GoalSpec spec, {int? maxReads}) => TurnBudget(
    maxTokens: spec.maxTokens,
    maxToolCalls: spec.maxToolCalls,
    maxReads: maxReads,
    deadline: spec.maxDuration == null
        ? null
        : DateTime.now().add(spec.maxDuration!),
  );

  /// A tool call as the step details show it.
  static Map<String, dynamic> _toolLine(Map<String, dynamic> raw) {
    try {
      final r = ToolResult.fromJson(raw);
      final out = r.output.trim();
      return {
        'name': r.call.name,
        'args': r.call.arguments,
        'ok': r.ok,
        'ms': r.elapsedMs,
        'output': out.length <= 400 ? out : '${out.substring(0, 400)}…',
      };
    } catch (_) {
      return {'name': '${raw['name'] ?? 'tool'}', 'ok': raw['ok'] == true};
    }
  }

  /// The reasoning block and the reply after it; a reply cut inside an
  /// unclosed block has no answer yet.
  static (String, String) splitThinking(String raw) {
    final open = raw.indexOf('<think>');
    final close = raw.lastIndexOf('</think>');
    if (close >= 0) {
      final start = open >= 0 && open < close ? open + 7 : 0;
      return (
        raw.substring(start, close).trim(),
        raw.substring(close + 8).trim(),
      );
    }
    if (open >= 0) return (raw.substring(open + 7).trim(), '');
    return ('', raw.trim());
  }

  /// The first JSON object in [text] (fences and chatter around it
  /// ignored), or null.
  static Map<String, dynamic>? parseJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    for (var end = text.lastIndexOf('}'); end > start;) {
      try {
        final v = jsonDecode(text.substring(start, end + 1));
        return v is Map ? Map<String, dynamic>.from(v) : null;
      } catch (_) {
        end = text.lastIndexOf('}', end - 1);
      }
    }
    return null;
  }

  static List<String> _strings(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is String && e.trim().isNotEmpty)
          e.trim()
        else if (e is Map &&
            (e['question'] ?? e['step'] ?? e['title']) is String)
          '${e['question'] ?? e['step'] ?? e['title']}'.trim(),
  ];

  static String _clip(String notes) => notes.length <= GoalTrace.maxReasoning
      ? notes
      : '${notes.substring(0, GoalTrace.maxReasoning)}…';

  static String ledger(GoalProgress p, {required int perStep}) =>
      _GoalReview.ledger(p, perStep: perStep);
  static String cited(GoalProgress p) => _GoalReview.cited(p);
  static String checkSummary(GoalProgress p) => _GoalReview.checkSummary(p);
  static GoalDecision decisionFromReview(
    Map<String, dynamic> reply,
    GoalProgress progress, {
    String notes = '',
  }) => _GoalReview.decisionFromReview(reply, progress, notes: notes);
  static String gapQuestion(GoalSpec spec, String criterion) =>
      _GoalReview.gapQuestion(spec, criterion);
  static List<GoalCriterion> validateCriteria(
    Map<String, dynamic> reply,
    GoalProgress p,
  ) => _GoalReview.validateCriteria(reply, p);
  static String reportPrompt(
    GoalSpec spec,
    GoalProgress progress, {
    required String findings,
    required String sourceList,
    required List<String> open,
    required String today,
  }) => _GoalReports.reportPrompt(
    spec,
    progress,
    findings: findings,
    sourceList: sourceList,
    open: open,
    today: today,
  );

  /// Whether the last report turn's raw text had reasoning or prompt echo
  /// in it ([GoalChecker.leaked]); the cleaned text alone cannot tell.
  bool _lastLeaked = false;

  static (String, List<GoalCheck>) withoutReportFigures(
    String report,
    List<GoalCheck> checks, {
    required GoalProgress progress,
    required String findings,
    required List<GoalCheck> Function(String text) check,
  }) => _GoalReports.withoutReportFigures(
    report,
    checks,
    progress: progress,
    findings: findings,
    check: check,
  );
}

final goalProvider = NotifierProvider<GoalNotifier, GoalProgress?>(
  GoalNotifier.new,
);
