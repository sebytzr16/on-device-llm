import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/utils/memory_admission.dart';
import 'package:ondevice_llm/desktop/model_tuner.dart';
import 'package:ondevice_llm/desktop/pc_optimization.dart';
import 'package:ondevice_llm/desktop/tune_benchmark_run.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/sd_engine.dart';

class _Samples extends Fake implements TuneBenchmarkRun {
  final TuneMeasurement Function(int, int) sample;
  final seen = <int>[];
  _Samples(this.sample);

  @override
  bool get cancelled => false;

  @override
  Future<bool> fits(TuneSettings settings) async => true;

  @override
  Future<TuneMeasurement> benchmark(
    TuneSettings settings, {
    int repetitions = 1,
    void Function(double)? progress,
    bool quick = false,
  }) async {
    expect(quick, isTrue);
    final batch = settings['batchSize'] as int;
    seen.add(batch);
    progress?.call(1);
    return sample(seen.length - 1, batch);
  }
}

void main() {
  test('end-to-end A/A drift aborts even when decode is stable', () async {
    final samples = _Samples(
      (round, _) =>
          TuneMeasurement(100, 'original', workloadRate: round.isEven ? 1 : 2),
    );
    final runner = OptimizeRunner(
      samples,
      [
        const InferenceSettings().copyWith(batchSize: 512),
        const InferenceSettings().copyWith(batchSize: 1024),
      ],
      'original',
      (_) {},
    );
    final report = await ModelTuner(runner, endToEnd: true).run(
      initial: {'setup': 0},
      candidates: {
        'setup': [1],
      },
    );
    expect(report.status, TuneStatus.drift);
    expect(report.changes, isEmpty);
    expect(samples.seen.length, 6);
  });

  test(
    'Optimize verifies prefill-led end-to-end wins with paired repeats',
    () async {
      final samples = _Samples(
        (_, batch) => TuneMeasurement(
          batch == 1024 ? 80 : 100,
          'original',
          workloadRate: batch == 1024 ? 2 : 1,
        ),
      );
      final fractions = <double>[];
      final runner = OptimizeRunner(
        samples,
        [
          const InferenceSettings().copyWith(batchSize: 512),
          const InferenceSettings().copyWith(batchSize: 1024),
        ],
        'original',
        fractions.add,
      );
      final report = await ModelTuner(runner, endToEnd: true).run(
        initial: {'setup': 0},
        candidates: {
          'setup': [1],
        },
      );
      expect(report.changes, {'setup': 1});
      expect(samples.seen, [
        512,
        512,
        512,
        512,
        512,
        512,
        512,
        1024,
        512,
        1024,
        512,
        1024,
      ]);
      expect(fractions, orderedEquals(List.generate(12, (i) => (i + 1) / 12)));
    },
  );

  for (final changesOutput in [false, true]) {
    test(
      'Optimize rejects ${changesOutput ? 'changed output' : 'a single noisy win'}',
      () async {
        final samples = _Samples(
          (round, batch) => TuneMeasurement(
            batch == 1024 ? 200 : 100,
            changesOutput && batch == 1024 ? 'different' : 'original',
            workloadRate: batch == 512
                ? 1
                : changesOutput || round == 7
                ? 2
                : 0.9,
          ),
        );
        final runner = OptimizeRunner(
          samples,
          [
            const InferenceSettings().copyWith(batchSize: 512),
            const InferenceSettings().copyWith(batchSize: 1024),
          ],
          'original',
          (_) {},
        );
        final report = await ModelTuner(runner, endToEnd: true).run(
          initial: {'setup': 0},
          candidates: {
            'setup': [1],
          },
        );
        expect(report.changes, isEmpty);
        expect(
          report.steps.single.decision,
          changesOutput ? TuneDecision.changesOutput : TuneDecision.noise,
        );
        expect(samples.seen.length, 12);
      },
    );
  }

  test(
    'winner selection scores full workload and retains original output gate',
    () {
      final a = const InferenceSettings().copyWith(batchSize: 512);
      final b = a.copyWith(batchSize: 1024);
      expect(
        pickOptimizeWinner(
          reference: 'original',
          runs: [
            (
              settings: a,
              measurement: const TuneMeasurement(
                100,
                'original',
                workloadRate: 1,
              ),
            ),
            (
              settings: b,
              measurement: const TuneMeasurement(
                80,
                'original',
                workloadRate: 2,
              ),
            ),
            (
              settings: a,
              measurement: const TuneMeasurement(
                300,
                'changed',
                workloadRate: 3,
              ),
            ),
          ],
        )?.settings,
        b,
      );
    },
  );

  test(
    'shared memory admission serializes allocation and recovers after failure',
    () async {
      final gate = MemoryAdmission();
      final held = Completer<void>();
      final events = <String>[];
      final first = gate.run(() async {
        events.add('chat');
        await held.future;
        throw StateError('load failed');
      });
      final failed = expectLater(first, throwsStateError);
      final second = gate.run(() async => events.add('create'));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['chat']);
      held.complete();
      await failed;
      await second;
      expect(events, ['chat', 'create']);
    },
  );

  test(
    'Create enters shared admission and cancellation prevents deferred load',
    () async {
      final held = Completer<void>();
      final entered = Completer<void>();
      final resident = MemoryAdmission.shared.run(() async {
        entered.complete();
        await held.future;
      });
      await entered.future;
      final calls = <String>[];
      final engine = SdEngine(
        invoke: (op, _) async {
          calls.add(op);
          return 1;
        },
      );
      final load = engine.load(key: 'image');
      final stopped = expectLater(load, throwsA(isA<SdOperationStopped>()));
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
      engine.cancel();
      held.complete();
      await resident;
      await stopped;
      expect(calls, isEmpty);
      await engine.dispose();
    },
  );

  test(
    'image and video models permit measured GPU placement and host override',
    () {
      for (final model in imageGenCatalog) {
        final paths = {for (final f in model.files) f.role: f.fileName};
        expect(model.loadSettings(paths).containsKey('offloadToCpu'), isFalse);
        expect(
          model.loadSettings(paths, offloadToCpu: true)['offloadToCpu'],
          isTrue,
        );
        expect(
          model.loadSettings(paths, offloadToCpu: false)['offloadToCpu'],
          isFalse,
        );
      }
    },
  );
}
