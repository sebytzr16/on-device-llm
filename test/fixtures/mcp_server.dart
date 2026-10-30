import 'dart:convert';
import 'dart:io';

/// A dependency-free MCP fixture; stdout contains only JSON-RPC lines.
Future<void> main(List<String> args) async {
  if (args.contains('--exit-immediately')) exit(7);
  var initialized = false;
  stderr.writeln('fixture ready');
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final request = jsonDecode(line) as Map;
    final method = request['method'];
    if (method == 'notifications/initialized') {
      initialized = true;
      continue;
    }
    final id = request['id'];
    if (id == null) continue;
    Object result;
    switch (method) {
      case 'initialize':
        result = {
          'protocolVersion': '2025-03-26',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'fixture', 'version': '1'},
        };
      case 'tools/list':
        if (!initialized) exit(3);
        result = {
          'tools': [
            {
              'name': 'echo',
              'description': 'Echo input text.',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'text': {'type': 'string'},
                },
                'required': ['text'],
              },
            },
            {
              'name': 'add',
              'description': 'Add two numbers.',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'a': {'type': 'number'},
                  'b': {'type': 'number'},
                },
                'required': ['a', 'b'],
              },
            },
          ],
        };
      case 'tools/call':
        final params = request['params'] as Map;
        final name = params['name'];
        final arguments = params['arguments'] as Map;
        if (name == 'crash') exit(7);
        if (name == 'timeout') continue;
        result = {
          'content': [
            {
              'type': 'text',
              'text': switch (name) {
                'echo' => arguments['text'],
                'add' => '${(arguments['a'] as num) + (arguments['b'] as num)}',
                _ => 'fixture error',
              },
            },
          ],
          if (name == 'error') 'isError': true,
        };
      default:
        stdout.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32601, 'message': 'Method not found'},
          }),
        );
        continue;
    }
    stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
    await stdout.flush();
  }
}
