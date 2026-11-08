part of 'llama_engine.dart';

// A second worker owns all side calls; main decode never waits for a helper
// step. Close is acknowledged before model reload/unload (owner, 2026-11-02).
class _SideClient {
  final ReceivePort events = ReceivePort();
  final Map<String, Map<String, dynamic>> metrics;
  final outputs = <String, StreamController<List<int>>>{};
  final starts = <String, void Function()>{};
  final ready = Completer<void>(), closed = Completer<void>();
  SendPort? commands;
  int get count => outputs.length;
  _SideClient(this.metrics);

  static Future<_SideClient> open(
    int address,
    String library,
    Map<String, Map<String, dynamic>> metrics,
    int sequences,
    int contextSize,
  ) async {
    final client = _SideClient(metrics);
    client.events.listen((dynamic event) {
      if (event is SendPort) {
        client.commands = event;
        client.ready.complete();
        return;
      }
      if (event == null || event is List) {
        client.fail('Helper worker exited');
        return;
      }
      final e = event as Map;
      if (e['type'] == 'closed') {
        client.fail('chat model changed');
        return;
      }
      if (e['type'] == 'error') {
        _log.warning('Agent batch worker error: ${e['error']}');
        client.fail(e['error'] as String);
        return;
      }
      final id = e['id'] as String;
      if (e['metrics'] case final Map values) {
        client.metrics[id] = Map<String, dynamic>.from(values);
      }
      if (e['type'] == 'started') client.starts.remove(id)?.call();
      if (e['bytes'] case final List bytes) {
        client.outputs[id]?.add(bytes.cast<int>());
      }
      if (e['done'] == true) {
        final output = client.outputs.remove(id);
        client.starts.remove(id);
        if (e['error'] != null) {
          if (e['error'] != 'cancelled') {
            _log.warning('Agent sequence $id failed: ${e['error']}');
          }
          output?.addError(StateError('${e['error']}'));
        }
        unawaited(output?.close());
      }
    });
    try {
      await Isolate.spawn(
        llamaSideWorker,
        [client.events.sendPort, address, library, sequences, contextSize],
        onError: client.events.sendPort,
        onExit: client.events.sendPort,
      );
      await client.ready.future;
      return client;
    } catch (_) {
      client.events.close();
      rethrow;
    }
  }

  void fail(String reason) {
    if (!ready.isCompleted) ready.completeError(StateError(reason));
    for (final output in outputs.values) {
      output.addError(StateError(reason));
      unawaited(output.close());
    }
    outputs.clear();
    starts.clear();
    if (!closed.isCompleted) closed.complete();
    events.close();
  }

  Stream<String> generate(
    String id,
    String request,
    void Function()? onStarted,
  ) {
    if (closed.isCompleted) throw StateError('chat model changed');
    final output = StreamController<List<int>>();
    outputs[id] = output;
    if (onStarted != null) starts[id] = onStarted;
    metrics[id] = {};
    commands!.send({'type': 'submit', 'id': id, 'request': request});
    return output.stream
        .transform(utf8.decoder)
        .transform(ThinkingTagNormalizer());
  }

  void cancel(String id) => commands?.send({'type': 'cancel', 'id': id});
  Future<void> close() async {
    if (closed.isCompleted) return;
    commands?.send({'type': 'close'});
    await closed.future;
  }
}

// Isolate entrypoint also exercised by the offline native integration test.
void llamaSideWorker(List<Object> args) {
  final events = args[0] as SendPort;
  final commands = ReceivePort();
  Pointer<Void> side = nullptr;
  final api = LlamaBindings(libraryPath: args[2] as String);
  final active = <int, String>{};
  final pending = <Map>[];
  bool stepping = false, closing = false;
  void send(Map<String, Object?> event) => events.send(event);
  void close() {
    if (side != nullptr) api.sideClose!(side);
    side = nullptr;
    send({'type': 'closed'});
    commands.close();
  }

  final count = (args.length > 3 ? args[3] as int : 4).clamp(1, 4);
  final context = (args.length > 4 ? args[4] as int : 4096).clamp(512, 65536);
  try {
    if (api.sideOpen == null) {
      throw StateError('Native bridge has no helper batches');
    }
    final options = jsonEncode({
      'n_seq': count,
      'n_ctx_per_seq': context,
      'adaptive': true,
      'kvCacheType': 'q8_0',
      'offload_kv': true,
    }).toNativeUtf8();
    final runtime = Pointer<Void>.fromAddress(args[1] as int);
    try {
      side = api.sideOpen!(runtime, options);
    } finally {
      calloc.free(options);
    }
    if (side == nullptr) throw StateError(api.error(runtime).toDartString());
    events.send(commands.sendPort);
  } catch (error) {
    send({'type': 'error', 'error': '$error'});
    close();
    return;
  }

  Future<void> pump() async {
    if (stepping) return;
    stepping = true;
    try {
      // Let submissions from one tool round join the first decode (owner, 2026-11-02).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      while (!closing && (pending.isNotEmpty || active.isNotEmpty)) {
        // Native admission defers growth until running KV drains; keep deferred
        // requests pending while work fitting the current allocation can join.
        var index = 0;
        while (index < pending.length && active.length < count) {
          final request = pending[index];
          final seq = List.generate(
            count,
            (i) => i,
          ).firstWhere((i) => !active.containsKey(i));
          final id = request['id'] as String;
          final json = (request['request'] as String).toNativeUtf8();
          try {
            final status = api.sideSubmit!(side, seq, json);
            if (status > 0) {
              index++;
              continue;
            }
            pending.removeAt(index);
            if (status < 0) {
              final error =
                  jsonDecode(api.sideStep!(side).toDartString()) as Map;
              send({'id': id, 'done': true, 'error': error['error']});
            } else {
              active[seq] = id;
              send({'type': 'started', 'id': id});
            }
          } finally {
            calloc.free(json);
          }
        }
        if (active.isNotEmpty) {
          final result = jsonDecode(api.sideStep!(side).toDartString()) as Map;
          if (result['error'] != null) throw StateError('${result['error']}');
          for (final event in result['events'] as List) {
            final e = event as Map;
            final seq = e['seq'] as int;
            send({
              'id': active[seq],
              'bytes': e['bytes'],
              'done': e['done'],
              'metrics': e['metrics'],
            });
            if (e['done'] == true) active.remove(seq);
          }
        }
        await Future<void>.delayed(Duration.zero);
      }
    } catch (error) {
      send({'type': 'error', 'error': '$error'});
      closing = true;
    } finally {
      stepping = false;
      if (closing) close();
    }
  }

  commands.listen((dynamic value) {
    final command = value as Map;
    if (command['type'] == 'close') {
      closing = true;
      if (!stepping) close();
    } else if (command['type'] == 'cancel') {
      final id = command['id'];
      pending.removeWhere((p) => p['id'] == id);
      final seq = active.entries.where((e) => e.value == id).firstOrNull?.key;
      if (seq != null) {
        api.sideCancel!(side, seq);
        active.remove(seq);
      }
      send({'id': id, 'done': true, 'error': 'cancelled'});
    } else {
      pending.add(command);
      unawaited(pump());
    }
  });
}
