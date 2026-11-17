import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/storage/model_file_leases.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

void _cooperative(List<Object?> args) => _fakeWorker(args, true);
void _stalled(List<Object?> args) => _fakeWorker(args, false);
void _fakeWorker(List<Object?> args, bool cooperate) {
  final events = args.first as SendPort;
  final commands = ReceivePort();
  events.send(commands.sendPort);
  int? request;
  String? first;
  Timer? pulse;
  commands.listen((dynamic value) {
    final m = value as Map;
    void send(String type, [Map<String, Object?> data = const {}]) =>
        events.send({'type': type, 'requestId': m['requestId'], ...data});
    switch (m['type']) {
      case 'load':
        if (m['path'] == 'memory-refused.gguf') {
          final config = jsonDecode(m['settings'] as String) as Map;
          send('error', {
            'message': config['backend'] == 'cpu'
                ? 'Unexpected CPU retry'
                : 'Not enough free memory for this model: 0 MB is free.',
          });
          break;
        }
        send('loaded', {'metrics': <String, Object?>{}});
      case 'generate':
        request = m['requestId'] as int;
        final config = jsonDecode(m['request'] as String) as Map;
        if ((config['settings'] as Map)['maxTokens'] == 1 &&
            (config['prefillSliceMs'] != 400 ||
                config['primePrefix'] is! String)) {
          send('error', {
            'message': 'Prime must request bounded prefill slices',
          });
          break;
        }
        if ((config['settings'] as Map)['maxTokens'] != 1 &&
            (config.containsKey('prefillSliceMs') ||
                config.containsKey('primePrefix'))) {
          send('error', {'message': 'Ordinary turns must keep normal batches'});
          break;
        }
        final messages = config['messages'] as List;
        first = (messages.first as Map)['content'] as String?;
        if ((messages.first as Map)['content'] == 'blocked') {
          sleep(const Duration(milliseconds: 300));
        }
        if ((messages.first as Map)['content'] == 'progress') {
          pulse = Timer.periodic(const Duration(milliseconds: 15), (_) {
            events.send({
              'type': 'prefill',
              'requestId': request,
              'read': 1,
              'total': 100,
            });
          });
        }
        if ((messages.first as Map)['content'] == 'advancing') {
          var read = 0;
          pulse = Timer.periodic(const Duration(milliseconds: 15), (_) {
            read++;
            events.send({
              'type': 'prefill',
              'requestId': request,
              'read': read,
              'total': 1000,
            });
          });
        }
        if ((messages.first as Map)['content'] == 'pulse') {
          pulse = Timer.periodic(const Duration(milliseconds: 15), (_) {
            events.send({
              'type': 'bytes',
              'requestId': request,
              'data': Uint8List.fromList(utf8.encode('x')),
            });
          });
        }
      case 'preview':
        final config = jsonDecode(m['request'] as String) as Map;
        final messages = (config['messages'] as List).cast<Map>();
        send('preview', {
          'result': {
            'formattedPrompt':
                '<s>${messages.first['content']}</s><u>${messages.last['content']}</u>',
          },
        });
      case 'cancel':
        if (cooperate) {
          pulse?.cancel();
          void done() => events.send({
            'type': 'done',
            'requestId': request,
            'metrics': <String, Object?>{},
          });
          // A prefill batch that finishes well after the Stop timeout.
          if (first == 'slow stop') {
            Timer(const Duration(milliseconds: 200), done);
          } else {
            done();
          }
        }
      case 'unload':
        send('unloaded');
      case 'dispose':
        pulse?.cancel();
        commands.close();
    }
  });
}

Stream<String> _generate(LlamaEngine e, [String text = 'stall']) => e.generate(
  messages: [
    {'role': 'user', 'content': text},
  ],
  fallbackTemplate: 'chatml',
  settings: const InferenceSettings(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<LlamaEngine> engine({
    bool cooperative = false,
    Duration tokenTimeout = const Duration(milliseconds: 80),
  }) async {
    final e = LlamaEngine(
      workerEntrypoint: cooperative ? _cooperative : _stalled,
      tokenTimeout: tokenTimeout,
      stopTimeout: const Duration(milliseconds: 40),
    );
    addTearDown(e.dispose);
    await e.loadModel(
      modelPath: 'fake.gguf',
      settings: const InferenceSettings(),
    );
    return e;
  }

  test(
    'unload cancels an active response and waits before releasing model',
    () async {
      final e = await engine(cooperative: true);
      final done = _generate(e).drain<void>();
      expect(e.isBusy, isTrue);
      await e.unload();
      await done;
      expect(e.isBusy, isFalse);
      expect(e.isLoaded, isFalse);
    },
  );

  test(
    'unresponsive cancellation is bounded and retires the loaded worker',
    () async {
      final e = await engine(tokenTimeout: const Duration(seconds: 10));
      final done = _generate(e).drain<void>();
      await e.unload().timeout(const Duration(seconds: 1));
      await done;
      expect(e.isBusy, isFalse);
      expect(e.isLoaded, isFalse);
    },
  );

  test(
    'no-token watchdog reports an error and clears busy without native events',
    () async {
      final e = await engine();
      final errors = <Object>[];
      final done = Completer<void>();
      _generate(e).listen((_) {}, onError: errors.add, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 1));
      expect(errors.single.toString(), contains('No token received'));
      expect(e.isBusy, isFalse);
      expect(e.isLoaded, isFalse);
    },
  );

  test('token arrivals reset watchdog and Stop still works', () async {
    final e = await engine(cooperative: true);
    final tokens = <String>[];
    final done = Completer<void>();
    _generate(e, 'pulse').listen(tokens.add, onDone: done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    expect(tokens.length, greaterThan(2));
    expect(e.isBusy, isTrue);
    e.cancel();
    await done.future.timeout(const Duration(seconds: 1));
    expect(e.isBusy, isFalse);
  });

  test(
    'retired FFI worker keeps leases and blocks reload until it exits',
    () async {
      final e = await engine(tokenTimeout: const Duration(milliseconds: 40));
      final done = Completer<void>();
      _generate(
        e,
        'blocked',
      ).listen((_) {}, onError: (Object _) {}, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 1));
      expect(e.isBusy, isFalse);
      expect(
        ModelFileLeases.instance.holders(['fake.gguf']),
        contains('llama.cpp'),
      );
      await expectLater(
        e.loadModel(
          modelPath: 'other.gguf',
          settings: const InferenceSettings(),
        ),
        throwsA(
          predicate<Object>((e) => e.toString().contains('still stopping')),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(ModelFileLeases.instance.holders(['fake.gguf']), isEmpty);
      await e.loadModel(
        modelPath: 'other.gguf',
        settings: const InferenceSettings(),
      );
      expect(e.isLoaded, isTrue);
    },
  );

  test(
    'Stop wins even when an uncooperative worker keeps emitting bytes',
    () async {
      final e = await engine();
      final done = Completer<void>();
      _generate(e, 'pulse').listen((_) {}, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(e.isBusy, isTrue);
      e.cancel();
      await done.future.timeout(const Duration(seconds: 1));
      expect(e.isBusy, isFalse);
    },
  );

  test(
    'prefill progress cannot keep a tokenless generation busy forever',
    () async {
      final e = await engine();
      final errors = <Object>[];
      final done = Completer<void>();
      _generate(
        e,
        'progress',
      ).listen((_) {}, onError: errors.add, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 1));
      expect(errors.single.toString(), contains('No token received'));
      expect(e.isBusy, isFalse);
    },
  );

  test(
    'advancing prefill keeps a slow prompt alive past the timeout',
    () async {
      final e = await engine();
      final errors = <Object>[];
      final sub = _generate(e, 'advancing').listen((_) {}, onError: errors.add);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(errors, isEmpty);
      expect(e.isBusy, isTrue);
      e.cancel();
      await sub.cancel();
    },
  );

  test(
    'a turn that stops slow priming keeps the model loaded and answers',
    () async {
      final e = await engine(
        cooperative: true,
        tokenTimeout: const Duration(seconds: 2),
      );
      final prime = e.primePrompt(
        system: 'slow stop',
        fallbackTemplate: 'chatml',
        settings: const InferenceSettings(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(e.isPriming, isTrue);
      final first = Completer<String>();
      final sub = _generate(e, 'pulse').listen((t) {
        if (!first.isCompleted) first.complete(t);
      });
      expect(await first.future.timeout(const Duration(seconds: 1)), 'x');
      await prime;
      expect(e.isLoaded, isTrue);
      e.cancel();
      await sub.cancel();
    },
  );

  test('RAM admission refuses embedding without a CPU retry', () async {
    DesktopHost.active = true;
    addTearDown(() => DesktopHost.active = false);
    final e = await engine(cooperative: true);
    await expectLater(
      e.loadEmbedder(
        modelPath: 'memory-refused.gguf',
        placement: const InferenceSettings(
          backend: GpuBackend.vulkan,
          nGpuLayers: 999,
        ),
      ),
      throwsA(
        isA<ModelLoadException>().having(
          (e) => e.message,
          'reason',
          contains('Not enough free memory'),
        ),
      ),
    );
  });

  test('missing explicit draft produces normal decoding config before FFI', () {
    for (final mode in ['draft', 'dflash']) {
      final config =
          jsonDecode(
                LlamaEngine.loadConfig(
                  settings: InferenceSettings(speculationMode: mode),
                ),
              )
              as Map;
      expect(config['speculationMode'], 'off');
      expect(config['draftModel'], '');
      expect(config['speculationFallback'], contains('missing'));
    }
  });
}
