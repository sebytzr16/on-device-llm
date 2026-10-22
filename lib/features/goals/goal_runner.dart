import 'dart:math';
import '../../inference/engine/turn_budget.dart';

import '../retrieval/domain/subject_terms.dart';
import '../tools/phone_actions.dart';
import 'goal_deliverables.dart';
import 'goal_rules.dart';
import 'goal_specialization.dart';
import 'goal_criterion.dart';
import 'goal_clarification.dart';

export 'goal_rules.dart';
export 'goal_specialization.dart';
export 'goal_criterion.dart';
export 'goal_clarification.dart';

enum GoalStatus { ready, running, paused, completed, partial, stopped, failed }

/// Where a running goal is: planning its steps, researching one, checking
/// the findings against the criteria, writing the report, checking the
/// report against the findings (and fixing it once), or preparing what the
/// goal asked to have made from it (files, events, messages).
enum GoalPhase {
  clarifying,
  planning,
  researching,
  checking,
  writing,
  verifying,
  delivering,
  confirming,
  done,
}

class GoalSpec {
  final String objective;
  final String successCriteria;
  final int? maxSteps;
  final Duration? maxDuration;
  final int? maxTokens;
  final int? maxToolCalls;

  /// Original allowance for each continuation, separate from cumulative caps.
  final GoalSpec? initialAllowance;
  final GoalSpecialization specialization;

  /// The names the goal is about, which every phase must keep exactly
  /// (read from the objective when the user set none; see [SubjectTerms]).
  final List<String> terms;

  /// The user's own rules, one per line ("Prices in CAD", "Only 2026
  /// sources"); every phase follows them.
  final String rules;
  final List<GoalClarification> clarifications;
  final double completionTarget;
  final String searchGuidance;

  const GoalSpec({
    required this.objective,
    required this.successCriteria,
    this.maxSteps = 6,
    this.maxDuration = const Duration(minutes: 30),
    this.maxTokens = 64000,
    this.maxToolCalls = 20,
    this.initialAllowance,
    this.specialization = GoalSpecialization.general,
    this.terms = const [],
    this.rules = '',
    this.clarifications = const [],
    this.completionTarget = 0.85,
    this.searchGuidance = '',
  }) : assert(completionTarget > 0 && completionTarget <= 1);

  /// The subject lock: the names given, else those in the objective.
  SubjectTerms get subject =>
      terms.isNotEmpty ? SubjectTerms(terms) : SubjectTerms.of(objective);

  /// Text whose names are allowed even when they look like drift: the
  /// user's own words.
  String get allowed => '$objective\n$successCriteria\n$effectiveRules';

  String get clarificationContext => clarifications
      .map(
        (q) =>
            '${q.question}\n${q.answer.isEmpty ? 'Not answered: use reasonable assumptions and state them in the report.' : 'User answer: ${q.answer}'}',
      )
      .join('\n\n');

  String get effectiveRules => [
    if (rules.trim().isNotEmpty) rules,
    if (searchGuidance.trim().isNotEmpty)
      'User search and report guidance (instructions, not evidence):\n$searchGuidance',
    if (clarifications.isNotEmpty)
      'User clarification context (preferences, not research evidence):\n$clarificationContext',
  ].join('\n\n');

  GoalSpec copyWith({
    String? objective,
    String? successCriteria,
    String? rules,
    String? searchGuidance,
    double? completionTarget,
    int? maxSteps,
    Duration? maxDuration,
    int? maxTokens,
    int? maxToolCalls,
    List<String>? terms,
    GoalSpec? initialAllowance,
    List<GoalClarification>? clarifications,
    bool unlimitedSteps = false,
    bool unlimitedDuration = false,
    bool unlimitedTokens = false,
    bool unlimitedToolCalls = false,
  }) => GoalSpec(
    objective: objective ?? this.objective,
    successCriteria: successCriteria ?? this.successCriteria,
    maxSteps: unlimitedSteps ? null : maxSteps ?? this.maxSteps,
    maxDuration: unlimitedDuration ? null : maxDuration ?? this.maxDuration,
    maxTokens: unlimitedTokens ? null : maxTokens ?? this.maxTokens,
    maxToolCalls: unlimitedToolCalls ? null : maxToolCalls ?? this.maxToolCalls,
    initialAllowance: initialAllowance ?? this.initialAllowance,
    specialization: specialization,
    terms: terms ?? this.terms,
    rules: rules ?? this.rules,
    clarifications: clarifications ?? this.clarifications,
    completionTarget: completionTarget ?? this.completionTarget,
    searchGuidance: searchGuidance ?? this.searchGuidance,
  );

  /// The share of the criteria the last review found met. A criterion it
  /// did not assess, or assessed in a form that failed validation, counts
  /// as not met (it no longer zeroes the rest).
  double coverage(List<GoalCriterion> assessments) {
    final items = criteriaItems;
    if (assessments.length != items.length || items.isEmpty) return 0;
    for (var i = 0; i < items.length; i++) {
      if (assessments[i].text != items[i]) return 0;
    }
    return assessments
            .where((c) => c.satisfied && c.validationError.isEmpty)
            .length /
        items.length;
  }

  bool meetsTarget(List<GoalCriterion> assessments) =>
      coverage(assessments) + 1e-9 >= completionTarget;

  bool get unlimited =>
      maxSteps == null &&
      maxDuration == null &&
      maxTokens == null &&
      maxToolCalls == null;

  /// The criteria, or what "done" means when none were given.
  String get criteria => successCriteria.trim().isEmpty
      ? specialization == GoalSpecialization.math
            ? 'The calculation is answered correctly, with a clear derivation.'
            : 'The goal is answered completely, with every important claim backed by a cited source.'
      : successCriteria.trim();

  List<String> get criteriaItems => GoalRules.criteriaLines(criteria);

  /// What the goal asks to have made besides the report.
  List<GoalDeliverable> get deliverables => GoalDeliverables.of(objective);

  static final _broad = RegExp(
    r'(?<![\p{L}\p{N}])(?:compar\w*|versus|vs\.?|best|top \d+|recommend\w*|options?|alternatives?|pros|cons|plan|planning|itinerary|strateg\w*|analy[sz]\w*|overview|history|timeline|guide|review|reviews|which (?:one|should)|should i|'
    r'meilleure?s?|recommand\w*|stratégie|historique|chronologie|avis|lequel|laquelle|'
    r'mejore?s?|recomiend\w*|recomendaci\w*|estrategia|análisis|historia|cronolog\w*|reseñas?|cuál conviene)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  /// A narrow factual goal ("Find the official Nikon Z30 weight"): one
  /// short question (3 to 25 words), at most one criterion, nothing to
  /// compare or plan.
  /// It takes the quick path: no planning call, one research step, a
  /// review without the thinking pass (audit G4, 2026-10-08: the planner
  /// and reviewer spent 54 s on a one-fact goal).
  bool get quick {
    if (specialization == GoalSpecialization.news ||
        specialization == GoalSpecialization.code) {
      return false;
    }
    if (criteriaItems.length > 1 || clarifications.isNotEmpty) return false;
    final q = GoalDeliverables.researchPart(objective);
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final sentences = q
        .split(RegExp(r'[.?!]+(?:\s|$)'))
        .where((x) => x.trim().isNotEmpty)
        .length;
    return words >= 3 && words <= 25 && sentences <= 2 && !_broad.hasMatch(q);
  }
}

/// A source a step used, in the goal's global numbering.
class GoalSource {
  final String title, url;
  final String? outlet;
  final String evidence;
  final DateTime? publishedAt, retrievedAt;
  const GoalSource({
    required this.title,
    required this.url,
    this.outlet,
    this.evidence = '',
    this.publishedAt,
    this.retrievedAt,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    if (outlet != null) 'outlet': outlet,
    if (evidence.isNotEmpty) 'evidence': evidence,
    if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
    if (retrievedAt != null) 'retrievedAt': retrievedAt!.toIso8601String(),
  };

  factory GoalSource.fromJson(Map<String, dynamic> j) => GoalSource(
    title: j['title'] as String? ?? '',
    url: j['url'] as String? ?? '',
    outlet: j['outlet'] as String?,
    evidence: j['evidence'] as String? ?? '',
    publishedAt: DateTime.tryParse(j['publishedAt'] as String? ?? ''),
    retrievedAt: DateTime.tryParse(j['retrievedAt'] as String? ?? ''),
  );
}

enum GoalTaskStatus { pending, done, failed }

enum GoalTaskKind { research, recordOutcome }

/// How a step was researched, for the expandable details on the Goals page:
/// the searches, the tool calls, the sources (global numbers), the model's
/// reasoning and what it cost.
class GoalTrace {
  final List<String> queries;

  /// `{name, args, ok, output}` per tool call, as the chat recorded them.
  final List<Map<String, dynamic>> tools;

  /// The step's sources in the goal's numbering.
  final List<int> sources;
  final String reasoning;
  final int promptTokens, tokens, ms, attempts;
  final double tokensPerSecond;
  const GoalTrace({
    this.queries = const [],
    this.tools = const [],
    this.sources = const [],
    this.reasoning = '',
    this.promptTokens = 0,
    this.tokens = 0,
    this.ms = 0,
    this.attempts = 1,
    this.tokensPerSecond = 0,
  });

  /// Reasoning kept per step (the page shows it; the goal is saved whole).
  static const maxReasoning = 6000;

  GoalTrace withSources(List<int> numbers) => GoalTrace(
    queries: queries,
    tools: tools,
    sources: numbers,
    reasoning: reasoning,
    promptTokens: promptTokens,
    tokens: tokens,
    ms: ms,
    attempts: attempts,
    tokensPerSecond: tokensPerSecond,
  );

  Map<String, dynamic> toJson() => {
    if (queries.isNotEmpty) 'queries': queries,
    if (tools.isNotEmpty) 'tools': tools,
    if (sources.isNotEmpty) 'sources': sources,
    if (reasoning.isNotEmpty) 'reasoning': reasoning,
    'promptTokens': promptTokens,
    'tokens': tokens,
    'ms': ms,
    'attempts': attempts,
    'tps': tokensPerSecond,
  };

  static GoalTrace? fromJson(Object? j) {
    if (j is! Map) return null;
    return GoalTrace(
      queries: [
        for (final q in (j['queries'] as List?) ?? const [])
          if (q is String) q,
      ],
      tools: [
        for (final t in (j['tools'] as List?) ?? const [])
          if (t is Map) Map<String, dynamic>.from(t),
      ],
      sources: [
        for (final n in (j['sources'] as List?) ?? const [])
          if (n is num) n.toInt(),
      ],
      reasoning: j['reasoning'] as String? ?? '',
      promptTokens: (j['promptTokens'] as num?)?.toInt() ?? 0,
      tokens: (j['tokens'] as num?)?.toInt() ?? 0,
      ms: (j['ms'] as num?)?.toInt() ?? 0,
      attempts: (j['attempts'] as num?)?.toInt() ?? 1,
      tokensPerSecond: (j['tps'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One research step of the plan: a question a search can answer, and what
/// was found for it.
class GoalTask {
  final String question;
  final GoalTaskStatus status;

  /// The step's answer with its citations renumbered into the goal's
  /// global source list.
  final String findings;
  final String? error;

  /// What the checker found in the step's answer.
  final List<GoalCheck> checks;
  final GoalTrace? trace;
  const GoalTask(
    this.question, {
    this.kind = GoalTaskKind.research,
    this.status = GoalTaskStatus.pending,
    this.findings = '',
    this.error,
    this.checks = const [],
    this.trace,
  });

  final GoalTaskKind kind;

  /// Findings the report must not use (the step researched something else).
  bool get excluded => checks.any((c) => c.excludes);

  GoalTask copyWith({
    GoalTaskStatus? status,
    String? findings,
    String? error,
    List<GoalCheck>? checks,
    GoalTrace? trace,
  }) => GoalTask(
    question,
    kind: kind,
    status: status ?? this.status,
    findings: findings ?? this.findings,
    error: error ?? this.error,
    checks: checks ?? this.checks,
    trace: trace ?? this.trace,
  );

  Map<String, dynamic> toJson() => {
    'question': question,
    'kind': kind.name,
    'status': status.name,
    'findings': findings,
    if (error != null) 'error': error,
    if (checks.isNotEmpty) 'checks': [for (final c in checks) c.toJson()],
    if (trace != null) 'trace': trace!.toJson(),
  };

  factory GoalTask.fromJson(Map<String, dynamic> j) => GoalTask(
    j['question'] as String? ?? '',
    kind: GoalTaskKind.values.asNameMap()[j['kind']] ?? GoalTaskKind.research,
    status:
        GoalTaskStatus.values.asNameMap()[j['status']] ??
        GoalTaskStatus.pending,
    findings: j['findings'] as String? ?? '',
    error: j['error'] as String?,
    checks: GoalCheck.listFromJson(j['checks']),
    trace: GoalTrace.fromJson(j['trace']),
  );
}

/// What a research step produced.
class GoalStepResult {
  final String answer;

  /// The step's sources in its own citation order ([1] is the first).
  final List<GoalSource> sources;
  final int tokens, toolCalls;
  final List<GoalCheck> checks;

  /// Sources in [trace] are the step's own numbers; the runner moves them
  /// into the goal's numbering.
  final GoalTrace? trace;
  const GoalStepResult({
    required this.answer,
    this.sources = const [],
    this.tokens = 0,
    this.toolCalls = 0,
    this.checks = const [],
    this.trace,
  });
}

/// The planner's questions and its reasoning (shown under the plan).
class GoalPlan {
  final List<String> questions;
  final String notes;
  const GoalPlan(this.questions, {this.notes = ''});
}

class GoalDecision {
  final List<GoalCriterion> criteria;

  final bool satisfied;
  final String nextStep;
  final List<String> missing;

  /// Research questions that would close the gaps (at most a few).
  final List<String> nextSteps;

  /// The reviewer's reply could not be read, so nothing was checked. Not
  /// the same as satisfied: the runner asks again once.
  final bool unchecked;

  /// The reviewer's reasoning.
  final String notes;
  const GoalDecision({
    required this.satisfied,
    this.nextStep = '',
    this.missing = const [],
    this.nextSteps = const [],
    this.unchecked = false,
    this.notes = '',
    this.criteria = const [],
  });

  static const uncheckedNote =
      'Not checked against the success criteria: the review reply could not be read.';
}

class GoalUsage {
  final int tokens;
  final int toolCalls;
  const GoalUsage({this.tokens = 0, this.toolCalls = 0});
}

/// A prepared action the user opened in the phone's app ([opened]), or
/// tried to and no app could take it.
class GoalActionOutcome {
  final bool opened;
  final bool confirmed;

  /// The outcome is already part of a continuation's evidence.
  final bool included;
  final DateTime at;
  const GoalActionOutcome({
    required this.opened,
    required this.at,
    this.confirmed = false,
    this.included = false,
  });

  Map<String, dynamic> toJson() => {
    'opened': opened,
    'confirmed': confirmed,
    'included': included,
    'at': at.toIso8601String(),
  };

  static GoalActionOutcome? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}');
    if (at == null) return null;
    return GoalActionOutcome(
      opened: raw['opened'] == true,
      confirmed: raw['confirmed'] == true,
      included: raw['included'] == true,
      at: at,
    );
  }
}

/// What the delivery phase prepared, and what it could not.
class GoalDelivery {
  final List<PhoneAction> actions;

  /// One line per requested deliverable left out, with the reason.
  final List<String> missing;
  final Map<int, GoalActionOutcome> outcomes;
  const GoalDelivery({
    this.actions = const [],
    this.missing = const [],
    this.outcomes = const {},
  });
}

class GoalProgress {
  final GoalSpec spec;
  final GoalStatus status;
  final GoalPhase phase;

  /// Research steps completed (the step budget counts these).
  final int steps;
  final int usedTokens;
  final int usedToolCalls;
  final DateTime startedAt;
  final List<GoalTask> tasks;
  final List<GoalSource> sources;

  /// Criteria reviews done so far.
  final int reviews;

  /// [steps] when the last review was recorded: a review runs again only
  /// once there is new evidence, so Continue does not re-review the same
  /// findings (review, 2026-09-28: Continue reset the reviews and
  /// the same unreadable review ran again and again).
  final int reviewedSteps;

  /// Extra research rounds added for gaps a review named (at most
  /// [GoalRunner.maxGapRounds]).
  final int gapRounds;

  /// The models that ran the goal, in order of first use; the page shows
  /// these, not what the settings select now.
  final List<String> models;
  final String report;
  final String latestAnswer;
  final String nextStep;
  final List<String> missing;
  final String? error;

  /// What the checker still finds in the report (after at most one fix).
  final List<GoalCheck> reportChecks;

  /// The planner's and the last reviewer's reasoning.
  final String planNotes, reviewNotes;
  final bool criteriaSatisfied;
  final List<GoalCriterion> criteria;
  final bool clarificationChecked;
  final DateTime? awaitingInputSince;

  /// Things the finished goal prepared on the phone (events, alarms,
  /// drafts, files); each is confirmed by the user in the app it opens.
  final List<PhoneAction> actions;

  /// The actions step is running (not saved).
  final bool preparingActions;

  /// What became of each prepared action (by its index in [actions]): the
  /// step after "prepare" is the user opening it in the phone's app, where
  /// it is confirmed (audit G2).
  final Map<int, GoalActionOutcome> actionOutcomes;

  const GoalProgress({
    required this.spec,
    required this.status,
    required this.steps,
    this.phase = GoalPhase.planning,
    this.usedTokens = 0,
    this.usedToolCalls = 0,
    required this.startedAt,
    this.tasks = const [],
    this.sources = const [],
    this.reviews = 0,
    this.reviewedSteps = 0,
    this.gapRounds = 0,
    this.models = const [],
    this.report = '',
    this.latestAnswer = '',
    this.nextStep = '',
    this.missing = const [],
    this.error,
    this.reportChecks = const [],
    this.planNotes = '',
    this.reviewNotes = '',
    this.criteriaSatisfied = false,
    this.criteria = const [],
    this.clarificationChecked = false,
    this.awaitingInputSince,
    this.actions = const [],
    this.preparingActions = false,
    this.actionOutcomes = const {},
  });

  int get done => tasks.where((t) => t.status != GoalTaskStatus.pending).length;
  GoalTask? get nextTask =>
      tasks.where((t) => t.status == GoalTaskStatus.pending).firstOrNull;

  GoalProgress copyWith({
    GoalSpec? spec,
    GoalStatus? status,
    GoalPhase? phase,
    int? steps,
    int? usedTokens,
    int? usedToolCalls,
    List<GoalTask>? tasks,
    List<GoalSource>? sources,
    int? reviews,
    int? reviewedSteps,
    int? gapRounds,
    List<String>? models,
    String? report,
    String? latestAnswer,
    String? nextStep,
    List<String>? missing,
    String? error,
    bool clearError = false,
    List<GoalCheck>? reportChecks,
    String? planNotes,
    String? reviewNotes,
    bool? criteriaSatisfied,
    List<GoalCriterion>? criteria,
    bool? clarificationChecked,
    DateTime? awaitingInputSince,
    bool clearAwaitingInput = false,
    DateTime? startedAt,
    List<PhoneAction>? actions,
    bool? preparingActions,
    Map<int, GoalActionOutcome>? actionOutcomes,
  }) => GoalProgress(
    spec: spec ?? this.spec,
    status: status ?? this.status,
    phase: phase ?? this.phase,
    steps: steps ?? this.steps,
    usedTokens: usedTokens ?? this.usedTokens,
    usedToolCalls: usedToolCalls ?? this.usedToolCalls,
    startedAt: startedAt ?? this.startedAt,
    tasks: tasks ?? this.tasks,
    sources: sources ?? this.sources,
    reviews: reviews ?? this.reviews,
    reviewedSteps: reviewedSteps ?? this.reviewedSteps,
    gapRounds: gapRounds ?? this.gapRounds,
    models: models ?? this.models,
    report: report ?? this.report,
    latestAnswer: latestAnswer ?? this.latestAnswer,
    nextStep: nextStep ?? this.nextStep,
    missing: missing ?? this.missing,
    error: clearError ? null : error ?? this.error,
    reportChecks: reportChecks ?? this.reportChecks,
    planNotes: planNotes ?? this.planNotes,
    reviewNotes: reviewNotes ?? this.reviewNotes,
    criteriaSatisfied: criteriaSatisfied ?? this.criteriaSatisfied,
    criteria: criteria ?? this.criteria,
    clarificationChecked: clarificationChecked ?? this.clarificationChecked,
    awaitingInputSince: clearAwaitingInput
        ? null
        : awaitingInputSince ?? this.awaitingInputSince,
    actions: actions ?? this.actions,
    preparingActions: preparingActions ?? this.preparingActions,
    // New actions start without outcomes.
    actionOutcomes:
        actionOutcomes ?? (actions == null ? this.actionOutcomes : const {}),
  );
}

/// Runs a goal the way a researcher would: plan the questions, research
/// them one at a time (each a clean, searchable question — the old runner
/// sent a 60-word template, which became the search query), keep the
/// findings, check them against the criteria once the plan is done, fill
/// the gaps it names in one extra round at most, then write the report
/// from the findings with citations to the real sources, and what was not
/// covered. Every phase checkpoints; pause, stop and the budgets are
/// honoured between steps.
class GoalRunner {
  final Future<List<GoalClarification>> Function(GoalSpec spec)? clarify;

  /// Research one step; returns its answer and sources.
  final Future<GoalStepResult> Function(
    GoalSpec spec,
    GoalTask task,
    GoalProgress progress,
  )
  research;

  /// The first plan: a few searchable questions.
  final Future<GoalPlan> Function(GoalSpec spec) plan;

  /// Whether the findings meet the criteria, and what to research next.
  final Future<GoalDecision> Function(GoalSpec spec, GoalProgress progress)
  evaluate;

  /// The final report from the findings.
  final Future<String> Function(GoalSpec spec, GoalProgress progress) write;

  /// Prepares the deliverables the goal asks for from the finished report
  /// ([GoalSpec.deliverables]); its tokens are charged to this goal before
  /// it is saved as complete (audit G1).
  final Future<GoalDelivery> Function(GoalSpec spec, GoalProgress progress)?
  deliver;

  /// Checks the report against the findings and fixes it once when the
  /// checks fail; returns the report to keep and what is still wrong.
  final Future<(String, List<GoalCheck>)> Function(
    GoalSpec spec,
    GoalProgress progress,
    String report,
  )?
  verify;
  final Future<void> Function(GoalProgress progress) checkpoint;

  /// Tokens spent by the planner, reviewer and writer (not the steps).
  final GoalUsage Function()? overheadUsage;

  /// The model answering now (recorded in [GoalProgress.models]).
  final String Function()? modelName;
  final DateTime Function() now;

  /// Most tasks a goal may grow to.
  static const maxTasks = 14;

  /// Reviews of the same findings: an unreadable reply is asked once more,
  /// then the report is written from the findings.
  static const maxReviewAttempts = 2;

  /// Extra research rounds for the gaps a review names (decision,
  /// 2026-09-28: "at most one extra research round, only for a named gap").
  static const maxGapRounds = 1;

  /// Questions one extra round may add.
  static const maxGapQuestions = 2;

  GoalProgress? progress;
  bool _pauseRequested = false;
  bool _stopRequested = false;
  bool _active = false;

  GoalRunner({
    required this.research,
    required this.plan,
    required this.evaluate,
    required this.write,
    required this.checkpoint,
    this.clarify,
    this.verify,
    this.deliver,
    this.overheadUsage,
    this.modelName,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  void pause() => _pauseRequested = true;
  void stop() => _stopRequested = true;

  Future<void> _save(GoalProgress p) async {
    progress = p;
    await checkpoint(p);
  }

  /// Each phase receives only the resource allowance still available.
  GoalSpec _remaining(GoalProgress p) => p.spec.copyWith(
    maxTokens: p.spec.maxTokens == null
        ? null
        : max(0, p.spec.maxTokens! - p.usedTokens),
    maxToolCalls: p.spec.maxToolCalls == null
        ? null
        : max(0, p.spec.maxToolCalls! - p.usedToolCalls),
    maxDuration: p.spec.maxDuration == null
        ? null
        : Duration(
            milliseconds: max(
              0,
              p.spec.maxDuration!.inMilliseconds -
                  now().difference(p.startedAt).inMilliseconds,
            ),
          ),
  );

  bool _resourceLimitReached(GoalProgress p) =>
      (p.spec.maxTokens != null && p.usedTokens >= p.spec.maxTokens!) ||
      (p.spec.maxDuration != null &&
          now().difference(p.startedAt) >= p.spec.maxDuration!);

  String _interim(GoalProgress p) => [
    for (final task in p.tasks)
      if (task.status == GoalTaskStatus.done &&
          !task.excluded &&
          task.findings.isNotEmpty)
        '### ${task.question}\n\n${task.findings}',
  ].join('\n\n');

  GoalProgress _charge(GoalProgress p) {
    final extra = overheadUsage?.call() ?? const GoalUsage();
    final model = modelName?.call().trim() ?? '';
    return p.copyWith(
      usedTokens: p.usedTokens + extra.tokens,
      usedToolCalls: p.usedToolCalls + extra.toolCalls,
      models: model.isEmpty || p.models.contains(model)
          ? null
          : [...p.models, model],
    );
  }

  /// Steps saved before figures no source states were left out of the
  /// findings carry them still (the `figures` check used to exclude the
  /// whole step): they are cleaned the same way now, and the check becomes
  /// the note of what was left out.
  static GoalProgress withoutLegacyFigures(GoalProgress p) {
    bool legacy(GoalTask t) =>
        t.status == GoalTaskStatus.done &&
        t.checks.any((c) => c.kind == GoalCheckKind.figures);
    if (p.spec.specialization == GoalSpecialization.math ||
        !p.tasks.any(legacy)) {
      return p;
    }
    final evidence = [for (final s in p.sources) s.evidence];
    GoalTask cleaned(GoalTask t) {
      final (text, removed) = evidence.isEmpty
          ? (t.findings, const <String>[])
          : GoalChecker.withoutUnsupported(t.findings, evidence);
      return t.copyWith(
        findings: text,
        checks: [
          for (final c in t.checks)
            if (c.kind != GoalCheckKind.figures) c,
          if (removed.isNotEmpty)
            GoalCheck(GoalCheckKind.droppedFigures, removed.take(5).join(', ')),
        ],
      );
    }

    return p.copyWith(
      tasks: [for (final t in p.tasks) legacy(t) ? cleaned(t) : t],
    );
  }

  Future<GoalProgress> run(GoalSpec spec, {GoalProgress? resume}) async {
    if (_active) throw StateError('A goal is already running.');
    _active = true;
    _pauseRequested = false;
    _stopRequested = false;
    // A resumed goal runs under the spec given now (a continued goal gets
    // a fresh budget).
    var current = resume == null
        ? GoalProgress(
            spec: spec,
            status: GoalStatus.running,
            steps: 0,
            startedAt: now(),
            nextStep: spec.objective,
          )
        : withoutLegacyFigures(
            resume,
          ).copyWith(spec: spec, status: GoalStatus.running, clearError: true);
    var reviewAttempts = 0;
    final taskCapacity = maxTasks + (resume?.tasks.length ?? 0);
    try {
      await _save(current);
      if (_resourceLimitReached(current)) {
        current = current.copyWith(status: GoalStatus.paused);
        return current;
      }
      if (current.awaitingInputSince != null) {
        current = current.copyWith(status: GoalStatus.paused);
        return current;
      }
      if (current.tasks.isEmpty &&
          !current.clarificationChecked &&
          clarify != null &&
          !current.spec.quick) {
        current = current.copyWith(phase: GoalPhase.clarifying);
        await _save(current);
        final questions = await clarify!(_remaining(current));
        current = _charge(current).copyWith(clarificationChecked: true);
        if (_stopRequested || _pauseRequested) {
          current = current.copyWith(
            status: _stopRequested ? GoalStatus.stopped : GoalStatus.paused,
          );
          return current;
        }
        if (questions.isNotEmpty) {
          current = current.copyWith(
            spec: current.spec.copyWith(
              clarifications: questions.take(3).toList(),
            ),
            status: GoalStatus.paused,
            awaitingInputSince: now(),
          );
          return current;
        }
      }
      if (current.tasks.isEmpty || current.phase == GoalPhase.planning) {
        current = current.copyWith(phase: GoalPhase.planning);
        await _save(current);
        // A narrow factual goal is its own single step (audit G4).
        final planned = current.tasks.isEmpty && current.spec.quick
            ? GoalPlan([GoalDeliverables.researchPart(current.spec.objective)])
            : await plan(_remaining(current));
        current = _charge(current).copyWith(
          planNotes: planned.notes,
          phase: GoalPhase.researching,
          tasks: [
            ...current.tasks,
            for (final q in _clean(
              planned.questions,
              spec,
              orObjective: true,
            ).take(maxTasks))
              GoalTask(q),
          ],
        );
        await _save(current);
      }
      while (true) {
        if (_stopRequested) {
          current = current.copyWith(status: GoalStatus.stopped);
          break;
        }
        final task = current.nextTask;
        if (task != null) {
          if (_pauseRequested) {
            current = current.copyWith(status: GoalStatus.paused);
            break;
          }
          if (_limitReached(current)) {
            // Out of budget with questions left: a report from what was
            // found beats none; Continue researches the rest and rewrites.
            current = current.done > 0
                ? await _writeReport(spec, current, finished: false)
                : current.copyWith(status: GoalStatus.paused);
            break;
          }
          current = current.copyWith(
            phase: GoalPhase.researching,
            nextStep: task.question,
          );
          await _save(current);
          final index = current.tasks.indexOf(task);
          GoalTask finished;
          var sources = current.sources;
          var tokens = 0, calls = 0;
          try {
            final result = await research(_remaining(current), task, current);
            final merged = renumber(result.answer, result.sources, sources);
            sources = merged.$2;
            finished = task.copyWith(
              status: GoalTaskStatus.done,
              findings: merged.$1,
              checks: result.checks,
              trace: result.trace?.withSources([
                for (final s in result.sources)
                  sources.indexWhere((g) => _samePage(g, s)) + 1,
              ]),
            );
            tokens = result.tokens;
            calls = result.toolCalls;
          } catch (e) {
            if (e is TurnLimitException) {
              current = _charge(
                current,
              ).copyWith(status: GoalStatus.paused, error: e.reason);
              if (current.report.isEmpty && current.done > 0) {
                current = current.copyWith(report: _interim(current));
              }
              break;
            }
            if (_stopRequested) {
              current = current.copyWith(status: GoalStatus.stopped);
              break;
            }
            finished = task.copyWith(
              status: GoalTaskStatus.failed,
              error: '$e',
            );
          }
          final tasks = [...current.tasks]..[index] = finished;
          current = current.copyWith(
            tasks: tasks,
            sources: sources,
            steps: current.steps + 1,
            usedTokens: current.usedTokens + tokens,
            usedToolCalls: current.usedToolCalls + calls,
            latestAnswer: finished.findings.isEmpty
                ? current.latestAnswer
                : finished.findings,
            criteriaSatisfied: false,
          );
          current = _charge(current);
          await _save(current);
          continue;
        }
        // Every planned step is done: review the findings once there is
        // new evidence (an unreadable reply is asked once more), research
        // the gaps it names in one extra round at most, then write. A goal
        // out of budget with gap questions pauses with an interim report;
        // Continue researches them.
        if (current.steps > current.reviewedSteps &&
            !_resourceLimitReached(current)) {
          if (_pauseRequested) {
            current = current.copyWith(status: GoalStatus.paused);
            break;
          }
          current = current.copyWith(phase: GoalPhase.checking);
          await _save(current);
          final decision = await evaluate(_remaining(current), current);
          final again =
              decision.unchecked && ++reviewAttempts < maxReviewAttempts;
          final targetMet =
              !decision.unchecked &&
              (decision.satisfied || spec.meetsTarget(decision.criteria));
          current = _charge(current).copyWith(
            reviewNotes: [
              decision.notes,
              if (decision.unchecked && !again)
                'The review could not be read twice. The report is written '
                    'from the findings and lists what they do not cover.',
            ].where((s) => s.isNotEmpty).join('\n\n'),
            reviews: current.reviews + 1,
            reviewedSteps: again ? null : current.steps,
            missing: decision.unchecked
                ? const [GoalDecision.uncheckedNote]
                : decision.missing,
            nextStep: decision.nextStep,
            criteriaSatisfied: targetMet,
            criteria: decision.criteria,
          );
          if (again) continue;
          reviewAttempts = 0;
          final added =
              !targetMet &&
                  !decision.unchecked &&
                  current.gapRounds < maxGapRounds
              ? [
                  for (final q
                      in _clean(
                        decision.nextSteps,
                        spec,
                        asked: [for (final t in current.tasks) t.question],
                      ).take(
                        max(
                          0,
                          min(
                            maxGapQuestions,
                            taskCapacity - current.tasks.length,
                          ),
                        ),
                      ))
                    GoalTask(q),
                ]
              : const <GoalTask>[];
          if (added.isNotEmpty) {
            current = current.copyWith(
              tasks: [...current.tasks, ...added],
              gapRounds: current.gapRounds + 1,
            );
            await _save(current);
            continue;
          }
        }
        if (_stopRequested) {
          current = current.copyWith(status: GoalStatus.stopped);
          break;
        }
        current = await _writeReport(spec, current, finished: true);
        break;
      }
    } catch (error) {
      current = _charge(current).copyWith(
        status: _stopRequested
            ? GoalStatus.stopped
            : error is TurnLimitException
            ? GoalStatus.paused
            : GoalStatus.failed,
        error: _stopRequested ? null : error.toString(),
      );
      if (current.report.isEmpty && current.done > 0) {
        current = current.copyWith(report: _interim(current));
      }
    } finally {
      progress = current;
      try {
        await checkpoint(current);
      } finally {
        _active = false;
      }
    }
    return current;
  }

  /// Writes the report from the findings; a goal with questions still open
  /// ([finished] false) is left paused with its interim report.
  Future<GoalProgress> _writeReport(
    GoalSpec spec,
    GoalProgress current, {
    required bool finished,
  }) async {
    if (_stopRequested || _pauseRequested) {
      return current.copyWith(
        status: _stopRequested ? GoalStatus.stopped : GoalStatus.paused,
      );
    }
    if (_resourceLimitReached(current)) {
      final report = current.report.isNotEmpty
          ? current.report
          : _interim(current);
      return current.copyWith(
        report: report,
        latestAnswer: report,
        status: GoalStatus.paused,
      );
    }
    current = current.copyWith(phase: GoalPhase.writing);
    await _save(current);
    var report = await write(_remaining(current), current);
    current = _charge(current);
    // A reply that was all reasoning is cleaned to nothing: the findings
    // themselves are the report then.
    if (report.trim().isEmpty) report = _interim(current);
    var checks = const <GoalCheck>[];
    if (verify != null &&
        !_stopRequested &&
        !_pauseRequested &&
        !_resourceLimitReached(current)) {
      current = current.copyWith(phase: GoalPhase.verifying, report: report);
      await _save(current);
      (report, checks) = await verify!(_remaining(current), current, report);
    }
    final complete =
        finished &&
        current.criteriaSatisfied &&
        (current.missing.isEmpty || spec.meetsTarget(current.criteria)) &&
        report.trim().isNotEmpty &&
        checks.every((c) => !c.fixable) &&
        current.nextTask == null &&
        (current.tasks.every(
              (t) => t.status == GoalTaskStatus.done && !t.excluded,
            ) ||
            (current.criteria.isNotEmpty &&
                (current.criteria.every((c) => c.satisfied) ||
                    spec.meetsTarget(current.criteria)) &&
                current.tasks.any(
                  (t) => t.status == GoalTaskStatus.done && !t.excluded,
                ))) &&
        (verify == null || current.phase == GoalPhase.verifying);
    var delivered = const GoalDelivery();
    var deliveryMissing = const <String>[];
    if (finished &&
        deliver != null &&
        spec.deliverables.isNotEmpty &&
        report.trim().isNotEmpty &&
        !_pauseRequested) {
      current = _charge(current).copyWith(
        phase: GoalPhase.delivering,
        report: report,
        latestAnswer: report,
        reportChecks: checks,
      );
      await _save(current);
      if (_stopRequested) {
        deliveryMissing = [
          for (final d in spec.deliverables)
            GoalDeliverables.missingEntry(d, 'stopped'),
        ];
      } else {
        delivered = await deliver!(_remaining(current), current);
        deliveryMissing = delivered.missing;
      }
    }
    final awaitingActions = delivered.actions.indexed.any(
      (entry) =>
          entry.$2.kind != 'save_file' &&
          delivered.outcomes[entry.$1]?.confirmed != true,
    );
    return _charge(current).copyWith(
      report: report,
      latestAnswer: report,
      reportChecks: checks,
      actions: deliver != null && finished && spec.deliverables.isNotEmpty
          ? delivered.actions
          : null,
      actionOutcomes:
          deliver != null && finished && spec.deliverables.isNotEmpty
          ? delivered.outcomes
          : null,
      missing: deliveryMissing.isEmpty
          ? null
          : [
              for (final m in current.missing)
                if (!GoalDeliverables.isMissingEntry(m)) m,
              ...deliveryMissing,
            ],
      phase: finished
          ? awaitingActions
                ? GoalPhase.confirming
                : GoalPhase.done
          : GoalPhase.researching,
      status: _stopRequested
          ? GoalStatus.stopped
          : _pauseRequested
          ? GoalStatus.paused
          : complete && deliveryMissing.isEmpty && !awaitingActions
          ? GoalStatus.completed
          : finished
          ? GoalStatus.partial
          : GoalStatus.paused,
    );
  }

  bool _limitReached(GoalProgress current) {
    final spec = current.spec;
    if (spec.maxSteps != null && current.steps >= spec.maxSteps!) {
      return true;
    }
    if (spec.maxDuration != null &&
        now().difference(current.startedAt) >= spec.maxDuration!) {
      return true;
    }
    if (spec.maxTokens != null && current.usedTokens >= spec.maxTokens!) {
      return true;
    }
    if (spec.maxToolCalls != null &&
        current.usedToolCalls >= spec.maxToolCalls!) {
      return true;
    }
    return false;
  }

  static String _norm(String q) => q
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static final _filler =
      ('what which who whom whose when where why how does did are was were '
              'has have had can could should would will the and for with from '
              'about into than there that this these those they them their '
              'its any some each all you')
          .split(' ')
          .toSet();

  /// The words that carry a question's meaning, lightly stemmed so
  /// "charging" and "charge", "prices" and "price" meet.
  static Set<String> terms(String text) => {
    for (final w in _norm(text).split(' '))
      if (w.length > 2 && !_filler.contains(w))
        w.replaceFirst(RegExp(r'(?:ing|ed|es|s|e)$'), ''),
  };

  /// Whether [a] asks what [b] asks, possibly reworded. The goal's own
  /// words are left out ([ignore]): every question shares them, and a
  /// question anchored with the goal (see [anchored]) must not look like
  /// every other anchored one.
  static bool sameQuestion(
    String a,
    String b, {
    Set<String> ignore = const {},
  }) {
    final x = terms(a).difference(ignore), y = terms(b).difference(ignore);
    if (x.isEmpty || y.isEmpty) return x.isEmpty && y.isEmpty;
    return x.intersection(y).length / x.union(y).length >= 0.6;
  }

  static const _pronouns = {'it', 'its', 'this', 'they', 'them', 'their'};

  /// A question that leans on the goal for its subject ("What do they
  /// cost?") is useless as a search query on its own: it gets the goal
  /// appended. A question without such a pronoun, or one that repeats the
  /// goal's words, names its subject and stays as written.
  static String anchored(String question, GoalSpec spec) {
    final leans = _norm(question).split(' ').any(_pronouns.contains);
    final shared = terms(question).intersection(terms(spec.objective));
    if (!leans || shared.length >= 2) return question;
    var subject = spec.objective.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (subject.length > 100) {
      final cut = subject.lastIndexOf(' ', 100);
      subject = '${subject.substring(0, cut > 40 ? cut : 100)}…';
    }
    return '$question ($subject)';
  }

  static final _process = RegExp(
    r'\bsteps? \d+\b|\bcitations?\b|\bcited\b|\bcite\b|\bclaims?\b|\bbacked by\b|\b(?:verify|confirm|check|ensure) (?:that|they|whether|if|all|the (?:claims|sources|findings|citations))\b|\bthe (?:findings|research|sources) (?:above|provided|listed)\b',
    caseSensitive: false,
  );

  /// Usable questions: trimmed, de-numbered, anchored to the goal's subject,
  /// without repeats of each other or of [asked] (reworded ones included);
  /// with [orObjective], the objective itself when nothing usable is left
  /// (a plan is never empty).
  static List<String> _clean(
    List<String> questions,
    GoalSpec spec, {
    List<String> asked = const [],
    bool orObjective = false,
  }) {
    final ignore = terms(spec.objective);
    final subject = spec.subject;
    Set<String> subjects(String question) => {
      for (final term in subject.terms)
        if (SubjectTerms.names(question, term)) term,
    };
    final out = <String>[];
    for (final raw in questions) {
      final q = raw
          .trim()
          .replaceFirst(
            RegExp(r'^(?:[-*•]|\d+[.)]|step \d+:?)\s*', caseSensitive: false),
            '',
          )
          .trim();
      if (q.length < 8 || q.length > 300) continue;
      // A question about the research itself is not researchable: "Confirm
      // that all claims … have explicit citations", "verify the prices in
      // Step 1" (a Qwen3.5 0.8B reviewer on the phone, 2026-09-24).
      if (_process.hasMatch(q)) continue;
      // Making the file or the event is the delivery phase's job.
      if (GoalDeliverables.isDeliverableQuestion(q)) continue;
      final targets = subjects(q);
      final repeat = [...asked, ...out].any((o) {
        final previousTargets = subjects(o);
        return _norm(o) == _norm(q) ||
            (targets.length == previousTargets.length &&
                targets.containsAll(previousTargets) &&
                sameQuestion(o, q, ignore: ignore));
      });
      if (repeat) continue;
      // Drifted names go back to the goal's; a question leaning on a
      // pronoun gets the goal appended; one with no subject at all gets the
      // goal's names ("each camera" searched webcams on the phone).
      final fixed = subject.isEmpty
          ? q
          : subject.repair(q, allowed: spec.allowed, addSubject: false);
      final leaned = anchored(fixed, spec);
      out.add(
        leaned != fixed || subject.isEmpty
            ? leaned
            : subject.repair(fixed, allowed: spec.allowed),
      );
    }
    if (out.isEmpty && orObjective) {
      return [GoalDeliverables.researchPart(spec.objective)];
    }
    return out;
  }

  static final _tracking = RegExp(
    r'^(?:utm_\w+|fbclid|gclid|dclid|msclkid|mc_cid|mc_eid|igshid|ref|ref_src)$',
    caseSensitive: false,
  );

  /// The page a URL names, for finding repeats: without the scheme, "www.",
  /// fragment, trailing slash and tracking parameters.
  static String pageKey(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.host.isEmpty) return url.trim();
    var path = u.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final query = [
      for (final p in u.query.split('&'))
        if (p.isNotEmpty && !_tracking.hasMatch(p.split('=').first)) p,
    ]..sort();
    return '${u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '')}'
        '${u.hasPort ? ':${u.port}' : ''}$path'
        '${query.isEmpty ? '' : '?${query.join('&')}'}';
  }

  static bool _samePage(GoalSource a, GoalSource b) =>
      a.url.trim().isEmpty || b.url.trim().isEmpty
      ? a.url == b.url && a.evidence == b.evidence
      : pageKey(a.url) == pageKey(b.url);

  /// Evidence kept per source when a page's passages are merged.
  static const maxEvidence = 24000;

  /// [a] with the passages of [b] (the same page read again) it lacks.
  static GoalSource _merged(GoalSource a, GoalSource b) {
    final seen = {for (final l in a.evidence.split('\n')) l.trim()};
    final extra = StringBuffer();
    var length = a.evidence.length + 4;
    for (final line in b.evidence.split('\n')) {
      final l = line.trim();
      if (l.isEmpty || !seen.add(l)) continue;
      if (length + l.length + 1 > maxEvidence) break;
      extra.writeln(l);
      length += l.length + 1;
    }
    if (extra.isEmpty) return a;
    return GoalSource(
      title: a.title,
      url: a.url,
      outlet: a.outlet ?? b.outlet,
      evidence: '${a.evidence}\n[…]\n${extra.toString().trim()}',
      publishedAt: a.publishedAt ?? b.publishedAt,
      retrievedAt: a.retrievedAt ?? b.retrievedAt,
    );
  }

  /// A step's answer with its citations moved into the goal's numbering:
  /// the step's [k] becomes the global number of the same page (added to
  /// [global] when new). The same page read again — another excerpt, or
  /// another address for it — stays one source: the passages it lacked are
  /// added, so the earlier citations keep theirs (a page read by three
  /// steps was listed three times). Returns the text and the grown list.
  static (String, List<GoalSource>) renumber(
    String answer,
    List<GoalSource> local,
    List<GoalSource> global,
  ) {
    final all = [...global];
    final map = <int, int>{};
    for (var i = 0; i < local.length; i++) {
      final at = all.indexWhere((g) => _samePage(g, local[i]));
      if (at >= 0) {
        all[at] = _merged(all[at], local[i]);
        map[i + 1] = at + 1;
      } else {
        all.add(local[i]);
        map[i + 1] = all.length;
      }
    }
    final text = answer.replaceAllMapped(RegExp(r'\[(\d+(?:\s*,\s*\d+)*)\]'), (
      m,
    ) {
      final numbers =
          m[1]!
              .split(',')
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>()
              .map((n) => map[n])
              .whereType<int>()
              .toSet()
              .toList()
            ..sort();
      return numbers.isEmpty ? '' : '[${numbers.join(', ')}]';
    });
    return (text, all);
  }
}
