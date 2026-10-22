import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../data/local/database/app_database.dart';
import '../providers/chat_provider.dart';
import '../../../../core/design/app_dialog.dart';

/// One quiet line after an answer when Memory stored something: the first
/// fact, a count if there are more, a pencil to review and a cross to
/// dismiss. The pencil opens a dialog that explains what Memory is and
/// lets the user correct, keep or discard exactly those facts.
class MemoryBanner extends ConsumerWidget {
  final List<Memory> learned;
  const MemoryBanner(this.learned, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.l10n;
    final notifier = ref.read(chatProvider.notifier);
    final first = learned.first.content;
    final more = learned.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesign.lg, AppDesign.xs, 6, 0),
      child: Row(
        key: const Key('memory-banner'),
        children: [
          Icon(Icons.psychology_alt_outlined, size: 14, color: c.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              more > 0 ? t.rememberedMore(first, more) : t.rememberedOne(first),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.mono.copyWith(color: c.textMuted),
            ),
          ),
          IconButton(
            key: const Key('memory-edit'),
            tooltip: t.reviewMemory,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showLearnedDialog(context, ref, learned),
          ),
          IconButton(
            key: const Key('memory-dismiss'),
            tooltip: t.dismiss,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close),
            onPressed: notifier.dismissLearned,
          ),
        ],
      ),
    );
  }
}

/// Explains Memory in two sentences and shows the just-stored facts, one
/// per line, editable. Save keeps the edited lines (empty lines delete);
/// Discard removes them all.
Future<void> showLearnedDialog(
  BuildContext context,
  WidgetRef ref,
  List<Memory> learned,
) async {
  final t = context.l10n;
  final controller = TextEditingController(
    text: learned.map((m) => m.content).join('\n'),
  );
  final notifier = ref.read(chatProvider.notifier);
  final choice = await showAppDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(t.memoryDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppDesign.md,
        children: [
          Text(t.memoryDialogHint, style: context.text.bodyMuted),
          TextField(
            key: const Key('memory-edit-field'),
            controller: controller,
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(hintText: t.memoryDialogFieldHint),
          ),
        ],
      ),
      actions: [
        FilledButton(
          style: dangerButtonStyle(context.colors),
          key: const Key('memory-discard'),
          onPressed: () => Navigator.pop(context, 'discard'),
          child: Text(t.discard),
        ),
        FilledButton(
          key: const Key('memory-save'),
          onPressed: () => Navigator.pop(context, 'save'),
          child: Text(t.save),
        ),
      ],
    ),
  );
  final lines = controller.text.split('\n');
  controller.dispose();
  switch (choice) {
    case 'discard':
      await notifier.dismissLearned(discard: true);
    case 'save':
      await notifier.editLearned(lines);
    default:
      break;
  }
}
