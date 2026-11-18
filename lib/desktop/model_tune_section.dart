import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../core/providers/shared_providers.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../core/island/status_island.dart';
import '../features/optimize/benchmark_receipt.dart';
import '../features/optimize/optimize_setups.dart';
import '../features/optimize/optimize_controller.dart';

class ModelOptimizeSection extends ConsumerStatefulWidget {
  final ModelInfo model;
  final InferenceSettings settings;
  final ValueChanged<Map<String, dynamic>>? onTuned;
  const ModelOptimizeSection({
    super.key,
    required this.model,
    required this.settings,
    this.onTuned,
    this.autoStart = false,
  });

  /// Starts the run as soon as the section opens (the first-run offer).
  final bool autoStart;

  @override
  ConsumerState<ModelOptimizeSection> createState() =>
      _ModelOptimizeSectionState();
}

class _ModelOptimizeSectionState extends ConsumerState<ModelOptimizeSection> {
  OptimizeController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  void dispose() {
    _controller?.cancel();
    super.dispose();
  }

  Future<void> _start() => ref
      .read(optimizeControllerProvider(widget.model.id).notifier)
      .start(widget.model, widget.settings, onTuned: widget.onTuned);

  String _keepReason(AppLocalizations t, OptimizeKeepReason reason) =>
      switch (reason) {
        OptimizeKeepReason.outputChanged => t.desktopOptimizeKeptOutput,
        OptimizeKeepReason.baselineUnavailable => t.desktopOptimizeKeptBaseline,
        OptimizeKeepReason.slower => t.desktopOptimizeKept,
        OptimizeKeepReason.noisy => t.desktopOptimizeKeptNoise,
      };

  @override
  Widget build(BuildContext context) {
    final provider = optimizeControllerProvider(widget.model.id);
    _controller = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (previous?.running == true &&
          !next.running &&
          !next.failed &&
          (next.saved || next.kept != null)) {
        showIslandToast(
          context,
          next.saved
              ? context.l10n.desktopOptimizeSaved
              : _keepReason(context.l10n, next.kept!),
        );
      }
    });
    final optimize = ref.watch(provider);
    final rates = optimize.rates;
    final step = optimize.step, progress = optimize.progress;
    final changes = optimize.changes, kept = optimize.kept;
    final t = context.l10n;
    final mobile = ref.watch(optimizeMobileProvider);
    final error = switch (optimize.failure) {
      OptimizeFailure.measurement => t.optimizeMeasurementError,
      OptimizeFailure.save => t.optimizeSaveError,
      OptimizeFailure.reload => t.optimizeReloadError,
      null => null,
    };
    final busy =
        ref.watch(sessionBusyProvider) ||
        ref.watch(modelManagerProvider).isLoadingModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mobile
              ? t.optimizeSettingsHint(widget.model.displayName)
              : t.desktopOptimizeHint,
          style: context.text.caption.copyWith(color: context.colors.textMuted),
        ),
        if (optimize.running) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(switch (step) {
                  (final n, final total) => t.desktopOptimizeStep(n, total),
                  null => t.desktopOptimizeBaseline,
                }, style: context.text.caption),
              ),
              Text(
                t.desktopOptimizeProgress(
                  ((progress ?? 0) * 100).floor().clamp(0, 99),
                ),
                key: const Key('desktop-optimize-percent'),
                style: context.text.small.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: progress),
          TextButton(
            onPressed: () => _controller?.cancel(),
            child: Text(t.tuneCancel),
          ),
        ] else
          FilledButton.icon(
            key: const Key('desktop-optimize'),
            onPressed: busy || widget.model.localPath == null ? null : _start,
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: Text(mobile ? t.optimizeSettingsTitle : t.desktopOptimize),
          ),
        if (error != null)
          Text(
            error,
            style: context.text.small.copyWith(color: context.colors.danger),
          ),
        if (rates != null)
          Text(
            t.desktopOptimizeRates(
              rates.$1 > 0 ? rates.$1.toStringAsFixed(1) : t.tuneUnavailable,
              rates.$2.toStringAsFixed(1),
            ),
          ),
        if (changes != null) Text(changes),
        if (kept != null)
          Text(
            _keepReason(t, kept),
            key: const Key('desktop-optimize-kept-reason'),
            style: context.text.small.copyWith(color: context.colors.textMuted),
          ),
      ],
    );
  }
}

/// Shared entry point for the phone's model card, beside its benchmark action.
class BenchmarkHistoryButton extends StatelessWidget {
  final String modelId;
  const BenchmarkHistoryButton({super.key, required this.modelId});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.l10n.benchmarkHistory,
    icon: const Icon(Icons.history),
    onPressed: () => showAppDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(AppDesign.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dialog.l10n.benchmarkHistory,
                        style: dialog.text.title,
                      ),
                    ),
                    IconButton(
                      tooltip: dialog.l10n.desktopClose,
                      onPressed: () => Navigator.pop(dialog),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: BenchmarkReceiptSection(modelId: modelId),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class BenchmarkReceiptSection extends ConsumerStatefulWidget {
  final String modelId;
  const BenchmarkReceiptSection({super.key, required this.modelId});

  @override
  ConsumerState<BenchmarkReceiptSection> createState() =>
      _BenchmarkReceiptSectionState();
}

class _BenchmarkReceiptSectionState
    extends ConsumerState<BenchmarkReceiptSection> {
  final _selected = <BenchmarkReceipt>{};

  @override
  void didUpdateWidget(BenchmarkReceiptSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId) _selected.clear();
  }

  Future<void> _delete({BenchmarkReceipt? receipt, bool clear = false}) async {
    final t = context.l10n;
    final selected = receipt == null ? _selected.toList() : [receipt];
    final store = ref.read(benchmarkReceiptsProvider.notifier);
    final modelId = widget.modelId;
    if (!await confirmAction(
      context,
      title: clear ? t.benchmarkClearHistory : t.benchmarkDeleteReceipts,
      message: clear
          ? t.benchmarkClearHistoryConfirm
          : t.benchmarkDeleteReceiptsConfirm(selected.length),
      confirmLabel: clear ? t.benchmarkClearHistory : t.benchmarkDeleteReceipts,
      destructive: true,
    )) {
      return;
    }
    try {
      if (clear) {
        await store.clearModel(modelId);
      } else {
        await store.remove(modelId, selected);
      }
      if (mounted) setState(() => _selected.removeAll(selected));
    } catch (_) {
      if (mounted) {
        showIslandToast(context, t.historyRemoveError, tone: IslandTone.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final receipts = ref
        .watch(benchmarkReceiptsProvider)
        .where((r) => r.json['modelId'] == widget.modelId)
        .toList()
        .reversed;
    _selected.retainAll(receipts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (receipts.isEmpty)
          Text(t.benchmarkHistoryEmpty, style: context.text.caption),
        if (receipts.isNotEmpty) ...[
          Text(t.benchmarkHistory, style: context.text.label),
          Text(
            t.benchmarkHistoryHint,
            style: context.text.caption.copyWith(
              color: context.colors.textMuted,
            ),
          ),
          Wrap(
            spacing: AppDesign.sm,
            children: [
              TextButton(
                onPressed: _selected.isEmpty ? null : () => _delete(),
                child: Text(t.benchmarkDeleteSelected(_selected.length)),
              ),
              TextButton(
                onPressed: () => _delete(clear: true),
                child: Text(t.benchmarkClearHistory),
              ),
            ],
          ),
        ],
        for (final receipt in receipts)
          ExpansionTile(
            key: ObjectKey(receipt),
            leading: Checkbox(
              value: _selected.contains(receipt),
              semanticLabel: t.benchmarkSelectReceipt(
                _receiptWhen(context, receipt.json['timestamp']),
              ),
              onChanged: (selected) => setState(() {
                if (selected == true) {
                  _selected.add(receipt);
                } else {
                  _selected.remove(receipt);
                }
              }),
            ),
            title: Text(
              t.tuneReceipt(_receiptWhen(context, receipt.json['timestamp'])),
              style: context.text.small,
            ),
            subtitle: Text(
              '${receipt.json['modelFile']} · ${receipt.json['backend'] ?? t.tuneUnknown}',
              style: context.text.caption,
            ),
            children: [
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: Text(t.benchmarkDeleteReceipt),
                onPressed: () => _delete(receipt: receipt),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    for (final label in [
                      t.tunePromptClass,
                      t.tuneMedianRate,
                      t.tuneSpreadRate,
                      t.tuneTtft,
                      t.tunePromptRate,
                      t.tuneAcceptance,
                    ])
                      DataColumn(label: Text(label)),
                  ],
                  rows: [
                    for (final entry
                        in ((receipt.json['promptClasses'] as Map?) ?? {})
                            .entries)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(switch (entry.key) {
                              'short' => t.tuneShortPrompt,
                              'longPrefill' => t.tuneLongPrompt,
                              _ => t.tuneCodePrompt,
                            }),
                          ),
                          for (final key in [
                            'medianTokensPerSecond',
                            'spreadTokensPerSecond',
                            'medianTtftMs',
                            'medianPromptTokensPerSecond',
                            'medianDraftAcceptance',
                          ])
                            DataCell(
                              Text(
                                (entry.value[key] as num?)?.toStringAsFixed(
                                      2,
                                    ) ??
                                    t.tuneUnavailable,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              ExpansionTile(
                title: Text(t.tuneReceiptDetails, style: context.text.caption),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(receipt.json),
                    style: context.text.caption,
                  ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.save_alt_rounded),
                label: Text(t.tuneExport),
                onPressed: () async {
                  try {
                    final result = await FilePicker.saveFile(
                      fileName: 'benchmark-receipt.json',
                      dialogTitle: t.tuneExport,
                      bytes: utf8.encode(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(receipt.json),
                      ),
                      mimeType: 'application/json',
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                    );
                    if (result != null && context.mounted) {
                      showIslandToast(context, t.tuneExported);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      showIslandToast(
                        context,
                        t.tuneError,
                        tone: IslandTone.error,
                      );
                    }
                  }
                },
              ),
            ],
          ),
      ],
    );
  }
}

/// A receipt's UTC ISO timestamp as the user's local date and time; anything
/// unparsable is shown as stored.
String _receiptWhen(BuildContext context, Object? stamp) {
  final raw = stamp?.toString() ?? '';
  final time = DateTime.tryParse(raw)?.toLocal();
  if (time == null) return raw;
  final m = MaterialLocalizations.of(context);
  return '${m.formatShortDate(time)} '
      '${m.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
}
