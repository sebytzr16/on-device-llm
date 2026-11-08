import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/server_usage.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

import 'device_model_server_test.dart' show FakeEngine;

class _Headers implements HttpHeaders {
  final Map<String, String> values;
  _Headers(this.values);
  @override
  List<String>? operator [](String name) =>
      values[name] == null ? null : [values[name]!];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection implements HttpConnectionInfo {
  @override
  final InternetAddress remoteAddress;
  _Connection(String address) : remoteAddress = InternetAddress(address);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpRequest {
  @override
  final HttpHeaders headers;
  @override
  final HttpConnectionInfo connectionInfo;
  _Request(String address, Map<String, String> headers)
    : headers = _Headers(headers),
      connectionInfo = _Connection(address);
  @override
  String get method => 'POST';
  @override
  Uri get uri => Uri.parse(DeviceModelServer.completionsPath);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'workspace completion tokens belong to its submitting socket peer',
    () async {
      const token = '0123456789abcdef0123456789abcdef';
      final completionServed = Completer<void>();
      final log = <ServedRequest>[];
      var usage = const ServerUsage();
      late DeviceModelServer server;
      late WorkspaceApi api;
      late Map<String, String> credentials;
      api = WorkspaceApi(
        capabilities: const ['server_execution'],
        run: (job, input) async {
          credentials = api.completionHeaders(job);
          // Even a valid credential cannot be used by a network peer. Another
          // API/server instance and a guessed credential cannot attribute either.
          expect(
            api.completionClient(_Request('10.0.0.222', credentials)),
            isNull,
          );
          expect(
            api.completionClient(_Request('::1', credentials)),
            '127.0.0.2',
          );
          expect(
            api.completionClient(
              _Request('127.0.0.1', {credentials.keys.single: 'forged'}),
            ),
            isNull,
          );
          final other = WorkspaceApi(
            capabilities: const [],
            run: (_, _) async {},
          );
          expect(
            other.completionClient(_Request('127.0.0.1', credentials)),
            isNull,
          );
          await other.dispose();
          final engine = RemoteEngine();
          try {
            await engine
                .generate(
                  messages: const [
                    {'role': 'user', 'content': 'phone'},
                  ],
                  fallbackTemplate: '',
                  settings: InferenceSettings(
                    remoteEnabled: true,
                    remoteProfiles: [
                      RemoteProfile(
                        id: 'host',
                        name: 'This server',
                        providerId: 'custom',
                        baseUrl: 'http://127.0.0.1:${server.port}/v1/',
                        model: 'test-model',
                        headers: api.completionHeaders(job),
                      ),
                    ],
                    remoteProfileId: 'host',
                    remoteApiKeys: const {'host': token},
                  ),
                )
                .drain<void>();
          } finally {
            engine.dispose();
          }
        },
      );
      server = DeviceModelServer(
        engine: FakeEngine()
          ..reportedMetrics = {'promptTokens': 10, 'tokens': 20},
        settings: () => const InferenceSettings(),
        modelId: 'test-model',
        fallbackTemplate: '',
        accessToken: token,
        workspace: api,
        onServed: (request) {
          log.add(request);
          usage = usage.record(request);
          if (request.completion && !completionServed.isCompleted) {
            completionServed.complete();
          }
        },
      );
      await server.start();
      addTearDown(server.stop);
      final phone = HttpClient()
        ..connectionFactory = (uri, proxyHost, proxyPort) =>
            Socket.startConnect(
              uri.host,
              uri.port,
              sourceAddress: InternetAddress('127.0.0.2'),
            );
      addTearDown(() => phone.close(force: true));
      final request = await phone.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/v1/workspace/jobs'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'requestId': 'phone-job'}));
      final response = await request.close();
      expect(response.statusCode, 202);
      final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      final job = api.jobs[body['jobId'] as String]!;
      await job.execution;
      await completionServed.future.timeout(const Duration(seconds: 5));
      expect(job.terminal, isTrue);
      final eventsRequest = await phone.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/workspace/jobs/${job.id}/events',
        ),
      );
      eventsRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $token',
      );
      final eventsResponse = await eventsRequest.close();
      expect(eventsResponse.statusCode, 200);
      final events = await utf8.decoder.bind(eventsResponse).join();
      expect(events, contains('"type":"done"'));
      expect(usage.clients.keys, ['127.0.0.2']);
      expect(usage.clients['127.0.0.2']!.tokens, 30);
      expect(usage.promptTokens, 10);
      expect(usage.completionTokens, 20);
      expect(usage.models['test-model']!.tokens, 30);
      final completion = log.singleWhere((r) => r.completion);
      expect(completion.client, '127.0.0.1');
      expect(completion.attributedClient, '127.0.0.2');
      // Finished jobs cannot retain attribution credentials.
      expect(api.completionClient(_Request('127.0.0.1', credentials)), isNull);
    },
  );
}
