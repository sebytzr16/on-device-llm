import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/platform/desktop_host.dart';
import '../../core/storage/app_directories.dart';
import '../../features/tools/domain/tool_spec.dart';
import 'mcp_client.dart';
import 'mcp_config.dart';

enum McpStatus { disabled, connecting, ready, error }

enum McpConsent { once, always, deny }

typedef McpConfirmation =
    Future<McpConsent> Function(String server, ToolCall call);
typedef McpConnector = Future<McpTransport> Function(McpServerConfig config);

class McpServerState {
  final McpServerConfig config;
  McpStatus status = McpStatus.disabled;
  Object? error;
  McpClient? client;
  List<Map<String, dynamic>> tools = [];
  McpServerState(this.config);
}

/// One Windows-only owner for processes, discovery and consent. ToolRunner
/// snapshots specs, but dispatch rechecks live state after every confirmation.
class McpRegistry extends ChangeNotifier {
  final Future<Directory> Function() directory;
  final McpConnector? connector;
  final Duration timeout;
  McpRegistry({
    required this.directory,
    this.connector,
    this.timeout = const Duration(seconds: 30),
  });
  final servers = <String, McpServerState>{};
  final _disabledServers = <String>{},
      _disabledTools = <String>{},
      _allowed = <String>{};
  McpConfirmation? confirm;
  Object? error;
  bool loaded = false, _disposed = false;
  Future<void> _writes = Future.value();
  String _raw = '{"mcpServers": {}}';
  String get raw => _raw;
  bool serverEnabled(String name) => !_disabledServers.contains(name);
  bool toolEnabled(String name) => !_disabledTools.contains(name);
  bool alwaysAllowed(String name) => _allowed.contains(name);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<File> _file(String name) async {
    final dir = await directory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  Future<void> load() async {
    try {
      final config = await _file('mcp.json');
      if (await config.exists()) {
        _raw = await config.readAsString();
      } else {
        await config.writeAsString(_raw, flush: true);
      }
      final parsed = McpServerConfig.parse(_raw);
      final prefs = await _file('mcp-permissions.json');
      if (await prefs.exists()) {
        final j = jsonDecode(await prefs.readAsString()) as Map;
        _disabledServers.addAll(List<String>.from(j['disabledServers'] ?? []));
        _disabledTools.addAll(List<String>.from(j['disabledTools'] ?? []));
        // External edits to mcp.json must invalidate executable/URL trust too.
        if (j['config'] == _raw) {
          _allowed.addAll(List<String>.from(j['allowedTools'] ?? []));
        }
      }
      if (_disposed) return;
      for (final config in parsed.values) {
        servers[config.name] = McpServerState(config);
      }
      loaded = true;
      _changed();
      await Future.wait(servers.keys.toList().map(restart));
    } catch (e) {
      error = e;
      loaded = true;
      _changed();
    }
  }

  Future<void> _write(String name, String contents) {
    final next = _writes.catchError((_) {}).then((_) async {
      final file = await _file(name);
      await file.writeAsString(contents, flush: true);
    });
    _writes = next;
    return next;
  }

  Future<void> _preferences() => _write(
    'mcp-permissions.json',
    jsonEncode({
      'disabledServers': _disabledServers.toList(),
      'disabledTools': _disabledTools.toList(),
      'allowedTools': _allowed.toList(),
      'config': _raw,
    }),
  );
  Future<void> saveConfig(String raw) => _saveConfig(raw);

  Future<void> _saveConfig(String raw, {bool clearApprovals = true}) async {
    final parsed = McpServerConfig.parse(raw);
    await _write('mcp.json', raw);
    // Changes to executable/URL invalidate trust, including old tool grants.
    if (clearApprovals) _allowed.clear();
    _raw = raw;
    await _preferences();
    final old = servers.values.toList();
    servers.clear();
    for (final config in parsed.values) {
      servers[config.name] = McpServerState(config);
    }
    _raw = raw;
    error = null;
    loaded = true;
    _changed();
    await Future.wait(
      old.map((s) async {
        await s.client?.close();
      }),
    );
    if (!_disposed) await Future.wait(servers.keys.toList().map(restart));
  }

  /// Returns a one-shot undo that merges this server into the current config.
  Future<Future<void> Function()> remove(String name) async {
    final config = servers[name]!.config;
    final enabled = serverEnabled(name);
    final prefix = mcpToolName(name, '');
    final disabled = _disabledTools.where((t) => t.startsWith(prefix)).toSet();
    final allowed = _allowed.where((t) => t.startsWith(prefix)).toSet();
    String encode(Iterable<McpServerConfig> configs) =>
        const JsonEncoder.withIndent('  ').convert({
          'mcpServers': {for (final c in configs) c.name: c.toJson()},
        });
    await _saveConfig(
      encode([
        for (final s in servers.values)
          if (s.config.name != name) s.config,
      ]),
      clearApprovals: false,
    );
    var restored = false;
    return () async {
      if (restored || _disposed) return;
      if (servers.containsKey(name)) {
        throw const McpException(McpProblem.config);
      }
      enabled ? _disabledServers.remove(name) : _disabledServers.add(name);
      _disabledTools.removeWhere((t) => t.startsWith(prefix));
      _disabledTools.addAll(disabled);
      _allowed.addAll(allowed);
      await _saveConfig(
        encode([for (final s in servers.values) s.config, config]),
        clearApprovals: false,
      );
      restored = true;
    };
  }

  Future<void> enableServer(String name, bool enabled) async {
    enabled ? _disabledServers.remove(name) : _disabledServers.add(name);
    _changed();
    await _preferences();
    await restart(name);
  }

  Future<void> enableTool(String name, bool enabled) async {
    enabled ? _disabledTools.remove(name) : _disabledTools.add(name);
    _changed();
    await _preferences();
  }

  Future<void> revoke(String name) async {
    _allowed.remove(name);
    _changed();
    await _preferences();
  }

  Future<void> restart(String name) async {
    final state = servers[name];
    if (state == null || _disposed) return;
    // An identity token also prevents two overlapping restarts from publishing
    // the older process or its tools.
    final token = Object();
    _starts[name] = token;
    final old = state.client;
    state.client = null;
    state.tools = [];
    state.error = null;
    state.status = serverEnabled(name)
        ? McpStatus.connecting
        : McpStatus.disabled;
    _changed();
    await old?.close();
    if (!serverEnabled(name) ||
        _disposed ||
        servers[name] != state ||
        _starts[name] != token) {
      return;
    }
    McpClient? client;
    try {
      final transport = connector != null
          ? await connector!(state.config)
          : state.config.url != null
          ? HttpMcpTransport(state.config.url!)
          : await StdioMcpTransport.start(
              state.config,
              log: (line) => Logger('MCP.$name').info(line),
            );
      client = McpClient(
        transport,
        timeout: timeout,
        onFailure: (e) {
          if (state.client != client || _disposed) return;
          state.status = McpStatus.error;
          state.error = e;
          state.tools = [];
          Logger('MCP.$name').warning(e);
          _changed();
        },
      );
      if (_disposed ||
          servers[name] != state ||
          !serverEnabled(name) ||
          _starts[name] != token) {
        await client.close();
        return;
      }
      state.client = client;
      await client.initialize();
      final tools = await client.listTools();
      if (_disposed ||
          servers[name] != state ||
          !serverEnabled(name) ||
          state.client != client) {
        await client.close();
        return;
      }
      final names = <String>{};
      if (tools.any((t) => !names.add(t['name'] as String))) {
        throw const McpException(McpProblem.protocol);
      }
      state.tools = tools;
      state.status = McpStatus.ready;
      _changed();
    } catch (e) {
      if (!_disposed && servers[name] == state && _starts[name] == token) {
        state.tools = [];
        state.status = McpStatus.error;
        state.error = e;
        _changed();
      }
      await client?.close();
    }
  }

  final _starts = <String, Object>{};

  List<ToolSpec> get specs => [
    for (final s in servers.values)
      if (serverEnabled(s.config.name) && s.status == McpStatus.ready)
        for (final tool in s.tools)
          if (toolEnabled(mcpToolName(s.config.name, tool['name'] as String)))
            ToolSpec(
              name: mcpToolName(s.config.name, tool['name'] as String),
              description:
                  '${s.config.name}: ${tool['description'] ?? tool['name']}',
              parameters: Map<String, dynamic>.from(tool['inputSchema'] as Map),
            ),
  ];

  Future<ToolResult> call(
    ToolCall call, {
    required String Function(Object) explain,
    required String unsupportedContent,
    bool Function()? permitted,
  }) async {
    final watch = Stopwatch()..start();
    try {
      McpServerState? server;
      String? original;
      for (final s in servers.values) {
        for (final tool in s.tools) {
          if (mcpToolName(s.config.name, tool['name'] as String) == call.name) {
            server = s;
            original = tool['name'] as String;
          }
        }
      }
      if (server == null ||
          !specs.any((t) => t.name == call.name) ||
          permitted?.call() == false) {
        throw const McpException(McpProblem.unavailable);
      }
      final client = server.client;
      if (!_allowed.contains(call.name)) {
        final choice =
            await (confirm?.call(server.config.name, call) ??
                    Future.value(McpConsent.deny))
                .timeout(
                  const Duration(minutes: 5),
                  onTimeout: () => McpConsent.deny,
                );
        if (choice == McpConsent.deny) {
          throw const McpException(McpProblem.denied);
        }
        if (choice == McpConsent.always) {
          // Persist only if approval still applies to this exact process/config.
          if (server.client != client ||
              servers[server.config.name] != server) {
            throw const McpException(McpProblem.unavailable);
          }
          _allowed.add(call.name);
          try {
            await _preferences();
          } catch (_) {
            _allowed.remove(call.name);
            rethrow;
          }
          _changed();
        }
      }
      if (_disposed ||
          server.client != client ||
          client == null ||
          servers[server.config.name] != server ||
          permitted?.call() == false ||
          !specs.any((s) => s.name == call.name)) {
        throw const McpException(McpProblem.unavailable);
      }
      final result = await client.callTool(original!, call.args);
      final content = result['content'];
      final output = <String>[];
      if (content is List) {
        for (final item in content) {
          if (item is Map && item['type'] == 'text' && item['text'] is String) {
            output.add(item['text'] as String);
          } else {
            output.add(unsupportedContent);
          }
        }
      }
      if (result['structuredContent'] != null) {
        output.add(jsonEncode(result['structuredContent']));
      }
      var text = output.join('\n');
      if (text.length > 6000) text = text.substring(0, 6000);
      return ToolResult(
        call: call,
        output: text,
        ok: result['isError'] != true,
        elapsedMs: watch.elapsedMilliseconds,
      );
    } catch (e) {
      return ToolResult(
        call: call,
        output: explain(e),
        ok: false,
        elapsedMs: watch.elapsedMilliseconds,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    confirm = null;
    for (final s in servers.values) {
      unawaited(s.client?.close() ?? Future.value());
    }
    servers.clear();
    super.dispose();
  }
}

final mcpRegistryProvider = Provider<McpRegistry>((ref) {
  final registry = McpRegistry(directory: appDataDirectory);
  if (DesktopHost.active && Platform.isWindows) unawaited(registry.load());
  ref.onDispose(registry.dispose);
  return registry;
});
