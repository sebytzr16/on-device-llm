import 'dart:convert';

/// Validation codes are translated by the desktop host.
enum McpProblem {
  config,
  loopback,
  protocol,
  closed,
  timeout,
  unavailable,
  denied,
}

class McpException implements Exception {
  final McpProblem problem;
  final String detail;
  const McpException(this.problem, [this.detail = '']);
  @override
  String toString() => '${problem.name}: $detail';
}

class McpServerConfig {
  final String name;
  final String? command, url;
  final List<String> args;
  final Map<String, String> env;
  const McpServerConfig({
    required this.name,
    this.command,
    this.url,
    this.args = const [],
    this.env = const {},
  });

  static Uri loopback(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'http' ||
        !const ['127.0.0.1', 'localhost'].contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const McpException(McpProblem.loopback);
    }
    return uri;
  }

  static Map<String, McpServerConfig> parse(String text) {
    try {
      final root = jsonDecode(text);
      if (root is! Map || root['mcpServers'] is! Map) {
        throw const McpException(McpProblem.config);
      }
      final result = <String, McpServerConfig>{};
      for (final entry in (root['mcpServers'] as Map).entries) {
        final name = entry.key;
        final v = entry.value;
        if (name is! String ||
            name.trim().isEmpty ||
            v is! Map ||
            (v.containsKey('command') == v.containsKey('url'))) {
          throw const McpException(McpProblem.config);
        }
        final args = v['args'] ?? <String>[];
        final env = v['env'] ?? <String, String>{};
        if (args is! List ||
            args.any((x) => x is! String) ||
            env is! Map ||
            env.entries.any((e) => e.key is! String || e.value is! String)) {
          throw const McpException(McpProblem.config);
        }
        final url = v['url'];
        final command = v['command'];
        if (url != null) {
          if (url is! String) throw const McpException(McpProblem.config);
          loopback(url);
        } else if (command is! String || command.trim().isEmpty) {
          throw const McpException(McpProblem.config);
        }
        result[name] = McpServerConfig(
          name: name,
          command: command as String?,
          url: url as String?,
          args: List<String>.from(args),
          env: Map<String, String>.from(env),
        );
      }
      return result;
    } on McpException {
      rethrow;
    } catch (_) {
      throw const McpException(McpProblem.config);
    }
  }

  Map<String, Object> toJson() => {
    if (url != null)
      'url': url!
    else ...{
      'command': command!,
      'args': args,
      'env': env,
    },
  };
}

/// Escape every non-alphanumeric byte, including underscores. This is
/// injective even for names containing the namespace separator.
String mcpToolName(String server, String tool) {
  String encode(String s) => utf8
      .encode(s)
      .map(
        (b) =>
            (b >= 48 && b <= 57) ||
                (b >= 65 && b <= 90) ||
                (b >= 97 && b <= 122)
            ? String.fromCharCode(b)
            : '_${b.toRadixString(16).padLeft(2, '0')}',
      )
      .join();
  return '${encode(server)}__${encode(tool)}';
}
