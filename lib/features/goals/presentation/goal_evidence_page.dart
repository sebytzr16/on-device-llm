import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_design.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/external_links.dart';
import '../goal_runner.dart';
import 'goal_provider.dart';

/// Compares the retained retrieval snapshots, with the same citation numbers
/// used in the report. Assessment explanations are kept separate from sources.
class GoalEvidencePage extends ConsumerStatefulWidget {
  final String? initialCriterion;
  const GoalEvidencePage({super.key, this.initialCriterion});

  @override
  ConsumerState<GoalEvidencePage> createState() => _GoalEvidencePageState();
}

class _GoalEvidencePageState extends ConsumerState<GoalEvidencePage> {
  String? _criterion;
  int? _left, _right;
  String _query = '';
  bool _selected = false;

  void _select(GoalProgress goal, String? text) {
    final criterion = goal.criteria.where((c) => c.text == text).firstOrNull;
    final numbers = <int>{
      ...?criterion?.evidence.map((e) => e.source),
      for (final q in criterion?.quotes ?? const <GoalCriterionQuote>[])
        ...GoalChecker.citations(q.quote),
      for (final step in criterion?.steps ?? const <int>[])
        if (step > 0 && step <= goal.tasks.length)
          ...?goal.tasks[step - 1].trace?.sources,
    }.where((n) => n > 0 && n <= goal.sources.length).toList();
    _criterion = text;
    _left = numbers.firstOrNull ?? (goal.sources.isEmpty ? null : 1);
    _right = numbers.length > 1
        ? numbers[1]
        : goal.sources.length > 1
        ? (_left == 1 ? 2 : 1)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final goal = ref.watch(goalProvider);
    final t = context.l10n;
    if (goal == null) {
      return Scaffold(appBar: AppBar(title: Text(t.goalEvidenceWorkspace)));
    }
    if (!_selected) {
      _select(goal, widget.initialCriterion);
      _selected = true;
    }
    if (!goal.spec.criteriaItems.contains(_criterion)) _criterion = null;
    final assessment = goal.criteria
        .where((c) => c.text == _criterion)
        .firstOrNull;
    final panels = <Widget>[
      _source(context, goal, _left, (n) => setState(() => _left = n), 'left'),
      if (goal.sources.length > 1)
        _source(
          context,
          goal,
          _right,
          (n) => setState(() => _right = n),
          'right',
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(t.goalEvidenceWorkspace),
        actions: [
          if (goal.status != GoalStatus.running)
            IconButton(
              key: const Key('evidence-steer'),
              tooltip: t.goalRefine,
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.tune),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDesign.lg),
        children: [
          Text(t.goalEvidenceSnapshotHint, style: context.text.bodyMuted),
          const SizedBox(height: AppDesign.md),
          DropdownButtonFormField<String>(
            key: ValueKey('evidence-criterion-${_criterion ?? 'all'}'),
            initialValue: _criterion ?? '',
            isExpanded: true,
            decoration: InputDecoration(labelText: t.goalCriteriaReview),
            items: [
              DropdownMenuItem(value: '', child: Text(t.all)),
              for (final item in goal.spec.criteriaItems.toSet())
                DropdownMenuItem(
                  value: item,
                  child: Text(
                    item,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (text) => setState(() => _select(goal, text)),
          ),
          if (assessment != null) ...[
            const SizedBox(height: AppDesign.md),
            Text(
              assessment.satisfied && assessment.validationError.isEmpty
                  ? t.goalEvidenceSupported
                  : t.goalEvidenceGap,
              style: context.text.title,
            ),
            if (assessment.explanation.isNotEmpty)
              SelectableText(assessment.explanation),
            if (assessment.validationError.isNotEmpty)
              Text(
                assessment.validationError,
                style: TextStyle(color: context.colors.danger),
              ),
            for (final item in assessment.evidence)
              SelectableText('[${item.source}] “${item.quote}”'),
          ],
          if (goal.sources.isEmpty) ...[
            const SizedBox(height: AppDesign.lg),
            Text(t.goalEvidenceMissing),
          ] else ...[
            const SizedBox(height: AppDesign.md),
            TextField(
              key: const Key('evidence-search'),
              decoration: InputDecoration(
                labelText: t.goalEvidenceFind,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: AppDesign.lg),
            LayoutBuilder(
              builder: (context, bounds) {
                if (bounds.maxWidth < 760 || panels.length == 1) {
                  return Column(children: panels);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final panel in panels) Expanded(child: panel),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _source(
    BuildContext context,
    GoalProgress goal,
    int? number,
    ValueChanged<int?> select,
    String side,
  ) {
    final t = context.l10n;
    final n = number != null && number > 0 && number <= goal.sources.length
        ? number
        : null;
    final source = n == null ? null : goal.sources[n - 1];
    final steps = [
      for (var i = 0; i < goal.tasks.length; i++)
        if (goal.tasks[i].trace?.sources.contains(n) == true) i + 1,
    ];
    final matching =
        source != null &&
        (_query.isEmpty ||
            source.evidence.toLowerCase().contains(_query.toLowerCase()));
    return Card(
      key: Key('evidence-panel-$side'),
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              key: ValueKey('evidence-source-$side-$n'),
              initialValue: n,
              isExpanded: true,
              decoration: InputDecoration(labelText: t.goalSourcesTitle),
              items: [
                for (var i = 0; i < goal.sources.length; i++)
                  DropdownMenuItem(
                    value: i + 1,
                    child: Text(
                      '[${i + 1}] ${goal.sources[i].title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: select,
            ),
            if (source != null) ...[
              const SizedBox(height: AppDesign.sm),
              SelectableText(source.url, style: context.text.bodyMuted),
              if (source.publishedAt != null)
                Text(
                  '${t.goalEvidencePublished}: ${source.publishedAt!.toLocal()}',
                ),
              if (source.retrievedAt != null)
                Text(
                  '${t.goalEvidenceRetrieved}: ${source.retrievedAt!.toLocal()}',
                ),
              if (steps.isNotEmpty) Text(t.goalEvidenceSteps(steps.join(', '))),
              Wrap(
                children: [
                  if ([
                    'https',
                    'http',
                  ].contains(Uri.tryParse(source.url)?.scheme))
                    TextButton.icon(
                      onPressed: () => openExternalLink(source.url),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(t.goalEvidenceOpen),
                    ),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(
                        text:
                            '[${n!}] ${source.title}\n${source.url}\n${source.evidence}',
                      ),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(t.goalEvidenceCopy),
                  ),
                ],
              ),
              const Divider(),
              if (source.evidence.isEmpty)
                Text(t.goalEvidenceMissing)
              else if (!matching)
                Text(t.goalEvidenceNoMatch)
              else
                SelectableText(source.evidence),
              for (final step in steps) ...[
                const Divider(),
                Text(
                  '$step. ${goal.tasks[step - 1].question}',
                  style: context.text.label,
                ),
                if (goal.tasks[step - 1].excluded)
                  Text(
                    t.goalEvidenceExcluded,
                    style: TextStyle(color: context.colors.danger),
                  ),
                SelectableText(goal.tasks[step - 1].findings),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
