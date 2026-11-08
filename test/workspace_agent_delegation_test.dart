import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/hosting/workspace_jobs.dart';
import 'package:ondevice_llm/features/hosting/workspace_workflow.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';
import 'device_model_server_test.dart' show FakeEngine;

class _Coordinator extends FakeEngine {
  final int planned;
  final limits = <int>[];
  final prompts = <List<Map<String, Object>>>[];
  _Coordinator(this.planned);
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    limits.add(settings.maxTokens);
    prompts.add(messages);
    if (limits.length > 1) {
      yield 'Combined result from all four real agents.';
    } else if (planned == 0) {
      yield 'I fired all four agents. Here is the entire website: <html>...</html>';
    } else {
      for (var i = 0; i < planned; i++) {
        yield '<tool_call>{"name":"ask_helper","arguments":{"task":"Part $i"}}</tool_call>';
      }
    }
  }
}

void main() {
  for (final planned in [0, 1, 4]) {
    test(
      'server starts exactly four real jobs when coordinator emits $planned calls',
      () async {
        final engine = _Coordinator(planned);
        const settings = InferenceSettings(
          toolsEnabled: true,
          toolHelper: true,
          toolWeb: false,
          agentMaxConcurrent: 4,
          maxTokens: 4096,
        );
        final tasks = <String>[];
        final allStarted = Completer<void>();
        final tools = ToolRunner(
          scraper: DuckDuckGoScraper(),
          reader: WebPageReader(),
          settings: settings,
          helperMaxConcurrent: 4,
          helper: (task, input) async {
            tasks.add(task);
            if (tasks.length == 4) allStarted.complete();
            await allStarted.future;
            return 'Completed: $task';
          },
        );
        final job = WorkspaceJob('job', 'request', 'fingerprint');
        await WorkspaceWorkflow(
              engine: engine,
              tools: tools,
              settings: settings,
            )
            .run(job, [
              {
                'role': 'user',
                'content':
                    'Write a pizzeria website. use four specialized  agents to compose it. Print all HTML.',
              },
            ])
            .timeout(const Duration(seconds: 5));
        final events = await job.events().toList();
        expect(tasks, hasLength(4));
        expect(tasks.toSet(), hasLength(4));
        expect(
          events.where((event) => event['type'] == 'tool_finished'),
          hasLength(4),
        );
        expect(
          events
              .where((event) => event['type'] == 'activity_text')
              .map((event) => event['data']['text'])
              .join(),
          isNot(contains('I fired')),
        );
        expect(engine.limits, [512, 4096]);
        expect('${engine.prompts.last}', isNot(contains('I fired')));
        expect(
          '${engine.prompts.last.first['content']}',
          contains('Write ONE direct answer'),
        );
        expect(
          '${engine.prompts.last.first['content']}',
          contains('Never paste a helper reply verbatim'),
        );
        expect(
          '${engine.prompts.last.first['content']}',
          contains('unless the user asked for code'),
        );
        for (final task in tasks) {
          expect('${engine.prompts.last}', contains('Completed: $task'));
        }
        expect(
          events
              .where((event) => event['type'] == 'answer')
              .single['data']['text'],
          'Combined result from all four real agents.',
        );
      },
    );
  }

  test('explicit requests do not bypass disabled tools', () async {
    final engine = _Coordinator(0);
    const settings = InferenceSettings(toolsEnabled: false);
    final tools = ToolRunner(
      scraper: DuckDuckGoScraper(),
      reader: WebPageReader(),
      settings: settings,
      helper: (_, _) async => fail('Tools are disabled'),
    );
    final job = WorkspaceJob('job', 'request', 'fingerprint');
    await WorkspaceWorkflow(
      engine: engine,
      tools: tools,
      settings: settings,
    ).run(job, [
      {'role': 'user', 'content': 'Use four agents'},
    ]);
    expect(tools.trace, isEmpty);
    expect(engine.limits, [settings.maxTokens]);
  });
}
