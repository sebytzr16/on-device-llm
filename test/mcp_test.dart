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

class EndlessMcpTransport extends FakeMcpTransport {
  final int toolCount;
  final String description;
  final Duration delay;
  EndlessMcpTransport({
    this.toolCount = 0,
    this.description = '',
    this.delay = Duration.zero,
  });
  int pages = 0;
  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (message['method'] != 'tools/list') return super.send(message);
    sent.add(message);
    await Future<void>.delayed(delay);
    if (controller.isClosed) return;
    controller.add({
      'jsonrpc': '2.0',
      'id': message['id'],
      'result': {
        'tools': [
          for (var i = 0; i < toolCount; i++)
            {
              'name': 'tool$i',
              'description': description,
              'inputSchema': {'type': 'object'},
            },
        ],
        'nextCursor': '${++pages}',
      },
    });
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
        '{"mcpServers":{"fixture":{"url":"http://localhost:1/mcp"}}}',
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
        await registry.saveConfig(
          '{"mcpServers":{"fixture":{"url":"http://localhost:2/mcp"}}}',
        );
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
    test('remote confirmation required even for always-allowed tools', () async {
      // Set up always-allowed locally
      registry.confirm = (_, _) async => McpConsent.always;
      await run();
      expect(registry.alwaysAllowed(call.name), true);
      registry.confirm = (_, _) async =>
          throw StateError('local confirm must not be called');

      // Simulate a remote call with its own confirmation callback
      var remotePrompted = false;
      Future<McpConsent> remoteConfirmation(
        String server,
        ToolCall call,
      ) async {
        remotePrompted = true;
        return McpConsent.once;
      }

      final result = await registry.call(
        call,
        explain: (e) => mcpExplain(t, e),
        unsupportedContent: t.mcpUnsupportedContent,
        confirmation: remoteConfirmation,
      );
      expect(result.ok, true);
      expect(
        remotePrompted,
        true,
        reason:
            'Remote confirmation must be prompted even for always-allowed tools',
      );
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
    test(
      'a damaged permissions file keeps servers listed but disabled',
      () async {
        await File(
          '${directory.path}/mcp-permissions.json',
        ).writeAsString('["not", "an", "object"]');
        final restored = McpRegistry(
          directory: () async => directory,
          connector: (_) async => FakeMcpTransport(),
        );
        await restored.load();
        addTearDown(restored.dispose);
        expect(restored.error, isNull);
        expect(restored.loaded, isTrue);
        expect(restored.servers.keys, contains('fixture'));
        // Nothing reviewed the servers, so none may run until enabled again.
        expect(restored.serverEnabled('fixture'), isFalse);
        expect(restored.alwaysAllowed(call.name), isFalse);
      },
    );
    test(
      'a malformed permissions field keeps executable approvals off',
      () async {
        final dir = await Directory.systemTemp.createTemp('mcp-partial-');
        addTearDown(() => dir.delete(recursive: true));
        final command = McpRegistry(
          directory: () async => dir,
          connector: (_) async => FakeMcpTransport(),
        );
        addTearDown(command.dispose);
        final executable = File('${dir.path}/fixture.exe')
          ..writeAsStringSync('fixture');
        await command.saveConfig(
          jsonEncode({
            'mcpServers': {
              'fixture': {'command': executable.path},
            },
          }),
        );
        await command.enableServer('fixture', true, reviewed: true);
        expect(command.serverEnabled('fixture'), isTrue);
        final prefs = File('${dir.path}/mcp-permissions.json');
        final snapshot = jsonDecode(await prefs.readAsString()) as Map;
        // The approvals decode fine; a later field no longer does.
        snapshot['disabledTools'] = <Object>[1];
        await prefs.writeAsString(jsonEncode(snapshot));

        final restored = McpRegistry(
          directory: () async => dir,
          connector: (_) async => FakeMcpTransport(),
        );
        await restored.load();
        addTearDown(restored.dispose);
        expect(restored.serverEnabled('fixture'), isFalse);
        expect(restored.alwaysAllowed(call.name), isFalse);
      },
    );
    test(
      'a grant is not published while its permissions write is pending',
      () async {
        final dir = await Directory.systemTemp.createTemp('mcp-grant-');
        addTearDown(() => dir.delete(recursive: true));
        final reached = Completer<void>();
        final gate = Completer<void>();
        var gated = false;
        final local = McpRegistry(
          directory: () async {
            if (gated) {
              if (!reached.isCompleted) reached.complete();
              await gate.future;
            }
            return dir;
          },
          connector: (_) async => FakeMcpTransport(),
        );
        addTearDown(local.dispose);
        await local.saveConfig(
          '{"mcpServers":{"fixture":{"url":"http://localhost:1/mcp"}}}',
        );
        local.confirm = (_, _) async => McpConsent.always;
        gated = true;
        final pending = local.call(
          call,
          explain: (e) => mcpExplain(t, e),
          unsupportedContent: t.mcpUnsupportedContent,
        );
        await reached.future;
        expect(local.alwaysAllowed(call.name), isFalse);
        gate.complete();
        expect((await pending).ok, isTrue);
        expect(local.alwaysAllowed(call.name), isTrue);
      },
    );
    test(
      'a change whose write failed is not persisted by a later change',
      () async {
        final good = await Directory.systemTemp.createTemp('mcp-serial-');
        final broken = await Directory.systemTemp.createTemp('mcp-broken-');
        addTearDown(() {
          good.deleteSync(recursive: true);
          broken.deleteSync(recursive: true);
        });
        // The atomic write fails while any live file stays intact.
        await Directory('${broken.path}/mcp-permissions.json.tmp').create();
        var failing = false;
        final serial = McpRegistry(
          directory: () async {
            final dir = failing ? broken : good;
            failing = false;
            return dir;
          },
          connector: (_) async => FakeMcpTransport(),
        );
        addTearDown(serial.dispose);
        await serial.saveConfig(
          '{"mcpServers":{"fixture":{"url":"http://localhost:1/mcp"}}}',
        );
        failing = true;
        final first = serial.enableTool('tool_a', false);
        final second = serial.enableTool('tool_b', false);
        await expectLater(first, throwsA(isA<FileSystemException>()));
        await second;
        expect(serial.toolEnabled('tool_a'), isTrue);
        expect(serial.toolEnabled('tool_b'), isFalse);
        final saved =
            jsonDecode(
                  await File(
                    '${good.path}/mcp-permissions.json',
                  ).readAsString(),
                )
                as Map;
        expect(saved['disabledTools'], ['tool_b']);
      },
    );
    test(
      'a failed permissions write leaves the committed config live',
      () async {
        registry.confirm = (_, _) async => McpConsent.always;
        expect((await run()).ok, isTrue);
        expect(registry.alwaysAllowed(call.name), isTrue);
        // mcp.json commits, then the atomic permissions write fails.
        final temp = Directory('${directory.path}/mcp-permissions.json.tmp');
        await temp.create();
        await expectLater(
          registry.saveConfig(
            '{"mcpServers":{"other":{"url":"http://localhost:2/mcp"}}}',
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(registry.raw, contains('other'));
        expect(registry.servers.keys, ['other']);
        expect(registry.serverEnabled('other'), isFalse);
        expect(registry.servers['other']!.status, McpStatus.disabled);
        expect(registry.alwaysAllowed(call.name), isFalse);
        await temp.delete();
      },
    );
    test('hosted calls require a host decision despite local grants', () async {
      registry.confirm = (_, _) async => McpConsent.always;
      expect((await run()).ok, isTrue);
      final sent = transport.sent.length;
      registry.confirmHosted = (_, _) async => McpConsent.deny;
      final result = await registry.call(
        call,
        explain: (e) => mcpExplain(t, e),
        unsupportedContent: t.mcpUnsupportedContent,
        requireHostConfirmation: true,
        confirmation: (_, _) async => McpConsent.once,
      );
      expect(result.ok, isFalse);
      expect(transport.sent, hasLength(sent));
    });

    for (final missingDigest in [false, true]) {
      test(
        'unverified URL config remains disabled (missing digest: $missingDigest)',
        () async {
          final raw = File('${directory.path}/mcp.json');
          await raw.writeAsString(
            '{"mcpServers":{"fixture":{"url":"http://localhost:2/mcp"},"added":{"url":"http://localhost:3/mcp"}}}',
          );
          if (missingDigest) {
            final prefs = File('${directory.path}/mcp-permissions.json');
            final snapshot = jsonDecode(await prefs.readAsString()) as Map;
            snapshot.remove('configDigest');
            await prefs.writeAsString(jsonEncode(snapshot));
          }
          var connects = 0;
          final next = McpRegistry(
            directory: () async => directory,
            connector: (_) async {
              connects++;
              return FakeMcpTransport();
            },
          );
          addTearDown(next.dispose);
          await next.load();
          expect(connects, 0);
          expect(next.serverEnabled('fixture'), isFalse);
          expect(next.serverEnabled('added'), isFalse);
          await next.enableServer('fixture', true);
          expect(connects, 1);
          expect(next.serverEnabled('added'), isFalse);
        },
      );
    }

    test(
      'Always Allow is rejected after a queued server replacement',
      () async {
        final saving = Completer<void>();
        final unblock = Completer<void>();
        var hold = false;
        final queued = McpRegistry(
          directory: () async {
            if (hold) {
              hold = false;
              saving.complete();
              await unblock.future;
            }
            return directory;
          },
          connector: (_) async => FakeMcpTransport(),
        );
        addTearDown(queued.dispose);
        await queued.saveConfig(registry.raw);
        final asked = Completer<void>();
        final consent = Completer<McpConsent>();
        queued.confirm = (_, _) {
          asked.complete();
          return consent.future;
        };
        final pending = queued.call(
          call,
          explain: (e) => '$e',
          unsupportedContent: '',
        );
        await asked.future;
        hold = true;
        final replace = queued.saveConfig(
          '{"mcpServers":{"fixture":{"url":"http://localhost:2/mcp"}}}',
        );
        await saving.future;
        consent.complete(McpConsent.always);
        await Future<void>.delayed(Duration.zero);
        unblock.complete();
        await replace;
        expect((await pending).ok, isFalse);
        expect(queued.alwaysAllowed(call.name), isFalse);
      },
    );

    test(
      'restarts recheck approval after preparing a working directory',
      () async {
        final preparing = Completer<void>();
        final unblock = Completer<void>();
        var hold = false;
        var starts = 0;
        final executable = File('${directory.path}/fixture.exe')
          ..writeAsStringSync('fixture');
        final guarded = McpRegistry(
          directory: () async {
            if (hold) {
              hold = false;
              preparing.complete();
              await unblock.future;
            }
            return directory;
          },
          connector: (_) async {
            starts++;
            return FakeMcpTransport();
          },
        );
        addTearDown(guarded.dispose);
        await guarded.saveConfig(
          jsonEncode({
            'mcpServers': {
              'fixture': {'command': executable.path},
            },
          }),
        );
        await guarded.enableServer('fixture', true, reviewed: true);
        expect(starts, 1);
        hold = true;
        final restarting = guarded.restart('fixture');
        await preparing.future;
        await guarded.enableServer('fixture', false);
        unblock.complete();
        await restarting;
        expect(starts, 1);
        expect(guarded.servers['fixture']!.status, McpStatus.disabled);
      },
    );

    test('changing an approved executable requires a new review', () async {
      var starts = 0;
      final executable = File('${directory.path}/fixture.exe')
        ..writeAsStringSync('original');
      final guarded = McpRegistry(
        directory: () async => directory,
        connector: (_) async {
          starts++;
          return FakeMcpTransport();
        },
      );
      addTearDown(guarded.dispose);
      await guarded.saveConfig(
        jsonEncode({
          'mcpServers': {
            'fixture': {'command': executable.path},
          },
        }),
      );
      await guarded.enableServer('fixture', true, reviewed: true);
      expect(starts, 1);
      await executable.writeAsString('replacement');
      await guarded.restart('fixture');
      expect(starts, 1);
      expect(guarded.specs, isEmpty);
      await guarded.enableServer('fixture', true, reviewed: true);
      expect(starts, 2);
    });

    test('a failed permission write rolls the change back', () async {
      registry.confirm = (_, _) async => McpConsent.always;
      expect((await run()).ok, isTrue);
      expect(registry.alwaysAllowed(call.name), isTrue);
      // A folder where the temporary file belongs makes every write fail while
      // the live snapshot stays valid.
      final temp = Directory('${directory.path}/mcp-permissions.json.tmp');
      await temp.create();
      await expectLater(
        registry.revoke(call.name),
        throwsA(isA<FileSystemException>()),
      );
      expect(registry.alwaysAllowed(call.name), isTrue);
      await expectLater(
        registry.enableTool(call.name, false),
        throwsA(isA<FileSystemException>()),
      );
      expect(registry.toolEnabled(call.name), isTrue);
      await temp.delete();
      // The untouched snapshot still restores the grant in a fresh registry.
      final restored = McpRegistry(
        directory: () async => directory,
        connector: (_) async => FakeMcpTransport(),
      );
      await restored.load();
      addTearDown(restored.dispose);
      expect(restored.alwaysAllowed(call.name), isTrue);
    });
    test('a running server stays available during a config save', () async {
      final dir = await Directory.systemTemp.createTemp('mcp-save-');
      addTearDown(() => dir.delete(recursive: true));
      final reached = Completer<void>();
      final gate = Completer<void>();
      var gated = false, calls = 0;
      final local = McpRegistry(
        directory: () async {
          // The first write of a save is mcp.json; hold the permissions write.
          if (gated && ++calls >= 2) {
            if (!reached.isCompleted) reached.complete();
            await gate.future;
          }
          return dir;
        },
        connector: (_) async => FakeMcpTransport(),
      );
      addTearDown(local.dispose);
      const raw = '{"mcpServers":{"fixture":{"url":"http://localhost:1/mcp"}}}';
      await local.saveConfig(raw);
      expect(local.serverEnabled('fixture'), isTrue);
      calls = 0;
      gated = true;
      final saving = local.saveConfig(raw);
      await reached.future;
      // Permissions are still being written, but an unrelated save must not
      // make a running server unavailable to a chat turn.
      expect(local.serverEnabled('fixture'), isTrue);
      expect(local.specs, isNotEmpty);
      gate.complete();
      await saving;
      expect(local.serverEnabled('fixture'), isTrue);
    });
    test('an enable click survives a queued identical config save', () async {
      final raw = registry.raw;
      await registry.enableServer('fixture', false);
      expect(registry.serverEnabled('fixture'), isFalse);
      final saving = registry.saveConfig('  $raw');
      final enabling = registry.enableServer('fixture', true);
      await saving;
      await enabling;
      expect(registry.serverEnabled('fixture'), isTrue);
    });

    test('a queued enable cannot approve a replacement executable', () async {
      String config(String path) => jsonEncode({
        'mcpServers': {
          'fixture': {'command': path},
        },
      });
      final first = File('${directory.path}/first.exe')
        ..writeAsStringSync('one');
      final second = File('${directory.path}/second.exe')
        ..writeAsStringSync('two');
      await registry.saveConfig(config(first.path));
      final saving = registry.saveConfig(config(second.path));
      await expectLater(
        registry.enableServer('fixture', true, reviewed: true),
        throwsA(isA<McpException>()),
      );
      await saving;
      expect(registry.servers['fixture']!.config.command, second.path);
      expect(registry.serverEnabled('fixture'), isFalse);
    });

    test(
      'editing another server preserves a stdio client and its grants',
      () async {
        final executable = File('${directory.path}/fixture.exe')
          ..writeAsStringSync('fixture');
        String config(int port) => jsonEncode({
          'mcpServers': {
            'fixture': {'command': executable.path},
            'other': {'url': 'http://localhost:$port/mcp'},
          },
        });
        await registry.saveConfig(config(1));
        await registry.enableServer('fixture', true, reviewed: true);
        registry.confirm = (_, _) async => McpConsent.always;
        expect((await run()).ok, isTrue);
        final unchanged = registry.servers['fixture']!.client;
        final changed = registry.servers['other']!.client;

        await registry.saveConfig(config(2));
        expect(registry.serverEnabled('fixture'), isTrue);
        expect(registry.servers['fixture']!.client, same(unchanged));
        expect(registry.servers['other']!.client, isNot(same(changed)));
        expect(registry.alwaysAllowed(call.name), isTrue);
        final restored = McpRegistry(
          directory: () async => directory,
          connector: (_) async => FakeMcpTransport(),
        );
        addTearDown(restored.dispose);
        await restored.load();
        expect(restored.serverEnabled('fixture'), isTrue);
        expect(restored.alwaysAllowed(call.name), isTrue);
      },
    );
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
      final root = await Directory.systemTemp.createTemp('mcp-work-test-');
      addTearDown(() => root.delete(recursive: true));
      final stderr = <String>[];
      final transport = await StdioMcpTransport.start(
        McpServerConfig(
          name: 'fixture',
          command: bundledDart(),
          args: [File('test/fixtures/mcp_server.dart').absolute.path],
        ),
        log: stderr.add,
        approved: true,
        workingDirectory: root,
      );
      final client = McpClient(transport, timeout: const Duration(seconds: 2));
      addTearDown(client.close);
      await client.initialize();
      final context = await client.callTool('context', {});
      final launch =
          jsonDecode(
                ((context['content'] as List).single as Map)['text'] as String,
              )
              as Map;
      expect(launch['cwd'], root.absolute.path);
      final environment = launch['env'] as Map;
      expect(environment['HOME'], root.absolute.path);
      expect(environment['USERPROFILE'], root.absolute.path);
      expect(environment['PATH'], isNull);
      expect(environment['Path'], isNull);
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
  test('Windows batch file args reject shell metacharacters', () {
    // .cmd target: forbidden chars should throw
    expect(
      () => StdioMcpTransport.validateWindowsBatchArgs(r'C:\node\npx.cmd', [
        'normal',
        'arg',
      ]),
      returnsNormally,
    );
    for (final bad in [
      '&',
      '|',
      '<',
      '>',
      '^',
      '%',
      '"',
      'a&b',
      'a|b',
      'a"b',
    ]) {
      expect(
        () => StdioMcpTransport.validateWindowsBatchArgs(r'C:\node\npx.cmd', [
          bad,
        ]),
        throwsA(
          isA<McpException>().having(
            (e) => e.problem,
            'problem',
            McpProblem.batchArgs,
          ),
        ),
        reason: 'arg: $bad',
      );
    }
    // .bat target: same restrictions
    expect(
      () => StdioMcpTransport.validateWindowsBatchArgs(r'C:\scripts\run.bat', [
        'bad&arg',
      ]),
      throwsA(
        isA<McpException>().having(
          (e) => e.problem,
          'problem',
          McpProblem.batchArgs,
        ),
      ),
    );
    // Non-batch targets: no restriction
    expect(
      () => StdioMcpTransport.validateWindowsBatchArgs(r'C:\tools\server.exe', [
        '&',
        '|',
        '<',
        '>',
        '^',
        '%',
        '"',
      ]),
      returnsNormally,
    );
    expect(
      () => StdioMcpTransport.validateWindowsBatchArgs(
        'npx', // unresolved, not a batch file
        ['&', '|'],
      ),
      returnsNormally,
    );
  });
  test(
    'long tool aliases are stable, bounded and dispatch through reverse map',
    () async {
      final name = 'server' * 20;
      final tool = 'echo';
      final alias = mcpToolName(name, tool);
      expect(alias.length, lessThanOrEqualTo(64));
      expect(alias, mcpToolName(name, tool));
      expect(alias, isNot(mcpToolName(name, '$tool!')));
      final dir = await Directory.systemTemp.createTemp('mcp-alias');
      final transport = FakeMcpTransport();
      final registry = McpRegistry(
        directory: () async => dir,
        connector: (_) async => transport,
      );
      addTearDown(() async {
        registry.dispose();
        await dir.delete(recursive: true);
      });
      await registry.saveConfig(
        jsonEncode({
          'mcpServers': {
            name: {'url': 'http://localhost:1/mcp'},
          },
        }),
      );
      registry.confirm = (_, _) async => McpConsent.once;
      expect(registry.specs.single.name, alias);
      final result = await registry.call(
        ToolCall(id: 'a', name: alias, arguments: '{}'),
        explain: (e) => '$e',
        unsupportedContent: 'unsupported',
      );
      expect(result.ok, true);
      expect((transport.sent.last['params'] as Map)['name'], tool);
    },
  );

  test(
    'timeout and Stop send cancellation for the pending request id',
    () async {
      for (final stop in [false, true]) {
        final transport = FakeMcpTransport()..silent = true;
        final client = McpClient(
          transport,
          timeout: const Duration(milliseconds: 20),
        );
        final result = client.callTool('slow', {});
        final check = expectLater(result, throwsA(isA<McpException>()));
        if (stop) client.cancelPending();
        await check;
        expect(transport.sent.last['method'], 'notifications/cancelled');
        expect(
          (transport.sent.last['params'] as Map)['requestId'],
          transport.sent.first['id'],
        );
        await client.close();
      }
    },
  );

  test('tool discovery stops at its total page budget', () async {
    final transport = EndlessMcpTransport();
    final client = McpClient(transport);
    await expectLater(client.listTools(), throwsA(isA<McpException>()));
    expect(transport.pages, 100);
    await client.close();
  });
  test(
    'registry cancels running MCP tool when turn permission is revoked',
    () async {
      final dir = await Directory.systemTemp.createTemp('mcp-stop');
      final transport = FakeMcpTransport();
      final registry = McpRegistry(
        directory: () async => dir,
        connector: (_) async => transport,
      );
      addTearDown(() async {
        registry.dispose();
        await dir.delete(recursive: true);
      });
      await registry.saveConfig(
        '{"mcpServers":{"fixture":{"url":"http://localhost:1/mcp"}}}',
      );
      registry.confirm = (_, _) async => McpConsent.once;
      transport.silent = true;
      var permitted = true;
      final result = registry.call(
        call,
        explain: (e) => '$e',
        unsupportedContent: 'unsupported',
        permitted: () => permitted,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      permitted = false;
      expect((await result).ok, false);
      expect(transport.sent.last['method'], 'notifications/cancelled');
    },
  );

  for (final oversizedBytes in [false, true]) {
    test(
      'tool discovery bounds ${oversizedBytes ? 'bytes' : 'tool count'}',
      () async {
        final transport = EndlessMcpTransport(
          toolCount: oversizedBytes ? 1 : 1001,
          description: oversizedBytes ? 'x' * (4 * 1024 * 1024) : '',
        );
        final client = McpClient(transport);
        await expectLater(client.listTools(), throwsA(isA<McpException>()));
        expect(transport.pages, 1);
        await client.close();
      },
    );
  }

  test('tool discovery has a total time budget across pages', () async {
    final transport = EndlessMcpTransport(
      delay: const Duration(milliseconds: 30),
    );
    final client = McpClient(
      transport,
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(client.listTools(), throwsA(isA<McpException>()));
    expect(
      transport.sent.where((m) => m['method'] == 'tools/list').length,
      lessThanOrEqualTo(2),
    );
    expect(transport.sent.last['method'], 'notifications/cancelled');
    await client.close();
  });
}
