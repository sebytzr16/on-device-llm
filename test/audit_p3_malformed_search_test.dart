import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';

void main() {
  test(
    'malformed links and invalid escapes do not hide valid search results',
    () {
      final scraper = DuckDuckGoScraper();
      addTearDown(scraper.dispose);
      final results = scraper.parseHtml(
        '''<div class="result"><a class="result__a" href="http://[broken">Broken</a></div>
<div class="result"><a class="result__a" href="/l/?uddg=%ZZ">Bad escape</a></div>
<div class="result"><a class="result__a" href="https://example.org/Good">Good</a><a class="result__snippet">Useful snippet</a></div>''',
      );
      expect(results, hasLength(1));
      expect(results.single.url, 'https://example.org/Good');
      expect(results.single.rank, 1);
    },
  );
}
