import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_usage.dart';

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  RequestOptions? last;
  String? lastBody;
  _Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    lastBody = options.data is String ? options.data as String : null;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

RemoteEngine engineWith(Dio dio) => RemoteEngine(
  dio: dio,
  usage: RemoteUsageLog(prefs: () => null),
);
InferenceSettings hosted(String provider) => InferenceSettings(
  remoteEnabled: true,
  remoteProfiles: [
    RemoteProfile(
      id: 'audit',
      name: 'Audit',
      providerId: provider,
      baseUrl: 'https://offline.invalid',
      model: 'claude-sonnet-4-5',
    ),
  ],
  remoteProfileId: 'audit',
  remoteApiKeys: {'audit': 'test-key'},
  maxTokens: 4096,
  contextSize: 16384,
);

void main() {
  test(
    'Anthropic signed and redacted thinking replay unchanged before tool use',
    () async {
      final blocks = [
        {
          'type': 'thinking',
          'thinking': 'private thought',
          'signature': 'signed+/=',
        },
        {'type': 'redacted_thinking', 'data': 'opaque+/='},
      ];
      final frames = [
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'thinking',
            'thinking': '',
            'signature': '',
          },
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': 'private thought'},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'signed+/='},
        },
        {'type': 'content_block_start', 'index': 1, 'content_block': blocks[1]},
        {
          'type': 'content_block_start',
          'index': 2,
          'content_block': {
            'type': 'tool_use',
            'id': 'c1',
            'name': 'search',
            'input': {},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 2,
          'delta': {'type': 'input_json_delta', 'partial_json': '{}'},
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
        },
        {'type': 'message_stop'},
      ];
      var requests = 0;
      final adapter = _Adapter(
        (_) => ResponseBody.fromString(
          requests++ == 0
              ? frames.map((e) => 'data: ${jsonEncode(e)}\n\n').join()
              : 'data: {"type":"message_stop"}\n',
          200,
        ),
      );
      final engine = engineWith(Dio()..httpClientAdapter = adapter);
      addTearDown(engine.dispose);
      final history = <Map<String, Object>>[
        {'role': 'user', 'content': 'hi'},
      ];
      await engine
          .generate(
            messages: history,
            fallbackTemplate: '',
            settings: hosted('anthropic'),
          )
          .join();
      history.add({
        'role': 'assistant',
        'content': '',
        'tool_calls': engine.metrics['toolCalls'] as List,
      });
      history.add({'role': 'tool', 'tool_call_id': 'c1', 'content': 'found'});
      await engine
          .generate(
            messages: history,
            fallbackTemplate: '',
            settings: hosted('anthropic'),
          )
          .join();
      final body = jsonDecode(adapter.lastBody!) as Map;
      final replay = body['messages'][1]['content'] as List;
      expect(replay.take(2), blocks);
      expect(replay[2], {
        'type': 'tool_use',
        'id': 'c1',
        'name': 'search',
        'input': {},
      });
      expect(body['messages'][2], {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': 'c1', 'content': 'found'},
        ],
      });
      expect(requests, 2);
    },
  );
}
