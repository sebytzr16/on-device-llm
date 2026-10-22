import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';
import '../../domain/entities/turn_run.dart';

class ContextInspectorPage extends StatelessWidget {
  final TurnRun run;
  const ContextInspectorPage({super.key, required this.run});

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final audit = run.metrics['contextAudit'];
    final data = audit is Map ? audit : const {};
    final turns = [
      for (final row in data['turns'] as List? ?? const [])
        if (row is Map) row,
    ];
    final sources = [
      for (final row in data['sources'] as List? ?? const [])
        if (row is Map) row,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t.contextInspector)),
      body: ListView(
        padding: const EdgeInsets.all(AppDesign.lg),
        children: [
          Text(
            '${run.modelName} · ${run.at.toLocal()}',
            style: context.text.bodyMuted,
          ),
          const SizedBox(height: AppDesign.md),
          Text(t.contextSnapshotHint),
          if (data.isEmpty)
            Text(t.contextSnapshotMissing)
          else ...[
            const SizedBox(height: AppDesign.md),
            Text(
              '${t.contextTokens}: ${run.metrics['contextUsed'] ?? '—'} / '
              '${run.metrics['contextSize'] ?? run.settings['contextSize'] ?? '—'}',
              style: context.text.title,
            ),
            if (data['isolated'] == true) Text(t.contextIsolated),
            if (data['documentNotice'] is String)
              Text(data['documentNotice'] as String),
            const SizedBox(height: AppDesign.lg),
            ExpansionTile(
              key: const Key('context-instructions'),
              title: Text(t.contextInstructions),
              subtitle: Text(
                '${data['instructionChars']} ${t.contextCharacters}',
              ),
              children: [SelectableText('${data['instructions'] ?? ''}')],
            ),
            const SizedBox(height: AppDesign.md),
            Text(t.contextMessages, style: context.text.title),
            Text(
              '${t.contextIncluded}: ${data['includedMessages'] ?? 0} · '
              '${t.contextOmitted}: ${data['omittedMessages'] ?? 0}',
            ),
            if ((data['earlierEntriesHidden'] as num? ?? 0) > 0)
              Text(
                '${t.contextEarlierHidden}: ${data['earlierEntriesHidden']}',
              ),
            for (final row in turns)
              ListTile(
                key: ValueKey('context-message-${row['id']}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  row['included'] == true
                      ? Icons.check_circle_outline
                      : Icons.remove_circle_outline,
                ),
                title: SelectableText('${row['role']}: ${row['excerpt']}'),
                subtitle: Text(
                  [
                    row['included'] == true
                        ? t.contextIncluded
                        : row['reason'] == 'isolated'
                        ? t.contextOmittedIsolated
                        : row['reason'] == 'reviewed_summary'
                        ? t.contextSummary
                        : t.contextOmittedLimit,
                    '${row['chars']} ${t.contextCharacters}',
                    if ((row['images'] as num? ?? 0) > 0)
                      '${row['images']} ${t.contextImages}',
                    if ((row['documents'] as num? ?? 0) > 0)
                      '${row['documents']} ${t.contextDocuments}',
                  ].join(' · '),
                ),
              ),
            const SizedBox(height: AppDesign.md),
            Text(t.goalSourcesTitle, style: context.text.title),
            for (final source in sources)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('[${source['number']}] ${source['title']}'),
                subtitle: SelectableText(
                  [
                    '${source['url']}',
                    '${source['chars']} ${t.contextCharacters}',
                    if (source['snippetOnly'] == true) t.contextSnippetOnly,
                    if (source['stale'] == true) t.contextStale,
                    if (source['retrievedAt'] != null)
                      '${source['retrievedAt']}',
                  ].join('\n'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
