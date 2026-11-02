import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/request_queue.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

import 'device_model_server_test.dart' show FakeEngine;

class _DisconnectEngine extends FakeEngine implements RawCompletionEngine {
  final started = Completer<void>(), cancelled = Completer<void>();
  @override
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }

  Stream<String> _answer() async* {
    started.complete();
    yield 'partial';
    await cancelled.future;
  }

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) => _answer();

  @override
  Stream<String> generateRaw({
    required String prompt,
    required InferenceSettings settings,
  }) => _answer();
}

void main() {
  for (final path in [
    '/v1/chat/completions',
    '/v1/completions',
    '/v1/responses',
    '/v1/messages',
  ]) {
    test('disconnect cancels a non-streaming generation: $path', () async {
      const token = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final engine = _DisconnectEngine();
      final finished = Completer<void>();
      final server = DeviceModelServer(
        engine: engine,
        settings: () => const InferenceSettings(),
        modelId: 'test',
        fallbackTemplate: '',
        accessToken: token,
        onServed: (_) {
          if (!finished.isCompleted) finished.complete();
        },
      );
      await server.start();
      addTearDown(server.stop);
      addTearDown(engine.cancel);
      final socket = await Socket.connect('127.0.0.1', server.port!);
      addTearDown(socket.destroy);
      final body = jsonEncode({
        'model': 'test',
        'max_tokens': 100,
        if (path == '/v1/responses')
          'input': 'hello'
        else if (path == '/v1/completions')
          'prompt': 'hello'
        else
          'messages': [
            {'role': 'user', 'content': 'hello'},
          ],
      });
      socket.write(
        'POST $path HTTP/1.1\r\nHost: localhost\r\n'
        'Authorization: Bearer $token\r\nContent-Type: application/json\r\n'
        'Content-Length: ${utf8.encode(body).length}\r\n\r\n$body',
      );
      await socket.flush();
      await engine.started.future.timeout(const Duration(seconds: 5));
      socket.destroy();
      await engine.cancelled.future.timeout(const Duration(seconds: 5));
      await finished.future.timeout(const Duration(seconds: 5));
      expect(server.busy, isFalse);
    });
  }
  test(
    'abandoned waiters free their slot without releasing the active owner',
    () async {
      final queue = RequestQueue();
      addTearDown(queue.close);
      await queue.acquire('model');
      final left = Completer<void>();
      final abandoned = queue.acquire('model', abandoned: left.future);
      final checked = expectLater(
        abandoned,
        throwsA(isA<RouteRefusal>().having((e) => e.status, 'status', 499)),
      );
      var granted = false;
      final next = queue.acquire('model').then((_) => granted = true);
      left.complete();
      await checked;
      expect(granted, isFalse);
      queue.release('model');
      await next;
      expect(granted, isTrue);
      queue.release('model');
    },
  );
  test('late abandonment does not cancel a granted queue entry', () async {
    final queue = RequestQueue();
    addTearDown(queue.close);
    await queue.acquire('model');
    final left = Completer<void>();
    final next = queue.acquire('model', abandoned: left.future);
    queue.release('model');
    await next;
    left.complete();
    await Future<void>.delayed(Duration.zero);
    queue.release('model');
    await queue.acquire('model');
  });
}
