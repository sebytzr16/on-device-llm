// Live debugging aid for the extractor's container choice; skipped unless
// LIVE_WEB=1. Prints each landmark candidate and its text length.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  final live = Platform.environment['LIVE_WEB'] == '1';
  final urls = (Platform.environment['LIVE_URLS'] ?? '')
      .split('|')
      .where((u) => u.isNotEmpty);
  for (final url in urls) {
    test('extract debug $url', () async {
      final client = HttpClient()
        ..userAgent =
            'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Mobile Safari/537.36 OnDeviceLLM/1.0';
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final doc = html.parse(
        body.replaceAll(
          RegExp(r'<script\b[\s\S]*?</script\s*>', caseSensitive: false),
          ' ',
        ),
      );
      int len(dynamic e) =>
          (e.text as String).replaceAll(RegExp(r'\s+'), ' ').trim().length;
      // ignore: avoid_print
      print('\n=== $url body=${len(doc.body)}');
      for (final sel in [
        'article',
        'main',
        '[role="main"]',
        '#content, #main-content, .post-content, .entry-content, .article-body, .article-content, .mw-parser-output',
      ]) {
        final all = doc.body!.querySelectorAll(sel);
        for (final e in all.take(5)) {
          // ignore: avoid_print
          print(
            '  $sel -> <${e.localName} class="${e.className}"> text=${len(e)}',
          );
        }
      }
      for (final e in doc.body!.querySelectorAll(
        '[hidden],[aria-hidden="true"],aside,header,nav,footer,form,dialog',
      )) {
        if (len(e) > 500) {
          // ignore: avoid_print
          print(
            '  REMOVED <${e.localName} class="${e.className}"> text=${len(e)}',
          );
        }
      }
    }, skip: live ? false : 'set LIVE_WEB=1');
  }
}
