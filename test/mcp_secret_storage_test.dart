import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_client.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_config.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_registry.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

class _Transport implements McpTransport {
  final controller = StreamController<Map<String, dynamic>>();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<Map<String, dynamic>> get messages => controller.stream;
  @override
  Future<void> send(Map<String, dynamic> message) async {
    sent.add(message);
    if (!message.containsKey('id')) return;
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
          {'type': 'text', 'text': 'ok'},
        ],
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

void main() {
  late Directory directory;
  late _Transport transport;
  late McpRegistry registry;
  final alias = mcpToolName('fixture', 'echo');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mcp-secret-store');
    transport = _Transport();
    registry = McpRegistry(
      directory: () async => directory,
      connector: (_) async => transport,
    );
  });

  tearDown(() async {
    registry.dispose();
    await directory.delete(recursive: true);
  });

  File permissions() =>
      File('${directory.path}${Platform.pathSeparator}mcp-permissions.json');

  test(
    'permission storage stores a digest, not a copy of env secrets',
    () async {
      const secret = 'mcp-env-secret-value';
      final raw = jsonEncode({
        'mcpServers': {
          'fixture': {
            'command': 'fixture',
            'env': {'TOKEN': secret},
          },
        },
      });
      await registry.saveConfig(raw);
      await registry.enableServer('fixture', true, reviewed: true);
      registry.confirm = (_, _) async => McpConsent.always;
      final result = await registry.call(
        ToolCall(id: 'c', name: alias, arguments: '{}'),
        explain: (error) => '$error',
        unsupportedContent: 'unsupported',
      );
      expect(result.ok, true);
      expect(registry.alwaysAllowed(alias), true);

      final text = await permissions().readAsString();
      expect(text.contains(secret), false);
      final json = jsonDecode(text) as Map;
      expect(json.containsKey('config'), false);
      expect(json['configDigest'], isA<String>());
      expect(json['configDigest'], isNot(raw));
    },
  );

  test('an older plaintext config copy is removed on load', () async {
    const secret = 'legacy-env-secret-value';
    final raw = jsonEncode({
      'mcpServers': {
        'fixture': {
          'command': 'fixture',
          'env': {'TOKEN': secret},
        },
      },
    });
    await File(
      '${directory.path}${Platform.pathSeparator}mcp.json',
    ).writeAsString(raw);
    await permissions().writeAsString(
      jsonEncode({
        'disabledServers': <String>[],
        'disabledTools': <String>[],
        'allowedTools': [alias],
        'config': raw,
      }),
    );

    await registry.load();
    expect(registry.error, isNull);
    final text = await permissions().readAsString();
    expect(text.contains(secret), false);
    final json = jsonDecode(text) as Map;
    expect(json.containsKey('config'), false);
    expect(json['configDigest'], isA<String>());
    // The legacy raw value is not trusted: approvals are re-confirmed.
    expect(registry.alwaysAllowed(alias), false);
  });
}
