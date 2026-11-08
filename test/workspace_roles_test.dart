import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/hosting/presentation/hosted_workspace.dart';
import 'package:ondevice_llm/features/hosting/workspace_jobs.dart';
import 'package:ondevice_llm/features/hosting/workspace_workflow.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

/// Records what the engine under test actually hands to its transport.
class _RecordingEngine implements TextEngine {
  final generateSettings = <InferenceSettings>[];
  final previewSettings = <InferenceSettings>[];
  List<Map<String, Object>> lastMessages = const [];
  @override
  Map<String, dynamic> get metrics => const {'tokens': 1, 'promptTokens': 1};
  @override
  void cancel() {}
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    previewSettings.add(settings);
    lastMessages = messages;
    return const {};
  }

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    generateSettings.add(settings);
    lastMessages = messages;
    yield 'Done.';
  }
}

WorkspaceWorkflow _workflow(
  _RecordingEngine engine,
  InferenceSettings settings,
) => WorkspaceWorkflow(
  engine: engine,
  settings: settings,
  tools: ToolRunner(
    scraper: DuckDuckGoScraper(),
    reader: WebPageReader(),
    settings: settings,
  ),
);

void main() {
  group('C04: single leading system message', () {
    test('phone system entry merges into the server system message', () async {
      const settings = InferenceSettings(toolsEnabled: false);
      final engine = _RecordingEngine();
      final job = WorkspaceJob('c04', 'req-c04', 'fp-c04');
      await _workflow(engine, settings).run(job, [
        {'role': 'system', 'content': 'Phone instructions: answer briefly.'},
        {'role': 'user', 'content': 'What is 2+2?'},
      ]);
      final roles = [for (final m in engine.lastMessages) m['role'] as String];
      expect(roles, [
        'system',
        'user',
      ], reason: 'Qwen-style chat templates reject a second system message.');
      final system = engine.lastMessages.first['content'] as String;
      expect(system, contains("running on the user's server"));
      expect(system, contains('Phone instructions: answer briefly.'));
    });

    test('a mid-history system entry is merged too', () async {
      const settings = InferenceSettings(toolsEnabled: false);
      final engine = _RecordingEngine();
      final job = WorkspaceJob('c04b', 'req-c04b', 'fp-c04b');
      await _workflow(engine, settings).run(job, [
        {'role': 'system', 'content': 'First phone note.'},
        {'role': 'user', 'content': 'Plan a trip.'},
        {'role': 'assistant', 'content': 'Sure.'},
        {'role': 'system', 'content': 'Second phone note.'},
        {'role': 'user', 'content': 'Go.'},
      ]);
      final roles = [for (final m in engine.lastMessages) m['role'] as String];
      expect(roles, ['system', 'user', 'assistant', 'user']);
      final system = engine.lastMessages.first['content'] as String;
      expect(system, contains('First phone note.'));
      expect(system, contains('Second phone note.'));
    });
  });

  group('C06: round settings reach the hosted engine', () {
    final connection = const InferenceSettings(
      maxTokens: 4096,
      temperature: 0.7,
      remoteEnabled: true,
      remoteProfiles: [
        RemoteProfile(
          id: 'host',
          name: 'This server',
          providerId: 'custom',
          baseUrl: 'http://127.0.0.1:8787/v1/',
          model: 'qwen',
        ),
      ],
      remoteProfileId: 'host',
      remoteApiKeys: {'host': 'session-token'},
    );

    test(
      'generate merges the round settings over the fixed connection',
      () async {
        final client = _RecordingEngine();
        final engine = HostedWorkspaceEngine(client, connection);
        final round = connection.copyWith(maxTokens: 512, temperature: 0.2);
        await engine
            .generate(
              messages: [
                {'role': 'user', 'content': 'hi'},
              ],
              fallbackTemplate: '',
              settings: round,
              toolChoice: 'none',
            )
            .toList();
        final sent = client.generateSettings.single;
        expect(
          sent.maxTokens,
          512,
          reason: 'The planning-round token limit must be transmitted.',
        );
        expect(sent.temperature, 0.2);
        expect(sent.remoteEnabled, isTrue);
        expect(sent.activeRemoteProfile?.id, 'host');
        expect(sent.remoteUri?.toString(), 'http://127.0.0.1:8787/v1/');
        expect(sent.remoteApiKey, 'session-token');
      },
    );

    test(
      'previewPrompt merges the round settings over the fixed connection',
      () async {
        final client = _RecordingEngine();
        final engine = HostedWorkspaceEngine(client, connection);
        final round = connection.copyWith(maxTokens: 512);
        await engine.previewPrompt(
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
          fallbackTemplate: '',
          settings: round,
        );
        final sent = client.previewSettings.single;
        expect(sent.maxTokens, 512);
        expect(sent.remoteEnabled, isTrue);
        expect(sent.activeRemoteProfile?.id, 'host');
        expect(sent.remoteApiKey, 'session-token');
      },
    );
  });
}
