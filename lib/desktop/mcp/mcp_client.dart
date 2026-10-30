import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_config.dart';

abstract class McpTransport {
  Stream<Map<String, dynamic>> get messages;
  Future<void> send(Map<String, dynamic> message);
  Future<void> close();
}

class StdioMcpTransport implements McpTransport {
  final Process _process;
  final _messages = StreamController<Map<String, dynamic>>();
  late final StreamSubscription<String> _stdout, _stderr;
  bool _closing = false;
  StdioMcpTransport._(this._process, void Function(String) log) {
    _stdout = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final message = jsonDecode(line);
            if (message is! Map) throw const FormatException();
            _messages.add(Map<String, dynamic>.from(message));
          } catch (_) {
            _messages.addError(const McpException(McpProblem.protocol));
          }
        }, onError: _messages.addError);
    _stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(log);
    _process.exitCode.then((code) async {
      if (!_closing) {
        _messages.addError(McpException(McpProblem.closed, '$code'));
      }
      await _stdout.cancel();
      await _stderr.cancel();
      await _messages.close();
    });
  }
  static Future<StdioMcpTransport> start(
    McpServerConfig config, {
    void Function(String)? log,
  }) async => StdioMcpTransport._(
    await Process.start(
      Platform.isWindows
          ? resolveWindowsCommand(config.command!, config.env)
          : config.command!,
      config.args,
      environment: config.env,
    ),
    log ?? (_) {},
  );

  /// mcp.json files say "npx" or "uvx"; on Windows those are npx.cmd and
  /// uvx.exe, which Process.start only finds with the extension. Searches
  /// PATH with PATHEXT like a shell would; anything else is left as given.
  static String resolveWindowsCommand(
    String command,
    Map<String, String> env, {
    Map<String, String>? system,
    bool Function(String path)? exists,
  }) {
    if (command.contains(RegExp(r'[\\/:]')) || command.contains('.')) {
      return command;
    }
    final base = system ?? Platform.environment;
    String? read(String key) {
      for (final source in [env, base]) {
        for (final e in source.entries) {
          if (e.key.toUpperCase() == key) return e.value;
        }
      }
      return null;
    }

    final found = exists ?? (path) => File(path).existsSync();
    final exts = (read('PATHEXT') ?? '.COM;.EXE;.BAT;.CMD')
        .split(';')
        .where((e) => e.isNotEmpty);
    for (final dir in (read('PATH') ?? '').split(';')) {
      if (dir.trim().isEmpty) continue;
      for (final ext in exts) {
        final candidate = '${dir.trim()}\\$command${ext.toLowerCase()}';
        if (found(candidate)) return candidate;
      }
    }
    return command;
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Future<void> send(Map<String, dynamic> message) async {
    _process.stdin.writeln(jsonEncode(message));
    await _process.stdin.flush();
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    // Do not await stdin.close: a server may never drain its input.
    unawaited(_process.stdin.close().catchError((_) {}));
    try {
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // npx.cmd and friends run the real server as a child: end the tree.
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/T', '/F', '/PID', '${_process.pid}']);
      } else {
        _process.kill();
      }
    }
  }
}

/// Streamable HTTP POST responses can be JSON or SSE. Redirects are never
/// followed, so a loopback endpoint cannot redirect to the public network.
class HttpMcpTransport implements McpTransport {
  final Uri uri;
  final HttpClient _http = HttpClient();
  final _messages = StreamController<Map<String, dynamic>>();
  String? _session;
  String? protocol;
  bool _closed = false;
  HttpMcpTransport(String url) : uri = McpServerConfig.loopback(url) {
    _http.connectionTimeout = const Duration(seconds: 10);
    _http.findProxy = (_) => 'DIRECT';
  }
  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_closed) throw const McpException(McpProblem.closed);
    final request = await _http.postUrl(uri);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json, text/event-stream');
    if (_session != null) request.headers.set('Mcp-Session-Id', _session!);
    if (protocol != null) {
      request.headers.set('MCP-Protocol-Version', protocol!);
    }
    request.write(jsonEncode(message));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpException(McpProblem.protocol, 'HTTP ${response.statusCode}');
    }
    _session ??= response.headers.value('Mcp-Session-Id');
    if (response.statusCode == 202 || response.statusCode == 204) {
      await response.drain<void>();
      return;
    }
    bool emit(String text) {
      final value = jsonDecode(text);
      if (value is! Map) throw const McpException(McpProblem.protocol);
      if (!_closed) _messages.add(Map<String, dynamic>.from(value));
      return message.containsKey('id') &&
          value['id'] == message['id'] &&
          (value.containsKey('result') || value.containsKey('error'));
    }

    if (response.headers.contentType?.mimeType == 'text/event-stream') {
      final data = <String>[];
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (data.isNotEmpty) {
            final complete = emit(data.join('\n'));
            data.clear();
            if (complete) break;
          }
        } else if (line.startsWith('data:')) {
          data.add(line.substring(5).replaceFirst(RegExp(r'^ '), ''));
        }
      }
      if (data.isNotEmpty) emit(data.join('\n'));
    } else {
      emit(await utf8.decoder.bind(response).join());
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _http.close(force: true);
    await _messages.close();
  }
}

class McpClient {
  static const protocolVersion = '2025-03-26';
  final McpTransport transport;
  final Duration timeout;
  final void Function(Object)? onFailure;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  int _id = 0;
  bool _closed = false;
  McpClient(
    this.transport, {
    this.timeout = const Duration(seconds: 30),
    this.onFailure,
  }) {
    _subscription = transport.messages.listen(
      _receive,
      onError: _fail,
      onDone: () {
        if (!_closed) _fail(const McpException(McpProblem.closed));
      },
    );
  }
  void _receive(Map<String, dynamic> message) {
    if (_closed) return;
    if (message['jsonrpc'] != '2.0') {
      _fail(const McpException(McpProblem.protocol));
      return;
    }
    final id = message['id'];
    if (message.containsKey('method')) {
      // Client capabilities are empty. Server requests must receive an error
      // rather than hanging (sampling, roots, elicitation are unsupported).
      if (id != null) {
        unawaited(
          transport
              .send({
                'jsonrpc': '2.0',
                'id': id,
                'error': {'code': -32601, 'message': 'Method not found'},
              })
              .catchError(_fail),
        );
      }
      return;
    }
    final pending = _pending.remove(id);
    if (pending == null) return;
    if (message['error'] != null) {
      pending.completeError(
        McpException(McpProblem.protocol, jsonEncode(message['error'])),
      );
    } else if (message['result'] is Map) {
      pending.complete(Map<String, dynamic>.from(message['result'] as Map));
    } else {
      pending.completeError(const McpException(McpProblem.protocol));
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    _closed = true;
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    onFailure?.call(error);
    unawaited(transport.close());
  }

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_closed) throw const McpException(McpProblem.closed);
    final id = ++_id;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    // Attach the error handler before sending (a process can exit immediately).
    final result = completer.future.timeout(
      timeout,
      onTimeout: () => throw const McpException(McpProblem.timeout),
    );
    unawaited(
      transport
          .send({
            'jsonrpc': '2.0',
            'id': id,
            'method': method,
            'params': params,
          })
          .timeout(timeout)
          .catchError((Object error) {
            final pending = _pending.remove(id);
            pending?.completeError(error);
            if (error is IOException) _fail(error);
          }),
    );
    try {
      return await result;
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> initialize() async {
    final result = await request('initialize', {
      'protocolVersion': protocolVersion,
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'OnDevice LLM', 'version': '1.0.0'},
    });
    final version = result['protocolVersion'];
    if (!const [
      '2024-11-05',
      '2025-03-26',
      '2025-06-18',
      '2025-11-25',
    ].contains(version)) {
      throw const McpException(McpProblem.protocol);
    }
    if (transport is HttpMcpTransport) {
      (transport as HttpMcpTransport).protocol = version as String;
    }
    await transport
        .send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        .timeout(timeout);
  }

  Future<List<Map<String, dynamic>>> listTools() async {
    final tools = <Map<String, dynamic>>[];
    final seen = <String>{};
    String? cursor;
    do {
      final result = await request('tools/list', {'cursor': ?cursor});
      if (result['tools'] is! List) {
        throw const McpException(McpProblem.protocol);
      }
      for (final tool in result['tools'] as List) {
        if (tool is! Map ||
            tool['name'] is! String ||
            (tool['name'] as String).isEmpty ||
            (tool['description'] != null && tool['description'] is! String) ||
            tool['inputSchema'] is! Map) {
          throw const McpException(McpProblem.protocol);
        }
        tools.add(Map<String, dynamic>.from(tool));
      }
      cursor = result['nextCursor'] as String?;
      if (cursor != null && !seen.add(cursor)) {
        throw const McpException(McpProblem.protocol);
      }
    } while (cursor != null);
    return tools;
  }

  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) => request('tools/call', {'name': name, 'arguments': arguments});
  Future<void> close() async {
    _closed = true;
    for (final pending in _pending.values) {
      pending.completeError(const McpException(McpProblem.closed));
    }
    _pending.clear();
    await _subscription.cancel();
    await transport.close();
  }
}
