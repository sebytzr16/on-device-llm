import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';
import '../../../core/island/status_island.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/motion/motion.dart';
import '../phone_actions.dart';

/// The actions an answer (or a goal) prepared, one card each. A tap opens
/// the phone's own app filled in; the user confirms there.
class PhoneActionCards extends StatelessWidget {
  final List<PhoneAction> actions;

  /// When each action was opened in its app (by index), shown on its card.
  final Map<int, DateTime> opened;
  final Map<int, DateTime> confirmed;
  final void Function(int index)? onConfirmed;

  /// Told when an action is opened (true) or no app could take it.
  final void Function(int index, bool opened)? onLaunched;
  const PhoneActionCards({
    super.key,
    required this.actions,
    this.opened = const {},
    this.confirmed = const {},
    this.onConfirmed,
    this.onLaunched,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, a) in actions.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.sm),
            child: Material(
              color: c.surfaceRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDesign.rMd),
                side: BorderSide(color: c.hairline),
              ),
              child: Column(
                children: [
                  ListTile(
                    key: Key('phone-action-$i'),
                    leading: Icon(_icon(a.kind), color: c.accent),
                    title: Text(
                      a.title.isEmpty ? _label(context, a.kind) : a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: a.detail.isEmpty && opened[i] == null
                        ? null
                        : Text(
                            [
                              if (a.detail.isNotEmpty) a.detail,
                              if (confirmed[i] != null)
                                context.l10n.actionConfirmedAt(
                                  TimeOfDay.fromDateTime(
                                    confirmed[i]!,
                                  ).format(context),
                                )
                              else if (opened[i] != null)
                                context.l10n.actionOpenedAt(
                                  TimeOfDay.fromDateTime(
                                    opened[i]!,
                                  ).format(context),
                                ),
                            ].join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMuted,
                          ),
                    trailing: FilledButton.tonal(
                      key: Key('phone-action-go-$i'),
                      onPressed: confirmed[i] == null
                          ? () => _go(context, a, i)
                          : null,
                      child: Text(_label(context, a.kind)),
                    ),
                  ),
                  if (onConfirmed != null &&
                      opened[i] != null &&
                      confirmed[i] == null &&
                      a.kind != 'save_file')
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: Key('phone-action-confirm-$i'),
                        onPressed: () => onConfirmed!(i),
                        icon: const Icon(Icons.check),
                        label: Text(context.l10n.actionConfirmDone),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Text(context.l10n.actionConfirmHint, style: context.text.small),
      ],
    );
  }

  Future<void> _go(BuildContext context, PhoneAction a, int i) async {
    AppHaptics.tick();
    final toast = islandToastFor(context);
    final missing = context.l10n.actionNoApp;
    final ok = await PhoneActions.launch(a);
    if (!ok) toast(missing, tone: IslandTone.warning);
    onLaunched?.call(i, ok);
  }

  static IconData _icon(String kind) => switch (kind) {
    'create_event' => Icons.event_outlined,
    'set_reminder' => Icons.notifications_active_outlined,
    'set_alarm' => Icons.alarm,
    'set_timer' => Icons.timer_outlined,
    'draft_message' => Icons.edit_note,
    _ => Icons.description_outlined,
  };

  static String _label(BuildContext context, String kind) {
    final t = context.l10n;
    return switch (kind) {
      'create_event' => t.actionEvent,
      'set_reminder' => t.actionReminder,
      'set_alarm' => t.actionAlarm,
      'set_timer' => t.actionTimer,
      'draft_message' => t.actionMessage,
      _ => t.actionFile,
    };
  }
}
