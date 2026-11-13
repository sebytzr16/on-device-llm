import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_client.dart';
import 'package:ondevice_llm/desktop/mcp/mcp_config.dart';

Matcher _protocolProblem() => isA<McpException>().having(
  (error) => error.problem,
  'problem',
  McpProblem.protocol,
);

void main() {
  test(
    'a line over the byte budget fails before the whole line is kept',
    () async {
      final oversized = Stream<List<int>>.value(
        utf8.encode('x' * (McpTransport.maxMessageBytes + 1)),
      );
      await expectLater(mcpLines(oversized), emitsError(_protocolProblem()));
    },
  );

  test('bounded lines keep short and CRLF lines intact', () async {
    final lines = await mcpLines(
      Stream.fromIterable([utf8.encode('one\r\ntwo\n')]),
    ).toList();
    expect(lines, ['one', 'two']);
  });

  for (final mode in ['json', 'sse-line', 'sse-event']) {
    test(
      '$mode response over the byte budget is rejected before parsing',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final payload = 'x' * McpTransport.maxMessageBytes;
        final message = jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'result': {'value': payload},
        });
        server.listen((request) async {
          await utf8.decoder.bind(request).join();
          if (mode == 'json') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(message);
          } else {
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            if (mode == 'sse-line') {
              request.response.write('data: $message\n\n');
            } else {
              // Each data line is under the line budget; the event is not.
              for (var i = 0; i < 3; i++) {
                request.response.write('data: ${'y' * (2 * 1024 * 1024)}\n');
              }
              request.response.write('\n');
            }
          }
          try {
            await request.response.close();
          } catch (_) {
            // The client closes the lane once the budget is exceeded.
          }
        });
        final client = McpClient(
          HttpMcpTransport('http://127.0.0.1:${server.port}/mcp'),
        );
        addTearDown(client.close);
        await expectLater(client.request('probe'), throwsA(_protocolProblem()));
      },
    );
  }
}
