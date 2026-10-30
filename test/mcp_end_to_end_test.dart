import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_config.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_registry.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_strings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

// flutter test runs in flutter_tester, which cannot execute a Dart script.
// Use the SDK belonging to the resolved Flutter package in that case.
String _dartExecutable() {
  final executable = File(Platform.resolvedExecutable);
  if (executable.uri.pathSegments.last ==
      (Platform.isWindows ? 'dart.exe' : 'dart')) {
    return executable.path;
  }
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final flutter = (config['packages'] as List).cast<Map>().firstWhere(
    (package) => package['name'] == 'flutter',
  );
  final root = configFile.uri.resolve('${flutter['rootUri']}/../../');
  return File.fromUri(
    root.resolve(
      'bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
    ),
  ).path;
}

void main() {
  final t = AppLocalizationsEn();
  const name = 'local fixture';
  final echoName = mcpToolName(name, 'echo');
  late Directory directory;
  late McpRegistry registry;

  String configuration({String? command, List<String> extraArgs = const []}) =>
      jsonEncode({
        'mcpServers': {
          name: {
            'command': command ?? _dartExecutable(),
            'args': [
              File('test/fixtures/mcp_server.dart').absolute.path,
              ...extraArgs,
            ],
          },
        },
      });

  Future<ToolResult> echo(String text) => registry.call(
    ToolCall(
      id: 'echo-call',
      name: echoName,
      arguments: jsonEncode({'text': text}),
    ),
    explain: (error) => mcpExplain(t, error),
    unsupportedContent: t.mcpUnsupportedContent,
  );

  setUp(() async {
    // Keep configuration and permission writes out of the user's AppData.
    directory = await Directory('.dart_tool').createTemp('mcp-end-to-end-');
    registry = McpRegistry(
      directory: () async => directory,
      timeout: const Duration(seconds: 5),
    );
    await registry.load();
    expect(registry.error, isNull);
    expect(registry.servers, isEmpty);
  });

  tearDown(() async {
    // Await process shutdown before deleting its configuration directory.
    try {
      await registry.saveConfig('{"mcpServers":{}}');
    } finally {
      registry.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'add, discover, approve, call, persist consent and remove over stdio',
    () async {
      await registry
          .saveConfig(configuration())
          .timeout(const Duration(seconds: 15));
      final state = registry.servers[name]!;
      expect(state.status, McpStatus.ready);
      expect(state.error, isNull);
      expect(state.tools.map((tool) => tool['name']), ['echo', 'add']);
      expect(registry.specs.map((spec) => spec.name), [
        echoName,
        mcpToolName(name, 'add'),
      ]);
      expect(registry.specs.first.parameters['required'], ['text']);

      // With no confirmation handler the app must refuse execution.
      final denied = await echo('no permission');
      expect(denied.ok, isFalse);
      expect(denied.output, t.mcpDeniedError);
      var prompts = 0;
      registry.confirm = (server, call) async {
        expect(server, name);
        expect(call.name, echoName);
        prompts++;
        return McpConsent.deny;
      };
      expect((await echo('explicit denial')).output, t.mcpDeniedError);

      // Hold approval open: the call must not complete before a decision.
      final approval = Completer<McpConsent>();
      final asked = Completer<void>();
      registry.confirm = (_, _) {
        prompts++;
        asked.complete();
        return approval.future;
      };
      var completed = false;
      final pending = echo('Hello, stdio! é 🌱\nSecond line').then((result) {
        completed = true;
        return result;
      });
      await asked.future;
      expect(completed, isFalse);
      approval.complete(McpConsent.once);
      final result = await pending;
      expect(result.ok, isTrue);
      expect(result.output, 'Hello, stdio! é 🌱\nSecond line');
      expect(registry.alwaysAllowed(echoName), isFalse);

      registry.confirm = (_, _) async {
        prompts++;
        return McpConsent.always;
      };
      expect((await echo('persist this grant')).ok, isTrue);
      expect(prompts, 3);
      expect(registry.alwaysAllowed(echoName), isTrue);
      registry.confirm = (_, _) async =>
          fail('persisted approval must skip prompt');
      expect((await echo('already approved')).output, 'already approved');

      // Restart the registry and a real subprocess from the saved files.
      await state.client!.close();
      registry.dispose();
      registry = McpRegistry(
        directory: () async => directory,
        timeout: const Duration(seconds: 5),
      );
      await registry.load().timeout(const Duration(seconds: 15));
      expect(registry.servers[name]!.status, McpStatus.ready);
      expect(registry.alwaysAllowed(echoName), isTrue);
      expect(
        (await echo('grant survived reload')).output,
        'grant survived reload',
      );
      await registry.revoke(echoName);
      expect((await echo('revoked')).output, t.mcpDeniedError);

      final client = registry.servers[name]!.client!;
      await registry.remove(name).timeout(const Duration(seconds: 10));
      expect(registry.servers, isEmpty);
      expect(registry.specs, isEmpty);
      expect(jsonDecode(registry.raw)['mcpServers'], isEmpty);
      final saved = jsonDecode(
        await File('${directory.path}/mcp.json').readAsString(),
      );
      expect(saved['mcpServers'], isEmpty);
      final removed = await echo('removed');
      expect(removed.ok, isFalse);
      expect(removed.output, t.mcpUnavailableError);
      await expectLater(client.listTools(), throwsA(isA<McpException>()));
    },
  );

  test(
    'a nonexistent command reports a launch error without hanging',
    () async {
      final missing = File(
        '${directory.path}/missing-mcp-server',
      ).absolute.path;
      await registry
          .saveConfig(configuration(command: missing))
          .timeout(const Duration(seconds: 15));
      final state = registry.servers[name]!;
      expect(state.status, McpStatus.error);
      expect(state.error, isA<ProcessException>());
      expect(mcpExplain(t, state.error!), contains(missing));
      expect(registry.specs, isEmpty);
      expect((await echo('unavailable')).output, t.mcpUnavailableError);
    },
  );

  test(
    'a server exiting during initialization reports closed, not timeout',
    () async {
      await registry
          .saveConfig(configuration(extraArgs: ['--exit-immediately']))
          .timeout(const Duration(seconds: 15));
      final state = registry.servers[name]!;
      expect(state.status, McpStatus.error);
      expect(
        state.error,
        isA<McpException>().having(
          (error) => error.problem,
          'problem',
          McpProblem.closed,
        ),
      );
      expect(mcpExplain(t, state.error!), t.mcpClosedError);
      expect(registry.specs, isEmpty);
    },
  );

  test(
    'a running server crash fails its pending call and withdraws tools',
    () async {
      await registry
          .saveConfig(configuration())
          .timeout(const Duration(seconds: 15));
      final client = registry.servers[name]!.client!;
      await expectLater(
        client.callTool('crash', {}).timeout(const Duration(seconds: 10)),
        throwsA(
          isA<McpException>().having(
            (error) => error.problem,
            'problem',
            McpProblem.closed,
          ),
        ),
      );
      expect(registry.servers[name]!.status, McpStatus.error);
      expect(registry.specs, isEmpty);
      expect((await echo('after crash')).output, t.mcpUnavailableError);
    },
  );
}
