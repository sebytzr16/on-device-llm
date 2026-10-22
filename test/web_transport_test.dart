import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';

/// Transport fixture matrix for the page reader (roadmap SEC/WEB): a real
/// loopback HTTP server plays each awkward server so redirects, limits,
/// deadlines and cancellation are exercised over sockets, not mocks.
void main() {
  late HttpServer server;
  late Uri base;
  // Route table filled per test: path -> handler.
  final routes = <String, Future<void> Function(HttpRequest)>{};

  String article(String body) =>
      '<html><head><title>Fixture</title></head><body><article>'
      '<h1>Fixture</h1><p>$body</p></article></body></html>';
  final longBody = 'Fixture paragraph text repeated for readability. ' * 6;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    PublicWebPolicy.fixturePort = server.port;
    server.listen((req) async {
      final handler = routes[req.uri.path];
      if (handler == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      try {
        await handler(req);
      } catch (_) {
        // A client that hung up mid-body makes the response throw; fine.
      }
    });
  });
  tearDownAll(() async {
    PublicWebPolicy.fixturePort = null;
    await server.close(force: true);
  });
  setUp(routes.clear);

  Future<void> html(HttpRequest req, String body, {int status = 200}) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..write(body);
    await req.response.close();
  }

  Future<void> redirect(HttpRequest req, String to, {int status = 302}) async {
    req.response
      ..statusCode = status
      ..headers.set(HttpHeaders.locationHeader, to)
      ..write('moved');
    await req.response.close();
  }

  test('reads a plain 200 page and reports the final address', () async {
    routes['/page'] = (r) => html(r, article(longBody));
    final page = await WebPageReader().read(base.resolve('/page'));
    expect(page.title, 'Fixture');
    expect(page.text, contains('Fixture paragraph text'));
    expect(page.finalUri, base.resolve('/page'));
  });

  test('sends the resolved page language on every read', () async {
    String? received;
    routes['/language'] = (request) {
      received = request.headers.value(HttpHeaders.acceptLanguageHeader);
      return html(request, article(longBody));
    };
    await WebPageReader().read(
      base.resolve('/language'),
      language: 'fr-CA,fr;q=0.9,en;q=0.7',
    );
    expect(received, 'fr-CA,fr;q=0.9,en;q=0.7');
  });

  test('follows a bounded redirect chain to the final page', () async {
    routes['/a'] = (r) => redirect(r, '/b', status: 301);
    routes['/b'] = (r) => redirect(r, base.resolve('/c').toString());
    routes['/c'] = (r) => redirect(r, '/d#frag', status: 308);
    routes['/d'] = (r) => html(r, article(longBody));
    final page = await WebPageReader().read(base.resolve('/a'));
    expect(page.finalUri, base.resolve('/d'));
  });

  test(
    'refuses redirect loops, chains over four hops and empty targets',
    () async {
      routes['/loop1'] = (r) => redirect(r, '/loop2');
      routes['/loop2'] = (r) => redirect(r, '/loop1');
      await expectLater(
        WebPageReader().read(base.resolve('/loop1')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            'Redirect loop.',
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        routes['/hop$i'] = (r) => redirect(r, '/hop${i + 1}');
      }
      routes['/hop6'] = (r) => html(r, article(longBody));
      await expectLater(
        WebPageReader().read(base.resolve('/hop0')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            'Too many redirects.',
          ),
        ),
      );
      routes['/nowhere'] = (r) async {
        r.response.statusCode = 302;
        await r.response.close();
      };
      await expectLater(
        WebPageReader().read(base.resolve('/nowhere')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            'Redirect has no destination.',
          ),
        ),
      );
    },
  );

  test(
    'a redirect into a private address is rejected before connecting',
    () async {
      routes['/inside'] = (r) => redirect(r, 'http://10.0.0.1/admin');
      await expectLater(
        WebPageReader().read(base.resolve('/inside')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            contains('Private and special-use'),
          ),
        ),
      );
      routes['/meta'] = (r) => redirect(r, 'http://169.254.169.254/latest');
      await expectLater(
        WebPageReader().read(base.resolve('/meta')),
        throwsFormatException,
      );
      routes['/lan'] = (r) => redirect(r, 'http://printer.local/');
      await expectLater(
        WebPageReader().read(base.resolve('/lan')),
        throwsFormatException,
      );
    },
  );

  test('non-200 statuses and non-text types are errors', () async {
    routes['/missing'] = (r) => html(r, article(longBody), status: 404);
    await expectLater(
      WebPageReader().read(base.resolve('/missing')),
      throwsA(isA<HttpException>()),
    );
    routes['/json'] = (r) async {
      r.response.headers.contentType = ContentType.json;
      r.response.write('{"a": 1}');
      await r.response.close();
    };
    await expectLater(
      WebPageReader().read(base.resolve('/json')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'm',
          'This page is not HTML, plain text, a feed or PDF.',
        ),
      ),
    );
  });

  test('XHTML reads as a page; RSS reads as a feed of stories', () async {
    routes['/xhtml'] = (r) async {
      r.response.headers.contentType = ContentType(
        'application',
        'xhtml+xml',
        charset: 'utf-8',
      );
      r.response.write(article(longBody));
      await r.response.close();
    };
    final page = await WebPageReader().read(base.resolve('/xhtml'));
    expect(page.text, contains('Fixture paragraph text'));
    expect(page.feedItems, isNull);

    routes['/feed'] = (r) async {
      r.response.headers.contentType = ContentType(
        'application',
        'rss+xml',
        charset: 'utf-8',
      );
      r.response.write(
        '<?xml version="1.0"?><rss version="2.0"><channel><title>Fixture News</title>'
        '<item><title>Council approves transit plan</title><link>https://news.example/a</link>'
        '<description>The vote was 9-2.</description><pubDate>Tue, 22 Sep 2026 18:00:00 GMT</pubDate></item>'
        '<item><title>Rain expected tomorrow</title><link>https://news.example/b</link></item>'
        '</channel></rss>',
      );
      await r.response.close();
    };
    final items = await WebPageReader().readFeed(base.resolve('/feed'));
    expect(items.map((i) => i.title), [
      'Council approves transit plan',
      'Rain expected tomorrow',
    ]);
    expect(items.first.summary, 'The vote was 9-2.');
    // A feed read as a page is readable lines.
    final asPage = await WebPageReader().read(base.resolve('/feed'));
    expect(asPage.text, contains('Council approves transit plan'));
    expect(asPage.title, 'Fixture News');

    routes['/xml'] = (r) async {
      r.response.headers.contentType = ContentType('application', 'xml');
      r.response.write('<config><value>${'x' * 200}</value></config>');
      await r.response.close();
    };
    await expectLater(
      WebPageReader().read(base.resolve('/xml')),
      throwsFormatException,
    );
  });

  test('oversize pages are refused by header and by streamed size', () async {
    routes['/big-header'] = (r) async {
      r.response.headers.contentType = ContentType.html;
      r.response.contentLength = WebPageReader.maxBytes + 1;
      r.response.write('<html>');
      await r.response.close();
    };
    await expectLater(
      WebPageReader().read(base.resolve('/big-header')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'm',
          'Page is too large.',
        ),
      ),
    );
    // Chunked with no length: the reader must stop reading at the cap, not
    // buffer the whole thing. The overshoot is far larger than any socket
    // buffer, or a fast loopback (Linux CI) takes it all before the hang-up.
    var sent = 0;
    const flood = WebPageReader.maxBytes + 32 * 1024 * 1024;
    routes['/big-stream'] = (r) async {
      r.response.headers.contentType = ContentType.html;
      final chunk = List.filled(64 * 1024, 0x61);
      while (sent < flood) {
        r.response.add(chunk);
        sent += chunk.length;
        await r.response.flush();
      }
      await r.response.close();
    };
    await expectLater(
      WebPageReader().read(base.resolve('/big-stream')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'm',
          'Page is too large.',
        ),
      ),
    );
    expect(sent, lessThan(flood));
  });

  /// A raw socket server that answers one request with headers and then
  /// trickles body bytes forever; the client hanging up ends its read stream,
  /// which is the disconnect signal the app relies on.
  Future<(Uri, Future<void>)> trickler({int prefix = 16}) async {
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final gone = Completer<void>();
    raw.listen((socket) {
      socket.listen(
        (_) {},
        onDone: () {
          if (!gone.isCompleted) gone.complete();
          raw.close();
        },
        onError: (_) {
          if (!gone.isCompleted) gone.complete();
          raw.close();
        },
      );
      socket.write(
        'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n'
        'Transfer-Encoding: chunked\r\n\r\n',
      );
      final head = '<html><body><p>${'y' * prefix}';
      socket.write('${head.length.toRadixString(16)}\r\n$head\r\n');
      () async {
        while (!gone.isCompleted) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (gone.isCompleted) break;
          try {
            socket.write('1\r\nx\r\n');
            await socket.flush();
          } catch (_) {
            if (!gone.isCompleted) gone.complete();
          }
        }
      }();
    });
    PublicWebPolicy.fixturePort = raw.port;
    return (Uri.parse('http://127.0.0.1:${raw.port}/trickle'), gone.future);
  }

  test(
    'a trickling server hits the total deadline and is disconnected',
    () async {
      final (uri, gone) = await trickler();
      addTearDown(() => PublicWebPolicy.fixturePort = server.port);
      final clock = Stopwatch()..start();
      await expectLater(
        WebPageReader().read(uri, timeout: const Duration(seconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
      await gone.timeout(const Duration(seconds: 5));
    },
  );

  test('cancellation mid-body stops the read and closes the socket', () async {
    final (uri, gone) = await trickler(prefix: 200);
    addTearDown(() => PublicWebPolicy.fixturePort = server.port);
    final token = CancelToken();
    final read = WebPageReader().read(uri, cancelToken: token);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    token.cancel('user stopped');
    await expectLater(read, throwsA(anything));
    await gone.timeout(const Duration(seconds: 5));
  });

  test('a cancelled token refuses to start at all', () async {
    routes['/page'] = (r) => html(r, article(longBody));
    final token = CancelToken()..cancel();
    await expectLater(
      WebPageReader().read(base.resolve('/page'), cancelToken: token),
      throwsA(isA<StateError>()),
    );
  });

  test('PDF links go through the injected extractor', () async {
    final pdfBytes = utf8.encode('%PDF-1.4 fake ${'x' * 200}');
    routes['/paper.pdf'] = (r) async {
      r.response.headers.contentType = ContentType('application', 'pdf');
      r.response.add(pdfBytes);
      await r.response.close();
    };
    // Without an extractor the link is refused, as before.
    await expectLater(
      WebPageReader().read(base.resolve('/paper.pdf')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'm',
          contains('PDF links are not supported'),
        ),
      ),
    );
    var seen = 0;
    final page = await WebPageReader(
      pdfText: (bytes) async {
        seen = bytes.length;
        return '--- Page 1 ---\nAttention is all you need. $longBody';
      },
    ).read(base.resolve('/paper.pdf'));
    expect(seen, pdfBytes.length);
    expect(page.title, 'paper');
    expect(page.text, contains('Attention is all you need'));
    expect(page.publishedAt, isNull);
  });

  test('a dated article carries its publication date', () async {
    routes['/dated'] = (r) => html(
      r,
      '<html><head><title>Fixture</title><meta property="article:published_time" content="2025-01-15T09:30:00Z"></head><body><article><p>$longBody</p></article></body></html>',
    );
    final page = await WebPageReader().read(base.resolve('/dated'));
    expect(page.publishedAt, DateTime.utc(2025, 1, 15, 9, 30));
  });

  test('latin-1 pages decode by their declared charset', () async {
    routes['/latin'] = (r) async {
      r.response.headers.contentType = ContentType(
        'text',
        'html',
        charset: 'iso-8859-1',
      );
      r.response.add(latin1.encode(article('Café crème et pâté. $longBody')));
      await r.response.close();
    };
    final page = await WebPageReader().read(base.resolve('/latin'));
    expect(page.text, contains('Café crème et pâté'));
  });

  test(
    'plain text is returned verbatim and short pages are rejected',
    () async {
      routes['/txt'] = (r) async {
        r.response.headers.contentType = ContentType.text;
        r.response.write('Line one of a plain document.\n$longBody');
        await r.response.close();
      };
      final page = await WebPageReader().read(base.resolve('/txt'));
      expect(page.text, startsWith('Line one'));
      routes['/short'] = (r) => html(r, '<html><body><p>hi</p></body></html>');
      await expectLater(
        WebPageReader().read(base.resolve('/short')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            contains('No readable page text'),
          ),
        ),
      );
    },
  );

  test('the fixture hook is off outside tests', () {
    final port = PublicWebPolicy.fixturePort;
    PublicWebPolicy.fixturePort = null;
    expect(
      () => PublicWebPolicy.validate(base.resolve('/page')),
      throwsFormatException,
    );
    expect(PublicWebPolicy.isPublic(InternetAddress.loopbackIPv4), false);
    PublicWebPolicy.fixturePort = port;
  });
}
