import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_registry.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

import 'chat_test.dart' show TestEngine, TestModels, TestSettings;
import 'mcp_test.dart' show FakeMcpTransport;

class _Settings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(toolsEnabled: true);
}

class _Engine extends TestEngine {
  final bool native;
  final requests =
      <({List<Map<String, Object>> messages, List<ToolSpec> tools})>[];
  _Engine(this.native) {
    metrics = {'supportsTools': native};
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
    requests.add((messages: List.of(messages), tools: List.of(tools)));
    if (!messages.any((m) => m['role'] == 'tool')) {
      metrics = {
        'supportsTools': native,
        'toolCalls': [
          {
            'id': 'mcp-call',
            'name': 'fixture__echo',
            'arguments': '{"text":"hello"}',
          },
        ],
      };
      yield native
          ? '<tool_call>{"name":"fixture__echo","arguments":{"text":"hello"}}</tool_call>'
          : '```tool\n{"name":"fixture__echo","arguments":{"text":"hello"}}\n```';
    } else {
      metrics = {'supportsTools': native, 'toolCalls': <Object>[]};
      yield 'The tool call was denied.';
    }
  }
}

void main() {
  for (final native in [true, false]) {
    test(
      'MCP Deny reaches the model through the ${native ? 'native' : 'text'} chat tool loop',
      () async {
        final previous = DesktopHost.active;
        DesktopHost.active = true;
        final directory = await Directory.systemTemp.createTemp('mcp-chat-');
        final transport = FakeMcpTransport();
        final registry = McpRegistry(
          directory: () async => directory,
          connector: (_) async => transport,
        );
        await registry.saveConfig(
          '{"mcpServers":{"fixture":{"command":"fake"}}}',
        );
        var confirmations = 0;
        registry.confirm = (_, _) async {
          confirmations++;
          return McpConsent.deny;
        };
        final engine = _Engine(native);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            llamaEngineProvider.overrideWithValue(engine),
            settingsProvider.overrideWith(_Settings.new),
            modelManagerProvider.overrideWith(TestModels.new),
            mcpRegistryProvider.overrideWithValue(registry),
            zimWikipediaProvider.overrideWith((ref) async => null),
          ],
        );
        addTearDown(() async {
          container.dispose();
          registry.dispose();
          await db.close();
          await directory.delete(recursive: true);
          DesktopHost.active = previous;
        });
        await container
            .read(chatProvider.notifier)
            .send('Use the fixture echo tool to echo hello.');
        expect(confirmations, 1);
        if (native) {
          expect(
            engine.requests.first.tools.map((t) => t.name),
            contains('fixture__echo'),
          );
          expect(
            engine.requests.first.tools.map((t) => t.name),
            contains('calculator'),
          );
        } else {
          expect(
            engine.requests.first.messages.first['content'],
            contains('fixture__echo'),
          );
        }
        final result = engine.requests.last.messages.lastWhere(
          (m) => m['role'] == 'tool',
        );
        expect(result['name'], 'fixture__echo');
        expect(result['content'], AppLocalizationsEn().mcpDeniedError);
        expect(
          transport.sent.where((m) => m['method'] == 'tools/call'),
          isEmpty,
        );
        expect(
          container.read(chatProvider).messages.last.content,
          'The tool call was denied.',
        );
      },
      skip: !Platform.isWindows,
    );
  }
}
