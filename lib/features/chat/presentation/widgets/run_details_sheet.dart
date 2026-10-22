import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../domain/entities/turn_run.dart';
import '../screens/context_inspector_page.dart';
import '../../../../core/motion/motion.dart';

/// What produced one answer (CHAT-04): model, preset, the settings in force,
/// what the engine ran with and what it measured — with a copy button so a
/// bug report or a comparison carries the exact conditions.
Future<void> showRunDetailsSheet(BuildContext context, TurnRun run) =>
    showMorphSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RunDetailsSheet(run),
    );

class _RunDetailsSheet extends StatelessWidget {
  final TurnRun run;
  const _RunDetailsSheet(this.run);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    final m = run.metrics;
    String fmt(Object? v) =>
        v is double ? v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2) : '$v';
    final measured = <(String, String)>[
      if (m['backend'] != null)
        ('backend', m['backend'].toString().split(' / ').first),
      if (m['tokensPerSecond'] is num)
        ('speed', '${fmt(m['tokensPerSecond'])} tok/s'),
      if (m['firstTokenMs'] is num)
        ('first token', '${(m['firstTokenMs'] as num).round()} ms'),
      if (m['promptTokens'] != null) ('prompt tokens', '${m['promptTokens']}'),
      if (m['cachedPromptTokens'] is num &&
          (m['cachedPromptTokens'] as num) > 0)
        ('cached', '${m['cachedPromptTokens']}'),
      if (m['tokens'] != null) ('generated', '${m['tokens']}'),
      if (m['thinkingTokens'] is num && (m['thinkingTokens'] as num) > 0)
        ('thinking', '${m['thinkingTokens']}'),
      if (m['contextUsed'] != null && m['contextSize'] != null)
        ('context', '${m['contextUsed']} / ${m['contextSize']}'),
      if (m['peakRssMb'] is num) ('peak RSS', '${fmt(m['peakRssMb'])} MB'),
      if (m['trimmedMessages'] is num && (m['trimmedMessages'] as num) > 0)
        ('trimmed turns', '${m['trimmedMessages']}'),
      if (run.sources > 0) ('sources', '${run.sources}'),
      if (m['searchProviders'] is List)
        for (final p in m['searchProviders'] as List)
          if (p is Map)
            (
              '${p['provider']}',
              '${p['status']} · ${p['relevant']} relevant / ${p['parsed']} parsed',
            ),
      if (m['stages'] is Map)
        for (final phase in (m['stages'] as Map).entries)
          ('${phase.key}', '${phase.value} ms'),
    ];
    final s = run.settings;
    final settings = <(String, String)>[
      for (final k in const [
        'temperature',
        'topP',
        'minP',
        'topK',
        'repetitionPenalty',
        'maxTokens',
        'contextSize',
        'thinkingModeEnabled',
        'thinkingBudgetTokens',
        'webMode',
        'knowledgeCollection',
        'memoryEnabled',
        'promptCache',
        'backend',
        'kvCacheType',
        'vCacheType',
        'seed',
        'presencePenalty',
        'frequencyPenalty',
        'responseFormat',
        'toolsEnabled',
        'toolChoice',
        'draftModelId',
      ])
        if (s[k] != null &&
            s[k].toString().isNotEmpty &&
            !(k == 'seed' && s[k] == 0) &&
            !(k == 'presencePenalty' && s[k] == 0) &&
            !(k == 'frequencyPenalty' && s[k] == 0) &&
            !(k == 'responseFormat' && s[k] == 'text') &&
            !(k == 'toolsEnabled' && s[k] == false) &&
            !(k == 'toolChoice' &&
                (s[k] == 'auto' || s['toolsEnabled'] != true)))
          (
            run.origins.containsKey(k) ? '$k (${run.origins[k]})' : k,
            fmt(s[k]),
          ),
    ];
    final tools = <(String, String)>[
      for (final t in run.toolTrace)
        (
          '${(t['call'] as Map?)?['name']}(${_short((t['call'] as Map?)?['arguments'])})',
          '${t['ok'] == true ? 'ok' : 'error'} · ${t['elapsedMs']} ms',
        ),
    ];
    final speculation = <(String, String)>[
      if (m['draftModel'] is String && (m['draftModel'] as String).isNotEmpty)
        ('draft model', m['draftModel'].toString()),
      if (m['draftProposed'] is num && (m['draftProposed'] as num) > 0)
        (
          'drafts accepted',
          '${m['draftAccepted']} / ${m['draftProposed']} (${((m['draftAcceptRate'] as num? ?? 0) * 100).round()}%)',
        ),
      if (m['draftSpeedup'] is num && (m['draftSpeedup'] as num) > 0)
        (
          'draft speed',
          '${(m['draftSpeedup'] as num).toStringAsFixed(2)}x plain',
        ),
      if (m['draftDisabled'] == true)
        (
          'drafting',
          'paused after ${m['draftRounds']} rounds (${(m['draftAcceptRate'] as num? ?? 1) < 0.35 ? 'acceptance below 35%' : 'slower than plain decoding'})',
        ),
      if (m['finishReason'] is String &&
          (m['finishReason'] as String).isNotEmpty)
        ('ended by', m['finishReason'].toString()),
    ];
    final e = run.engine;
    final engine = <(String, String)>[
      for (final k in const [
        'threads',
        'batchThreads',
        'batchSize',
        'microBatchSize',
        'contextSize',
        'requestedGpuLayers',
        'flashAttentionPolicy',
        'memory',
      ])
        if (e[k] != null) (k, fmt(e[k])),
    ];
    Widget table(String title, List<(String, String)> rows) => rows.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: AppDesign.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.label.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: AppDesign.xs),
                for (final (k, v) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            k,
                            style: context.text.mono.copyWith(
                              color: c.textFaint,
                            ),
                          ),
                        ),
                        // Long values (paused-drafting reasons, backend
                        // names) wrap instead of overflowing the sheet.
                        Expanded(
                          child: Text(
                            v,
                            textAlign: TextAlign.right,
                            style: context.text.mono.copyWith(color: c.text),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => AppSheet(
        title: t.runDetails,
        meta:
            '${run.modelName} · ${run.presetName} · ${run.at.toLocal().toString().substring(0, 16)}',
        scrollable: false,
        primary: FilledButton.icon(
          key: const Key('run-copy'),
          label: Text(t.copyRunDetails),
          icon: const Icon(Icons.copy_outlined),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: run.plainText()));
            showIslandToast(context, t.runDetailsCopied, tone: IslandTone.done);
          },
        ),
        children: [
          ListView(
            key: const Key('run-details'),
            controller: controller,
            padding: EdgeInsets.zero,
            children: [
              table(t.runMeasured, [...measured, ...speculation]),
              if (m['memoryUsed'] is List &&
                  (m['memoryUsed'] as List).isNotEmpty)
                ExpansionTile(
                  title: Text(t.memoryUsed),
                  children: [
                    for (final note in (m['memoryUsed'] as List).toSet())
                      ListTile(title: SelectableText('$note')),
                  ],
                ),
              if (m['evidenceAudit'] is Map &&
                  ((m['evidenceAudit'] as Map)['unsupportedClaims'] as List? ??
                          [])
                      .isNotEmpty)
                ListTile(
                  title: Text(t.unverifiedFeatures),
                  subtitle: Text(
                    '${(m['evidenceAudit'] as Map)['unsupportedClaims']}',
                  ),
                ),
              ListTile(
                key: const Key('run-context-inspector'),
                leading: const Icon(Icons.manage_search),
                title: Text(t.contextInspector),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ContextInspectorPage(run: run),
                  ),
                ),
              ),
              table(t.runSettings, settings),
              table(t.runEngine, engine),
              table('Tools', tools),
            ],
          ),
        ],
      ),
    );
  }
}

String _short(Object? v) {
  final s = v?.toString() ?? '';
  return s.length > 40 ? '${s.substring(0, 37)}…' : s;
}
