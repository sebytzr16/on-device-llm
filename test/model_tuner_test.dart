import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/benchmark_receipt.dart';
import 'package:ondevice_llm/desktop/pc_optimization.dart';
import 'package:ondevice_llm/desktop/model_tuner.dart';
import 'package:ondevice_llm/desktop/tune_benchmark_run.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Runner implements TuneRunner {
  final TuneMeasurement Function(int, TuneSettings) sample;
  final bool fitsMemory;
  int calls = 0;
  bool cancelled = false;
  final seen = <TuneSettings>[];
  void Function()? onMeasure;
  _Runner(this.sample, {this.fitsMemory = true});
  @override
  Future<bool> fits(TuneSettings settings) async => fitsMemory;
  @override
  Future<TuneMeasurement> measure(TuneSettings settings) async {
    seen.add(settings);
    onMeasure?.call();
    return sample(calls++, settings);
  }

  @override
  void cancel() => cancelled = true;
}

Future<TuneReport> _run(_Runner runner) => ModelTuner(runner).run(
  initial: {'batchSize': 256},
  candidates: {
    'batchSize': [512],
  },
);

void main() {
  test(
    'estimateFits uses the native admission budget including total RAM reserve',
    () {
      const settings = InferenceSettings();
      expect(
        TuneBenchmarkRun.estimateFits({
          'ramNeedMb': 15000,
          'ramAvailableMb': 18000,
          'ramBudgetMb': 14000,
        }, settings),
        isFalse,
      );
      expect(
        TuneBenchmarkRun.estimateFits({
          'ramNeedMb': 4000,
          'ramAvailableMb': 18000,
          'ramBudgetMb': 14000,
          'ramPagedMb': 20000,
        }, settings),
        isTrue,
      );
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('optimization measures threads and batch without changing MTP Auto', () {
    final candidates = modelTuneCandidates(const InferenceSettings());
    expect(candidates.keys, unorderedEquals(['batchSize', 'cpuThreads']));
    expect(candidates['batchSize'], [512, 1024]);
    expect(candidates, isNot(contains('draftModelId')));
    expect(candidates, isNot(contains('flashAttention')));
  });
  test('A/A drift aborts before candidates', () async {
    final runner = _Runner(
      (i, _) => TuneMeasurement(i.isEven ? 100 : 110, 'same'),
    );
    final report = await _run(runner);
    expect(report.status, TuneStatus.drift);
    expect(runner.calls, 6);
    expect(report.changes, isEmpty);
  });
  test('gain within measured noise is rejected', () async {
    final runner = _Runner(
      (i, s) => TuneMeasurement(
        [95, 95, 100, 100, 105, 105][i % 6] + (s['batchSize'] == 512 ? 3 : 0),
        'same',
      ),
    );
    final report = await _run(runner);
    expect(report.status, TuneStatus.complete);
    expect(report.steps.single.decision, TuneDecision.noise);
    expect(report.changes, isEmpty);
  });
  test('batch knobs are judged on prompt reading speed', () async {
    // Faster prompt reading, same writing speed: accepted.
    final faster = await _run(
      _Runner(
        (_, s) => TuneMeasurement(
          100,
          'same',
          prefillTokensPerSecond: s['batchSize'] == 512 ? 3000 : 2000,
        ),
      ),
    );
    expect(faster.steps.single.decision, TuneDecision.accepted);
    expect(faster.changes, {'batchSize': 512});
    // Faster writing only: a batch size does not earn it.
    final writing = await _run(
      _Runner(
        (_, s) => TuneMeasurement(
          s['batchSize'] == 512 ? 150 : 100,
          'same',
          prefillTokensPerSecond: 2000,
        ),
      ),
    );
    expect(writing.steps.single.decision, TuneDecision.noise);
    // Other knobs keep the writing speed.
    final threads =
        await ModelTuner(
          _Runner(
            (_, s) => TuneMeasurement(
              s['cpuThreads'] == 4 ? 150 : 100,
              'same',
              prefillTokensPerSecond: 2000,
            ),
          ),
        ).run(
          initial: {'cpuThreads': 2},
          candidates: {
            'cpuThreads': [4],
          },
        );
    expect(threads.changes, {'cpuThreads': 4});
  });
  test('prompt reading drift between A/A slots refuses batch knobs', () async {
    // Same settings, B slots read 50% faster: a batch change would ride it.
    final runner = _Runner(
      (i, _) => TuneMeasurement(
        100,
        'same',
        prefillTokensPerSecond: i.isEven ? 2000 : 3000,
      ),
    );
    final report = await ModelTuner(runner).run(
      initial: {'batchSize': 256, 'cpuThreads': 2},
      candidates: {
        'batchSize': [512],
        'cpuThreads': [4],
      },
    );
    expect(report.status, TuneStatus.complete);
    expect(report.steps.first.knob, 'batchSize');
    expect(report.steps.first.decision, TuneDecision.noise);
    expect(report.changes, isEmpty);
    // The batch knob was not measured; the thread knob was.
    expect(runner.calls, 12);
  });
  test('faster greedy output change is refused', () async {
    final report = await _run(
      _Runner(
        (_, s) => TuneMeasurement(
          s['batchSize'] == 512 ? 150 : 100,
          s['batchSize'] == 512 ? 'different' : 'same',
        ),
      ),
    );
    expect(report.steps.single.decision, TuneDecision.changesOutput);
    expect(report.changes, isEmpty);
  });
  test('within-run spread contributes to the rejection threshold', () async {
    final report = await _run(
      _Runner(
        (_, s) => TuneMeasurement(
          s['batchSize'] == 512 ? 105 : 100,
          'same',
          relativeNoise: 0.1,
        ),
      ),
    );
    expect(report.steps.single.decision, TuneDecision.noise);
    expect(report.steps.single.noise, 0.1);
  });
  test('cancelling a later candidate leaves the report incomplete', () async {
    final runner = _Runner(
      (_, s) => TuneMeasurement(s['batchSize'] == 512 ? 150 : 100, 'same'),
    );
    final tuner = ModelTuner(runner);
    runner.onMeasure = () {
      if (runner.calls == 12) tuner.cancel();
    };
    final report = await tuner.run(
      initial: {'batchSize': 256, 'cpuThreads': 2},
      candidates: {
        'batchSize': [512],
        'cpuThreads': [4],
      },
    );
    expect(report.status, TuneStatus.cancelled);
    expect(report.changes, {'batchSize': 512});
  });
  test('memory skip does not measure candidate', () async {
    final runner = _Runner(
      (_, _) => const TuneMeasurement(100, 'same'),
      fitsMemory: false,
    );
    final report = await _run(runner);
    expect(report.steps.single.decision, TuneDecision.memory);
    expect(runner.calls, 6);
  });
  test('cancel stops measurement rounds', () async {
    final runner = _Runner(
      (_, s) => TuneMeasurement(s['batchSize'] == 512 ? 150 : 100, 'same'),
    );
    final tuner = ModelTuner(runner);
    runner.onMeasure = () {
      if (runner.calls == 7) tuner.cancel();
    };
    final report = await tuner.run(
      initial: {'batchSize': 256},
      candidates: {
        'batchSize': [512],
      },
    );
    expect(report.status, TuneStatus.cancelled);
    expect(runner.cancelled, true);
    expect(runner.calls, 8);
  });
  test('stable wins interleave before being accepted', () async {
    final runner = _Runner(
      (_, s) => TuneMeasurement(s['batchSize'] == 512 ? 150 : 100, 'same'),
    );
    final report = await _run(runner);
    expect(runner.seen.skip(6).map((s) => s['batchSize']), [
      256,
      512,
      256,
      512,
      256,
      512,
    ]);
    expect(report.steps.single.decision, TuneDecision.accepted);
    expect(report.changes, {'batchSize': 512});
  });
  test('unsupported knob cannot become a fabricated win', () async {
    final report =
        await ModelTuner(
          _Runner((_, _) => const TuneMeasurement(100, 'same')),
        ).run(
          initial: {},
          candidates: {
            'draftMinP': [0.5],
          },
          unsupported: {'draftMinP'},
        );
    expect(report.steps.single.decision, TuneDecision.unsupported);
    expect(report.changes, isEmpty);
  });
  test(
    'memory admission respects RAM and VRAM reserve and unknown estimates',
    () {
      const s = InferenceSettings();
      final estimate = {
        'ramNeedMb': 1000,
        'ramAvailableMb': 8000,
        'gpuLayers': 20,
        'vramNeedMb': 2000,
        'vramFreeMb': 3000,
      };
      expect(TuneBenchmarkRun.estimateFits(estimate, s), true);
      expect(
        TuneBenchmarkRun.estimateFits({...estimate, 'vramFreeMb': 2100}, s),
        false,
      );
      expect(
        TuneBenchmarkRun.estimateFits({...estimate, 'ramNeedMb': 7500}, s),
        false,
      );
      expect(TuneBenchmarkRun.estimateFits({}, s), false);
    },
  );
  test(
    'every receipt survives reload and statistics retain output hashes',
    () async {
      final stats = BenchmarkReceipt.statistics([
        for (final rate in [90, 110, 100])
          {
            'tokensPerSecond': rate,
            'firstTokenMs': 50,
            'promptTokensPerSecond': 200,
            'draftAcceptance': 0.75,
            'outputHash': benchmarkOutputHash('answer'),
          },
      ]);
      expect(stats['medianTokensPerSecond'], 100);
      expect(stats['spreadTokensPerSecond'], 20);
      expect(stats['medianDraftAcceptance'], 0.75);
      final c = ProviderContainer();
      final receipts = c.read(benchmarkReceiptsProvider.notifier);
      for (var i = 0; i < 2; i++) {
        await receipts.save(
          BenchmarkReceipt({
            'modelId': 'same',
            'timestamp': '$i',
            'promptClasses': stats,
          }),
        );
      }
      c.dispose();
      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      await restored.read(benchmarkReceiptsProvider.notifier).ready;
      expect(restored.read(benchmarkReceiptsProvider).length, 2);
      expect(
        restored.read(benchmarkReceiptsProvider).last.json['promptClasses'],
        stats,
      );
    },
  );
}
