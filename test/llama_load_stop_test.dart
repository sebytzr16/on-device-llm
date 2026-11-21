import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/data/storage/model_file_leases.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

/// A load that takes its time and only finishes when the Stop reaches it.
/// `late.gguf` finishes *successfully* after the cancel, like a Stop that
/// arrived too late: the engine must free what the load built instead of
/// keeping it loaded behind an idle UI.
void _slowLoad(List<Object?> args) => _fakeWorker(args, answerCancel: false);

/// A worker that ignores the load and the cancel: the engine must retire it
/// rather than stay busy forever.
void _deafLoad(List<Object?> args) => _fakeWorker(args, answerCancel: null);

/// A worker that finishes the load after the Stop but never answers the
/// unload and does not leave: the engine cannot free the runtime and must
/// report that instead of a silent Stop (E3).
void _stuckUnload(List<Object?> args) => _fakeWorker(
  args,
  answerCancel: false,
  answerUnload: false,
  exitDelay: const Duration(seconds: 2),
);

void _fakeWorker(
  List<Object?> args, {
  required bool? answerCancel,
  bool answerUnload = true,
  Duration? exitDelay,
}) {
  final events = args.first as SendPort;
  final commands = ReceivePort();
  events.send(commands.sendPort);
  String? path;
  // The load the late answer belongs to: a worker answers the command it is
  // running, and the engine matches that answer to the load it stopped.
  int? loadId;
  var loading = false;
  var closing = false;
  commands.listen((dynamic value) {
    final m = value as Map;
    void send(String type, [Map<String, Object?> data = const {}]) =>
        events.send({'type': type, 'requestId': m['requestId'], ...data});
    void settle(String type, [Map<String, Object?> data = const {}]) =>
        events.send({'type': type, 'requestId': loadId, ...data});
    switch (m['type']) {
      case 'load':
        path = m['path'] as String;
        loadId = m['requestId'] as int?;
        // A deaf worker never answers a load at all: the engine has to give
        // up on it instead of waiting for the whole Stop timeout forever.
        if (answerCancel == null) break;
        if (path == 'late.gguf' || path == 'cancelled.gguf') {
          loading = true;
        } else {
          send('loaded', {'metrics': <String, Object?>{}});
        }
      case 'cancel':
        if (answerCancel == null || !loading) break;
        // The cancel races the load, which is already reading weights.
        Timer(const Duration(milliseconds: 40), () {
          if (!loading) return;
          loading = false;
          if (path == 'late.gguf') {
            settle('loaded', {'metrics': <String, Object?>{}});
          } else {
            settle('error', {'message': 'Loading cancelled.', 'load': true});
          }
        });
      case 'unload':
        if (!answerUnload) break;
        send('unloaded');
      case 'dispose':
        if (closing) break;
        closing = true;
        final delay = exitDelay;
        if (delay == null) {
          commands.close();
        } else {
          Timer(delay, commands.close);
        }
    }
  });
}

/// A helper client whose native close never comes back: unloading the model
/// must not wait for it (audit 07 row 3).
class _StuckBatch implements HelperBatch {
  _StuckBatch(this.config);

  @override
  final SideConfig config;
  final cancelled = <String>[];

  @override
  int get count => 0;

  @override
  Future<void> get drained => Future.value();

  @override
  Stream<String> generate(
    String id,
    String request,
    void Function()? onStarted,
  ) => const Stream.empty();

  @override
  void cancel(String id) => cancelled.add(id);

  @override
  Future<void> close() => Completer<void>().future;
}

/// Waits for the engine to be inside a native call, so the test never races
/// the isolate spawn.
Future<void> _busy(LlamaEngine engine) async {
  final clock = Stopwatch()..start();
  while (!engine.isBusy) {
    if (clock.elapsed > const Duration(seconds: 5)) {
      fail('The engine never started its native call.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a load that finishes after Stop is freed and the engine idles',
    () async {
      final engine = LlamaEngine(
        workerEntrypoint: _slowLoad,
        stopTimeout: const Duration(seconds: 1),
      );
      addTearDown(engine.dispose);
      final loading = engine.loadModel(
        modelPath: 'late.gguf',
        settings: const InferenceSettings(),
      );
      // The Stop is reported as a Stop, not as a load error.
      final failed = expectLater(loading, throwsA(isA<ModelLoadStopped>()));
      await _busy(engine);
      engine.cancel();
      await failed;
      expect(engine.isLoaded, isFalse);
      expect(engine.isBusy, isFalse);
      // Nothing stays mapped or locked behind the user's back.
      expect(ModelFileLeases.instance.holders(['late.gguf']), isEmpty);
    },
  );

  test('a load that ignores Stop is retired instead of staying busy', () async {
    final engine = LlamaEngine(
      workerEntrypoint: _deafLoad,
      stopTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(engine.dispose);
    final loading = engine.loadModel(
      modelPath: 'deaf.gguf',
      settings: const InferenceSettings(),
    );
    final failed = expectLater(
      loading,
      throwsA(
        isA<ModelLoadException>()
            .having((e) => e is ModelLoadStopped, 'not a Stop', isFalse)
            .having(
              (e) => e.message,
              'message',
              contains('stopped before the operation finished'),
            ),
      ),
    );
    await _busy(engine);
    // The engine gives up on the worker after its Stop timeout; the pending
    // load ends instead of leaving the engine busy for the whole process.
    await engine.stopAndWait();
    await failed;
    expect(engine.isBusy, isFalse);
    expect(engine.isLoaded, isFalse);
  });

  test('a Stop during a load retires a worker that never answers', () async {
    final engine = LlamaEngine(
      workerEntrypoint: _deafLoad,
      stopTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(engine.dispose);
    final loading = engine.loadModel(
      modelPath: 'deaf.gguf',
      settings: const InferenceSettings(),
    );
    final failed = expectLater(
      loading,
      throwsA(
        isA<ModelLoadException>().having(
          (e) => e is ModelLoadStopped,
          'not a Stop',
          isFalse,
        ),
      ),
    );
    await _busy(engine);
    // The manager's Stop only calls cancel(): a worker that ignores both the
    // load and the Stop must not leave the engine busy forever.
    engine.cancel();
    await failed.timeout(const Duration(seconds: 5));
    expect(engine.isBusy, isFalse);
    expect(engine.isLoaded, isFalse);
  });

  test('a stopped load whose runtime stays mapped is a load error', () async {
    final engine = LlamaEngine(
      workerEntrypoint: _stuckUnload,
      stopTimeout: const Duration(milliseconds: 300),
    );
    addTearDown(engine.dispose);
    final loading = engine.loadModel(
      modelPath: 'late.gguf',
      settings: const InferenceSettings(),
    );
    // The load finishes after the Stop, but the worker never answers the
    // unload and does not exit: the engine cannot free the runtime, so it
    // must report a load error instead of a Stop (E3).
    final failed = expectLater(
      loading,
      throwsA(
        isA<ModelLoadException>().having(
          (e) => e is ModelLoadStopped,
          'not a Stop',
          isFalse,
        ),
      ),
    );
    await _busy(engine);
    engine.cancel();
    await failed.timeout(const Duration(seconds: 10));
  });

  test('a cancelled load does not block the next load', () async {
    final engine = LlamaEngine(
      workerEntrypoint: _slowLoad,
      stopTimeout: const Duration(seconds: 1),
    );
    addTearDown(engine.dispose);
    final loading = engine.loadModel(
      modelPath: 'cancelled.gguf',
      settings: const InferenceSettings(),
    );
    final failed = expectLater(loading, throwsA(isA<ModelLoadStopped>()));
    await _busy(engine);
    engine.cancel();
    await failed;
    // The aborted load left nothing behind that the next one has to fight.
    await engine
        .loadModel(modelPath: 'other.gguf', settings: const InferenceSettings())
        .timeout(const Duration(seconds: 5));
    expect(engine.isLoaded, isTrue);
  });

  test('unload frees the model when the helper never closes', () async {
    final engine = LlamaEngine(
      workerEntrypoint: _slowLoad,
      stopTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(engine.dispose);
    engine.sideOpener = (config) async => _StuckBatch(config);
    await engine.loadModel(
      modelPath: 'stuck-side.gguf',
      settings: const InferenceSettings(),
    );
    await engine.openSide(sequences: 2, contextSize: 4096);
    // The helper never acknowledges its close: unload must still finish, free
    // the files and leave the engine ready for the next model.
    await engine.unload().timeout(const Duration(seconds: 5));
    expect(engine.isLoaded, isFalse);
    expect(ModelFileLeases.instance.holders(['stuck-side.gguf']), isEmpty);
    await engine
        .loadModel(modelPath: 'other.gguf', settings: const InferenceSettings())
        .timeout(const Duration(seconds: 5));
    expect(engine.isLoaded, isTrue);
  });
}
