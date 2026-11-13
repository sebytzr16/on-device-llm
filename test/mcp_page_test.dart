import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_page.dart';
import 'mcp_test.dart' show FakeMcpTransport;
import 'package:ondevice_llm/desktop/mcp/mcp_registry.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

void main() {
  final t = AppLocalizationsEn();
  const call = ToolCall(
    id: 'c1',
    name: 'fixture__echo',
    arguments: '{"camelCase": "Hello"}',
  );
  for (final choice in McpConsent.values) {
    testWidgets(
      'confirmation dialog displays server, tool, arguments and ${choice.name}',
      (tester) async {
        McpConsent? answer;
        await tester.pumpWidget(
          MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    answer = await confirmMcpCall(
                      context,
                      'fixture',
                      call.name,
                      const JsonEncoder.withIndent('  ').convert(call.args),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('fixture'), findsOneWidget);
        expect(find.text(call.name), findsOneWidget);
        expect(
          find.text(const JsonEncoder.withIndent('  ').convert(call.args)),
          findsOneWidget,
        );
        await tester.tap(
          find.text(switch (choice) {
            McpConsent.once => t.mcpOnce,
            McpConsent.always => t.mcpAlways,
            McpConsent.deny => t.mcpDeny,
          }),
        );
        await tester.pumpAndSettle();
        expect(answer, choice);
      },
    );
  }

  testWidgets('stdio enable requires a separate trusted-code warning', (
    tester,
  ) async {
    // Real file IO must run outside the widget test's fake async zone.
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('mcp-page-review-'),
    ))!;
    var starts = 0;
    final registry = McpRegistry(
      directory: () async => dir,
      connector: (_) async {
        starts++;
        return FakeMcpTransport();
      },
    );
    addTearDown(() async {
      registry.dispose();
      await dir.delete(recursive: true);
    });
    await tester.runAsync(
      () => registry.saveConfig(
        '{"mcpServers":{"fixture":{"command":"preinstalled"}}}',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mcpRegistryProvider.overrideWithValue(registry)],
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          home: const Scaffold(body: DesktopMcpPage()),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text(t.mcpExecutableWarning), findsOneWidget);
    expect(starts, 0);
    await tester.tap(find.text(t.mcpDeny));
    await tester.pumpAndSettle();
    expect(starts, 0);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.mcpEnableExecutable));
    for (var i = 0; i < 20 && starts == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(starts, 1);
  });

  testWidgets('MCP page validates raw JSON before saving', (tester) async {
    final registry = McpRegistry(
      directory: () async => throw StateError('must not write invalid config'),
    );
    registry.loaded = true;
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mcpRegistryProvider.overrideWithValue(registry)],
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          home: const Scaffold(body: DesktopMcpPage()),
        ),
      ),
    );
    await tester.tap(find.text(t.mcpEdit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{');
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(find.text(t.mcpConfigError), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
