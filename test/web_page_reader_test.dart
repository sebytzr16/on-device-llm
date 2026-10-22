import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';

void main() {
  test('publication date from JSON-LD, meta tags or <time>', () {
    expect(
      WebPageReader.publishedAt(
        '<html><head><script type="application/ld+json">{"@type":"NewsArticle","datePublished":"2025-03-04T10:00:00Z"}</script></head><body></body></html>',
      ),
      DateTime.utc(2025, 3, 4, 10),
    );
    expect(
      WebPageReader.publishedAt(
        '<html><head><meta property="article:published_time" content="2024-11-30"></head><body></body></html>',
      ),
      DateTime.utc(2024, 11, 30),
    );
    expect(
      WebPageReader.publishedAt(
        '<html><body><time datetime="2023-06-01T08:00:00+02:00">June</time></body></html>',
      ),
      DateTime.utc(2023, 6, 1, 6),
    );
    // Future or ancient dates, and pages without one, give nothing.
    expect(
      WebPageReader.publishedAt(
        '<html><head><meta name="date" content="2099-01-01"></head></html>',
      ),
      isNull,
    );
    expect(WebPageReader.publishedAt('<html><body>hi</body></html>'), isNull);
  });

  test('rejects local, metadata, transition and special-use addresses', () {
    for (final address in [
      '0.0.0.0',
      '127.0.0.1',
      '10.0.0.1',
      '100.64.0.1',
      '169.254.169.254',
      '172.16.0.1',
      '192.168.1.1',
      '192.0.0.8',
      '192.0.2.1',
      '198.18.0.1',
      '198.51.100.1',
      '203.0.113.1',
      '224.0.0.1',
      '255.255.255.255',
      '::1',
      '::ffff:127.0.0.1',
      'fc00::1',
      'fe80::1',
      '64:ff9b::7f00:1',
      '2002:7f00::1',
      '2001:db8::1',
    ]) {
      expect(
        PublicWebPolicy.isPublic(InternetAddress(address)),
        false,
        reason: address,
      );
    }
    for (final address in [
      '1.1.1.1',
      '8.8.8.8',
      '2606:4700:4700::1111',
      // WordPress VIP (Global News and other publishers): ordinary space
      // next to the two special /24s of 192.0.0.0/16.
      '192.0.66.184',
      '192.0.78.9',
    ]) {
      expect(
        PublicWebPolicy.isPublic(InternetAddress(address)),
        true,
        reason: address,
      );
    }
    for (final url in [
      'file:///etc/passwd',
      'http://localhost',
      'http://router.local',
      'http://127.0.0.1',
      'https://user:pass@example.com',
      'https://example.com:8443',
    ]) {
      expect(
        () => PublicWebPolicy.validate(Uri.parse(url)),
        throwsFormatException,
      );
    }
  });
  test('extracts article structure and removes scripts and navigation', () {
    final (title, text) = WebPageReader.extract('''<html><title>Example</title>
      <nav>Menu</nav><article><h1>Heading</h1><p>Useful <strong>facts</strong>.</p>
      <script>steal()</script><div hidden>Secret</div><ul><li>First</li><li>Second</li></ul>
      </article><footer>Footer</footer></html>''');
    expect(title, 'Example');
    expect(text, 'Heading\nUseful facts.\nFirst\nSecond');
  });
  test('picks the article body over sidebars, comments and link lists', () {
    final (title, text) = WebPageReader.extract('''<html><head>
      <meta property="og:title" content="Flutter 3.47 released"><title>Blog</title></head><body>
      <div class="sidebar"><p>Trending now: ten posts you missed this week on the blog.</p></div>
      <div id="wrapper">
        <div class="post-body">
          <h1>Flutter 3.47 released</h1>
          <p>Today we are releasing Flutter 3.47.4, the latest stable version of the framework, with faster builds and new widgets.</p>
          <p>The release also updates Dart to 3.11 and improves Impeller on Android devices across the board.</p>
          <table><tr><th>Channel</th><td>stable</td></tr><tr><th>Version</th><td>3.47.4</td></tr></table>
        </div>
        <ul class="related-posts"><li><a href="/a">Older post one</a></li><li><a href="/b">Older post two</a></li></ul>
        <div id="comments"><p>First! Great release, thanks a lot for all the hard work on this.</p></div>
      </div></body></html>''');
    expect(title, 'Flutter 3.47 released');
    expect(text, contains('releasing Flutter 3.47.4'));
    expect(text, contains('Version | 3.47.4'));
    expect(text, isNot(contains('Trending now')));
    expect(text, isNot(contains('Older post')));
    expect(text, isNot(contains('First!')));
  });
  test('caps extracted text and preserves plain text', () {
    final (_, text) = WebPageReader.extract(
      'a' * (WebPageReader.maxCharacters + 5000),
      plainText: true,
    );
    expect(text.length, WebPageReader.maxCharacters);
  });

  test('keeps an article that React streams in a hidden segment', () {
    // Next.js pages (Sportsnet, Yahoo) send the shell first and the article
    // later in <div hidden id="S:0">, moved into place by a script.
    final paragraphs = List.generate(
      8,
      (i) =>
          '<p>Paragraph $i of the game report: the Blue Jays lost 4-3 and '
          'fell 3.5 games out of the last wild-card spot.</p>',
    ).join();
    final (_, text) = WebPageReader.extract('''<html><body>
      <main><article><p>The Blue Jays could be eliminated on Tuesday.</p>
      <template id="B:0"></template></article></main>
      <div hidden>Sign in to continue</div>
      <div hidden id="S:0"><article>$paragraphs</article></div>
      <script>\$RC("B:0","S:0")</script></body></html>''');
    expect(text, contains('Paragraph 7 of the game report'));
    expect(text, isNot(contains('Sign in to continue')));
  });

  test('script-rendered pages fall back to their JSON-LD article body', () {
    final body = 'The council voted 9-2 to approve the transit plan. ' * 20;
    final page = WebPageReader.extractPage('''<html><head>
      <meta property="og:description" content="Council approves the plan after a long debate on funding.">
      <script type="application/ld+json">{"@type":"NewsArticle","datePublished":"2026-09-22T10:00:00Z","articleBody":"$body"}</script>
      </head><body><div id="app">Loading…</div></body></html>''');
    expect(page.text, contains('voted 9-2'));
    expect(page.publishedAt, DateTime.utc(2026, 9, 22, 10));
  });

  test('huge script payloads are stripped before parsing', () {
    final junk = '<script>${'var x = "<p>not text</p>";' * 50000}</script>';
    final clock = Stopwatch()..start();
    final (_, text) = WebPageReader.extract(
      '<html><body>$junk<article><p>${'Readable sentence. ' * 20}</p></article>$junk</body></html>',
    );
    expect(text, startsWith('Readable sentence.'));
    expect(text, isNot(contains('not text')));
    expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
  });
  test('refuses private URLs before making a request', () async {
    await expectLater(
      WebPageReader().read(Uri.parse('http://169.254.169.254/')),
      throwsFormatException,
    );
  });
}
