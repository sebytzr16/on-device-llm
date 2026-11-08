import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../core/providers/shared_providers.dart';
import '../data/storage/model_storage.dart';
import '../features/models/domain/entities/model_catalog.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../features/settings/presentation/providers/model_profiles_provider.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../core/island/status_island.dart';
import 'benchmark_receipt.dart';
import 'model_speed_section.dart';
import 'model_tuner.dart';
import 'pc_optimization.dart';
import 'tune_benchmark_run.dart';

class ModelOptimizeSection extends ConsumerStatefulWidget {
  final ModelInfo model;
  final InferenceSettings settings;
  final ValueChanged<Map<String, dynamic>>? onTuned;
  const ModelOptimizeSection({
    super.key,
    required this.model,
    required this.settings,
    this.onTuned,
  });

  @override
  ConsumerState<ModelOptimizeSection> createState() =>
      _ModelOptimizeSectionState();
}

class _ModelOptimizeSectionState extends ConsumerState<ModelOptimizeSection> {
  TuneBenchmarkRun? _run;
  bool _failed = false;
  (double, double)? _rates;
  (int, int)? _step;
  double? _progress;

  @override
  void dispose() {
    _run?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (ref.read(sessionBusyProvider) ||
        ref.read(modelManagerProvider).isLoadingModel) {
      return;
    }
    final busy = ref.read(sessionBusyProvider.notifier);
    final manager = ref.read(modelManagerProvider.notifier);
    final profiles = ref.read(modelProfilesProvider.notifier);
    final global = ref.read(settingsProvider.notifier);
    final receipts = ref.read(benchmarkReceiptsProvider.notifier);
    final estimator = ref.read(llamaEstimatorProvider);
    final model = widget.model, original = widget.settings;
    // A loaded model holds the memory the estimates read as free, so every
    // layer count looked over budget; the estimates below unload it and the
    // run loads the model again at the end.
    busy.state = true;
    final runner = TuneBenchmarkRun(
      engine: ref.read(modelSpeedEngineProvider),
      model: model,
      load: (s) => manager.loadModel(model, forChat: true, settings: s),
      estimate: (s) async {
        // Each benchmark leaves the model loaded; its memory would read as
        // taken and every next setup as over budget. The next load reloads.
        if (ref.read(modelManagerProvider).loadedModelId != null) {
          await manager.unloadModel(ownsBusy: true);
        }
        final projector = model.projector ?? visionProjectors[model.id];
        final mmproj =
            projector != null &&
                ref.read(modelManagerProvider).vision.contains(model.id)
            ? (await ModelStorage.modelFile(projector.fileName)).path
            : null;
        return estimator.estimate(
          modelPath: model.localPath!,
          settings: s,
          mmprojPath: mmproj,
          draftModelPath: manager.draftPathFor(model, s.draftModelId),
        );
      },
      save: receipts.save,
    );
    setState(() {
      _run = runner;
      _failed = false;
      _rates = null;
      _step = null;
      _progress = 0;
    });
    var finalSettings = original;
    try {
      await profiles.ready;
      await global.ready;
      await manager.ready;
      final defaults = await pcOptimizationDefaults(
        current: original,
        defaults: global.defaults,
        estimate: runner.estimate,
      );
      if (runner.cancelled) return;
      // Each setup gets one quick round (three prompts) so big models finish
      // in minutes; one whose greedy answer differs from the reference
      // setup's is less accurate and cannot win.
      final setups = pcOptimizationSetups(
        defaults,
        mtpHead: autoMtpHead(model.localPath!) != null,
      );
      // The current settings' run, then each setup: equal shares of the bar.
      final stages = setups.length + 1;
      void progress(int stage, double part) {
        if (mounted) setState(() => _progress = (stage + part) / stages);
      }

      // Do not deliberately benchmark a configuration already over budget.
      final before = await runner.fits(original.toJson())
          ? await runner.benchmark(
              original.toJson(),
              progress: (f) => progress(0, f),
              quick: true,
            )
          : null;
      if (runner.cancelled) return;
      progress(1, 0);
      InferenceSettings? best;
      TuneMeasurement? after;
      String? reference;
      for (var i = 0; i < setups.length; i++) {
        if (runner.cancelled || !mounted) return;
        setState(() => _step = (i + 1, setups.length));
        if (!await runner.fits(setups[i].toJson())) {
          progress(i + 2, 0);
          continue;
        }
        final m = await runner.benchmark(
          setups[i].toJson(),
          progress: (f) => progress(i + 1, f),
          quick: true,
        );
        progress(i + 2, 0);
        reference ??= m.outputHash;
        if (m.outputHash != reference) continue;
        if (after == null || m.tokensPerSecond > after.tokensPerSecond) {
          best = setups[i];
          after = m;
        }
      }
      if (runner.cancelled || !mounted) return;
      if (best == null || after == null) throw StateError('No setup measured');
      final faster =
          before == null ||
          after.tokensPerSecond >= before.tokensPerSecond * 0.97;
      final winner = best, rate = after.tokensPerSecond;
      if (faster) {
        final changes = {
          for (final key in pcOptimizationKeys) key: winner.toJson()[key],
        };
        // The model's profile sits above the app-wide settings, so the
        // winner applies without touching other models (audit P1-13).
        await profiles.set(model.id, {...profiles.of(model.id), ...changes});
        finalSettings = winner;
        widget.onTuned?.call(changes);
      }
      if (mounted) {
        setState(() => _rates = (before?.tokensPerSecond ?? 0, rate));
        showIslandToast(
          context,
          faster
              ? context.l10n.desktopOptimizeSaved
              : context.l10n.desktopOptimizeKept,
        );
      }
    } catch (_) {
      if (mounted && !runner.cancelled) setState(() => _failed = true);
    } finally {
      try {
        await manager.loadModel(model, forChat: true, settings: finalSettings);
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }
      busy.state = false;
      if (mounted) {
        setState(() {
          _run = null;
          _step = null;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final busy =
        ref.watch(sessionBusyProvider) ||
        ref.watch(modelManagerProvider).isLoadingModel;
    final rates = _rates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.desktopOptimizeHint,
          style: context.text.caption.copyWith(color: context.colors.textMuted),
        ),
        if (_run != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(switch (_step) {
                  (final n, final total) => t.desktopOptimizeStep(n, total),
                  null => t.desktopOptimizeBaseline,
                }, style: context.text.caption),
              ),
              Text(
                t.desktopOptimizeProgress(
                  ((_progress ?? 0) * 100).floor().clamp(0, 99),
                ),
                key: const Key('desktop-optimize-percent'),
                style: context.text.small.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: _progress),
          TextButton(
            onPressed: () => _run?.cancel(),
            child: Text(t.tuneCancel),
          ),
        ] else
          FilledButton.icon(
            key: const Key('desktop-optimize'),
            onPressed: busy || widget.model.localPath == null ? null : _start,
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: Text(t.desktopOptimize),
          ),
        if (_failed)
          Text(
            t.tuneError,
            style: context.text.small.copyWith(color: context.colors.danger),
          ),
        if (rates != null)
          Text(
            t.desktopOptimizeRates(
              rates.$1 > 0 ? rates.$1.toStringAsFixed(1) : t.tuneUnavailable,
              rates.$2.toStringAsFixed(1),
            ),
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
                receipt.json['timestamp'] as String,
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
              t.tuneReceipt(receipt.json['timestamp'] as String),
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
