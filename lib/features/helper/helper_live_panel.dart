import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../../core/design/app_dialog.dart';
import '../../core/design/app_sheet.dart';
import '../../core/l10n/l10n.dart';
import '../../core/motion/motion.dart';
import 'helper_jobs.dart';

String helperPhaseLabel(BuildContext context, HelperPhase phase) =>
    switch (phase) {
      HelperPhase.queued => context.l10n.helperQueued,
      HelperPhase.loadingModel => context.l10n.helperLoading,
      HelperPhase.prefill => context.l10n.helperPrefill,
      HelperPhase.generating => context.l10n.helperGenerating,
      HelperPhase.done => context.l10n.helperDone,
      HelperPhase.failed => context.l10n.helperFailed,
      HelperPhase.cancelled => context.l10n.helperCancelled,
      HelperPhase.timedOut => context.l10n.helperTimedOut,
    };

String? _toolActivity(BuildContext context, HelperJob job) {
  final value = job.metrics['toolActivity'];
  if (value is! String) return null;
  if (value == 'approval') return context.l10n.agentWebWaiting;
  if (value.startsWith('search:')) {
    return context.l10n.agentSearching(value.substring(7));
  }
  if (value.startsWith('read:')) {
    return context.l10n.agentReading(value.substring(5));
  }
  return null;
}

class HelperLivePanel extends ConsumerStatefulWidget {
  final Alignment alignment;
  const HelperLivePanel({super.key, this.alignment = Alignment.bottomRight});

  @override
  ConsumerState<HelperLivePanel> createState() => _HelperLivePanelState();
}

class _HelperLivePanelState extends ConsumerState<HelperLivePanel> {
  // Phone agents start folded even while the desktop column opens its cards.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(helperJobsProvider.select((s) => s.expanded), (_, expanded) {
      if (!expanded) setState(() => _expanded = false);
    });
    final state = ref.watch(helperJobsProvider);
    final jobs = state.jobs.where((j) => state.visible.contains(j.id)).toList();
    if (jobs.isEmpty) return const SizedBox.shrink();
    final current = jobs.where((j) => !j.terminal).firstOrNull ?? jobs.last;
    final speed = jobs
        .where((j) => !j.terminal)
        .fold<double>(0, (total, job) => total + (job.tokensPerSecond ?? 0));
    final notifier = ref.read(helperJobsProvider.notifier);
    final t = context.l10n;
    return Align(
      alignment: widget.alignment,
      heightFactor: 1,
      child: Material(
        key: const Key('helper-live-strip'),
        color: context.colors.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.radius(AppDesign.rMd),
          side: BorderSide(color: context.colors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: SpringSize(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: AppDesign.actionHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        expanded: _expanded,
                        child: InkWell(
                          key: const Key('helper-live-toggle'),
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Padding(
                            padding: const EdgeInsets.only(left: AppDesign.md),
                            child: Row(
                              spacing: AppDesign.sm,
                              children: [
                                _PhaseDot(current.phase),
                                Flexible(
                                  child: Text(
                                    t.helperCount(jobs.length),
                                    style: context.text.small,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Flexible(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      spacing: AppDesign.sm,
                                      children: [
                                        for (final (index, job) in jobs.indexed)
                                          Tooltip(
                                            message:
                                                '${t.helperNumber(index + 1)} · ${helperPhaseLabel(context, job.phase)}',
                                            child: Row(
                                              spacing: 2,
                                              children: [
                                                Text(
                                                  '${index + 1}',
                                                  style: context.text.caption,
                                                ),
                                                _PhaseDot(job.phase),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                Text(
                                  '${speed.toStringAsFixed(1)} tok/s',
                                  style: context.text.caption,
                                ),
                                Tooltip(
                                  message: _expanded
                                      ? t.helperHideDetails
                                      : t.helperShowDetails,
                                  child: SizedBox(
                                    width: AppDesign.actionHeight,
                                    height: AppDesign.actionHeight,
                                    child: Icon(
                                      _expanded
                                          ? Icons.expand_more
                                          : Icons.expand_less,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('helper-live-dismiss'),
                      tooltip: t.dismiss,
                      onPressed: () {
                        setState(() => _expanded = false);
                        notifier.dismiss();
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              if (_expanded)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        (MediaQuery.sizeOf(context).height * .4 -
                                AppDesign.actionHeight)
                            .clamp(0.0, double.infinity),
                  ),
                  child: ListView(
                    key: const Key('helper-live-agents'),
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final (index, job) in jobs.indexed)
                        _PhoneAgentRow(index: index, job: job),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneAgentRow extends StatelessWidget {
  final int index;
  final HelperJob job;
  const _PhoneAgentRow({required this.index, required this.job});

  @override
  Widget build(BuildContext context) => Padding(
    key: Key('helper-phone-row-${job.id}'),
    padding: const EdgeInsets.only(left: AppDesign.md, right: AppDesign.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: AppDesign.xs,
          children: [
            Tooltip(
              message: helperPhaseLabel(context, job.phase),
              child: _PhaseDot(job.phase),
            ),
            Text(
              context.l10n.helperNumber(index + 1),
              style: context.text.caption,
            ),
            Expanded(
              child: Text(
                job.task,
                style: context.text.small,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              flex: 2,
              child: Text(
                '${job.tokens ?? '—'} tok · ${job.tokensPerSecond?.toStringAsFixed(1) ?? '—'} tok/s · ${(job.elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
                style: context.text.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: Key('agent-details-${job.id}'),
              tooltip: context.l10n.helperAllMetrics,
              icon: const Icon(Icons.info_outline, size: 16),
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SingleChildScrollView(
                      child: HelperJobCard(job: job),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (job.reason case final reason? when job.terminal)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.sm),
            child: Text(
              reason,
              style: context.text.caption.copyWith(
                color: context.colors.danger,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ),
  );
}

/// Windows: a thin column left of the conversation, like a coding agent's
/// side list, so helpers never cover the chat. Folded it lists each helper
/// with its task sliding past; open it shows the full cards in smaller type
/// (owner, 2026-11-02).
class HelperSideColumn extends ConsumerWidget {
  const HelperSideColumn({super.key});

  static const foldedWidth = 210.0;
  static const openWidth = 290.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(helperJobsProvider);
    final jobs = state.jobs.where((j) => state.visible.contains(j.id)).toList();
    final notifier = ref.read(helperJobsProvider.notifier);
    final t = context.l10n;
    final width = jobs.isEmpty
        ? 0.0
        : state.expanded
        ? openWidth
        : foldedWidth;
    final running = jobs.where((j) => !j.terminal).length;
    final speed = jobs
        .where((j) => !j.terminal)
        .fold<double>(0, (total, job) => total + (job.tokensPerSecond ?? 0));
    return AnimatedContainer(
      duration: AppMotion.track,
      curve: AppMotion.ease,
      width: width,
      child: jobs.isEmpty
          ? const SizedBox.shrink()
          : OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: width,
              maxWidth: width,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDesign.md,
                  AppDesign.sm,
                  0,
                  AppDesign.md,
                ),
                child: LayoutBuilder(
                  // Four agent cards fit the column; the panel only grows
                  // with its cards and leaves the rest free (owner, 2026-11-02).
                  builder: (context, box) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      key: const Key('helper-side-column'),
                      color: context.colors.surfaceRaised,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppDesign.radius(AppDesign.rLg),
                        side: BorderSide(color: context.colors.hairline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: MediaQuery(
                        // Smaller type keeps the column thin (owner, 2026-11-02).
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: const TextScaler.linear(.85)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: AppDesign.md,
                                    ),
                                    child: Text(
                                      running > 0
                                          ? '${t.helperCount(jobs.length)} · ${speed.toStringAsFixed(1)} tok/s'
                                          : t.helperCount(jobs.length),
                                      style: context.text.mono,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const Key('helper-live-toggle'),
                                  tooltip: state.expanded
                                      ? t.helperHideDetails
                                      : t.helperShowDetails,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: notifier.toggle,
                                  icon: Icon(
                                    state.expanded
                                        ? Icons.keyboard_double_arrow_left
                                        : Icons.keyboard_double_arrow_right,
                                    size: 16,
                                  ),
                                ),
                                IconButton(
                                  key: const Key('helper-live-dismiss'),
                                  tooltip: t.dismiss,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: notifier.dismiss,
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ),
                            Divider(height: 1, color: context.colors.hairline),
                            Flexible(
                              child: ListView(
                                shrinkWrap: true,
                                padding: state.expanded
                                    ? const EdgeInsets.all(AppDesign.sm)
                                    : EdgeInsets.zero,
                                children: [
                                  if (state.expanded)
                                    for (final (index, job) in jobs.indexed)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: AppDesign.sm,
                                        ),
                                        child: SizedBox(
                                          height:
                                              ((box.maxHeight - 64) / 4 -
                                                      AppDesign.sm)
                                                  .clamp(120.0, 240.0),
                                          child: _AgentCard(
                                            index: index,
                                            job: job,
                                          ),
                                        ),
                                      )
                                  else
                                    for (final (index, job) in jobs.indexed)
                                      _HelperRow(index: index, job: job),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// One agent in the Windows column: its number and phase, the task sliding
/// past, live counts, then what it is writing, pinned to the newest line.
/// The info button opens the full card with every measurement (owner, 2026-11-02).
class _AgentCard extends StatelessWidget {
  final int index;
  final HelperJob job;
  const _AgentCard({required this.index, required this.job});

  @override
  Widget build(BuildContext context) {
    final text = job.reply?.text ?? job.output;
    final seconds = (job.elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    return DecoratedBox(
      key: Key('agent-card-${job.id}'),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: context.colors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDesign.sm,
          AppDesign.xs,
          AppDesign.xs,
          AppDesign.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            Row(
              spacing: AppDesign.xs,
              children: [
                _PhaseDot(job.phase),
                Expanded(
                  child: Text(
                    '${context.l10n.helperNumber(index + 1)} · ${helperPhaseLabel(context, job.phase)}',
                    style: context.text.mono,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: Key('agent-details-${job.id}'),
                  tooltip: context.l10n.helperAllMetrics,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(AppDesign.xs),
                  onPressed: () => showAppDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: SingleChildScrollView(
                          child: HelperJobCard(job: job),
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline, size: 14),
                ),
              ],
            ),
            if (_toolActivity(context, job) case final activity?)
              Text(
                activity,
                style: context.text.small,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            MarqueeText(
              job.task,
              style: context.text.small.copyWith(color: context.colors.text),
            ),
            Text(
              '${job.tokens ?? 0} tok · ${job.tokensPerSecond?.toStringAsFixed(1) ?? '—'} tok/s · ${seconds}s',
              style: context.text.mono.copyWith(
                color: context.colors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Expanded(
              child: SingleChildScrollView(
                // Reversed so the newest words stay in view while it writes.
                reverse: true,
                child: Text(
                  text,
                  style: context.text.small.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseDot extends StatelessWidget {
  final HelperPhase phase;
  const _PhaseDot(this.phase);

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (phase) {
        HelperPhase.done => context.colors.success,
        HelperPhase.failed ||
        HelperPhase.timedOut ||
        HelperPhase.cancelled => context.colors.danger,
        _ => context.colors.accent,
      },
    ),
  );
}

class _HelperRow extends ConsumerWidget {
  final int index;
  final HelperJob job;
  const _HelperRow({required this.index, required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
    key: Key('helper-row-${job.id}'),
    onTap: ref.read(helperJobsProvider.notifier).toggle,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.md,
        vertical: AppDesign.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Row(
            spacing: AppDesign.xs,
            children: [
              _PhaseDot(job.phase),
              Expanded(
                child: Text(
                  '${context.l10n.helperNumber(index + 1)} · ${helperPhaseLabel(context, job.phase)}',
                  style: context.text.mono,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          MarqueeText(
            job.task,
            style: context.text.small.copyWith(color: context.colors.textMuted),
          ),
        ],
      ),
    ),
  );
}

class HelperJobCard extends StatelessWidget {
  final HelperJob job;
  const HelperJobCard({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    const unavailable = '—';
    final metrics = job.metrics;
    String ms(Object? value) =>
        value is num ? '${value.toStringAsFixed(0)} ms' : unavailable;
    return Padding(
      padding: const EdgeInsets.all(AppDesign.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDesign.sm,
        children: [
          Text(
            '${job.modelName} · ${helperPhaseLabel(context, job.phase)}',
            style: context.text.mono,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surfaceRaised,
              borderRadius: AppDesign.radius(AppDesign.rMd),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppDesign.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.helperTask, style: context.text.mono),
                  SelectableText(job.task),
                  if (job.inputPreview.isNotEmpty)
                    SelectableText(job.inputPreview, style: context.text.small),
                ],
              ),
            ),
          ),
          if (job.thinking.isNotEmpty)
            ExpansionTile(
              title: Text(
                t.thinking,
                style: context.text.small.copyWith(
                  color: context.colors.reasoning,
                ),
              ),
              children: [SelectableText(job.thinking)],
            ),
          if (_toolActivity(context, job) case final activity?)
            Text(activity, style: context.text.small),
          if (metrics['toolCalls'] case final List calls when calls.isNotEmpty)
            ExpansionTile(
              title: Text(t.agentToolCalls),
              children: [
                for (final call in calls)
                  ListTile(
                    title: Text('${(call as Map)['call']}'),
                    subtitle: SelectableText('${call['output']}'),
                  ),
              ],
            ),
          if (job.output.isNotEmpty)
            SelectableText(job.reply?.text ?? job.output),
          if (job.phase == HelperPhase.done && job.reportedTo != null)
            Text(
              t.helperReportedTo(job.reportedTo!),
              style: context.text.small,
            ),
          if (job.reason != null)
            Text(
              switch (job.reason) {
                'model is not downloaded' => t.helperNotDownloaded,
                'not enough available memory' => t.helperLowMemory,
                'model is busy' => t.helperModelBusy,
                'chat model changed' => t.helperModelChanged,
                'helper is disposed' => t.helperDisposed,
                'cancelled' => t.helperCancelled,
                'timed out' || 'loading timed out' => t.helperTimedOut,
                _ => t.helperInferenceFailed,
              },
              style: context.text.small.copyWith(color: context.colors.warning),
            ),
          Text(
            t.helperLiveStats(
              job.tokens?.toString() ?? unavailable,
              job.tokensPerSecond?.toStringAsFixed(1) ?? unavailable,
              job.promptTokens?.toString() ?? unavailable,
              ms(metrics['prefillMs'] ?? job.prefill?.inMilliseconds),
              (job.elapsed.inMilliseconds / 1000).toStringAsFixed(1),
              ms(metrics['firstTokenMs'] ?? job.firstToken?.inMilliseconds),
            ),
            style: context.text.mono,
          ),
          if (metrics['loadMs'] != null && metrics['sharedGpu'] != true)
            Text(
              t.helperLoadTime(ms(metrics['loadMs'])),
              style: context.text.mono,
            ),
          if ((metrics['loadProgress'] ?? metrics['prefillProgress'])
              case final num progress)
            LinearProgressIndicator(value: progress.toDouble().clamp(0, 1)),
          if (metrics['peakRssMb'] != null || metrics['backend'] != null)
            Text(
              metrics['sharedGpu'] == true
                  ? t.helperSharedResources(
                      metrics['backend']?.toString() ?? unavailable,
                      metrics['gpuLayers']?.toString() ?? unavailable,
                    )
                  : t.helperResources(
                      metrics['peakRssMb']?.toString() ?? unavailable,
                      metrics['backend']?.toString() ?? unavailable,
                      (metrics['gpuLayers'] ??
                                  (metrics['effectiveSettings']
                                      as Map?)?['nGpuLayers'])
                              ?.toString() ??
                          unavailable,
                    ),
              style: context.text.mono,
            ),
          if (metrics.isNotEmpty)
            ExpansionTile(
              title: Text(t.helperAllMetrics, style: context.text.small),
              children: [
                for (final (label, value) in helperMeasurementRows(metrics))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppDesign.xs),
                    child: SelectableText(
                      '$label: $value',
                      style: context.text.mono,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// The raw engine map repeats the chat template and the whole reply; keep the
// short values and flatten the settings the engine actually used (owner, 2026-11-02).
const _hiddenMeasurements = {'chatTemplate', 'toolContent', 'devices'};

List<(String, String)> helperMeasurementRows(Map<String, Object?> metrics) {
  String label(String key) {
    final words = key
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]}')
        .toLowerCase();
    return words.isEmpty
        ? key
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  String? value(Object? v) => switch (v) {
    null => null,
    final double d => d.toStringAsFixed(d.abs() >= 100 ? 0 : 2),
    final num n => '$n',
    final bool b => b ? 'yes' : 'no',
    final String s when s.isEmpty || s.length > 80 => null,
    final String s => s,
    _ => null,
  };

  final rows = <(String, String)>[];
  void add(String key, Object? v) {
    if (_hiddenMeasurements.contains(key)) return;
    final text = value(v);
    if (text != null) rows.add((label(key), text));
  }

  for (final entry in metrics.entries) {
    if (entry.value case final Map settings) {
      for (final s in settings.entries) {
        add('${s.key}', s.value);
      }
    } else {
      add(entry.key, entry.value);
    }
  }
  if (metrics['devices'] case final List devices) {
    final names = [
      for (final d in devices.whereType<Map>()) '${d['name'] ?? d['backend']}',
    ];
    if (names.isNotEmpty) rows.add(('Devices', names.join(', ')));
  }
  return rows;
}

class HelperUsedChip extends ConsumerWidget {
  final String messageId;
  const HelperUsedChip({super.key, required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(
      helperJobsProvider.select(
        (s) => s.jobs
            .where((j) => j.messageId == messageId)
            .map((j) => j.id)
            .join(','),
      ),
    );
    if (ids.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        key: Key('helper-used-$messageId'),
        avatar: const Icon(Icons.support_agent, size: 16),
        label: Text(context.l10n.helperUsed, style: context.text.mono),
        onPressed: () => showMorphSheet<void>(
          context: context,
          builder: (_) => _HelperDetails(ids: ids.split(',').toSet()),
        ),
      ),
    );
  }
}

class _HelperDetails extends ConsumerWidget {
  final Set<String> ids;
  const _HelperDetails({required this.ids});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AppSheet(
    title: context.l10n.helperLiveTitle,
    children: [
      for (final job in ref.watch(helperJobsProvider).jobs)
        if (ids.contains(job.id)) HelperJobCard(job: job),
    ],
  );
}
