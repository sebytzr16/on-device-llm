import '../../core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/app_design.dart';
import '../models/domain/entities/model_info.dart';
import 'benchmark.dart';
import '../../core/island/status_island.dart';
import '../../core/design/app_dialog.dart';

/// Shows [model]'s last benchmark, or runs one when there is none (or when
/// [runNow] asks for it); the result dialog offers Run again and the card
/// for sharing. Returns when the dialog closes. Tapping a benchmarked model
/// used to re-run it every time, so a result was only visible once.
Future<void> showBenchmarkDialog(
  BuildContext context,
  WidgetRef ref,
  ModelInfo model, {
  bool? runNow,
}) async {
  final notifier = ref.read(benchmarkProvider.notifier);
  await notifier.ready;
  if (!context.mounted) return;
  var run = runNow ?? ref.read(benchmarkProvider).results[model.id] == null;
  while (true) {
    if (!context.mounted) return;
    if (run) {
      try {
        final result = await showAppDialog<BenchmarkResult?>(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              _RunningDialog(model: model, notifier: notifier),
        );
        if (result == null) {
          final error = ref.read(benchmarkProvider).error;
          if (error != null && context.mounted) {
            showIslandToast(
              context,
              context.l10n.benchmarkFailed(error),
              tone: IslandTone.error,
            );
          }
          return;
        }
      } on StateError catch (e) {
        if (context.mounted) {
          showIslandToast(context, e.message);
        }
        return;
      }
    }
    final result = ref.read(benchmarkProvider).results[model.id];
    if (result == null || !context.mounted) return;
    final again = await showAppDialog<bool>(
      context: context,
      builder: (context) => _ResultDialog(result: result),
    );
    if (again != true) return;
    run = true;
  }
}

class _RunningDialog extends StatefulWidget {
  final ModelInfo model;
  final BenchmarkNotifier notifier;
  const _RunningDialog({required this.model, required this.notifier});
  @override
  State<_RunningDialog> createState() => _RunningDialogState();
}

class _RunningDialogState extends State<_RunningDialog> {
  @override
  void initState() {
    super.initState();
    widget.notifier
        .run(widget.model)
        .then((r) {
          if (mounted) Navigator.pop(context, r);
        })
        .catchError((Object e) {
          if (mounted) Navigator.pop(context, null);
        });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    content: Row(
      spacing: AppDesign.md,
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        Expanded(
          child: Text(
            context.l10n.benchmarkRunning(
              widget.model.displayName,
              BenchmarkResult.warmUps + BenchmarkResult.samplesPerRun,
            ),
            style: context.text.bodyMuted,
          ),
        ),
      ],
    ),
  );
}

class _ResultDialog extends StatelessWidget {
  final BenchmarkResult result;
  const _ResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = result.card();
    Widget row(String label, String value) => Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: context.text.label.copyWith(color: c.textFaint),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: context.text.monoStrong,
          ),
        ),
      ],
    );
    return AlertDialog(
      scrollable: true,
      title: Text(result.modelName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppDesign.md,
        children: [
          row('Backend', '${result.backend} · ${result.library}'),
          row('Prefill', '${result.prefillTps.toStringAsFixed(0)} tok/s'),
          row(
            '',
            '${result.promptTokens} tok in ${(result.prefillMs / 1000).toStringAsFixed(2)} s',
          ),
          row('Decode', '${result.decodeTps.toStringAsFixed(1)} tok/s'),
          if (result.samples.length > 1)
            row('Basis', 'median of ${result.samples.length}'),
          // What a first chat message costs (review #8).
          for (final (label, s) in [
            ('Chat', result.chat),
            ('Chat + tools', result.chatTools),
          ])
            if (s != null) ...[
              row(
                label,
                '${(s.prefillMs / 1000).toStringAsFixed(2)} s to first token',
              ),
              row(
                '',
                '${s.promptTokens} tok · ${s.decodeTps.toStringAsFixed(1)} tok/s',
              ),
            ],
          row('Threads', '${result.threads} / ${result.batchThreads}'),
          if (result.engineSummary.isNotEmpty)
            row('Engine', result.engineSummary),
          row('Peak RSS', '${result.peakRssMb.round()} MB'),
          row('Context', '${result.contextSize}'),
          if (result.thermalSummary.isNotEmpty)
            row('Thermal', result.thermalSummary),
          Text(
            context.l10n.benchmarkMeasuredAt(
              MaterialLocalizations.of(
                context,
              ).formatMediumDate(result.runAt.toLocal()),
            ),
            style: context.text.label.copyWith(color: c.textFaint),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          key: const Key('benchmark-run-again'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.replay, size: 16),
          label: Text(context.l10n.benchmarkRunAgain),
        ),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: card));
            showIslandToast(
              context,
              context.l10n.uiBenchmarkDialogBenchmarkCopied,
              tone: IslandTone.done,
            );
          },
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: Text(context.l10n.uiBenchmarkDialogCopy),
        ),
        TextButton.icon(
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: card, subject: 'OnDevice LLM benchmark'),
          ),
          icon: const Icon(Icons.ios_share, size: 16),
          label: Text(context.l10n.uiBenchmarkDialogShare),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.uiBenchmarkDialogDone),
        ),
      ],
    );
  }
}
