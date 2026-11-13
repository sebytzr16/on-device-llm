import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';
import '../../../core/island/status_island.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/motion/motion.dart';
import '../phone_actions.dart';

/// The actions an answer (or a goal) prepared, one card each. A tap opens
/// the phone's own app filled in; the user confirms there.
class PhoneActionCards extends StatefulWidget {
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
  State<PhoneActionCards> createState() => _PhoneActionCardsState();
}

class _PhoneActionCardsState extends State<PhoneActionCards> {
  final Set<int> _expanded = {};

  void _toggleExpanded(int index) {
    setState(() {
      if (_expanded.contains(index)) {
        _expanded.remove(index);
      } else {
        _expanded.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, a) in widget.actions.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.sm),
            child: Material(
              color: c.surfaceRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDesign.rMd),
                side: BorderSide(color: c.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    key: Key('phone-action-$i'),
                    leading: Icon(_icon(a.kind), color: c.accent),
                    title: Text(
                      a.title.isEmpty ? _label(context, a.kind) : a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: a.detail.isEmpty && widget.opened[i] == null
                        ? null
                        : Text(
                            [
                              if (a.detail.isNotEmpty) a.detail,
                              if (widget.confirmed[i] != null)
                                t.actionConfirmedAt(
                                  TimeOfDay.fromDateTime(
                                    widget.confirmed[i]!,
                                  ).format(context),
                                )
                              else if (widget.opened[i] != null)
                                t.actionOpenedAt(
                                  TimeOfDay.fromDateTime(
                                    widget.opened[i]!,
                                  ).format(context),
                                ),
                            ].join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMuted,
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('phone-action-expand-$i'),
                          onPressed: () => _toggleExpanded(i),
                          icon: Icon(
                            _expanded.contains(i)
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          tooltip: _expanded.contains(i)
                              ? t.actionCollapse
                              : t.actionExpand,
                        ),
                        FilledButton.tonal(
                          key: Key('phone-action-go-$i'),
                          onPressed: widget.confirmed[i] == null
                              ? () => _go(context, a, i)
                              : null,
                          child: Text(_actionButtonLabel(context, a.kind)),
                        ),
                      ],
                    ),
                  ),
                  if (_expanded.contains(i)) _ExpandedDetail(action: a),
                  if (widget.onConfirmed != null &&
                      widget.opened[i] != null &&
                      widget.confirmed[i] == null &&
                      a.kind != 'save_file')
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: Key('phone-action-confirm-$i'),
                        onPressed: () => widget.onConfirmed!(i),
                        icon: const Icon(Icons.check),
                        label: Text(t.actionConfirmDone),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Text(t.actionConfirmHint, style: context.text.small),
      ],
    );
  }

  Future<void> _go(BuildContext context, PhoneAction a, int i) async {
    AppHaptics.tick();
    final toast = islandToastFor(context);
    final missing = context.l10n.actionNoApp;
    final ok = await PhoneActions.launch(a);
    if (!ok) toast(missing, tone: IslandTone.warning);
    widget.onLaunched?.call(i, ok);
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

  /// Explicit button labels: Save / Share for save_file, otherwise the
  /// standard action label.
  static String _actionButtonLabel(BuildContext context, String kind) {
    final t = context.l10n;
    if (kind == 'save_file') {
      return t.actionSaveButton;
    }
    return _label(context, kind);
  }
}

/// Expandable detail section showing all fields for the action.
/// HTML content is displayed as escaped source text, never rendered.
class _ExpandedDetail extends StatelessWidget {
  final PhoneAction action;
  const _ExpandedDetail({required this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final details = action.fullDetail(context);
    if (details.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppDesign.rMd),
          bottomRight: Radius.circular(AppDesign.rMd),
        ),
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: const EdgeInsets.all(AppDesign.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in details) ...[
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  label,
                  style: context.text.label.copyWith(color: c.textMuted),
                ),
              ),
            SelectableText(
              value,
              style: context.text.body.copyWith(
                // Monospace for content to make HTML source readable
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: AppDesign.sm),
          ],
        ],
      ),
    );
  }
}
