import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/platform/child_process_job.dart';
import 'mcp_config.dart';

abstract class McpTransport {
  /// Largest message or SSE event accepted from a server before decoding.
  static const maxMessageBytes = 4 * 1024 * 1024;
  Stream<Map<String, dynamic>> get messages;
  Future<void> send(Map<String, dynamic> message);
  Future<void> close();
}

/// Splits UTF-8 [bytes] into lines while bounding the buffered bytes of one
/// line, so a broken server cannot make the client buffer without limit.
Stream<String> mcpLines(Stream<List<int>> bytes) async* {
  final pending = BytesBuilder(copy: false);
  void add(List<int> part) {
    if (pending.length + part.length > McpTransport.maxMessageBytes) {
      throw const McpException(McpProblem.protocol);
    }
    pending.add(part);
  }

  await for (final chunk in bytes) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0a) continue;
      add(chunk.sublist(start, i));
      yield _decodeLine(pending.takeBytes());
      start = i + 1;
    }
    if (start < chunk.length) add(chunk.sublist(start));
  }
  if (pending.length > 0) yield _decodeLine(pending.takeBytes());
}

String _decodeLine(Uint8List bytes) {
  var end = bytes.length;
  if (end > 0 && bytes[end - 1] == 0x0d) end--;
  try {
    return utf8.decode(bytes.sublist(0, end));
  } on FormatException {
    throw const McpException(McpProblem.protocol);
  }
}

class StdioMcpTransport implements McpTransport {
  final Process _process;
  final _messages = StreamController<Map<String, dynamic>>();
  late final StreamSubscription<String> _stdout, _stderr;
  bool _closing = false;
  Future<void> _sends = Future.value();
  StdioMcpTransport._(this._process, void Function(String) log) {
    _stdout = mcpLines(_process.stdout).listen((line) {
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
    bool approved = false,
    Directory? workingDirectory,
  }) async {
    if (!approved || workingDirectory == null) {
      throw const McpException(McpProblem.denied);
    }
    final command = config.command!;
    // No PATH search, package downloaders or shell command wrappers at launch.
    final executable = p.basenameWithoutExtension(command).toLowerCase();
    if (!p.isAbsolute(command) ||
        !await File(command).exists() ||
        const [
          'npx',
          'npm',
          'uvx',
          'uv',
          'pip',
          'pip3',
          'cmd',
          'powershell',
          'pwsh',
          'sh',
          'bash',
          'wscript',
          'cscript',
        ].contains(executable) ||
        (Platform.isWindows && !command.toLowerCase().endsWith('.exe'))) {
      throw const McpException(McpProblem.config);
    }
    await workingDirectory.create(recursive: true);
    final resolvedCommand = Platform.isWindows
        ? resolveWindowsCommand(config.command!, config.env)
        : config.command!;
    if (Platform.isWindows) {
      validateWindowsBatchArgs(resolvedCommand, config.args);
    }
    final process = await Process.start(
      resolvedCommand,
      config.args,
      workingDirectory: workingDirectory.absolute.path,
      includeParentEnvironment: false,
      environment: launchEnvironment(
        config.env,
        workingDirectory.absolute.path,
      ),
    );
    ChildProcessJob.adopt(process);
    // Stderr is not logged by default (S11). Pass a logger only when
    // developer/debug logging is explicitly enabled.
    return StdioMcpTransport._(process, log ?? (_) {});
  }

  /// Only OS bootstrap variables and explicitly configured server values.
  /// Redirect home/temp to the dedicated root; cwd is not an OS sandbox.
  static Map<String, String> launchEnvironment(
    Map<String, String> configured,
    String root, {
    Map<String, String>? system,
  }) {
    final base = system ?? Platform.environment;
    return {
      for (final e in base.entries)
        if (const ['SYSTEMROOT', 'WINDIR'].contains(e.key.toUpperCase()))
          e.key: e.value,
      ...configured,
      'HOME': root,
      'USERPROFILE': root,
      'TMP': root,
      'TEMP': root,
      'TMPDIR': root,
    };
  }

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

  /// Validates args for Windows batch file targets (.cmd/.bat).
  /// Rejects args containing shell metacharacters that cmd.exe would interpret.
  static void validateWindowsBatchArgs(
    String resolvedCommand,
    List<String> args,
  ) {
    final isBatch =
        resolvedCommand.toLowerCase().endsWith('.cmd') ||
        resolvedCommand.toLowerCase().endsWith('.bat');
    if (!isBatch) return;
    final forbidden = RegExp(r'[&|<>^%]|"');
    for (final arg in args) {
      if (forbidden.hasMatch(arg)) {
        throw const McpException(McpProblem.batchArgs);
      }
    }
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Future<void> send(Map<String, dynamic> message) {
    if (_closing) return Future.error(const McpException(McpProblem.closed));
    final next = _sends.then((_) async {
      _process.stdin.writeln(jsonEncode(message));
      await _process.stdin.flush();
    });
    _sends = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    // Let an in-flight flush finish before closing the sink.
    unawaited(_sends.then((_) => _process.stdin.close()).catchError((_) {}));
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
      var eventBytes = 0, responseBytes = 0;
      await for (final line in mcpLines(response)) {
        responseBytes += utf8.encode(line).length + 1;
        if (responseBytes > McpTransport.maxMessageBytes) {
          throw const McpException(McpProblem.protocol);
        }
        if (line.isEmpty) {
          if (data.isNotEmpty) {
            final complete = emit(data.join('\n'));
            data.clear();
            eventBytes = 0;
            if (complete) break;
          }
        } else if (line.startsWith('data:')) {
          final value = line.substring(5).replaceFirst(RegExp(r'^ '), '');
          eventBytes += utf8.encode(value).length + 1;
          if (eventBytes > McpTransport.maxMessageBytes) {
            throw const McpException(McpProblem.protocol);
          }
          data.add(value);
        }
      }
      if (data.isNotEmpty) emit(data.join('\n'));
    } else {
      // Bound the body before decoding it, not after joining it all.
      final body = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (body.length + chunk.length > McpTransport.maxMessageBytes) {
          throw const McpException(McpProblem.protocol);
        }
        body.add(chunk);
      }
      emit(utf8.decode(body.takeBytes()));
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
      onTimeout: () {
        _cancelRequest(id, 'Request timed out');
        throw const McpException(McpProblem.timeout);
      },
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

  void _cancelRequest(int id, String reason) {
    unawaited(
      transport
          .send({
            'jsonrpc': '2.0',
            'method': 'notifications/cancelled',
            'params': {'requestId': id, 'reason': reason},
          })
          .catchError((_) {}),
    );
  }

  void cancelPending() {
    for (final entry in _pending.entries.toList()) {
      _cancelRequest(entry.key, 'Stopped by user');
      entry.value.completeError(const McpException(McpProblem.closed));
    }
    _pending.clear();
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
    final watch = Stopwatch()..start();
    var pages = 0, bytes = 0;
    do {
      if (++pages > 100 || watch.elapsed >= timeout) {
        throw const McpException(
          McpProblem.protocol,
          'Tool discovery budget exceeded',
        );
      }
      final result = await request('tools/list', {'cursor': ?cursor}).timeout(
        timeout - watch.elapsed,
        onTimeout: () {
          cancelPending();
          throw const McpException(McpProblem.timeout);
        },
      );
      bytes += utf8.encode(jsonEncode(result)).length;
      if (bytes > 4 * 1024 * 1024 ||
          tools.length +
                  (result['tools'] is List
                      ? (result['tools'] as List).length
                      : 0) >
              1000) {
        throw const McpException(
          McpProblem.protocol,
          'Tool discovery budget exceeded',
        );
      }
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
    if (_closed) return;
    cancelPending();
    _closed = true;
    await _subscription.cancel();
    await transport.close();
  }
}
