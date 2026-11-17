import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/motion/motion.dart';

/// Shown when the conversation is empty: the headline, one line of
/// status, and the three things the message box cannot do by itself —
/// a researched goal, a photo, a file. Typing is the main action, so
/// nothing else competes with the box.
class ChatEmptyState extends StatelessWidget {
  final bool hasModel;

  /// The remote server's host while a remote model answers: the line must
  /// not claim the conversation stays on the phone.
  final String? remoteHost;

  /// Camera-first and file-first entries (FX-08).
  final VoidCallback? onAskPhoto, onAskFile;

  /// Opens Goals: multi-step research with a cited report.
  final VoidCallback? onResearchGoal;

  /// Opens Models when there is no model yet (first-run guide).
  final VoidCallback? onGetModel;
  const ChatEmptyState({
    super.key,
    required this.hasModel,
    this.remoteHost,
    this.onAskPhoto,
    this.onAskFile,
    this.onResearchGoal,
    this.onGetModel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // First run (owner 2026-11-16): one clear way to a model, and nothing
    // that needs a model competing with it.
    final getModel = !hasModel && remoteHost == null && onGetModel != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.phonePage,
          vertical: AppSpace.section,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          // Headline, line and chips arrive as a short cascade.
          children: [
            SpringEntrance(
              from: const Offset(-12, 0),
              fromScale: 0.6,
              scaleAlignment: Alignment.centerLeft,
              child: Container(width: 28, height: 2, color: c.accent),
            ),
            const SizedBox(height: AppSpace.lg),
            SpringEntrance(
              delay: SpringEntrance.cascade(1, stepMs: 60),
              from: const Offset(0, 18),
              child: Text(
                getModel
                    ? context.l10n.firstRunGetModelTitle
                    : context.l10n.emptyTitle,
                style: context.text.display,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            SpringEntrance(
              delay: SpringEntrance.cascade(2, stepMs: 60),
              from: const Offset(0, 12),
              child: Text(
                remoteHost != null
                    ? context.l10n.emptyRemote(remoteHost!)
                    : hasModel
                    ? context.l10n.emptyHasModel
                    : getModel
                    ? context.l10n.firstRunGetModelBody
                    : context.l10n.emptyNoModel,
                style: context.text.bodyMuted,
              ),
            ),
            const SizedBox(height: AppSpace.section),
            if (getModel)
              SpringEntrance(
                delay: SpringEntrance.cascade(3, stepMs: 60),
                child: Pressable(
                  child: FilledButton.icon(
                    key: const Key('first-run-get-model'),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                      minimumSize: const Size(0, AppDesign.actionHeight),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppDesign.radius(AppDesign.rFull),
                      ),
                      textStyle: context.text.title.copyWith(fontSize: 15),
                    ),
                    onPressed: onGetModel,
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: Text(context.l10n.firstRunGetModelButton),
                  ),
                ),
              )
            else
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final (i, chip) in [
                    // Goals first and marked with the accent: a different kind
                    // of task (several searches and a cited report).
                    if (onResearchGoal != null)
                      Tooltip(
                        message: context.l10n.emptyGoalHint,
                        child: ActionChip(
                          key: const Key('empty-goal'),
                          avatar: Icon(
                            Icons.flag_outlined,
                            size: 16,
                            color: c.accent,
                          ),
                          label: Text(context.l10n.emptyGoalTitle),
                          side: BorderSide(color: c.accent),
                          onPressed: onResearchGoal,
                        ),
                      ),
                    if (onAskPhoto != null)
                      ActionChip(
                        key: const Key('ask-photo'),
                        avatar: const Icon(
                          Icons.photo_camera_outlined,
                          size: 16,
                        ),
                        label: Text(context.l10n.askPhoto),
                        onPressed: onAskPhoto,
                      ),
                    if (onAskFile != null)
                      ActionChip(
                        key: const Key('ask-file'),
                        avatar: const Icon(Icons.attach_file, size: 16),
                        label: Text(context.l10n.askFile),
                        onPressed: onAskFile,
                      ),
                  ].indexed)
                    SpringEntrance(
                      delay: SpringEntrance.cascade(3 + i, stepMs: 60),
                      child: Pressable(child: chip),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
