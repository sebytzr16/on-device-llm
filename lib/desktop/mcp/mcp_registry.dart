import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/logging/quiet_failure.dart';
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
  final _pendingEnables = <String>{};
  final _approvedExecutables = <String, String>{};
  McpConfirmation? confirm, confirmHosted;
  Object? error;
  bool loaded = false, _disposed = false;
  Future<void> _writes = Future.value(), _mutations = Future.value();
  String _raw = '{"mcpServers": {}}';
  String get raw => _raw;

  /// Bind approvals to the configuration without writing a second copy of
  /// its secret-bearing env/args into the permissions file.
  String get _configDigest => sha256.convert(utf8.encode(_raw)).toString();
  String _identity(McpServerConfig config) =>
      sha256.convert(utf8.encode(jsonEncode(config.toJson()))).toString();
  Future<String> _executableApproval(McpServerConfig config) async {
    final path = await File(config.command!).resolveSymbolicLinks();
    final digest = await sha256.bind(File(path).openRead()).first;
    return executableApproval(_identity(config), path, digest);
  }

  bool serverEnabled(String name) {
    final config = servers[name]?.config;
    return !_disposed &&
        !_pendingEnables.contains(name) &&
        !_disabledServers.contains(name) &&
        config != null &&
        (config.command == null || _approvedExecutables.containsKey(name));
  }

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
        // First-run creation uses the same atomic writer: an interruption must
        // not leave unreadable JSON where the config belongs.
        await _write('mcp.json', _raw);
      }
      final parsed = McpServerConfig.parse(_raw);
      final prefs = await _file('mcp-permissions.json');
      var legacyConfig = false;
      // Only a complete snapshot may enable a server: a missing or damaged
      // file must not silently drop the user's saved disables.
      var permissionsIntact = false;
      if (await prefs.exists()) {
        try {
          final j = jsonDecode(await prefs.readAsString());
          final approved = j is Map ? j['approvedExecutables'] : null;
          final disabledServers = j is Map ? j['disabledServers'] : null;
          final disabledTools = j is Map ? j['disabledTools'] : null;
          final allowedTools = j is Map ? j['allowedTools'] : null;
          // Decode the whole snapshot before applying any of it: a malformed
          // field must not keep an executable approval while a later field
          // throws and discards the saved disables.
          final valid =
              approved is Map &&
              approved.keys.every((key) => key is String) &&
              approved.values.every((value) => value is String) &&
              disabledServers is List &&
              disabledServers.every((value) => value is String) &&
              disabledTools is List &&
              disabledTools.every((value) => value is String) &&
              (allowedTools == null ||
                  (allowedTools is List &&
                      allowedTools.every((value) => value is String)));
          if (valid) {
            final allowedToolsList = allowedTools == null
                ? const <String>[]
                : List<String>.from(allowedTools as List);
            _approvedExecutables.addAll({
              for (final entry in approved.entries)
                if ((entry.value as String).startsWith('v2:'))
                  entry.key as String: entry.value as String,
            });
            _disabledServers.addAll(List<String>.from(disabledServers));
            _disabledTools.addAll(List<String>.from(disabledTools));
            legacyConfig = (j as Map).containsKey('config');
            // External edits to mcp.json must invalidate executable/URL trust too.
            if (j['configDigest'] == _configDigest) {
              _allowed.addAll(allowedToolsList);
            }
            permissionsIntact = j['configDigest'] == _configDigest;
          }
        } catch (e, st) {
          // A truncated or hand-edited permissions file must not take every
          // MCP server down with it: it only loses grants, which are asked
          // again, and the next write replaces the damaged file.
          quietFailure('mcp_registry.load:permissions', e, st);
        }
      }
      if (!permissionsIntact) {
        // No complete snapshot means these servers were never reviewed here:
        // keep them off (a URL server has no other review gate) until the user
        // enables them again, and heal the file on the next write.
        _disabledServers.addAll(parsed.keys);
        _approvedExecutables.clear();
        legacyConfig = true;
      }
      if (_disposed) return;
      for (final config in parsed.values) {
        servers[config.name] = McpServerState(config);
      }
      loaded = true;
      _changed();
      // An older build kept the whole raw config, secrets included, here; a
      // damaged snapshot is replaced the same way.
      if (legacyConfig) await _mutate(_preferences);
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
      // Temp + rename like the engine markers: a crash mid-write can never
      // leave a truncated config or permissions file behind.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(contents, flush: true);
      await temp.rename(file.path);
    });
    _writes = next;
    return next;
  }

  Future<void> _preferences({String? grant}) => _write(
    'mcp-permissions.json',
    jsonEncode({
      'approvedExecutables': _approvedExecutables,
      'disabledServers': _disabledServers.toList(),
      'disabledTools': _disabledTools.toList(),
      'allowedTools': {..._allowed, ?grant}.toList(),
      'configDigest': _configDigest,
    }),
  );
  Future<void> saveConfig(String raw) => _mutate(() => _commitConfig(raw));

  /// Permission changes are read-modify-write transactions: run one at a time
  /// so a later snapshot cannot persist a change that an earlier one rolled
  /// back after its write failed.
  Future<void> _mutate(Future<void> Function() body) {
    final next = _mutations.then<void>((_) => body(), onError: (_) => body());
    _mutations = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _commitConfig(String raw, {void Function()? restore}) async {
    final parsed = McpServerConfig.parse(raw);
    final changed = {
      for (final entry in parsed.entries)
        if (servers[entry.key] == null ||
            _identity(servers[entry.key]!.config) != _identity(entry.value))
          entry.key,
    };
    final retired = servers.keys
        .where((name) => changed.contains(name) || !parsed.containsKey(name))
        .toSet();
    await _write('mcp.json', raw);
    if (retired.isNotEmpty) {
      _allowed.removeWhere((tool) {
        final owner = _aliases[tool]?.server;
        if (owner != null) return retired.contains(owner);
        // An unresolved hashed alias cannot be attributed to a server.
        return RegExp(r'^mcp_[0-9a-f]{60}$').hasMatch(tool) ||
            retired.any((name) => tool.startsWith(mcpToolName(name, '')));
      });
    }
    for (final name in retired) {
      _approvedExecutables.remove(name);
    }
    final beforeRestore = restore == null ? null : _allowed.toSet();
    restore?.call();
    _raw = raw;
    try {
      await _preferences();
    } catch (_) {
      // The config file is committed but the permissions file is not: keep a
      // server this edit added or changed from running unreviewed, and
      // publish the committed config before reporting the failure.
      if (beforeRestore != null) _allowed.retainAll(beforeRestore);
      for (final name in changed) {
        _approvedExecutables.remove(name);
        _disabledServers.add(name);
      }
      await _publish(parsed, changed, retired);
      rethrow;
    }
    await _publish(parsed, changed, retired);
  }

  Future<void> _publish(
    Map<String, McpServerConfig> parsed,
    Set<String> changed,
    Set<String> retired,
  ) async {
    if (_disposed) return;
    final old = [for (final name in retired) servers[name]!];
    final next = {
      for (final config in parsed.values)
        config.name: changed.contains(config.name)
            ? McpServerState(config)
            : servers[config.name]!,
    };
    servers
      ..clear()
      ..addAll(next);
    _aliases.removeWhere((_, target) => retired.contains(target.server));
    retired.forEach(_starts.remove);
    error = null;
    loaded = true;
    _changed();
    await Future.wait(
      old.map((s) async {
        await s.client?.close();
      }),
    );
    if (!_disposed) await Future.wait(changed.map(restart));
  }

  /// Returns a one-shot undo that merges this server into the current config.
  Future<Future<void> Function()> remove(String name) async {
    late McpServerConfig config;
    late bool enabled;
    late String? approval;
    late Set<String> disabled, allowed;
    final prefix = mcpToolName(name, '');
    bool belongs(String t) =>
        _aliases[t]?.server == name || t.startsWith(prefix);
    String encode(Iterable<McpServerConfig> configs) =>
        const JsonEncoder.withIndent('  ').convert({
          'mcpServers': {for (final c in configs) c.name: c.toJson()},
        });
    await _mutate(() async {
      config = servers[name]!.config;
      enabled = serverEnabled(name);
      approval = _approvedExecutables[name];
      disabled = _disabledTools.where(belongs).toSet();
      allowed = _allowed.where(belongs).toSet();
      await _commitConfig(
        encode([
          for (final s in servers.values)
            if (s.config.name != name) s.config,
        ]),
      );
    });
    var restored = false;
    return () => _mutate(() async {
      if (restored || _disposed) return;
      if (servers.containsKey(name)) {
        throw const McpException(McpProblem.config);
      }
      await _commitConfig(
        encode([for (final s in servers.values) s.config, config]),
        restore: () {
          enabled ? _disabledServers.remove(name) : _disabledServers.add(name);
          _disabledTools.removeWhere(belongs);
          _disabledTools.addAll(disabled);
          _allowed.addAll(allowed);
          if (approval != null) _approvedExecutables[name] = approval!;
        },
      );
      restored = true;
    });
  }

  Future<void> enableServer(
    String name,
    bool enabled, {
    bool reviewed = false,
  }) async {
    final requested = servers[name]?.config;
    final requestedIdentity = requested == null ? null : _identity(requested);
    var changed = false;
    await _mutate(() async {
      final config = servers[name]?.config;
      if (config == null ||
          _disposed ||
          _identity(config) != requestedIdentity) {
        throw const McpException(McpProblem.unavailable);
      }
      if (enabled && config.command != null && !reviewed) {
        throw const McpException(McpProblem.denied);
      }
      final previousApproval = _approvedExecutables[name];
      final wasDisabled = _disabledServers.contains(name);
      if (enabled && config.command != null) {
        try {
          _approvedExecutables[name] = await _executableApproval(config);
        } on FileSystemException {
          final state = servers[name]!;
          state.error = const McpException(McpProblem.config, 'command');
          state.status = McpStatus.error;
          return;
        }
      }
      if (!enabled) _approvedExecutables.remove(name);
      enabled ? _disabledServers.remove(name) : _disabledServers.add(name);
      if (enabled) _pendingEnables.add(name);
      try {
        await _preferences();
        changed = true;
      } catch (_) {
        if (previousApproval == null) {
          _approvedExecutables.remove(name);
        } else {
          _approvedExecutables[name] = previousApproval;
        }
        wasDisabled
            ? _disabledServers.add(name)
            : _disabledServers.remove(name);
        rethrow;
      } finally {
        _pendingEnables.remove(name);
      }
    });
    _changed();
    if (changed) await restart(name);
  }

  Future<void> enableTool(String name, bool enabled) => _mutate(() async {
    final wasDisabled = _disabledTools.contains(name);
    enabled ? _disabledTools.remove(name) : _disabledTools.add(name);
    _changed();
    try {
      await _preferences();
    } catch (_) {
      wasDisabled ? _disabledTools.add(name) : _disabledTools.remove(name);
      _changed();
      rethrow;
    }
  });

  Future<void> revoke(String name) => _mutate(() async {
    final wasAllowed = _allowed.remove(name);
    _changed();
    try {
      await _preferences();
    } catch (_) {
      if (wasAllowed) _allowed.add(name);
      _changed();
      rethrow;
    }
  });

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
    bool current() =>
        serverEnabled(name) && servers[name] == state && _starts[name] == token;
    McpClient? client;
    try {
      final command = state.config.command;
      final workingDirectory = command == null
          ? null
          : Directory(
              '${(await directory()).path}/mcp-work/${_identity(state.config)}',
            );
      if (!current()) return;
      final approval = _approvedExecutables[name];
      if (command != null && connector != null) {
        if (approval != await _executableApproval(state.config)) {
          throw const McpException(McpProblem.denied);
        }
        if (!current()) return;
      }
      final transport = connector != null
          ? await connector!(state.config)
          : state.config.url != null
          ? HttpMcpTransport(state.config.url!)
          : await StdioMcpTransport.start(
              state.config,
              approved: true,
              verifyLaunch: (path, digest) =>
                  current() &&
                  _approvedExecutables[name] ==
                      executableApproval(_identity(state.config), path, digest),
              workingDirectory: workingDirectory,
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
      for (final tool in tools) {
        final original = tool['name'] as String;
        final alias = mcpToolName(name, original);
        final existing = _aliases[alias];
        if (existing != null && existing != (server: name, tool: original)) {
          throw const McpException(McpProblem.protocol, 'Tool alias collision');
        }
        _aliases[alias] = (server: name, tool: original);
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
  final _aliases = <String, ({String server, String tool})>{};

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
    McpConfirmation? confirmation,
    bool requireHostConfirmation = false,
  }) async {
    final watch = Stopwatch()..start();
    try {
      McpServerState? server;
      String? original;
      final target = _aliases[call.name];
      if (target != null) {
        server = servers[target.server];
        original = target.tool;
      }
      if (server == null ||
          !specs.any((t) => t.name == call.name) ||
          permitted?.call() == false) {
        throw const McpException(McpProblem.unavailable);
      }
      final client = server.client;
      final selected = server;
      bool available() =>
          !_disposed &&
          client != null &&
          selected.client == client &&
          servers[selected.config.name] == selected &&
          permitted?.call() != false &&
          specs.any((s) => s.name == call.name);
      if (!_allowed.contains(call.name) ||
          confirmation != null ||
          requireHostConfirmation) {
        final choice =
            await ((requireHostConfirmation
                            ? confirmHosted
                            : confirmation ?? confirm)
                        ?.call(server.config.name, call) ??
                    Future.value(McpConsent.deny))
                .timeout(
                  const Duration(minutes: 5),
                  onTimeout: () => McpConsent.deny,
                );
        if (choice == McpConsent.deny) {
          throw const McpException(McpProblem.denied);
        }
        if (choice == McpConsent.always && !requireHostConfirmation) {
          await _mutate(() async {
            if (!available()) {
              throw const McpException(McpProblem.unavailable);
            }
            await _preferences(grant: call.name);
            _allowed.add(call.name);
            _changed();
          });
        }
      }
      if (client == null || !available()) {
        throw const McpException(McpProblem.unavailable);
      }
      final cancelWatch = permitted == null
          ? null
          : Timer.periodic(const Duration(milliseconds: 50), (_) {
              if (!permitted()) client.cancelPending();
            });
      final Map<String, dynamic> result;
      try {
        result = await client.callTool(original!, call.args);
      } finally {
        cancelWatch?.cancel();
      }
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
    confirmHosted = null;
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
