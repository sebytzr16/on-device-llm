// Live check of page extraction on real articles; skipped unless LIVE_WEB=1.
//   $env:LIVE_WEB=1; $env:LIVE_URLS='https://…|https://…'; flutter test test/live/reader_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';

void main() {
  final live = Platform.environment['LIVE_WEB'] == '1';
  final urls = (Platform.environment['LIVE_URLS'] ?? '')
      .split('|')
      .where((u) => u.isNotEmpty);
  for (final url in urls) {
    test('reads $url', () async {
      final clock = Stopwatch()..start();
      try {
        final page = await WebPageReader().read(Uri.parse(url));
        // ignore: avoid_print
        print(
          '\n=== $url\n${clock.elapsedMilliseconds} ms · "${page.title}" · '
          '${page.text.length} chars · published ${page.publishedAt}\n'
          '${page.text.substring(0, page.text.length.clamp(0, 700))}',
        );
      } catch (e) {
        // ignore: avoid_print
        print('\n=== $url\nFAILED after ${clock.elapsedMilliseconds} ms: $e');
      }
    }, skip: live ? false : 'set LIVE_WEB=1 to run against the network');
  }
}
