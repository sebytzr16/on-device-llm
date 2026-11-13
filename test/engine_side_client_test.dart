import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

/// Stands in for one native helper batch client: native fixes the context and
/// the sequence count when it opens, which is what the reopen must follow.
class _Batch implements HelperBatch {
  _Batch(this.config);

  @override
  final SideConfig config;
  int closes = 0;
  int active = 0;
  Completer<void>? gate;
  Completer<void>? _idle;

  @override
  int get count => active;

  @override
  Future<void> get drained {
    if (active == 0) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  @override
  Stream<String> generate(
    String id,
    String request,
    void Function()? onStarted,
  ) async* {
    active++;
    try {
      onStarted?.call();
      await gate?.future;
      yield 'answer for $id';
    } finally {
      active--;
      final idle = _idle;
      if (active == 0 && idle != null && !idle.isCompleted) {
        _idle = null;
        idle.complete();
      }
    }
  }

  @override
  void cancel(String id) {}

  @override
  Future<void> close() async => closes++;
}

InferenceSettings _agent(int contextSize, {int sequences = 2}) =>
    InferenceSettings(
      agentContextSize: contextSize,
      agentMaxConcurrent: sequences,
    ).forAgent();

void main() {
  late LlamaEngine engine;
  late List<_Batch> batches;

  setUp(() {
    engine = LlamaEngine();
    batches = [];
    engine.sideOpener = (config) async {
      final batch = _Batch(config);
      batches.add(batch);
      return batch;
    };
  });

  tearDown(() => engine.dispose());

  test('an unchanged agent configuration reuses the helper client', () async {
    await engine.openSide(sequences: 2, contextSize: 4096);
    await engine.openSide(sequences: 2, contextSize: 4096);

    expect(batches, hasLength(1));
    expect(batches.single.closes, 0);
  });

  test('a changed context reopens the helper client', () async {
    await engine.openSide(sequences: 2, contextSize: 4096);
    // The agent context goes from 4K to 16K between helper rounds.
    await engine.openSide(sequences: 2, contextSize: 16384);

    expect(batches.map((b) => b.config.contextSize), [4096, 16384]);
    expect(batches.first.closes, 1);
    expect(batches.last.closes, 0);
  });

  test('a changed sequence count reopens the helper client', () async {
    await engine.openSide(sequences: 2, contextSize: 4096);
    await engine.openSide(sequences: 4, contextSize: 4096);

    expect(batches.map((b) => b.config.sequences), [2, 4]);
    expect(batches.first.closes, 1);
  });

  test('a reopen waits for the running helper', () async {
    await engine.openSide(sequences: 2, contextSize: 4096);
    batches.single.gate = Completer<void>();
    final stream = engine.generateSide(
      jobId: 'job-1',
      messages: [
        {'role': 'user', 'content': 'write the notes'},
      ],
      fallbackTemplate: '',
      settings: _agent(4096),
    );
    final running = stream.toList();
    await Future<void>.delayed(Duration.zero);

    final reopen = engine.openSide(sequences: 2, contextSize: 16384);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      batches,
      hasLength(1),
      reason: 'the running helper keeps its client',
    );
    expect(batches.single.closes, 0);

    batches.single.gate!.complete();
    await reopen;
    expect(await running, ['answer for job-1']);
    expect(batches, hasLength(2));
    expect(batches.first.closes, 1);
  });

  test('helper rounds follow the agent context', () async {
    Future<List<String>> round(int context, String jobId) {
      final stream = engine.generateSide(
        jobId: jobId,
        messages: [
          {'role': 'user', 'content': jobId},
        ],
        fallbackTemplate: '',
        settings: _agent(context),
      );
      return stream.toList();
    }

    final first = await round(4096, 'job-4k');
    final second = await round(16384, 'job-16k');

    expect(first, ['answer for job-4k']);
    expect(second, ['answer for job-16k']);
    expect(batches.map((b) => b.config.contextSize), [4096, 16384]);
    expect(batches.first.closes, 1);
  });

  test('closeSide forgets the configuration', () async {
    await engine.openSide(sequences: 2, contextSize: 4096);
    await engine.closeSide();
    expect(batches.single.closes, 1);

    await engine.openSide(sequences: 2, contextSize: 4096);
    expect(batches, hasLength(2));
  });
}
