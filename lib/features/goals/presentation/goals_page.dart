import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../../core/design/markdown_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design/app_design.dart';
import '../../../core/design/markdown_tables.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/external_links.dart';
import '../../chat/presentation/providers/chat_provider.dart';
import '../../models/domain/entities/model_catalog.dart';
import '../../models/presentation/providers/model_manager_provider.dart';
import '../../retrieval/domain/subject_terms.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import '../../schedule/scheduled_prompt.dart';
import '../../tools/phone_actions.dart';
import '../../tools/presentation/phone_action_cards.dart';
import '../goal_deliverables.dart';
import '../goal_runner.dart';
import 'goal_provider.dart';
import 'goal_watch_provider.dart';
import 'goal_clarification_dialog.dart';
import 'goal_texts.dart';
import 'goal_evidence_page.dart';
import '../../../core/island/status_island.dart';
import '../../../core/motion/motion.dart';
import '../../../core/design/app_dialog.dart';

part 'goal_tiles.dart';
part 'goal_blocks.dart';
part 'goal_history.dart';

/// How much work a goal may do before it pauses for the user.
enum GoalBudget {
  // Token budgets doubled on 2026-09-24 when every phase thought first;
  // kept since 2026-09-28 (only the plan and review think) as room for
  // the evidence.
  quick('Quick', 'About 4 searches · up to 10 min', 4, 10, 64000, 12),
  standard('Standard', 'About 8 searches · up to 30 min', 8, 30, 128000, 30),
  deep('Deep', 'About 14 searches · up to 60 min', 14, 60, 256000, 60),
  unlimited(
    'Unlimited',
    'Until done, paused or stopped',
    null,
    null,
    null,
    null,
  ),
  custom('Custom', 'Set your own limits', null, null, null, null);

  final String label, detail;
  final int? steps, minutes, tokens, toolCalls;
  const GoalBudget(
    this.label,
    this.detail,
    this.steps,
    this.minutes,
    this.tokens,
    this.toolCalls,
  );
}

class GoalsPage extends ConsumerStatefulWidget {
  /// Prefills the goal (from the chat's "Research as a goal" entry points).
  final String? initialObjective;
  final GoalSpecialization? initialSpecialization;
  const GoalsPage({
    super.key,
    this.initialObjective,
    this.initialSpecialization,
  });

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  bool _showingQuestions = false;
  String? _questionPopupKey;
  late final _objective = TextEditingController(text: widget.initialObjective);
  final _criteria = TextEditingController();
  final _rules = TextEditingController();
  final _guidance = TextEditingController();
  late GoalSpecialization _kind =
      widget.initialSpecialization ?? GoalSpecialization.general;
  final _steps = TextEditingController(text: '6');
  final _minutes = TextEditingController(text: '30');
  final _tokens = TextEditingController(text: '64000');
  final _toolCalls = TextEditingController(text: '20');
  GoalBudget _budget = GoalBudget.standard;
  double _completionTarget = 0.85;

  /// The names the goal stays on; null follows the objective as it is
  /// typed, a list is the user's own edit.
  List<String>? _terms;

  List<String> get _subject => _terms ?? SubjectTerms.of(_objective.text).terms;

  static const _draftKey = 'goal_draft_v1';
  Timer? _draftTimer;
  Future<void> _draftWrites = Future.value();
  int _draftRevision = 0;
  bool _restoringDraft = false;
  bool _draftStarted = false;

  late final GoalNotifier _goals;
  final _setupScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _goals = ref.read(goalProvider.notifier);
    // Watched goals that are due are checked when Goals opens (the daily
    // notification opens it).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(ref.read(goalWatchProvider.notifier).checkDue()),
    );
    if (widget.initialObjective == null) {
      unawaited(_loadDraft());
    } else {
      // A new goal from the chat: a finished one gives way to it.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_goals.dismissFinished()),
      );
    }
    for (final c in [
      _objective,
      _criteria,
      _rules,
      _guidance,
      _steps,
      _minutes,
      _tokens,
      _toolCalls,
    ]) {
      c.addListener(_draftChanged);
    }
  }

  /// A goal being written survives leaving the page (the fields used to
  /// start empty every time).
  Future<void> _loadDraft() async {
    final revision = _draftRevision;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_draftKey);
      if (raw == null || !mounted || revision != _draftRevision) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _restoringDraft = true;
      setState(() {
        _objective.text = j['objective'] as String? ?? '';
        _criteria.text = j['criteria'] as String? ?? '';
        _rules.text = j['rules'] as String? ?? '';
        _guidance.text = j['searchGuidance'] as String? ?? '';
        final target = (j['completionTarget'] as num?)?.toDouble();
        _completionTarget = [0.8, 0.85, 0.9, 1.0].contains(target)
            ? target!
            : 0.85;
        _steps.text = j['steps'] as String? ?? '6';
        _minutes.text = j['minutes'] as String? ?? '30';
        _tokens.text = j['tokens'] as String? ?? '64000';
        _toolCalls.text = j['toolCalls'] as String? ?? '20';
        _kind = GoalSpecialization.byName(j['kind'] as String?);
        _budget =
            GoalBudget.values.asNameMap()[j['budget']] ?? GoalBudget.standard;
        final terms = j['terms'];
        _terms = terms is List ? [for (final t in terms) '$t'] : null;
      });
    } catch (_) {
    } finally {
      _restoringDraft = false;
    }
  }

  void _draftChanged() {
    if (_restoringDraft) return;
    _draftStarted = false;
    _draftRevision++;
    if (mounted) setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() {
    _draftRevision++;
    final empty = _objective.text.trim().isEmpty;
    // Snapshot before any await, including a final flush when the page closes.
    final data = jsonEncode({
      'objective': _objective.text,
      'criteria': _criteria.text,
      'rules': _rules.text,
      'searchGuidance': _guidance.text,
      'completionTarget': _completionTarget,
      'kind': _kind.name,
      'budget': _budget.name,
      'terms': ?_terms,
      'steps': _steps.text,
      'minutes': _minutes.text,
      'tokens': _tokens.text,
      'toolCalls': _toolCalls.text,
    });
    final write = _draftWrites.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (empty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, data);
      }
    });
    _draftWrites = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<void> _addTerm() async {
    final name = await promptText(
      context,
      title: context.l10n.goalSubjectAdd,
      hint: context.l10n.goalSubjectExample,
      confirmLabel: context.l10n.commonSave,
      fieldKey: const Key('goal-term-field'),
    );
    final t = name?.trim() ?? '';
    if (t.isEmpty || !mounted) return;
    setState(() => _terms = [..._subject.where((x) => x != t), t]);
    if (!_draftStarted) unawaited(_saveDraft());
  }

  @override
  void dispose() {
    // Leaving a finished goal puts it away into the past goals; next time
    // Goals opens on a new one.
    final goals = _goals;
    scheduleMicrotask(() => unawaited(goals.dismissFinished()));
    _draftTimer?.cancel();
    _setupScroll.dispose();
    if (!_draftStarted) unawaited(_saveDraft());
    _objective.dispose();
    _criteria.dispose();
    _rules.dispose();
    _guidance.dispose();
    _steps.dispose();
    _minutes.dispose();
    _tokens.dispose();
    _toolCalls.dispose();
    super.dispose();
  }

  void _start() {
    final objective = _objective.text.trim();
    if (objective.isEmpty) {
      showIslandToast(context, context.l10n.goalDescribeFirst);
      return;
    }
    GoalSpec spec;
    if (_budget == GoalBudget.custom) {
      final steps = int.tryParse(_steps.text);
      final minutes = int.tryParse(_minutes.text);
      final tokens = int.tryParse(_tokens.text);
      final calls = int.tryParse(_toolCalls.text);
      if ([steps, minutes, tokens, calls].any((v) => v == null || v < 1)) {
        showIslandToast(
          context,
          context.l10n.goalLimitsInvalid,
          tone: IslandTone.error,
        );
        return;
      }
      spec = GoalSpec(
        objective: objective,
        successCriteria: _criteria.text.trim(),
        searchGuidance: _guidance.text.trim(),
        maxSteps: steps,
        maxDuration: Duration(minutes: minutes!),
        maxTokens: tokens,
        maxToolCalls: calls,
        specialization: _kind,
        terms: _subject,
        rules: _rules.text.trim(),
      );
    } else {
      final b = _budget;
      spec = GoalSpec(
        objective: objective,
        successCriteria: _criteria.text.trim(),
        searchGuidance: _guidance.text.trim(),
        maxSteps: b.steps,
        maxDuration: b.minutes == null ? null : Duration(minutes: b.minutes!),
        maxTokens: b.tokens,
        maxToolCalls: b.toolCalls,
        specialization: _kind,
        terms: _subject,
        rules: _rules.text.trim(),
      );
    }
    spec = spec.copyWith(completionTarget: _completionTarget);
    _draftTimer?.cancel();
    _draftStarted = true;
    _draftWrites = _draftWrites.then((_) async {
      await (await SharedPreferences.getInstance()).remove(_draftKey);
    });
    unawaited(ref.read(goalProvider.notifier).start(spec));
  }

  @override
  Widget build(BuildContext context) {
    final goal = ref.watch(goalProvider);
    final waiting = goal?.awaitingInputSince?.toIso8601String();
    if (waiting != null && waiting != _questionPopupKey) {
      _questionPopupKey = waiting;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(goalProvider)?.awaitingInputSince != null) {
          unawaited(_askQuestions());
        }
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.goalsTitle),
        actions: [
          if (goal == null && ref.watch(goalHistoryProvider).isNotEmpty)
            IconButton(
              key: const Key('goal-past-jump'),
              tooltip: context.l10n.goalPastTitle,
              icon: const Icon(Icons.history),
              // The past goals are at the end of the form. The list is
              // built lazily, so its end is only known once reached.
              onPressed: () async {
                for (var i = 0; i < 4 && _setupScroll.hasClients; i++) {
                  final end = _setupScroll.position.maxScrollExtent;
                  if ((_setupScroll.offset - end).abs() < 1) break;
                  await _setupScroll.glideTo(
                    end,
                    context.motion,
                    duration: i == 0 ? AppMotion.glide : AppMotion.fadeIn,
                  );
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: goal == null ? _setup(context) : _progress(context, goal),
      ),
    );
  }

  Future<void> _askQuestions() async {
    final goal = ref.read(goalProvider);
    if (_showingQuestions || goal?.awaitingInputSince == null) return;
    _showingQuestions = true;
    final answers = await showAppDialog<Map<String, String>>(
      context: context,
      builder: (_) =>
          GoalClarificationDialog(questions: goal!.spec.clarifications),
    );
    _showingQuestions = false;
    if (!mounted || answers == null) return;
    unawaited(ref.read(goalProvider.notifier).answerClarifications(answers));
  }

  Future<void> _refine(GoalProgress goal) async {
    final objective = TextEditingController(text: goal.spec.objective);
    final criteria = TextEditingController(text: goal.spec.successCriteria);
    final rules = TextEditingController(text: goal.spec.rules);
    final guidance = TextEditingController(text: goal.spec.searchGuidance);
    var target = goal.spec.completionTarget;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(dialog.l10n.goalRefine),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: AppDesign.md,
                children: [
                  TextField(
                    key: const Key('goal-refine-objective'),
                    controller: objective,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: dialog.l10n.goalLabel,
                    ),
                  ),
                  TextField(
                    key: const Key('goal-refine-criteria'),
                    controller: criteria,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: dialog.l10n.goalCriteriaLabel,
                      helperText: dialog.l10n.goalCriteriaSeparate,
                    ),
                  ),
                  TextField(
                    key: const Key('goal-refine-rules'),
                    controller: rules,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: dialog.l10n.goalRulesLabel,
                    ),
                  ),
                  TextField(
                    key: const Key('goal-search-guidance'),
                    controller: guidance,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: dialog.l10n.goalSearchGuidance,
                      hintText: dialog.l10n.goalSearchGuidanceHint,
                    ),
                  ),
                  _coverageControl(
                    dialog,
                    target,
                    (v) => update(() => target = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(dialog.l10n.cancel),
            ),
            TextButton(
              onPressed: objective.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialog, false),
              child: Text(dialog.l10n.commonSave),
            ),
            FilledButton(
              onPressed: objective.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: Text(dialog.l10n.goalRefineRun),
            ),
          ],
        ),
      ),
    );
    final run = await Navigator.of(context).push(route);
    final changedObjective = objective.text.trim();
    final spec = goal.spec.copyWith(
      objective: changedObjective,
      successCriteria: criteria.text.trim(),
      rules: rules.text.trim(),
      searchGuidance: guidance.text.trim(),
      completionTarget: target,
      terms: changedObjective == goal.spec.objective
          ? goal.spec.terms
          : SubjectTerms.of(changedObjective).terms,
    );
    // The pop result arrives before the closing animation removes its fields.
    await route.completed;
    for (final controller in [objective, criteria, rules, guidance]) {
      controller.dispose();
    }
    if (run != null && mounted && changedObjective.isNotEmpty) {
      unawaited(ref.read(goalProvider.notifier).refine(spec, run: run));
    }
  }

  Future<void> _evidence([String? criterion]) async {
    final steer = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GoalEvidencePage(initialCriterion: criterion),
      ),
    );
    if (!mounted || steer != true) return;
    final goal = ref.read(goalProvider);
    if (goal != null && goal.status != GoalStatus.running) await _refine(goal);
  }

  Widget _coverageControl(
    BuildContext context,
    double target,
    ValueChanged<double> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.l10n.goalCompletionTarget, style: context.text.label),
      Wrap(
        spacing: AppDesign.sm,
        children: [
          for (final value in [0.8, 0.85, 0.9, 1.0])
            ChoiceChip(
              label: Text('${(value * 100).round()}%'),
              selected: target == value,
              onSelected: (_) => changed(value),
            ),
        ],
      ),
      Text(context.l10n.goalCompletionHint, style: context.text.bodyMuted),
    ],
  );

  Widget _setup(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(AppDesign.xl),
      controller: _setupScroll,
      children: [
        Text(context.l10n.goalIntro, style: context.text.bodyMuted),
        const SizedBox(height: AppDesign.xs),
        const _GoalModelIndicator(),
        if (!settings.webSearchEnabled) ...[
          const SizedBox(height: AppDesign.md),
          _Banner(
            icon: Icons.public_off_outlined,
            text: context.l10n.goalWebOff,
            color: c.warning,
          ),
        ],
        // Measured on the phone (2026-09-24, same goal): Gemma 4 E2B cited
        // every paragraph; Qwen3.5 0.8B stayed on the subject but cited
        // poorly and mixed figures. The tester found the same.
        if (_smallModel(ref) case final name?) ...[
          const SizedBox(height: AppDesign.md),
          _Banner(
            icon: Icons.tips_and_updates_outlined,
            text: context.l10n.goalSmallModel(name),
            color: c.accent,
          ),
        ],
        const SizedBox(height: AppDesign.lg),
        TextField(
          key: const Key('goal-objective'),
          controller: _objective,
          maxLines: 3,
          minLines: 2,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: context.l10n.goalLabel,
            hintText: context.l10n.goalExample,
            // The example shows before the first tap: an empty box that
            // only says "Goal" leaves a new user guessing.
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
        ),
        const SizedBox(height: AppDesign.lg),
        Text(context.l10n.goalKindTitle, style: context.text.title),
        const SizedBox(height: AppDesign.sm),
        Wrap(
          spacing: AppDesign.sm,
          runSpacing: AppDesign.sm,
          children: [
            for (final k in GoalSpecialization.values)
              ChoiceChip(
                key: Key('goal-kind-${k.name}'),
                avatar: Icon(_kindIcon(k), size: 18),
                label: Text(k.labelIn(context.l10n)),
                selected: _kind == k,
                onSelected: (_) {
                  setState(() => _kind = k);
                  unawaited(_saveDraft());
                },
              ),
          ],
        ),
        const SizedBox(height: AppDesign.xs),
        Text(_kind.descriptionIn(context.l10n), style: context.text.bodyMuted),
        const SizedBox(height: AppDesign.md),
        TextField(
          controller: _criteria,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            labelText: context.l10n.goalCriteriaLabel,
            helperText: context.l10n.goalCriteriaSeparate,
            hintText: _kind.criteriaIn(context.l10n),
            hintMaxLines: 3,
          ),
        ),
        const SizedBox(height: AppDesign.md),
        TextField(
          key: const Key('goal-setup-guidance'),
          controller: _guidance,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.l10n.goalSearchGuidance,
            hintText: context.l10n.goalSearchGuidanceHint,
          ),
        ),
        const SizedBox(height: AppDesign.lg),
        _guardrails(context),
        const SizedBox(height: AppDesign.lg),
        _coverageControl(context, _completionTarget, (v) {
          setState(() => _completionTarget = v);
          unawaited(_saveDraft());
        }),
        const SizedBox(height: AppDesign.lg),
        Text(context.l10n.goalBudgetTitle, style: context.text.title),
        const SizedBox(height: AppDesign.sm),
        for (final b in GoalBudget.values)
          RadioListTile<GoalBudget>(
            key: Key('goal-budget-${b.name}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: b,
            // ignore: deprecated_member_use
            groupValue: _budget,
            // ignore: deprecated_member_use
            onChanged: (v) {
              setState(() => _budget = v ?? _budget);
              unawaited(_saveDraft());
            },
            title: Text(_budgetText(context.l10n, b).$1),
            subtitle: Text(_budgetText(context.l10n, b).$2),
          ),
        if (_budget == GoalBudget.custom) ...[
          _number(_steps, context.l10n.goalMaxSteps),
          _number(_minutes, context.l10n.goalMaxMinutes),
          _number(_tokens, context.l10n.goalMaxTokens),
          _number(_toolCalls, context.l10n.goalMaxToolCalls),
        ],
        if (_budget == GoalBudget.unlimited)
          Padding(
            padding: const EdgeInsets.only(top: AppDesign.sm),
            child: Text(
              context.l10n.goalKeepOpen,
              style: context.text.bodyMuted,
            ),
          ),
        const SizedBox(height: AppDesign.xl),
        FilledButton.icon(
          key: const Key('goal-start'),
          onPressed: _start,
          icon: const Icon(Icons.flag_outlined),
          label: Text(context.l10n.goalStart),
        ),
        _Watches(
          onRunAgain: (objective) {
            _objective.text = objective;
            _setupScroll.glideTo(0, context.motion);
          },
        ),
        const _PastGoals(),
      ],
    );
  }

  /// The rules the goal runs under: the names it must stay on (from the
  /// objective, editable), the user's own rules, and the built-in ones.
  Widget _guardrails(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final names = _subject;
    return Material(
      color: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: AppDesign.radius(AppDesign.rMd),
        side: BorderSide(color: c.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 18, color: c.accent),
                const SizedBox(width: AppDesign.sm),
                Expanded(
                  child: Text(t.goalGuardrails, style: context.text.title),
                ),
              ],
            ),
            const SizedBox(height: AppDesign.sm),
            Text(t.goalSubjectTitle, style: context.text.label),
            const SizedBox(height: AppDesign.xs),
            Text(
              names.isEmpty ? t.goalSubjectNone : t.goalSubjectHint,
              style: context.text.small,
            ),
            const SizedBox(height: AppDesign.sm),
            Wrap(
              spacing: AppDesign.sm,
              runSpacing: AppDesign.xs,
              children: [
                for (final n in names)
                  InputChip(
                    key: Key('goal-term-$n'),
                    label: Text(n),
                    onDeleted: () {
                      setState(
                        () => _terms = [
                          for (final x in names)
                            if (x != n) x,
                        ],
                      );
                      unawaited(_saveDraft());
                    },
                  ),
                ActionChip(
                  key: const Key('goal-term-add'),
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(t.goalSubjectAdd),
                  onPressed: _addTerm,
                ),
                if (_terms != null)
                  TextButton(
                    onPressed: () {
                      setState(() => _terms = null);
                      unawaited(_saveDraft());
                    },
                    child: Text(t.goalSubjectReset),
                  ),
              ],
            ),
            const SizedBox(height: AppDesign.md),
            TextField(
              key: const Key('goal-rules'),
              controller: _rules,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: t.goalRulesLabel,
                hintText: t.goalRulesHint,
                hintMaxLines: 2,
              ),
            ),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('goal-builtin-rules'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: AppDesign.sm),
                title: Text(t.goalRulesBuiltIn, style: context.text.label),
                children: [
                  for (final r in [
                    t.goalRuleSubject,
                    t.goalRuleEvidence,
                    t.goalRuleOffTopic,
                    t.goalRuleFigures,
                    t.goalRuleThinking,
                    t.goalRuleCheck,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppDesign.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check, size: 16, color: c.success),
                          const SizedBox(width: AppDesign.sm),
                          Expanded(
                            child: Text(r, style: context.text.bodyMuted),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The loaded model's name when it is under 1.5B parameters and runs on
  /// the phone; goals are much better with a 2B-class model.
  static String? _smallModel(WidgetRef ref) {
    if (ref.watch(settingsProvider).usesRemote) return null;
    final model = ref.watch(modelManagerProvider).loadedModel;
    if (model == null) return null;
    final b =
        catalogMeta[model.id]?.parameterCountB ??
        model.parameterCountB?.toDouble();
    return b != null && b < 1.5 ? model.displayName : null;
  }

  static (String, String) _budgetText(AppLocalizations t, GoalBudget b) =>
      switch (b) {
        GoalBudget.quick => (t.goalBudgetQuick, t.goalBudgetQuickHint),
        GoalBudget.standard => (t.goalBudgetStandard, t.goalBudgetStandardHint),
        GoalBudget.deep => (t.goalBudgetDeep, t.goalBudgetDeepHint),
        GoalBudget.unlimited => (
          t.goalBudgetUnlimited,
          t.goalBudgetUnlimitedHint,
        ),
        GoalBudget.custom => (t.goalBudgetCustom, t.goalBudgetCustomHint),
      };

  Widget _number(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label),
  );

  Widget _progress(BuildContext context, GoalProgress goal) {
    final controller = ref.read(goalProvider.notifier);
    final running = goal.status == GoalStatus.running;
    final t = context.l10n;
    // A finished report comes first; how it was made follows below it
    // (request 2026-10-08).
    final finished = GoalNotifier.isFinished(goal) && goal.report.isNotEmpty;
    final buttons = _GoalActions(
      children: [
        OutlinedButton.icon(
          key: const Key('goal-evidence'),
          onPressed: goal.sources.isEmpty ? null : () => unawaited(_evidence()),
          icon: const Icon(Icons.compare_arrows),
          label: Text(t.goalEvidenceWorkspace, textAlign: TextAlign.center),
        ),
        if (running) ...[
          OutlinedButton.icon(
            key: const Key('goal-pause'),
            onPressed: controller.pause,
            icon: const Icon(Icons.pause),
            label: Text(t.goalPauseAfterStep, textAlign: TextAlign.center),
          ),
          FilledButton.icon(
            key: const Key('goal-stop'),
            onPressed: controller.stop,
            icon: const Icon(Icons.stop),
            label: Text(t.goalStop),
          ),
        ],
        if (!running && goal.awaitingInputSince == null)
          OutlinedButton.icon(
            key: const Key('goal-refine'),
            onPressed: () => unawaited(_refine(goal)),
            icon: const Icon(Icons.tune),
            label: Text(t.goalRefine),
          ),
        if (GoalNotifier.canContinue(goal))
          FilledButton.icon(
            key: const Key('goal-continue'),
            onPressed: () => unawaited(
              goal.awaitingInputSince != null
                  ? _askQuestions()
                  : controller.continueGoal(),
            ),
            icon: const Icon(Icons.play_arrow),
            label: Text(
              goal.awaitingInputSince != null
                  ? t.goalAnswerQuestions
                  : t.goalContinue,
            ),
          ),
        OutlinedButton.icon(
          key: const Key('goal-open-chat'),
          onPressed: running || controller.chatId == null
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  if (await controller.openChat()) navigator.pop();
                },
          icon: const Icon(Icons.forum_outlined),
          label: Text(t.goalOpenChat),
        ),
        if (!running)
          TextButton(
            key: const Key('goal-new'),
            onPressed: () => unawaited(controller.clear()),
            child: Text(t.goalNew),
          ),
      ],
    );
    final criteria = _criteriaBlocks(
      context,
      goal,
      onTap: (text) => unawaited(_evidence(text)),
    );
    final report = _reportBlocks(context, goal, running: running);
    final actions = _actionBlocks(context, goal);
    final details = _detailBlocks(context, goal, running: running);
    return ListView(
      key: const Key('goal-progress'),
      padding: const EdgeInsets.all(AppDesign.xl),
      children: finished
          ? [
              ..._headerBlocks(context, goal, compact: true),
              const SizedBox(height: AppDesign.sm),
              _statusRow(context, goal),
              ...report,
              ...actions,
              const SizedBox(height: AppDesign.lg),
              buttons,
              const SizedBox(height: AppDesign.xl),
              Divider(color: context.colors.hairline),
              const SizedBox(height: AppDesign.sm),
              Text(t.goalHowMade, style: context.text.title),
              const SizedBox(height: AppDesign.sm),
              ..._statsBlocks(context, goal),
              ...criteria,
              ...details,
            ]
          : [
              ..._headerBlocks(context, goal),
              const SizedBox(height: AppDesign.lg),
              _statusRow(context, goal),
              const SizedBox(height: AppDesign.sm),
              LinearProgressIndicator(value: _fraction(goal)),
              const SizedBox(height: AppDesign.sm),
              ..._statsBlocks(context, goal),
              ...criteria,
              const SizedBox(height: AppDesign.lg),
              buttons,
              ...report,
              ...actions,
              ...details,
            ],
    );
  }

  static bool _limitHit(GoalProgress g) {
    final s = g.spec;
    return (s.maxSteps != null && g.steps >= s.maxSteps!) ||
        (s.maxTokens != null && g.usedTokens >= s.maxTokens!) ||
        (s.maxToolCalls != null && g.usedToolCalls >= s.maxToolCalls!) ||
        (s.maxDuration != null &&
            DateTime.now().difference(g.startedAt) >= s.maxDuration!);
  }

  /// Writes the report (with its sources) to a Markdown file and opens the
  /// share sheet: save it to Files, Drive, or send it.
  static Future<void> _saveReport(BuildContext context, GoalProgress g) async {
    AppHaptics.tick();
    final name = g.spec.objective.length > 60
        ? g.spec.objective.substring(0, 60)
        : g.spec.objective;
    await PhoneActions.launch(
      PhoneAction('save_file', {
        'name': name,
        'format': 'md',
        'content': _withSources(g.report, g.sources),
      }),
    );
  }

  /// Watches this goal: a daily notification, at this time of day, opens
  /// Goals, which searches its question again and shows what changed
  /// ([GoalWatch]). Schedule lists the notification, to change or remove.
  static Future<void> _watch(BuildContext context, GoalProgress g) async {
    AppHaptics.tick();
    final toast = islandToastFor(context);
    final t = context.l10n;
    try {
      await ScheduleStore.requestPermission();
      final items = [...await ScheduleStore.list()];
      final existing = items.indexWhere(
        (p) => p.isGoal && p.prompt.trim() == g.spec.objective.trim(),
      );
      final now = DateTime.now();
      final item = existing >= 0
          ? items[existing].copyWith(enabled: true)
          : ScheduledPrompt(
              id: ScheduledPrompt.freshId(items),
              prompt: g.spec.objective,
              title: g.spec.objective.length > 40
                  ? '${g.spec.objective.substring(0, 40)}…'
                  : g.spec.objective,
              kind: 'goal',
              hour: now.hour,
              minute: now.minute,
            );
      if (existing >= 0) {
        items[existing] = item;
      } else {
        items.add(item);
      }
      await ScheduleStore.save(items);
      if (!context.mounted) return;
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(goalWatchProvider.notifier).watch(g.spec.objective, item);
      toast(t.goalWatchSet(item.time), tone: IslandTone.done);
    } catch (e) {
      toast(t.scheduleFailed('$e'), tone: IslandTone.warning);
    }
  }

  static String _withSources(String report, List<GoalSource> sources) {
    if (sources.isEmpty) return report;
    final b = StringBuffer('$report\n\nSources\n');
    for (var i = 0; i < sources.length; i++) {
      b.writeln('[${i + 1}] ${sources[i].title} — ${sources[i].url}');
    }
    return b.toString().trimRight();
  }
}
