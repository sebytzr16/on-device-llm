import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../goal_clarification.dart';
import '../../../core/design/app_design.dart';

/// A small, scrollable form: suggestions are optional and always editable.
class GoalClarificationDialog extends StatefulWidget {
  final List<GoalClarification> questions;
  const GoalClarificationDialog({super.key, required this.questions});

  @override
  State<GoalClarificationDialog> createState() =>
      _GoalClarificationDialogState();
}

class _GoalClarificationDialogState extends State<GoalClarificationDialog> {
  late final _answers = {
    for (final q in widget.questions)
      q.id: TextEditingController(text: q.answer),
  };

  @override
  void dispose() {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(t.goalQuestionsTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.goalQuestionsHint),
            for (final q in widget.questions) ...[
              const SizedBox(height: AppDesign.md),
              Text(q.question, style: Theme.of(context).textTheme.titleMedium),
              if (q.options.isNotEmpty) ...[
                const SizedBox(height: AppDesign.md),
                Wrap(
                  spacing: AppDesign.sm,
                  runSpacing: AppDesign.xs,
                  children: [
                    for (final option in q.options)
                      ChoiceChip(
                        label: Text(option),
                        selected: _answers[q.id]!.text == option,
                        onSelected: (selected) => setState(() {
                          _answers[q.id]!.text = selected ? option : '';
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppDesign.md),
              TextField(
                key: Key('goal-answer-${q.id}'),
                controller: _answers[q.id],
                minLines: 1,
                maxLines: 3,
                maxLength: 1000,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: t.goalYourAnswer),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.goalQuestionsLater),
        ),
        TextButton(
          key: const Key('goal-questions-skip'),
          onPressed: () => Navigator.of(context).pop(<String, String>{}),
          child: Text(t.goalQuestionsSkip),
        ),
        FilledButton(
          key: const Key('goal-questions-submit'),
          onPressed: () => Navigator.of(context).pop({
            for (final entry in _answers.entries)
              entry.key: entry.value.text.trim(),
          }),
          child: Text(t.goalContinue),
        ),
      ],
    );
  }
}
