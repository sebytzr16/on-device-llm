import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/app_design.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/focus_ring.dart';
import 'package:ondevice_llm/desktop/load_progress.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_config.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_page.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_registry.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

import 'mcp_test.dart' show FakeMcpTransport;

class _Models extends ModelManagerNotifier {
  final ModelManagerState initial;
  _Models(this.initial);
  @override
  ModelManagerState build() => initial;
}

class _Registry extends McpRegistry {
  bool restored = false;
  _Registry() : super(directory: () async => throw StateError('no IO')) {
    loaded = true;
    servers['fixture'] = McpServerState(
      const McpServerConfig(name: 'fixture', command: 'fixture'),
    );
  }
  @override
  Future<Future<void> Function()> remove(String name) async {
    servers.remove(name);
    notifyListeners();
    return () async => restored = true;
  }
}

void main() {
  final t = AppLocalizationsEn();
  test('load phases follow bridge boundaries and gate the projector', () {
    for (final value in [null, 0.0]) {
      expect(desktopLoadPhase(value), DesktopLoadPhase.preparing);
    }
    for (final value in [0.001, 0.5, 0.85, 0.899]) {
      expect(desktopLoadPhase(value), DesktopLoadPhase.weights);
    }
    for (final value in [0.9, 0.969]) {
      expect(
        desktopLoadPhase(value, hasProjector: true),
        DesktopLoadPhase.context,
      );
    }
    expect(desktopLoadPhase(0.97), DesktopLoadPhase.finishing);
    expect(
      desktopLoadPhase(0.97, hasProjector: true),
      DesktopLoadPhase.projector,
    );
    expect(desktopLoadPhase(1, hasProjector: true), DesktopLoadPhase.done);
    expect(desktopLoadPhase(1), DesktopLoadPhase.done);
  });

  testWidgets('preparing has an indeterminate bar and no zero percent', (
    tester,
  ) async {
    for (final value in [null, 0.0, 0.5, 0.9, 0.97, 1.0]) {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(value),
          overrides: [
            modelManagerProvider.overrideWith(
              () => _Models(
                ModelManagerState(isLoadingModel: true, loadProgress: value),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ModelLoadProgress(compact: true)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, value == null || value == 0 ? isNull : value);
      expect(find.text('0%'), findsNothing);
      expect(
        find.text(switch (desktopLoadPhase(value)) {
          DesktopLoadPhase.preparing => t.desktopLoadPhasePreparing,
          DesktopLoadPhase.weights => t.desktopLoadPhaseWeights('50%'),
          DesktopLoadPhase.context => t.desktopLoadPhaseContext,
          DesktopLoadPhase.finishing => t.desktopLoadPhaseFinishing,
          DesktopLoadPhase.done => t.desktopLoadPhaseDone,
          DesktopLoadPhase.projector => t.desktopLoadPhaseProjector,
        }),
        findsOneWidget,
      );
    }
  });

  test(
    'MCP undo restores config and switches, persists, and preserves later edits',
    () async {
      final dir = await Directory.systemTemp.createTemp('desktop-mcp-undo-');
      addTearDown(() => dir.delete(recursive: true));
      McpRegistry create() => McpRegistry(
        directory: () async => dir,
        connector: (_) async => FakeMcpTransport(),
      );
      final registry = create();
      addTearDown(registry.dispose);
      await registry.load();
      await registry.saveConfig(
        '{"mcpServers":{"fixture":{"command":"fixture","args":["a","b"],"env":{"X":"Y"}}}}',
      );
      final original = registry.servers['fixture']!.config.toJson();
      await registry.enableTool('fixture__echo', false);
      await registry.enableServer('fixture', false);
      final undo = await registry.remove('fixture');
      expect(registry.servers, isEmpty);
      await registry.saveConfig('{"mcpServers":{"later":{"command":"later"}}}');
      await undo();
      expect(registry.servers.keys, containsAll(['fixture', 'later']));
      expect(registry.servers['fixture']!.config.toJson(), original);
      expect(registry.serverEnabled('fixture'), isFalse);
      expect(registry.toolEnabled('fixture__echo'), isFalse);
      expect(registry.toolEnabled('fixture__other'), isTrue);
      expect(registry.servers['fixture']!.status, McpStatus.disabled);
      await undo();
      final reloaded = create();
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.servers['fixture']!.config.toJson(), original);
      expect(reloaded.serverEnabled('fixture'), isFalse);
      expect(reloaded.toolEnabled('fixture__echo'), isFalse);
      await registry.enableServer('fixture', true);
      expect(registry.servers['fixture']!.status, McpStatus.ready);
      expect(registry.specs.where((s) => s.name == 'fixture__echo'), isEmpty);
    },
  );

  test(
    'MCP undo reconnects an enabled server and rejects a replacement',
    () async {
      final dir = await Directory.systemTemp.createTemp('desktop-mcp-enabled-');
      addTearDown(() => dir.delete(recursive: true));
      final registry = McpRegistry(
        directory: () async => dir,
        connector: (_) async => FakeMcpTransport(),
      );
      addTearDown(registry.dispose);
      await registry.load();
      await registry.saveConfig(
        '{"mcpServers":{"fixture":{"command":"original"}}}',
      );
      final undo = await registry.remove('fixture');
      await undo();
      expect(registry.serverEnabled('fixture'), isTrue);
      expect(registry.servers['fixture']!.status, McpStatus.ready);
      expect(registry.specs.single.name, 'fixture__echo');
      final secondUndo = await registry.remove('fixture');
      await registry.saveConfig(
        '{"mcpServers":{"fixture":{"command":"replacement"}}}',
      );
      await expectLater(secondUndo(), throwsA(isA<McpException>()));
      expect(registry.servers['fixture']!.config.command, 'replacement');
    },
  );

  testWidgets('server removal offers a working Undo action', (tester) async {
    final registry = _Registry();
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
    await tester.tap(find.text(t.mcpRemove));
    await tester.pumpAndSettle();
    expect(find.text(t.desktopMcpUndoRemoved), findsOneWidget);
    await tester.tap(find.text(t.desktopMcpUndoAction));
    await tester.pumpAndSettle();
    expect(registry.restored, isTrue);
  });

  testWidgets('custom control exposes its label and paints keyboard focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopFocusRing(
            label: 'Model picker',
            child: InkWell(
              focusNode: node,
              onTap: () {},
              child: const Icon(Icons.memory),
            ),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Model picker'), findsOneWidget);
    node.requestFocus();
    await tester.pumpAndSettle();
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(DesktopFocusRing),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (container.foregroundDecoration! as BoxDecoration).border,
      Border.all(color: AppColors.light.accent, width: 2),
    );
    semantics.dispose();
  });

  test('light faint body text meets 4.5:1 on desktop surfaces and hover', () {
    final c = AppColors.light;
    for (final base in [
      c.ink,
      c.surface,
      c.surfaceRaised,
      c.surfaceOverlay,
      DesktopTheme.contentLayer(c),
    ]) {
      for (final background in [
        base,
        Color.alphaBlend(c.text.fade(0.08), base),
        Color.alphaBlend(c.accent.fade(0.12), base),
      ]) {
        final a = c.textFaint.computeLuminance();
        final b = background.computeLuminance();
        expect((b + 0.05) / (a + 0.05), greaterThanOrEqualTo(4.5));
      }
    }
  });
}
