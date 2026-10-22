import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'news_feed_parser.dart';

/// Only ordinary public HTTP(S) pages are readable. Every redirect and the
/// address used for the actual connection are checked, including DNS answers.
class PublicWebPolicy {
  /// Test hook: a loopback fixture server on this port passes the policy so
  /// the transport (redirects, limits, timeouts, cancellation) can be
  /// exercised against real sockets. Null in the app.
  @visibleForTesting
  static int? fixturePort;

  static bool _isFixture(Uri uri) =>
      fixturePort != null &&
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      uri.port == fixturePort;

  static void validate(Uri uri) {
    if (_isFixture(uri)) return;
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != (uri.scheme == 'https' ? 443 : 80)) {
      throw const FormatException(
        'Only public HTTP(S) URLs on standard ports are supported.',
      );
    }
    final host = uri.host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    if (!host.contains('.') && !host.contains(':') ||
        host == 'localhost' ||
        [
          '.localhost',
          '.local',
          '.internal',
          '.home',
          '.lan',
        ].any(host.endsWith)) {
      throw const FormatException('Local addresses cannot be read.');
    }
    final address = InternetAddress.tryParse(host);
    if (address != null && !isPublic(address)) {
      throw const FormatException(
        'Private and special-use addresses cannot be read.',
      );
    }
  }

  static bool isPublic(InternetAddress address) {
    if (fixturePort != null && address.isLoopback) return true;
    final b = address.rawAddress;
    if (b.length == 4) {
      return !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          // 192.0.0.0/24 and 192.0.2.0/24 only: the rest of 192.0.0.0/16
          // is ordinary address space (WordPress VIP serves Global News and
          // many other publishers from 192.0.64.0/18).
          (b[0] == 192 &&
              (b[1] == 168 ||
                  (b[1] == 0 && (b[2] == 0 || b[2] == 2)) ||
                  (b[1] == 88 && b[2] == 99))) ||
          (b[0] == 198 &&
              (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
          (b[0] == 203 && b[1] == 0 && b[2] == 113));
    }
    // Restrict IPv6 to global unicast and exclude transition/documentation ranges.
    // This also rejects mapped IPv4, loopback, link-local, ULA and NAT64.
    return b.length == 16 &&
        (b[0] & 0xe0) == 0x20 &&
        !(b[0] == 0x20 &&
            b[1] == 0x01 &&
            (b[2] < 2 || (b[2] == 0x0d && b[3] == 0xb8))) &&
        !(b[0] == 0x20 && b[1] == 0x02) &&
        !(b[0] == 0x3f && b[1] == 0xff && (b[2] & 0xf0) == 0);
  }
}

class WebPage {
  final String title, text;
  final Uri finalUri;

  /// When the text was fetched.
  final DateTime fetchedAt;

  /// The page's own publication date (JSON-LD, Open Graph / article meta,
  /// or a dated `<time>`), when it states one.
  final DateTime? publishedAt;

  /// The page's stated last update (`dateModified`, `article:modified_time`
  /// and the like), when it states one later than [publishedAt].
  final DateTime? updatedAt;

  /// The stories of an RSS/Atom feed, when the address was a feed.
  final List<FeedItem>? feedItems;
  const WebPage({
    required this.title,
    required this.text,
    required this.finalUri,
    required this.fetchedAt,
    this.publishedAt,
    this.updatedAt,
    this.feedItems,
  });
}

/// Text out of PDF bytes; the app passes pdfium via the attachment store.
typedef PdfTextExtractor = Future<String> Function(Uint8List bytes);

/// The parts of a page the reader keeps.
class ExtractedPage {
  final String title, text;
  final DateTime? publishedAt, updatedAt;
  const ExtractedPage(
    this.title,
    this.text,
    this.publishedAt, [
    this.updatedAt,
  ]);
}

/// Reads static HTML/plain text/feeds with bounded bytes, redirects and wall
/// time. No cookies, credentials, scripts, API key or hosted scraping service.
class WebPageReader {
  /// News sites ship multi-megabyte pages (a CNN article was 4.2 MB of HTML,
  /// measured 2026-09-23); most of it is script, which is stripped before
  /// parsing.
  static const maxBytes = 8 * 1024 * 1024;

  /// PDFs are bigger than pages for the same text; papers and manuals fit.
  static const maxPdfBytes = 16 * 1024 * 1024;

  /// Extracted text kept per page: long enough for a whole long-form
  /// article or reference entry, so a later question about the same page
  /// finds its answer without another request.
  static const maxCharacters = 150000;

  /// A page read less than this long ago is reused without a request.
  static const cacheTtl = Duration(minutes: 30);

  /// Feeds change faster than articles.
  static const feedTtl = Duration(minutes: 10);

  /// Pages stay available to the chat (follow-up questions, find_in_page)
  /// this long, and at most [memoryPages] of them, whatever their age.
  static const memoryTtl = Duration(hours: 12);
  static const memoryPages = 300;

  /// And at most this much text in total (~20 MB as Dart strings): 300
  /// full pages would be ~90 MB next to a loaded model on the phone.
  static const memoryCharacters = 10000000;

  /// Identifies the app while matching what publishers serve to phones:
  /// some sites refuse unknown agents outright (AP News answered 403 to the
  /// bare app agent and 200 to this one, measured 2026-09-23).
  static const userAgent =
      'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Mobile Safari/537.36 OnDeviceLLM/1.0';

  // Insertion order is recency order: a hit moves to the end.
  final LinkedHashMap<Uri, WebPage> _cache = LinkedHashMap();

  /// PDF support (phase 4); null refuses PDF links as before.
  final PdfTextExtractor? pdfText;
  WebPageReader({this.pdfText});

  void _keep(Uri key, WebPage page) {
    _cache.remove(key);
    _cache[key] = page;
    final cutoff = DateTime.now().toUtc().subtract(memoryTtl);
    _cache.removeWhere((_, p) => p.fetchedAt.isBefore(cutoff));
    var characters = 0;
    for (final p in _cache.values) {
      characters += p.text.length;
    }
    // Oldest first; the page just read always stays.
    while (_cache.length > 1 &&
        (_cache.length > memoryPages || characters > memoryCharacters)) {
      characters -= _cache.remove(_cache.keys.first)!.text.length;
    }
  }

  /// A page read in the last [memoryTtl], whatever its freshness, without a
  /// request: what follow-up questions and find_in_page look at.
  WebPage? remembered(Uri uri) {
    final key = uri.removeFragment();
    final page = _cache[key];
    if (page == null) return null;
    if (DateTime.now().toUtc().difference(page.fetchedAt) > memoryTtl) {
      _cache.remove(key);
      return null;
    }
    return page;
  }

  Future<WebPage> read(
    Uri uri, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 12),
    String language = 'en-US,en;q=0.9',
  }) async {
    PublicWebPolicy.validate(uri);
    final cacheKey = uri.removeFragment();
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().toUtc().difference(cached.fetchedAt) <
            (cached.feedItems != null ? feedTtl : cacheTtl)) {
      _keep(cacheKey, cached);
      return cached;
    }
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = userAgent
      ..autoUncompress = true;
    client.findProxy = (_) => 'DIRECT';
    var closed = false;
    void check() {
      if (closed || cancelToken?.isCancelled == true) {
        throw StateError('Page reading stopped.');
      }
    }

    client.connectionFactory = (url, proxyHost, proxyPort) async {
      check();
      PublicWebPolicy.validate(url);
      final addresses = await InternetAddress.lookup(url.host);
      check();
      if (addresses.isEmpty ||
          addresses.any((a) => !PublicWebPolicy.isPublic(a))) {
        throw const FormatException(
          'Host resolves to a private or special-use address.',
        );
      }
      // Connect to the validated address object, avoiding a second DNS lookup.
      // A custom connection factory owns TLS too. Verify against the original hostname.
      final task = await Socket.startConnect(addresses.first, url.port);
      if (closed || cancelToken?.isCancelled == true) task.cancel();
      if (url.scheme == 'https') {
        Socket? connected;
        final secure = task.socket.then((socket) async {
          connected = socket;
          check();
          return SecureSocket.secure(socket, host: url.host);
        });
        return ConnectionTask.fromSocket(secure, () {
          task.cancel();
          connected?.destroy();
        });
      }
      return task;
    };
    final finished = Completer<void>();
    unawaited(
      Future.any<void>([
        if (cancelToken != null) cancelToken.whenCancel.then((_) {}),
        finished.future,
      ]).then((_) {
        if (!finished.isCompleted) {
          closed = true;
          client.close(force: true);
        }
      }),
    );
    Future<WebPage> fetch() async {
      var current = uri.removeFragment();
      final seen = <String>{};
      for (var hop = 0; hop <= 4; hop++) {
        check();
        PublicWebPolicy.validate(current);
        if (!seen.add(current.toString())) {
          throw const FormatException('Redirect loop.');
        }
        final request = await client.getUrl(current);
        check();
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,text/plain;q=0.9,application/rss+xml;q=0.8,application/atom+xml;q=0.8,application/xml;q=0.7,application/pdf;q=0.7,*/*;q=0.5',
        );
        request.headers.set(HttpHeaders.acceptLanguageHeader, language);
        final response = await request.close();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          // Cancel the body immediately; never drain an unbounded redirect response.
          await response.listen((_) {}).cancel();
          if (location == null) {
            throw const FormatException('Redirect has no destination.');
          }
          final next = current.resolve(location).removeFragment();
          if (current.scheme == 'https' && next.scheme != 'https') {
            throw const FormatException('HTTPS downgrade refused.');
          }
          current = next;
          continue;
        }
        if (response.statusCode != 200) {
          throw HttpException(
            'Page returned HTTP ${response.statusCode}',
            uri: current,
          );
        }
        final type = response.headers.contentType;
        final mime = type?.mimeType ?? '';
        final isPdf =
            mime == 'application/pdf' ||
            (type == null && current.path.toLowerCase().endsWith('.pdf'));
        // XHTML is a page, not a feed.
        final isXml =
            _xmlTypes.contains(mime) ||
            (mime.endsWith('+xml') && mime != 'application/xhtml+xml');
        if (isPdf && pdfText == null) {
          throw const FormatException('PDF links are not supported here.');
        }
        if (!isPdf &&
            !isXml &&
            ![
              'text/html',
              'application/xhtml+xml',
              'text/plain',
            ].contains(mime)) {
          throw const FormatException(
            'This page is not HTML, plain text, a feed or PDF.',
          );
        }
        final limit = isPdf ? maxPdfBytes : maxBytes;
        if (response.contentLength > limit) {
          throw const FormatException('Page is too large.');
        }
        // This suspended frame was found corrupted in release crash dumps.
        // The running-total rewrite did not prevent the crash; the writer
        // remains unknown.
        final bytes = BytesBuilder();
        var received = 0;
        await for (final chunk in response) {
          check();
          received += chunk.length;
          if (received > limit) {
            throw const FormatException('Page is too large.');
          }
          bytes.add(chunk);
        }
        final data = bytes.takeBytes();
        var title = '';
        var text = '';
        DateTime? published;
        DateTime? updated;
        List<FeedItem>? feed;
        if (isPdf) {
          final pdf = await pdfText!(data);
          text = bounded(pdf);
          final name = current.pathSegments.isEmpty
              ? current.host
              : current.pathSegments.last;
          title = name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        } else {
          final charset = type?.charset?.toLowerCase();
          final Converter<List<int>, String> decoder =
              charset == 'iso-8859-1' || charset == 'windows-1252'
              ? latin1.decoder
              : const Utf8Decoder(allowMalformed: true);
          final body = decoder.convert(data);
          final isFeed =
              (isXml || mime == 'text/plain') &&
              NewsFeedParser.looksLikeFeed(body);
          // Other XML is only read when it is really an HTML page served
          // under an XML type.
          if (isXml &&
              !isFeed &&
              !body
                  .substring(0, body.length.clamp(0, 4000))
                  .toLowerCase()
                  .contains('<html')) {
            throw const FormatException(
              'This page is not HTML, plain text, a feed or PDF.',
            );
          }
          if (isFeed) {
            feed = NewsFeedParser.parse(body);
            title = _feedTitle(body) ?? current.host;
            text = bounded(NewsFeedParser.asText(feed));
          } else {
            final plain = mime == 'text/plain';
            final extracted = extractPage(body, plainText: plain);
            title = extracted.title;
            text = extracted.text;
            published = extracted.publishedAt;
            updated = extracted.updatedAt;
          }
        }
        if (text.length < 80) {
          throw const FormatException(
            'No readable page text; it may require JavaScript or sign-in.',
          );
        }
        final page = WebPage(
          title: title,
          text: text,
          finalUri: current,
          fetchedAt: DateTime.now().toUtc(),
          publishedAt: published,
          updatedAt: updated,
          feedItems: feed,
        );
        _keep(cacheKey, page);
        if (current != cacheKey) _keep(current, page);
        return page;
      }
      throw const FormatException('Too many redirects.');
    }

    try {
      return await fetch().timeout(timeout);
    } finally {
      closed = true;
      finished.complete();
      client.close(force: true);
    }
  }

  /// The stories of an RSS/Atom feed, through the same policy and limits
  /// as a page (cached for [feedTtl]).
  Future<List<FeedItem>> readFeed(
    Uri uri, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 6),
    String language = 'en-US,en;q=0.9',
  }) async {
    final page = await read(
      uri,
      cancelToken: cancelToken,
      timeout: timeout,
      language: language,
    );
    final items = page.feedItems;
    if (items == null) {
      throw const FormatException('This address is not a news feed.');
    }
    return items;
  }

  static const _xmlTypes = {
    'application/rss+xml',
    'application/atom+xml',
    'application/rdf+xml',
    'application/xml',
    'text/xml',
  };

  static String? _feedTitle(String body) {
    final m = RegExp(
      r'<title[^>]*>(?:<!\[CDATA\[)?([^<\]]{1,200})',
    ).firstMatch(body);
    final t = m?.group(1)?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  static String bounded(String text) =>
      text.substring(0, text.length.clamp(0, maxCharacters)).trim();

  /// The page's stated publication date: JSON-LD `datePublished`, then
  /// `article:published_time` / `datePublished` / `date` meta, then the
  /// first `<time datetime>`. Dates in the future or before 1990 are noise.
  static DateTime? publishedAt(String body) =>
      _publishedAt(html.parse(_stripScripts(body).$1), _jsonLd(body));

  static DateTime? _accept(String? raw) {
    if (raw == null) return null;
    // A bare date is a calendar day, not local midnight.
    final s = raw.trim();
    final d = DateTime.tryParse(
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ? '${s}T00:00:00Z' : s,
    );
    if (d == null) return null;
    final now = DateTime.now().toUtc();
    if (d.isAfter(now.add(const Duration(days: 1))) || d.year < 1990) {
      return null;
    }
    return d.toUtc();
  }

  static DateTime? _publishedAt(Document document, List<String> jsonLd) {
    for (final script in jsonLd) {
      final m = RegExp(r'"datePublished"\s*:\s*"([^"]+)"').firstMatch(script);
      final d = _accept(m?.group(1));
      if (d != null) return d;
    }
    for (final selector in const [
      'meta[property="article:published_time"]',
      'meta[name="article:published_time"]',
      'meta[itemprop="datePublished"]',
      'meta[name="datePublished"]',
      'meta[name="date"]',
      'meta[name="DC.date.issued"]',
      'meta[name="pubdate"]',
      'meta[name="sailthru.date"]',
      'meta[name="parsely-pub-date"]',
    ]) {
      final d = _accept(
        document.querySelector(selector)?.attributes['content'],
      );
      if (d != null) return d;
    }
    for (final t in document.querySelectorAll('time[datetime]')) {
      final d = _accept(t.attributes['datetime']);
      if (d != null) return d;
    }
    return null;
  }

  /// The page's stated last update: JSON-LD `dateModified`, then the
  /// modified-time meta tags. Kept only when later than [published] (a
  /// page "updated" before it was published is a template's date).
  static DateTime? _updatedAt(
    Document document,
    List<String> jsonLd,
    DateTime? published,
  ) {
    DateTime? keep(DateTime? d) =>
        d == null || (published != null && !d.isAfter(published)) ? null : d;
    for (final script in jsonLd) {
      final m = RegExp(r'"dateModified"\s*:\s*"([^"]+)"').firstMatch(script);
      final d = keep(_accept(m?.group(1)));
      if (d != null) return d;
    }
    for (final selector in const [
      'meta[property="article:modified_time"]',
      'meta[name="article:modified_time"]',
      'meta[property="og:updated_time"]',
      'meta[itemprop="dateModified"]',
      'meta[name="dateModified"]',
      'meta[name="last-modified"]',
      'meta[name="parsely-modified-date"]',
    ]) {
      final d = keep(
        _accept(document.querySelector(selector)?.attributes['content']),
      );
      if (d != null) return d;
    }
    return null;
  }

  static final _ldScript = RegExp(
    r'''<script[^>]+type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script\s*>''',
    caseSensitive: false,
  );

  static List<String> _jsonLd(String body) => [
    for (final m in _ldScript.allMatches(body)) m.group(1)!,
  ];

  /// Scripts, styles, inline SVG and comments are most of a modern news
  /// page's bytes and none of its text; dropping them before the DOM is
  /// built keeps a 4 MB page as cheap to parse as a small one.
  static (String, int) _stripScripts(String body) {
    final before = body.length;
    final stripped = body
        .replaceAll(
          RegExp(r'<script\b[\s\S]*?</script\s*>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style\b[\s\S]*?</style\s*>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<svg\b[\s\S]*?</svg\s*>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    return (stripped, before - stripped.length);
  }

  /// The article body a publisher declares in its JSON-LD (`articleBody`),
  /// for pages that render their text with scripts.
  static String? _ldArticleBody(List<String> scripts) {
    String? best;
    void visit(Object? node) {
      if (node is List) {
        for (final n in node) {
          visit(n);
        }
      } else if (node is Map) {
        final body = node['articleBody'] ?? node['text'];
        if (body is String &&
            body.length > 200 &&
            (best == null || body.length > best!.length)) {
          best = body;
        }
        for (final v in node.values) {
          if (v is Map || v is List) visit(v);
        }
      }
    }

    for (final s in scripts) {
      try {
        visit(jsonDecode(s.trim()));
      } catch (_) {}
    }
    return best;
  }

  /// Class/id fragments that mark page furniture rather than content. An
  /// element is only dropped when it holds a minority of the page's text, so
  /// a site that names its article "content-sidebar-wrap" keeps its article.
  static final _furniture = RegExp(
    r'(^|[\s_-])(comments?|sidebar|side-bar|footer|nav|navbar|navigation|menu|share|sharing|social|related|recommend(?:ed|ations)?|promo|advert(?:isement)?|ads?|banner|cookie|consent|popup|modal|newsletter|subscribe|breadcrumbs?|pagination|toolbar|sponsor|disclaimer|skip-link|masthead|toc|table-of-contents)([\s_-]|$)',
    caseSensitive: false,
  );

  static (String, String) extract(String body, {bool plainText = false}) {
    final page = extractPage(body, plainText: plainText);
    return (page.title, page.text);
  }

  static ExtractedPage extractPage(String body, {bool plainText = false}) {
    if (plainText) return ExtractedPage('', bounded(body), null);
    final jsonLd = _jsonLd(body);
    final document = html.parse(_stripScripts(body).$1);
    final title =
        document
            .querySelector('meta[property="og:title"]')
            ?.attributes['content']
            ?.trim() ??
        document.querySelector('title')?.text.trim() ??
        '';
    final description =
        document
            .querySelector('meta[property="og:description"]')
            ?.attributes['content']
            ?.trim() ??
        document
            .querySelector('meta[name="description"]')
            ?.attributes['content']
            ?.trim() ??
        '';
    final published = _publishedAt(document, jsonLd);
    final updated = _updatedAt(document, jsonLd, published);
    final whole = document.body == null ? 0 : _textLength(document.body!);
    for (final element in document.querySelectorAll(
      'script,style,noscript,nav,footer,header,form,button,iframe,svg,template,aside,dialog,menu,[role="navigation"],[role="banner"],[role="complementary"],[role="contentinfo"]',
    )) {
      element.remove();
    }
    // Hidden blocks are usually menus and modals, but React's streamed
    // server rendering delivers the article itself in `<div hidden
    // id="S:0">` for a script to move into place (Sportsnet and Yahoo
    // lost their whole article to this rule, measured 2026-09-23). Such
    // segments, and any hidden block holding much of the page, stay.
    for (final element in document.querySelectorAll(
      '[hidden],[aria-hidden="true"]',
    )) {
      final id = element.id;
      if (RegExp(r'^[SP]:\w+$').hasMatch(id)) continue;
      if (whole > 0 && _textLength(element) > whole * 0.3) continue;
      element.remove();
    }
    final shortTitle = title.substring(0, title.length.clamp(0, 300));
    final page = document.body;
    var text = '';
    if (page != null) {
      final total = _textLength(page);
      // Named furniture (comment threads, share bars, cookie banners…) goes
      // when it is clearly not the article.
      for (final element in page.querySelectorAll('[class],[id]')) {
        final marker =
            '${element.attributes['class'] ?? ''} ${element.attributes['id'] ?? ''}';
        if (_furniture.hasMatch(marker) && _textLength(element) < total * 0.4) {
          element.remove();
        }
      }
      final root = _contentRoot(page);
      final out = StringBuffer();
      const blocks = {
        'p',
        'div',
        'section',
        'article',
        'main',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'li',
        'tr',
        'pre',
        'blockquote',
        'dt',
        'dd',
        'figcaption',
      };
      void walk(Node node) {
        if (out.length >= maxCharacters) return;
        if (node is Text) {
          out.write(node.data.replaceAll(RegExp(r'\s+'), ' '));
          return;
        }
        final tag = node is Element ? node.localName : null;
        // A dense list of links (menus, "more articles") carries no evidence.
        if (node is Element &&
            (tag == 'ul' || tag == 'ol' || tag == 'div') &&
            _linkDensity(node) > 0.6 &&
            _textLength(node) < 400) {
          return;
        }
        if (blocks.contains(tag) || tag == 'br') out.writeln();
        // Table cells stay on one row so a fact keeps its column label.
        if (tag == 'td' || tag == 'th') out.write(' | ');
        for (final child in node.nodes) {
          walk(child);
        }
        if (blocks.contains(tag)) out.writeln();
      }

      walk(root);
      text = out
          .toString()
          .split('\n')
          .map((s) => s.trim().replaceFirst(RegExp(r'^\|\s*'), ''))
          .where((s) => s.isNotEmpty)
          .join('\n');
    }
    // Script-rendered articles: the publisher's own JSON-LD body is the
    // article; the markup held only teasers and links.
    if (text.length < 1500) {
      final declared = _ldArticleBody(jsonLd);
      if (declared != null && declared.length > text.length) {
        text = declared
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'[ \t]+'), ' ')
            .trim();
      }
    }
    // A page with next to no body text still has its summary line.
    if (text.length < 400 &&
        description.length > 60 &&
        !text.contains(description)) {
      text = '$description\n$text'.trim();
    }
    return ExtractedPage(shortTitle, bounded(text), published, updated);
  }

  static int _textLength(Element e) =>
      e.text.replaceAll(RegExp(r'\s+'), ' ').trim().length;

  static double _linkDensity(Element e) {
    final total = _textLength(e);
    if (total == 0) return 0;
    var linked = 0;
    for (final a in e.querySelectorAll('a')) {
      linked += _textLength(a);
    }
    return linked / total;
  }

  /// Readability-style choice of the element that holds the article: the
  /// explicit landmarks first, otherwise the container whose paragraphs carry
  /// the most non-link text. Falls back to the body for pages with no
  /// dominant block (documentation indexes, tables of data).
  static Element _contentRoot(Element body) {
    final landmark =
        body.querySelector('article') ??
        body.querySelector('main') ??
        body.querySelector('[role="main"]') ??
        body.querySelector(
          '#content, #main-content, .post-content, .entry-content, .article-body, .article-content, .mw-parser-output',
        );
    if (landmark != null && _textLength(landmark) >= _textLength(body) * 0.2) {
      return landmark;
    }
    final scores = <Element, double>{};
    for (final p in body.querySelectorAll(
      'p, pre, blockquote, li, td, dd, h1, h2, h3',
    )) {
      final length = _textLength(p);
      if (length < 25) continue;
      final score = length * (1 - _linkDensity(p));
      final parent = p.parent;
      if (parent == null) continue;
      scores[parent] = (scores[parent] ?? 0) + score;
      final grand = parent.parent;
      if (grand != null) scores[grand] = (scores[grand] ?? 0) + score / 2;
    }
    Element? best;
    var bestScore = 0.0;
    scores.forEach((e, s) {
      if (s > bestScore) {
        best = e;
        bestScore = s;
      }
    });
    if (best != null && _textLength(best!) >= _textLength(body) * 0.3) {
      return best!;
    }
    return body;
  }
}
