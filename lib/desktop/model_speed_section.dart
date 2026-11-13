import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../core/providers/shared_providers.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../features/benchmark/benchmark.dart';
import '../inference/engine/text_engine.dart';
import 'model_speed_results_provider.dart';
import 'benchmark_receipt.dart';
import 'model_tune_section.dart';
import 'tune_benchmark_run.dart';

final modelSpeedEngineProvider = Provider<TextEngine>(
  (ref) => ref.read(llamaEngineProvider),
);

class ModelSpeedSection extends ConsumerStatefulWidget {
  final ModelInfo model;
  final InferenceSettings settings;
  final Future<void> Function()? load;
  const ModelSpeedSection({
    super.key,
    required this.model,
    required this.settings,
    this.load,
  });
  @override
  ConsumerState<ModelSpeedSection> createState() => _ModelSpeedSectionState();
}

class _ModelSpeedSectionState extends ConsumerState<ModelSpeedSection> {
  TuneBenchmarkRun? _run;
  double _progress = 0;
  bool _failed = false;
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
    final results = ref.read(modelSpeedResultsProvider.notifier);
    final engine = ref.read(modelSpeedEngineProvider);
    final manager = ref.read(modelManagerProvider.notifier);
    final receipts = ref.read(benchmarkReceiptsProvider.notifier);
    final model = widget.model, settings = widget.settings;
    BenchmarkReceipt? measured;
    final draftFile = await manager.draftPathFor(model, settings.draftModelId);
    final run = TuneBenchmarkRun(
      engine: engine,
      model: model,
      load: (s) async {
        if (widget.load != null) {
          await widget.load!();
        } else {
          await manager.ready;
          await manager.loadModel(model, forChat: true, settings: s);
        }
      },
      estimate: (_) async => {},
      save: (receipt) async {
        await receipts.save(receipt);
        measured = receipt;
      },
      draftFile: draftFile,
    );
    busy.state = true;
    setState(() {
      _run = run;
      _progress = 0;
      _failed = false;
    });
    try {
      await run.benchmark(
        settings.toJson(),
        repetitions: 3,
        progress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!run.cancelled) {
        final classes = measured!.json['promptClasses'] as Map;
        final samples = [
          for (final stats in classes.values)
            BenchmarkSample(
              prefillMs: (stats['medianTtftMs'] as num).toDouble(),
              decodeTps: (stats['medianTokensPerSecond'] as num).toDouble(),
              peakRssMb:
                  (stats['rounds'][0]['peakRssMb'] as num?)?.toDouble() ?? 0,
              promptTokens:
                  (stats['rounds'][0]['promptTokens'] as num?)?.toInt() ?? 0,
              generated:
                  (stats['rounds'][0]['generated'] as num?)?.toInt() ?? 0,
            ),
        ];
        await results.save(
          ModelSpeedResult(
            modelId: model.id,
            shape: modelSpeedShape(settings),
            timestamp: DateTime.now(),
            samples: samples,
          ),
        );
      }
    } catch (_) {
      if (mounted && !run.cancelled) setState(() => _failed = true);
    } finally {
      busy.state = false;
      if (mounted) setState(() => _run = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final running = _run != null;
    final results = ref.watch(modelSpeedResultsProvider);
    final shape = modelSpeedShape(widget.settings);
    final result = results.values
        .where((r) => r.modelId == widget.model.id && r.shape == shape)
        .firstOrNull;
    final busy =
        ref.watch(sessionBusyProvider) ||
        ref.watch(modelManagerProvider).isLoadingModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.desktopBenchTitle, style: context.text.label),
        Text(
          t.tuneBenchHint,
          style: context.text.caption.copyWith(color: context.colors.textMuted),
        ),
        const SizedBox(height: 8),
        if (running) ...[
          LinearProgressIndicator(value: _progress),
          TextButton(
            onPressed: () {
              _run?.cancel();
            },
            child: Text(t.desktopBenchCancel),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: busy || widget.model.localPath == null ? null : _start,
            icon: const Icon(Icons.speed_rounded),
            label: Text(t.desktopBenchStart),
          ),
        if (_failed)
          Text(
            t.desktopBenchError,
            style: context.text.small.copyWith(color: context.colors.danger),
          ),
        if (result != null) ...[
          Text(
            t.desktopBenchLast(result.timestamp.toLocal().toString()),
            style: context.text.caption,
          ),
          Table(
            children: [
              TableRow(
                children: [
                  Text(t.desktopBenchFill),
                  Text(t.desktopBenchPp),
                  Text(t.desktopBenchTg),
                ],
              ),
              for (final sample in result.samples)
                TableRow(
                  children: [
                    Text('${sample.promptTokens}'),
                    Text(
                      t.desktopBenchRate(sample.prefillTps.toStringAsFixed(0)),
                    ),
                    Text(
                      t.desktopBenchRate(sample.decodeTps.toStringAsFixed(0)),
                    ),
                  ],
                ),
            ],
          ),
        ],
        BenchmarkReceiptSection(modelId: widget.model.id),
      ],
    );
  }
}
