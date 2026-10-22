import 'package:flutter/material.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';
import '../settings/presentation/widgets/settings_widgets.dart';
import 'scheduled_prompt.dart';
import '../../core/island/status_island.dart';
import '../../core/design/app_dialog.dart';

/// Settings > Scheduled prompts: a daily notification at a chosen time that
/// asks a saved prompt (or sets up a goal) when tapped.
class SchedulePage extends StatefulWidget {
  final Future<List<ScheduledPrompt>> Function() load;
  final Future<void> Function(List<ScheduledPrompt>) save;
  final Future<bool> Function() requestPermission;
  const SchedulePage({
    super.key,
    this.load = ScheduleStore.list,
    this.save = ScheduleStore.save,
    this.requestPermission = ScheduleStore.requestPermission,
  });

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<ScheduledPrompt>? _items;
  Object? _loadError;
  int _saveSerial = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final items = await widget.load();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _store(List<ScheduledPrompt> items) async {
    final previous = _items;
    final serial = ++_saveSerial;
    setState(() => _items = items);
    try {
      await widget.save(items);
    } catch (e) {
      if (mounted && serial == _saveSerial) {
        setState(() => _items = previous);
        showIslandToast(
          context,
          context.l10n.scheduleFailed('$e'),
          tone: IslandTone.error,
        );
      }
    }
  }

  Future<void> _edit(ScheduledPrompt? existing) async {
    final items = _items ?? const [];
    final saved = await showAppDialog<ScheduledPrompt>(
      context: context,
      builder: (_) => _ScheduleDialog(
        existing:
            existing ??
            ScheduledPrompt(
              id: ScheduledPrompt.freshId(items),
              prompt: '',
              hour: 8,
              minute: 0,
            ),
      ),
    );
    if (saved == null || !mounted) return;
    final allowed = await widget.requestPermission();
    if (!mounted) return;
    if (!allowed) {
      showIslandToast(context, context.l10n.scheduleNeedsNotifications);
    }
    await _store(
      [
        for (final p in items)
          if (p.id != saved.id) p,
        saved.copyWith(enabled: allowed && saved.enabled),
      ]..sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute)),
    );
  }

  Future<void> _setEnabled(ScheduledPrompt prompt, bool enabled) async {
    if (enabled && !await widget.requestPermission()) {
      if (mounted) {
        showIslandToast(context, context.l10n.scheduleNeedsNotifications);
      }
      return;
    }
    if (!mounted) return;
    await _store([
      for (final item in _items ?? const <ScheduledPrompt>[])
        item.id == prompt.id ? item.copyWith(enabled: enabled) : item,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.scheduleTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('schedule-add'),
        onPressed: items == null ? null : () => _edit(null),
        icon: const Icon(Icons.add_alarm),
        label: Text(context.l10n.scheduleNew),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDesign.lg,
            AppDesign.sm,
            AppDesign.lg,
            96,
          ),
          children: [
            SettingsNote(context.l10n.scheduleIntro, icon: Icons.schedule),
            const SizedBox(height: AppDesign.md),
            if (items == null && _loadError != null) ...[
              Text(context.l10n.scheduleLoadFailed('$_loadError')),
              TextButton(onPressed: _load, child: Text(context.l10n.retry)),
            ] else if (items == null)
              const Center(child: CircularProgressIndicator())
            else if (items.isEmpty)
              Text(context.l10n.scheduleEmpty, style: context.text.bodyMuted)
            else
              SettingsGroup(
                children: [
                  for (final p in items)
                    SettingsRow(
                      key: Key('schedule-${p.id}'),
                      leading: Text(
                        p.time,
                        style: context.text.monoStrong.copyWith(
                          color: p.enabled ? c.accent : c.textFaint,
                        ),
                      ),
                      title: Text(
                        p.title.isEmpty ? p.prompt : p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${p.isGoal ? context.l10n.goalLabel : context.l10n.scheduleChat} · ${p.prompt}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // TalkBack names the prompt the switch controls.
                          Semantics(
                            label:
                                '${p.time} · ${p.title.isEmpty ? p.prompt : p.title}',
                            child: Switch(
                              value: p.enabled,
                              onChanged: (v) => _setEnabled(p, v),
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.commonDelete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _store([
                              for (final q in items)
                                if (q.id != p.id) q,
                            ]),
                          ),
                        ],
                      ),
                      onTap: () => _edit(p),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  final ScheduledPrompt existing;
  const _ScheduleDialog({required this.existing});

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late final _title = TextEditingController(text: widget.existing.title);
  late final _prompt = TextEditingController(text: widget.existing.prompt);
  late TimeOfDay _time = TimeOfDay(
    hour: widget.existing.hour,
    minute: widget.existing.minute,
  );
  late String _kind = widget.existing.kind;

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing.prompt.isEmpty
            ? context.l10n.scheduleNewTitle
            : context.l10n.commonEdit,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppDesign.md,
          children: [
            SettingsRow(
              key: const Key('schedule-time'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(context.l10n.scheduleEveryDay(_time.format(context))),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (picked != null) setState(() => _time = picked);
              },
            ),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'chat',
                  label: Text(context.l10n.scheduleAskChat),
                ),
                ButtonSegment(
                  value: 'goal',
                  label: Text(context.l10n.scheduleOpenGoal),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            TextField(
              key: const Key('schedule-prompt'),
              controller: _prompt,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _kind == 'goal'
                    ? context.l10n.goalLabel
                    : context.l10n.shortcutPrompt,
                hintText: context.l10n.scheduleExample,
                hintMaxLines: 2,
              ),
            ),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: context.l10n.scheduleNotificationTitle,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('schedule-save'),
          onPressed: _prompt.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.existing.copyWith(
                    title: _title.text.trim(),
                    prompt: _prompt.text.trim(),
                    kind: _kind,
                    hour: _time.hour,
                    minute: _time.minute,
                  ),
                ),
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
