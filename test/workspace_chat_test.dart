import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/helper/helper_jobs.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

import 'chat_test.dart' show TestModels, TestSettings, TestEngine;
import 'device_model_server_test.dart' show FakeEngine;

class _NoLocalModels extends TestModels {
  @override
  ModelManagerState build() =>
      super.build().copyWith(catalog: [], clearLoaded: true);
}

class _PhoneSettings extends TestSettings {
  final int port;
  _PhoneSettings(this.port);
  @override
  InferenceSettings build() => super.build().copyWith(
    remoteEnabled: true,
    remoteProfiles: [
      RemoteProfile(
        id: 'pc',
        name: 'PC',
        providerId: 'custom',
        baseUrl: 'http://127.0.0.1:$port/v1/',
        model: 'server-model',
      ),
    ],
    remoteProfileId: 'pc',
    remoteApiKeys: const {'pc': '0123456789abcdef0123456789abcdef'},
    remoteDocuments: true,
    toolsEnabled: true,
    toolHelper: true,
    helperModelId: '@chat',
    webMode: WebMode.always,
  );
}

class _ForbiddenSearch extends DuckDuckGoScraper {
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async {
    fail('Phone must not perform web searches for server workspace turns.');
  }
}

void main() {
  test(
    'phone without local models uploads raw file and displays host agents',
    () async {
      SharedPreferences.setMockInitialValues({});
      late WorkspaceApi api;
      var serverRuns = 0;
      api = WorkspaceApi(
        capabilities: const ['server_execution'],
        run: (job, input) async {
          serverRuns++;
          expect(input['model'], 'server-model');
          final uploadId =
              (input['uploads'] as List).single['uploadId'] as String;
          expect(await api.uploads[uploadId]!.file.readAsString(), 'value\n42');
          job.emit('agent', {
            'id': 'server-agent',
            'task': 'Read the data',
            'modelName': 'Server model',
            'phase': 'generating',
            'output': 'Reading',
            'elapsedMs': 1,
          });
          job.emit('agent', {
            'id': 'server-agent',
            'task': 'Read the data',
            'modelName': 'Server model',
            'phase': 'done',
            'output': 'The value is 42.',
            'elapsedMs': 20,
          });
          job.emit('answer', {'text': 'The value is 42.'});
          job.emit('metrics', {
            'tokens': 6,
            'promptTokens': 30,
            'execution': 'server',
          });
        },
      );
      final server = DeviceModelServer(
        engine: FakeEngine(),
        settings: () => const InferenceSettings(),
        modelId: 'server-model',
        fallbackTemplate: '',
        accessToken: '0123456789abcdef0123456789abcdef',
        workspace: api,
      );
      await server.start();
      addTearDown(server.stop);
      final directory = await Directory.systemTemp.createTemp(
        'phone-workspace-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/data.csv');
      await file.writeAsString('value\n42');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final localEngine = TestEngine();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(localEngine),
          settingsProvider.overrideWith(() => _PhoneSettings(server.port!)),
          modelManagerProvider.overrideWith(_NoLocalModels.new),
          duckDuckGoScraperProvider.overrideWithValue(_ForbiddenSearch()),
        ],
      );
      addTearDown(() async {
        container.dispose();
        localEngine.dispose();
        await db.close();
      });
      expect(
        await container
            .read(chatProvider.notifier)
            .send(
              'Use an agent to analyze this file',
              attachments: [
                Attachment(
                  id: 'file',
                  kind: AttachmentKind.document,
                  name: 'data.csv',
                  mime: 'text/csv',
                  path: file.path,
                  sizeBytes: 8,
                ),
              ],
            ),
        isTrue,
      );
      final state = container.read(chatProvider);
      expect(state.error, isNull);
      expect(state.messages.last.content, 'The value is 42.');
      expect(serverRuns, 1);
      expect(localEngine.receivedMessages, isNull);
      final agents = container.read(helperJobsProvider).jobs;
      expect(agents.single.phase, HelperPhase.done);
      expect(agents.single.output, 'The value is 42.');
      expect(agents.single.modelName, contains('server'));
    },
  );
}
