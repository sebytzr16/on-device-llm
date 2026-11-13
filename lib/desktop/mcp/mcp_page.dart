import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../../core/design/app_dialog.dart';
import '../../core/island/status_island.dart';
import '../../core/l10n/l10n.dart';
import '../../core/motion/spring_controls.dart';
import '../developer_widgets.dart';
import 'mcp_config.dart';
import 'mcp_registry.dart';
import 'mcp_strings.dart';

Future<McpConsent> confirmMcpCall(
  BuildContext context,
  String server,
  String tool,
  String arguments,
) async {
  final t = context.l10n;
  return await showAppDialog<McpConsent>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: Text(t.mcpConfirm),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server, style: context.text.title),
                  const SizedBox(height: 8),
                  SelectableText(tool, style: context.text.mono),
                  const SizedBox(height: 16),
                  SelectableText(arguments, style: context.text.mono),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, McpConsent.deny),
              child: Text(t.mcpDeny),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialog, McpConsent.always),
              child: Text(t.mcpAlways),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, McpConsent.once),
              child: Text(t.mcpOnce),
            ),
          ],
        ),
      ) ??
      McpConsent.deny;
}

class DesktopMcpPage extends ConsumerWidget {
  const DesktopMcpPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(mcpRegistryProvider);
    final t = context.l10n;
    Future<void> act(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(mcpExplain(t, e))));
        }
      }
    }

    Future<void> edit() async {
      final text = await promptText(
        context,
        title: t.mcpEdit,
        initial: registry.raw,
        confirmLabel: t.save,
        minLines: 12,
        maxLines: 24,
        selectAll: false,
        style: context.text.mono,
        validate: (value) {
          try {
            McpServerConfig.parse(value);
            return null;
          } catch (e) {
            return mcpExplain(t, e);
          }
        },
      );
      if (text != null) await act(() => registry.saveConfig(text));
    }

    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DeveloperPageHeader(title: t.mcpTitle, subtitle: t.mcpHint),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DeveloperButton(
                label: t.mcpAdd,
                icon: Icons.add,
                primary: true,
                onPressed: registry.loaded
                    ? () async {
                        final result = await showAppDialog<String>(
                          context: context,
                          builder: (_) => _AddServer(existing: registry),
                        );
                        if (result != null) {
                          await act(() => registry.saveConfig(result));
                        }
                      }
                    : null,
              ),
              DeveloperButton(
                label: t.mcpEdit,
                icon: Icons.code,
                onPressed: registry.loaded ? edit : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!registry.loaded) const LinearProgressIndicator(),
          if (registry.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SelectableText(
                mcpExplain(t, registry.error!),
                style: TextStyle(color: context.colors.danger),
              ),
            ),
          if (registry.loaded && registry.servers.isEmpty)
            Text(t.mcpEmpty, style: context.text.bodyMuted),
          for (final server in registry.servers.values) ...[
            DeveloperCard(
              title: server.config.name,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: switch (server.status) {
                        McpStatus.ready => Colors.green,
                        McpStatus.error => context.colors.danger,
                        McpStatus.connecting => context.colors.accent,
                        McpStatus.disabled => context.colors.textFaint,
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(switch (server.status) {
                      McpStatus.ready => t.mcpReady,
                      McpStatus.error => t.mcpErrorStatus,
                      McpStatus.connecting => t.mcpConnecting,
                      McpStatus.disabled => t.mcpDisabled,
                    }),
                    const SizedBox(width: 16),
                    Text(t.mcpTools(server.tools.length)),
                    const Spacer(),
                    Semantics(
                      label: server.config.name,
                      child: Switch(
                        value: registry.serverEnabled(server.config.name),
                        onChanged: (v) => act(() async {
                          if (v && server.config.command != null) {
                            final approved = await showAppDialog<bool>(
                              context: context,
                              builder: (dialog) => AlertDialog(
                                title: Text(t.mcpExecutableReview),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(t.mcpExecutableWarning),
                                      const SizedBox(height: 16),
                                      SelectableText(
                                        jsonEncode(server.config.toJson()),
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialog, false),
                                    child: Text(t.mcpDeny),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialog, true),
                                    child: Text(t.mcpEnableExecutable),
                                  ),
                                ],
                              ),
                            );
                            if (approved != true) return;
                          }
                          if (registry.servers[server.config.name] != server) {
                            throw const McpException(McpProblem.denied);
                          }
                          await registry.enableServer(
                            server.config.name,
                            v,
                            reviewed: v,
                          );
                        }),
                      ),
                    ),
                  ],
                ),
                if (server.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SelectableText(
                      mcpExplain(t, server.error!),
                      style: TextStyle(color: context.colors.danger),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DeveloperButton(
                      label: t.mcpRestart,
                      icon: Icons.refresh,
                      onPressed: server.status == McpStatus.connecting
                          ? null
                          : () =>
                                act(() => registry.restart(server.config.name)),
                    ),
                    DeveloperButton(
                      label: t.mcpRemove,
                      icon: Icons.delete_outline,
                      onPressed: () => act(() async {
                        final undo = await registry.remove(server.config.name);
                        if (!context.mounted) return;
                        showIslandToast(
                          context,
                          t.desktopMcpUndoRemoved,
                          action: IslandAction(
                            t.desktopMcpUndoAction,
                            () => act(undo),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                for (final tool in server.tools) ...[
                  const Divider(height: 24),
                  // The card is a coloured box: give the tile its own
                  // Material so ink and background stay visible.
                  Material(
                    type: MaterialType.transparency,
                    child: SpringSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tool['name'] as String,
                        style: context.text.mono,
                      ),
                      subtitle: Text(tool['description'] as String? ?? ''),
                      value: registry.toolEnabled(
                        mcpToolName(server.config.name, tool['name'] as String),
                      ),
                      onChanged: (v) => act(
                        () => registry.enableTool(
                          mcpToolName(
                            server.config.name,
                            tool['name'] as String,
                          ),
                          v,
                        ),
                      ),
                    ),
                  ),
                  if (registry.alwaysAllowed(
                    mcpToolName(server.config.name, tool['name'] as String),
                  ))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DeveloperButton(
                        label: t.mcpRevoke,
                        onPressed: () => act(
                          () => registry.revoke(
                            mcpToolName(
                              server.config.name,
                              tool['name'] as String,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _AddServer extends StatefulWidget {
  final McpRegistry existing;
  const _AddServer({required this.existing});
  @override
  State<_AddServer> createState() => _AddServerState();
}

class _AddServerState extends State<_AddServer> {
  final _name = TextEditingController(),
      _command = TextEditingController(),
      _args = TextEditingController(text: '[]'),
      _env = TextEditingController(text: '{}');
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _command, _args, _env]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    try {
      final name = _name.text.trim();
      if (widget.existing.servers.containsKey(name)) {
        throw const McpException(McpProblem.config);
      }
      final json = const JsonEncoder.withIndent('  ').convert({
        'mcpServers': {
          for (final server in widget.existing.servers.values)
            server.config.name: server.config.toJson(),
          name: {
            'command': _command.text.trim(),
            'args': jsonDecode(_args.text),
            'env': jsonDecode(_env.text),
          },
        },
      });
      McpServerConfig.parse(json);
      Navigator.pop(context, json);
    } catch (e) {
      setState(
        () => _error = mcpExplain(
          context.l10n,
          e is FormatException ? const McpException(McpProblem.config) : e,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return AlertDialog(
      title: Text(t.mcpAdd),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in [
                (_name, t.mcpName),
                (_command, t.mcpCommand),
                (_args, t.mcpArgs),
                (_env, t.mcpEnv),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextField(
                    controller: entry.$1,
                    autofocus: entry.$1 == _name,
                    minLines: 1,
                    maxLines: entry.$1 == _env ? 5 : 3,
                    decoration: InputDecoration(labelText: entry.$2),
                  ),
                ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: context.colors.danger)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(t.mcpAdd)),
      ],
    );
  }
}
