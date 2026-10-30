import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_client.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_config.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_registry.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_strings.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

class FakeMcpTransport implements McpTransport {
  final controller = StreamController<Map<String, dynamic>>();
  final sent = <Map<String, dynamic>>[];
  bool silent = false, errorResult = false;
  @override
  Stream<Map<String, dynamic>> get messages => controller.stream;
  @override
  Future<void> send(Map<String, dynamic> message) async {
    sent.add(message);
    if (silent || !message.containsKey('id')) return;
    final Object result = switch (message['method']) {
      'initialize' => {
        'protocolVersion': McpClient.protocolVersion,
        'capabilities': {'tools': {}},
      },
      'tools/list' => {
        'tools': [
          {
            'name': 'echo',
            'description': 'Echo',
            'inputSchema': {'type': 'object'},
          },
        ],
      },
      'tools/call' => {
        'content': [
          {
            'type': 'text',
            'text': jsonEncode((message['params'] as Map)['arguments']),
          },
        ],
        'isError': errorResult,
      },
      _ => <String, dynamic>{},
    };
    controller.add({'jsonrpc': '2.0', 'id': message['id'], 'result': result});
  }

  @override
  Future<void> close() async {
    if (!controller.isClosed) await controller.close();
  }
}

String bundledDart() {
  final packages =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map;
  final flutter = (packages['packages'] as List).cast<Map>().firstWhere(
    (p) => p['name'] == 'flutter',
  );
  final root = Uri.parse('${flutter['rootUri']}/').resolve('../../');
  return File.fromUri(
    root.resolve(
      'bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
    ),
  ).path;
}

void main() {
  final t = AppLocalizationsEn();
  const call = ToolCall(
    id: 'c1',
    name: 'fixture__echo',
    arguments: '{"camelCase": "Hello"}',
  );
  test(
    'config accepts command/env and loopback URLs; rejects other network targets',
    () {
      final configs = McpServerConfig.parse(
        '{"mcpServers":{"a":{"command":"dart","args":["server.dart"],"env":{"A":"B"}},"b":{"url":"http://localhost:8000/mcp"}}}',
      );
      expect(configs['a']!.env, {'A': 'B'});
      expect(configs['b']!.url, 'http://localhost:8000/mcp');
      for (final url in [
        'https://localhost/mcp',
        'http://example.com',
        'http://127.0.0.2',
        'http://localhost.example.com',
        'http://user@localhost',
        'file:///mcp',
      ]) {
        expect(
          () => McpServerConfig.loopback(url),
          throwsA(
            isA<McpException>().having(
              (e) => e.problem,
              'problem',
              McpProblem.loopback,
            ),
          ),
        );
      }
      for (final config in [
        '{}',
        '{',
        '{"mcpServers": []}',
        '{"mcpServers":{"a":{"command":"x","args":[1]}}}',
        '{"mcpServers":{"a":{"command":"x","url":"http://localhost"}}}',
      ]) {
        expect(
          () => McpServerConfig.parse(config),
          throwsA(isA<McpException>()),
        );
      }
    },
  );
  test('text protocol preserves MCP argument keys', () {
    final call = TextToolProtocol.parse(
      '```tool\n{"name":"fixture__echo","arguments":{"camelCase":"hello"}}\n```',
      counter: 1,
    ).single;
    expect(call.args, {'camelCase': 'hello'});
  });
  test('namespaces preserve identity without collisions', () {
    expect(mcpToolName('server', 'tool'), 'server__tool');
    expect(mcpToolName('a__b', 'c'), isNot(mcpToolName('a', 'b__c')));
    expect(mcpToolName('a-b', 'c'), isNot(mcpToolName('a_b', 'c')));
  });
  test(
    'initialize, initialized notification, list, call and error results',
    () async {
      final transport = FakeMcpTransport();
      final client = McpClient(transport);
      addTearDown(client.close);
      await client.initialize();
      expect(transport.sent.map((m) => m['method']), [
        'initialize',
        'notifications/initialized',
      ]);
      expect((await client.listTools()).single['name'], 'echo');
      expect(
        (await client.callTool('echo', {'text': 'hello'}))['isError'],
        false,
      );
      transport.errorResult = true;
      expect((await client.callTool('echo', {}))['isError'], true);
    },
  );
  test('timeout removes pending request; crash fails pending calls', () async {
    final transport = FakeMcpTransport()..silent = true;
    Object? failure;
    final client = McpClient(
      transport,
      timeout: const Duration(milliseconds: 30),
      onFailure: (e) => failure = e,
    );
    addTearDown(client.close);
    await expectLater(
      client.initialize(),
      throwsA(
        isA<McpException>().having(
          (e) => e.problem,
          'problem',
          McpProblem.timeout,
        ),
      ),
    );
    final pending = client.callTool('echo', {});
    final check = expectLater(pending, throwsA(isA<McpException>()));
    transport.controller.addError(const McpException(McpProblem.closed));
    await check;
    expect(failure, isA<McpException>());
    await expectLater(client.listTools(), throwsA(isA<McpException>()));
  });

  group('registry and confirmation gate', () {
    late Directory directory;
    late McpRegistry registry;
    late FakeMcpTransport transport;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mcp-test-');
      registry = McpRegistry(
        directory: () async => directory,
        connector: (_) async => transport = FakeMcpTransport(),
      );
      await registry.saveConfig(
        '{"mcpServers":{"fixture":{"command":"fake"}}}',
      );
    });
    tearDown(() async {
      registry.dispose();
      await directory.delete(recursive: true);
    });
    Future<ToolResult> run({bool Function()? permitted}) => registry.call(
      call,
      explain: (e) => mcpExplain(t, e),
      unsupportedContent: t.mcpUnsupportedContent,
      permitted: permitted,
    );
    test(
      'Deny becomes a tool refusal and is recorded by the shared runner',
      () async {
        registry.confirm = (_, _) async => McpConsent.deny;
        final runner = ToolRunner(
          scraper: DuckDuckGoScraper(),
          reader: WebPageReader(),
          settings: const InferenceSettings(),
          externalTools: registry.specs,
          externalRun: (call) => registry.call(
            call,
            explain: (e) => mcpExplain(t, e),
            unsupportedContent: t.mcpUnsupportedContent,
          ),
        );
        final result = await runner.run(call);
        expect(result.ok, false);
        expect(result.output, t.mcpDeniedError);
        expect(runner.trace.single, result);
        expect(
          transport.sent.where((m) => m['method'] == 'tools/call'),
          isEmpty,
        );
      },
    );
    test('Allow once asks each time and preserves argument casing', () async {
      var prompts = 0;
      registry.confirm = (_, _) async {
        prompts++;
        return McpConsent.once;
      };
      expect((await run()).output, '{"camelCase":"Hello"}');
      expect((await run()).ok, true);
      expect(prompts, 2);
    });
    test(
      'Always allow persists, can be revoked, and config edits invalidate trust',
      () async {
        registry.confirm = (_, _) async => McpConsent.always;
        expect((await run()).ok, true);
        expect(registry.alwaysAllowed(call.name), true);
        final restored = McpRegistry(
          directory: () async => directory,
          connector: (_) async => FakeMcpTransport(),
        );
        await restored.load();
        expect(restored.alwaysAllowed(call.name), true);
        restored.dispose();
        registry.confirm = (_, _) async => throw StateError('must not ask');
        expect((await run()).ok, true);
        await registry.revoke(call.name);
        registry.confirm = (_, _) async => McpConsent.deny;
        expect((await run()).ok, false);
        registry.confirm = (_, _) async => McpConsent.always;
        await run();
        await registry.saveConfig(registry.raw);
        expect(registry.alwaysAllowed(call.name), false);
      },
    );
    test(
      'missing confirmation denies; disabled tool/server cannot execute',
      () async {
        expect((await run()).output, t.mcpDeniedError);
        await registry.enableTool(call.name, false);
        expect(registry.specs, isEmpty);
        registry.confirm = (_, _) async => McpConsent.once;
        expect((await run()).ok, false);
        await registry.enableTool(call.name, true);
        await registry.enableServer('fixture', false);
        expect(registry.specs, isEmpty);
        expect(registry.servers['fixture']!.status, McpStatus.disabled);
      },
    );
    test('external config edits invalidate persisted approval', () async {
      registry.confirm = (_, _) async => McpConsent.always;
      await run();
      await File(
        '${directory.path}/mcp.json',
      ).writeAsString('{"mcpServers":{"fixture":{"command":"changed"}}}');
      final restored = McpRegistry(
        directory: () async => directory,
        connector: (_) async => FakeMcpTransport(),
      );
      await restored.load();
      expect(restored.alwaysAllowed(call.name), false);
      restored.dispose();
    });
    test('revoked availability while confirming is rechecked', () async {
      final approval = Completer<McpConsent>();
      registry.confirm = (_, _) => approval.future;
      final pending = run();
      await registry.enableTool(call.name, false);
      approval.complete(McpConsent.once);
      expect((await pending).ok, false);
      expect(transport.sent.where((m) => m['method'] == 'tools/call'), isEmpty);
    });
    test('crash removes tools and Restart restores them', () async {
      transport.controller.addError(const McpException(McpProblem.closed));
      await Future<void>.delayed(Duration.zero);
      expect(registry.specs, isEmpty);
      expect(registry.servers['fixture']!.status, McpStatus.error);
      await registry.restart('fixture');
      expect(registry.specs.single.name, call.name);
      registry.confirm = (_, _) async => McpConsent.once;
      transport.errorResult = true;
      expect((await run()).ok, false);
    });
  });

  test(
    'Streamable HTTP JSON/SSE, session/protocol headers and no redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = <String>[];
      server.listen((request) async {
        final message =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final method = message['method'] as String;
        seen.add(method);
        if (method != 'initialize') {
          expect(request.headers.value('Mcp-Session-Id'), 'session');
          expect(
            request.headers.value('MCP-Protocol-Version'),
            McpClient.protocolVersion,
          );
        }
        if (method == 'notifications/initialized') {
          request.response.statusCode = 202;
        } else if (method == 'tools/list') {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'event: message\ndata: ${jsonEncode({
              'jsonrpc': '2.0',
              'id': message['id'],
              'result': {'tools': []},
            })}\n\n',
          );
        } else if (method == 'redirect') {
          request.response.statusCode = 307;
          request.response.headers.set('location', 'http://blocked.invalid');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.headers.set('Mcp-Session-Id', 'session');
          request.response.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': message['id'],
              'result': {'protocolVersion': McpClient.protocolVersion},
            }),
          );
        }
        await request.response.close();
      });
      final client = McpClient(
        HttpMcpTransport('http://127.0.0.1:${server.port}/mcp'),
      );
      addTearDown(client.close);
      await client.initialize();
      expect(await client.listTools(), isEmpty);
      expect(seen, ['initialize', 'notifications/initialized', 'tools/list']);
      await expectLater(
        client.request('redirect'),
        throwsA(isA<McpException>()),
      );
    },
  );

  test(
    'real bundled-Dart stdio server end to end, stderr, error, timeout and crash',
    () async {
      final stderr = <String>[];
      final transport = await StdioMcpTransport.start(
        McpServerConfig(
          name: 'fixture',
          command: bundledDart(),
          args: [File('test/fixtures/mcp_server.dart').absolute.path],
        ),
        log: stderr.add,
      );
      final client = McpClient(transport, timeout: const Duration(seconds: 2));
      addTearDown(client.close);
      await client.initialize();
      expect((await client.listTools()).map((t) => t['name']), ['echo', 'add']);
      expect((await client.callTool('echo', {'text': 'hello'}))['content'], [
        {'type': 'text', 'text': 'hello'},
      ]);
      expect((await client.callTool('add', {'a': 2, 'b': 3}))['content'], [
        {'type': 'text', 'text': '5'},
      ]);
      expect((await client.callTool('error', {}))['isError'], true);
      await expectLater(
        client.callTool('timeout', {}),
        throwsA(
          isA<McpException>().having(
            (e) => e.problem,
            'problem',
            McpProblem.timeout,
          ),
        ),
      );
      await expectLater(
        client.callTool('crash', {}),
        throwsA(
          isA<McpException>().having(
            (e) => e.problem,
            'problem',
            McpProblem.closed,
          ),
        ),
      );
      expect(stderr, contains('fixture ready'));
    },
  );
  test('Windows finds npx.cmd and uvx.exe on PATH like a shell', () {
    final files = {r'C:\node\npx.cmd', r'C:\uv\uvx.exe'};
    String resolve(String c, [Map<String, String> env = const {}]) =>
        StdioMcpTransport.resolveWindowsCommand(
          c,
          env,
          system: const {'Path': r'C:\node;C:\uv', 'PATHEXT': '.EXE;.CMD'},
          exists: files.contains,
        );
    expect(resolve('npx'), r'C:\node\npx.cmd');
    expect(resolve('uvx'), r'C:\uv\uvx.exe');
    expect(resolve('node.exe'), 'node.exe');
    expect(resolve(r'C:\tools\server.exe'), r'C:\tools\server.exe');
    expect(resolve('missing'), 'missing');
    expect(resolve('npx', {'PATH': r'C:\other'}), 'npx');
  });
}
