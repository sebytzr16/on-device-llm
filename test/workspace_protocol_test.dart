import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/hosting/workspace_workflow.dart';
import 'package:ondevice_llm/features/hosting/workspace_jobs.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/remote/workspace_client.dart';

import 'device_model_server_test.dart' show FakeEngine;

class _Rounds extends FakeEngine {
  final List<String> replies;
  int calls = 0;
  _Rounds(this.replies);
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    lastMessages = messages;
    yield replies[calls++];
  }
}

class _DropOnce implements HttpClientAdapter {
  final inner = IOHttpClientAdapter();
  bool dropped = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await inner.fetch(options, requestStream, cancelFuture);
    if (options.uri.path.endsWith('/events') && !dropped) {
      dropped = true;
      Stream<Uint8List> interrupted() async* {
        await for (final bytes in response.stream) {
          yield bytes;
          throw const SocketException('Simulated Meshnet interruption');
        }
      }

      return ResponseBody(
        interrupted(),
        response.statusCode,
        headers: response.headers,
      );
    }
    return response;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

class _HostSearch extends DuckDuckGoScraper {
  int calls = 0;
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async {
    calls++;
    return [
      SearchResult(
        title: 'Server search result',
        url: 'https://example.org/result',
        snippet: 'The result was retrieved on the server.',
        rank: 0,
        fetchedAt: DateTime.utc(2026, 11, 3),
      ),
    ];
  }
}

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  late DeviceModelServer server;
  late WorkspaceClient client;
  late InferenceSettings connection;
  final events = <Map<String, dynamic>>[];

  Future<void> start(WorkspaceApi api) async {
    SharedPreferences.setMockInitialValues({});
    events.clear();
    server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'server-model',
      fallbackTemplate: '',
      accessToken: token,
      workspace: api,
    );
    await server.start();
    connection = InferenceSettings(
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
    );
    client = WorkspaceClient();
    addTearDown(() async {
      client.dispose();
      await server.stop();
    });
  }

  test('shared upload survives one accepted job finishing', () async {
    late WorkspaceApi api;
    final gates = [Completer<void>(), Completer<void>()];
    final started = [Completer<void>(), Completer<void>()];
    api = WorkspaceApi(
      capabilities: const ['server_execution'],
      run: (job, input) async {
        final index = int.parse(input['requestId'] as String);
        started[index].complete();
        await gates[index].future;
      },
    );
    await start(api);
    addTearDown(() {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    final dir = await Directory.systemTemp.createTemp('workspace-shared-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/data.csv').writeAsString('shared');
    final id = await client.upload(connection, file.path, 'data.csv');
    final uploaded = api.uploads[id]!.file;
    Future<void> run(int index) => client.run(
      settings: connection,
      requestId: '$index',
      messages: [
        {'role': 'user', 'content': 'read'},
      ],
      uploads: [
        {'uploadId': id, 'message': 0},
      ],
      event: (_) {},
      approve: (_, _) async => false,
    );
    final first = run(0);
    await started[0].future;
    final second = run(1);
    await started[1].future;
    gates[0].complete();
    await first;
    expect(await uploaded.exists(), isTrue);
    expect(await api.uploads[id]!.file.readAsString(), 'shared');
    gates[1].complete();
    await second;
    expect(api.uploads[id], isNull);
    expect(await uploaded.exists(), isFalse);
  });

  for (final format in ['fenced', 'gemma', 'malformed gemma']) {
    test(
      'server runs calculator with $format calls without client tools',
      () async {
        final engine = _Rounds([
          if (format == 'malformed gemma')
            '<|tool_call>call:calculator","expression":"15+27"}<tool_call|>',
          if (format == 'gemma')
            '<|tool_call>call:calculator{expression:<|"|>15+27<|"|>}<tool_call|>'
          else
            '```tool\n{"name":"calculator","arguments":{"expression":"15+27"}}\n```',
          '42',
        ]);
        const settings = InferenceSettings(
          toolsEnabled: true,
          toolCalculator: true,
          toolMaxRounds: 3,
        );
        await start(
          WorkspaceApi(
            capabilities: const ['server_execution'],
            run: (job, input) async {
              final runner = ToolRunner(
                scraper: DuckDuckGoScraper(),
                reader: WebPageReader(),
                settings: settings,
                cancel: job.cancel,
              );
              await WorkspaceWorkflow(
                engine: engine,
                tools: runner,
                settings: settings,
              ).run(
                job,
                (input['messages'] as List)
                    .map((m) => Map<String, Object>.from(m as Map))
                    .toList(),
              );
            },
          ),
        );
        expect(await client.supported(connection), isTrue);
        await client.run(
          settings: connection,
          requestId: 'calc',
          messages: [
            {'role': 'user', 'content': '15+27'},
          ],
          event: events.add,
          approve: (_, _) async => fail('No approval expected'),
        );
        expect(
          events
              .where((e) => e['type'] == 'tool_finished')
              .single['data']['output'],
          contains('42'),
        );
        expect(
          events.where((e) => e['type'] == 'answer').single['data']['text'],
          '42',
        );
        expect(engine.calls, format == 'malformed gemma' ? 3 : 2);
      },
    );
  }

  test(
    'repeated malformed Gemma calls fail explicitly without executing',
    () async {
      const malformed =
          '<|tool_call>call:search_news","topic":"nuclear war"}<tool_call|>';
      final engine = _Rounds([malformed, malformed]);
      const settings = InferenceSettings(
        toolsEnabled: true,
        toolCalculator: true,
      );
      final job = WorkspaceJob('invalid', 'invalid', 'invalid');
      final runner = ToolRunner(
        scraper: DuckDuckGoScraper(),
        reader: WebPageReader(),
        settings: settings,
        cancel: job.cancel,
      );
      await expectLater(
        WorkspaceWorkflow(
          engine: engine,
          tools: runner,
          settings: settings,
        ).run(job, [
          {'role': 'user', 'content': 'Check for nuclear war news'},
        ]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('valid tool call'),
          ),
        ),
      );
      expect(engine.calls, 2);
      expect(runner.callCount, 0);
      expect(
        engine.lastMessages.last['content'],
        contains('No tool was executed'),
      );
    },
  );

  test(
    'server agents publish activity; phone approval releases host work',
    () async {
      var approved = false;
      await start(
        WorkspaceApi(
          capabilities: const ['server_execution'],
          run: (job, input) async {
            job.emit('agent', {
              'id': 'a',
              'phase': 'generating',
              'output': 'starting',
            });
            approved = await job.approve('Allow server web access?');
            job.emit('agent', {
              'id': 'a',
              'phase': 'done',
              'output': 'finished',
            });
            job.emit('answer', {'text': approved ? 'allowed' : 'denied'});
          },
        ),
      );
      await client.run(
        settings: connection,
        requestId: 'agents',
        messages: [
          {'role': 'user', 'content': 'launch an agent'},
        ],
        event: events.add,
        approve: (_, _) async => true,
      );
      expect(approved, isTrue);
      expect(events.where((e) => e['type'] == 'agent'), hasLength(2));
      expect(events.last['type'], 'done');
    },
  );

  test('authentication applies to capabilities, uploads and jobs', () async {
    var runs = 0;
    await start(
      WorkspaceApi(
        capabilities: const ['server_execution'],
        run: (_, _) async {
          runs++;
        },
      ),
    );
    final http = HttpClient();
    addTearDown(http.close);
    for (final endpoint in ['capabilities', 'jobs', 'uploads']) {
      final request = await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/v1/workspace/$endpoint'),
      );
      final response = await request.close();
      expect(response.statusCode, 401);
      await response.drain<void>();
    }
    expect(runs, 0);
  });

  test('raw uploads stay on host and do not accept local file paths', () async {
    late WorkspaceApi api;
    api = WorkspaceApi(
      capabilities: const ['server_execution'],
      run: (job, input) async {
        final upload = api
            .uploads[(input['uploads'] as List).single['uploadId'] as String]!;
        job.emit('answer', {'text': await upload.file.readAsString()});
      },
    );
    await start(api);
    final dir = await Directory.systemTemp.createTemp('workspace-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/data.csv');
    await file.writeAsString('value\n42');
    final id = await client.upload(connection, file.path, '../../data.csv');
    expect(api.uploads[id]!.name, 'data.csv');
    expect(await api.uploads[id]!.file.readAsString(), 'value\n42');
    await client.run(
      settings: connection,
      requestId: 'file',
      messages: [
        {'role': 'user', 'content': 'read'},
      ],
      uploads: [
        {'uploadId': id, 'message': 0},
      ],
      event: events.add,
      approve: (_, _) async => false,
    );
    expect(
      events.where((e) => e['type'] == 'answer').single['data']['text'],
      'value\n42',
    );
  });

  test(
    'transport interruption rejoins the same job without rerunning it',
    () async {
      var executions = 0;
      await start(
        WorkspaceApi(
          capabilities: const ['server_execution'],
          run: (job, input) async {
            executions++;
            job.emit('started');
            await Future<void>.delayed(const Duration(milliseconds: 300));
            job.emit('answer', {'text': 'Finished while disconnected'});
          },
        ),
      );
      client.dispose();
      final adapter = _DropOnce();
      client = WorkspaceClient(dio: Dio()..httpClientAdapter = adapter);
      await client.run(
        settings: connection,
        requestId: 'rejoin',
        messages: [
          {'role': 'user', 'content': 'work'},
        ],
        event: events.add,
        approve: (_, _) async => false,
      );
      expect(adapter.dropped, isTrue);
      expect(executions, 1);
      expect(events.any((e) => e['type'] == 'reconnecting'), isTrue);
      expect(
        events.where((e) => e['type'] == 'answer').single['data']['text'],
        'Finished while disconnected',
      );
      final sequences = events
          .where((e) => e['sequence'] != null)
          .map((e) => e['sequence'])
          .toList();
      expect(sequences.toSet().length, sequences.length);
    },
  );

  test('explicit stop cancels server-owned work', () async {
    final stopped = Completer<void>();
    await start(
      WorkspaceApi(
        capabilities: const ['server_execution'],
        run: (job, input) async {
          job.emit('started');
          await job.cancel.whenCancel;
          stopped.complete();
        },
      ),
    );
    final cancel = CancelToken();
    await client.run(
      settings: connection,
      requestId: 'stop',
      messages: [
        {'role': 'user', 'content': 'work'},
      ],
      event: (event) {
        events.add(event);
        if (event['type'] == 'started') cancel.cancel('Stop');
      },
      approve: (_, _) async => false,
      cancel: cancel,
    );
    await stopped.future.timeout(const Duration(seconds: 3));
  });

  test(
    'server prepares phone actions but leaves execution to confirmation cards',
    () async {
      final engine = _Rounds([
        '```tool\n{"name":"set_timer","arguments":{"minutes":2,"label":"Tea"}}\n```',
        'Your timer is ready to confirm.',
      ]);
      const settings = InferenceSettings(
        toolsEnabled: false,
        toolActions: true,
      );
      late ToolRunner runner;
      await start(
        WorkspaceApi(
          capabilities: const ['server_execution'],
          run: (job, input) async {
            runner = ToolRunner(
              scraper: DuckDuckGoScraper(),
              reader: WebPageReader(),
              settings: settings,
              cancel: job.cancel,
              phoneActions: true,
              actionsOnly: true,
            );
            await WorkspaceWorkflow(
              engine: engine,
              tools: runner,
              settings: settings,
            ).run(job, [
              {'role': 'user', 'content': 'Set a two minute timer'},
            ]);
          },
        ),
      );
      await client.run(
        settings: connection,
        requestId: 'timer',
        messages: [
          {'role': 'user', 'content': 'Set a two minute timer'},
        ],
        phoneActions: true,
        event: events.add,
        approve: (_, _) async => false,
      );
      final prepared = PhoneActions.fromTrace(
        runner.trace.map((r) => r.toJson()).toList(),
      );
      expect(prepared.single.kind, 'set_timer');
      expect(prepared.single.args['minutes'], 2);
      expect(
        events.where((e) => e['type'] == 'tool_finished').single['data']['ok'],
        isTrue,
      );
    },
  );

  test('connection web sharing flags and credentials stay scoped', () async {
    await start(
      WorkspaceApi(
        capabilities: const ['server_execution'],
        run: (job, input) async {
          final settings = input['settings'] as Map;
          expect(settings['toolWeb'], isFalse);
          expect(settings['webSearchEnabled'], isFalse);
          expect(settings.containsKey('remoteProfiles'), isFalse);
          expect(settings.containsKey('remoteApiKeys'), isFalse);
          expect(input['webOnly'], isTrue);
          job.emit('answer', {'text': 'No web requested.'});
        },
      ),
    );
    await client.run(
      settings: connection.copyWith(
        remoteWebResearch: false,
        webMode: WebMode.always,
      ),
      requestId: 'privacy',
      messages: [
        {'role': 'user', 'content': 'Hello'},
      ],
      webOnly: true,
      event: events.add,
      approve: (_, _) async => false,
    );
  });

  test('enabled remote web mode actually runs search on the server', () async {
    final search = _HostSearch();
    final engine = _Rounds([
      '```tool\n{"name":"search_web","arguments":{"query":"server test result"}}\n```',
      'The server found the result [1].',
    ]);
    await start(
      WorkspaceApi(
        capabilities: const ['server_execution'],
        run: (job, input) async {
          final settings = InferenceSettings.fromJson({
            ...const InferenceSettings().toJson(),
            ...input['settings'] as Map<String, dynamic>,
          });
          expect(settings.webSearchEnabled, isTrue);
          final runner = ToolRunner(
            scraper: search,
            reader: WebPageReader(),
            settings: settings,
            cancel: job.cancel,
          );
          await WorkspaceWorkflow(
            engine: engine,
            tools: runner,
            settings: settings,
          ).run(job, [
            {'role': 'user', 'content': 'Search for the server test result'},
          ]);
        },
      ),
    );
    await client.run(
      settings: connection.copyWith(
        toolsEnabled: true,
        webMode: WebMode.always,
        remoteWebResearch: true,
      ),
      requestId: 'web',
      messages: [
        {'role': 'user', 'content': 'Search for the server test result'},
      ],
      event: events.add,
      approve: (_, _) async => false,
    );
    expect(search.calls, greaterThan(0));
    expect(
      events.where((e) => e['type'] == 'tool_finished').single['data']['ok'],
      isTrue,
    );
    final sources =
        events.where((e) => e['type'] == 'sources').single['data']['items']
            as List;
    expect(sources.single['url'], 'https://example.org/result');
    expect(sources.single['fetchedAt'], startsWith('2026-11-03'));
  });
}
