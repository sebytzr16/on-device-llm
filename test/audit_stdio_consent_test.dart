import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_client.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_config.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_registry.dart';

import 'mcp_test.dart' show FakeMcpTransport;

void main() {
  test(
    'stdio never starts before review; approval is bound to each server configuration',
    () async {
      final dir = await Directory.systemTemp.createTemp('mcp-review-');
      addTearDown(() => dir.delete(recursive: true));
      var starts = 0;
      final registry = McpRegistry(
        directory: () async => dir,
        connector: (_) async {
          starts++;
          return FakeMcpTransport();
        },
      );
      addTearDown(registry.dispose);
      String config(String arg) => jsonEncode({
        'mcpServers': {
          'one': {
            'command': 'preinstalled',
            'args': [arg],
          },
          'two': {'command': 'another'},
        },
      });
      await registry.saveConfig(config('first'));
      await registry.restart('one');
      expect(starts, 0);
      expect(registry.serverEnabled('one'), isFalse);
      await expectLater(
        registry.enableServer('one', true),
        throwsA(isA<McpException>()),
      );
      expect(starts, 0);
      await registry.enableServer('one', true, reviewed: true);
      expect(starts, 1);
      expect(registry.serverEnabled('two'), isFalse);
      await registry.saveConfig(config('changed'));
      await registry.restart('one');
      expect(starts, 1);
      await registry.enableServer('one', true, reviewed: true);
      await registry.enableServer('one', false);
      await registry.restart('one');
      expect(starts, 2);
    },
  );

  test('old enabled preferences cannot auto-launch stdio on load', () async {
    final dir = await Directory.systemTemp.createTemp('mcp-legacy-review-');
    addTearDown(() => dir.delete(recursive: true));
    const raw =
        '{"mcpServers":{"legacy":{"command":"npx","args":["untrusted"]}}}';
    await File('${dir.path}/mcp.json').writeAsString(raw);
    await File('${dir.path}/mcp-permissions.json').writeAsString(
      jsonEncode({
        'config': raw,
        'disabledServers': [],
        'allowedTools': ['legacy__echo'],
      }),
    );
    var starts = 0;
    final registry = McpRegistry(
      directory: () async => dir,
      connector: (_) async {
        starts++;
        return FakeMcpTransport();
      },
    );
    addTearDown(registry.dispose);
    await registry.load();
    expect(starts, 0);
    expect(registry.serverEnabled('legacy'), isFalse);
    expect(registry.specs, isEmpty);
  });

  test(
    'direct transport launch requires review and a dedicated root; environment is minimal',
    () async {
      const config = McpServerConfig(name: 'unreviewed', command: 'npx');
      await expectLater(
        StdioMcpTransport.start(config),
        throwsA(isA<McpException>()),
      );
      final root = await Directory.systemTemp.createTemp('mcp-root-');
      addTearDown(() => root.delete(recursive: true));
      await expectLater(
        StdioMcpTransport.start(config, approved: true, workingDirectory: root),
        throwsA(isA<McpException>()),
      );
      final env = StdioMcpTransport.launchEnvironment(
        {'TOKEN': 'explicit', 'HOME': 'outside'},
        root.path,
        system: {'PATH': 'inherited', 'SECRET': 'hidden', 'SystemRoot': 'os'},
      );
      expect(env['SECRET'], isNull);
      expect(env['PATH'], isNull);
      expect(env['TOKEN'], 'explicit');
      expect(env['SystemRoot'], 'os');
      for (final key in ['HOME', 'USERPROFILE', 'TMP', 'TEMP', 'TMPDIR']) {
        expect(env[key], root.path);
      }
    },
  );
}
