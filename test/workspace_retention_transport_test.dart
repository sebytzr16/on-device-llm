import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/remote/workspace_client.dart';
import 'device_model_server_test.dart' show FakeEngine;

void main() {
  test(
    'compacted four-agent history replays through HTTP and keeps approvals',
    () async {
      SharedPreferences.setMockInitialValues({});
      const token = '0123456789abcdef0123456789abcdef';
      var approvals = 0;
      final api = WorkspaceApi(
        capabilities: const ['server_execution'],
        run: (job, input) async {
          expect((input['settings'] as Map)['agentTimeoutSeconds'], 900);
          for (var step = 0; step < 300; step++) {
            for (var agent = 0; agent < 4; agent++) {
              job.emit('agent', {
                'id': 'agent-$agent',
                'phase': 'generating',
                'output': '${'code ' * 2000}$step:$agent',
              });
            }
          }
          for (var agent = 0; agent < 4; agent++) {
            job.emit('agent', {
              'id': 'agent-$agent',
              'phase': 'done',
              'output': 'Final part $agent',
            });
          }
          final allowed = await job.approve('Allow the diagnostic action?');
          job.emit('answer', {
            'text': allowed ? 'Four parts combined' : 'Denied',
          });
        },
      );
      final server = DeviceModelServer(
        engine: FakeEngine(),
        settings: () => const InferenceSettings(),
        modelId: 'server-model',
        fallbackTemplate: '',
        accessToken: token,
        workspace: api,
      );
      await server.start();
      addTearDown(server.stop);
      final client = WorkspaceClient();
      addTearDown(client.dispose);
      final connection = InferenceSettings(
        remoteEnabled: true,
        remoteProfiles: [
          RemoteProfile(
            id: 'pc',
            name: 'PC',
            providerId: 'custom',
            baseUrl: 'http://127.0.0.1:${server.port}/v1/',
            model: 'server-model',
          ),
        ],
        remoteProfileId: 'pc',
        remoteApiKeys: const {'pc': token},
        agentTimeoutSeconds: 900,
      );
      final events = <Map<String, dynamic>>[];
      await client.run(
        settings: connection,
        requestId: 'long-four-agent-history',
        messages: [
          {'role': 'user', 'content': 'Use four agents'},
        ],
        event: events.add,
        approve: (_, _) async {
          approvals++;
          return true;
        },
      );
      expect(approvals, 1);
      expect(events.last['type'], 'done');
      expect(
        events
            .where((event) => event['type'] == 'answer')
            .single['data']['text'],
        'Four parts combined',
      );
      final completed = events
          .where(
            (event) =>
                event['type'] == 'agent' && event['data']['phase'] == 'done',
          )
          .map((event) => event['data']['id'])
          .toSet();
      expect(completed, hasLength(4));
      expect(events.any((event) => event['type'] == 'cancelled'), isFalse);
    },
  );
}
