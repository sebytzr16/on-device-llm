import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

class _Search extends DuckDuckGoScraper {
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async => const [
    SearchResult(
      title: 'Docs',
      url: 'https://example.org/docs',
      snippet: 'Snippet',
      rank: 1,
    ),
  ];
}

class _Reader extends WebPageReader {
  @override
  Future<WebPage> read(
    Uri uri, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 12),
    String language = 'en-US,en;q=0.9',
  }) async => WebPage(
    title: 'Docs',
    text: 'Page',
    finalUri: uri,
    fetchedAt: DateTime.utc(2026, 9, 19),
  );
}

/// A remote research turn with the user's Tools switch off: webOnly, with
/// recall and MCP tools present on the runner but not offered (R01).
ToolRunner _remoteRunner({Future<String> Function(String, String)? helper}) =>
    ToolRunner(
      scraper: _Search(),
      reader: _Reader(),
      settings: const InferenceSettings(
        webMode: WebMode.auto,
        toolsEnabled: true,
      ),
      remote: true,
      webOnly: true,
      recall: (_) async => 'note',
      helper: helper,
      externalTools: const [
        ToolSpec(name: 'mcp_files', description: 'Files', parameters: {}),
      ],
    );

void main() {
  test('webOnly with a helper keeps ask_helper and the web tools (R01)', () {
    final names = _remoteRunner(
      helper: (task, input) async => 'helper reply',
    ).specs().map((s) => s.name).toSet();
    expect(names, contains('ask_helper'));
    expect(names, contains('search_web'));
    expect(names, containsAll(['search_web', 'read_url', 'find_in_page']));
    // recall and MCP tools stay out of a web-only turn.
    expect(names, isNot(contains('recall')));
    expect(names, isNot(contains('mcp_files')));
    expect(names.difference(ToolRunner.webTools), {'ask_helper'});
  });

  test('webOnly without a helper does not offer ask_helper (R01)', () {
    final names = _remoteRunner().specs().map((s) => s.name).toSet();
    expect(names, isNot(contains('ask_helper')));
    expect(names, contains('search_web'));
    expect(names.difference(ToolRunner.webTools), isEmpty);
  });

  test(
    'ask_helper runs on a webOnly turn when a helper is set (R01)',
    () async {
      final r = _remoteRunner(
        helper: (task, input) async => 'summary of $input',
      );
      final out = await r.run(
        const ToolCall(
          id: 'h1',
          name: 'ask_helper',
          arguments: '{"task":"Summarise","input":"long text"}',
        ),
      );
      expect(out.ok, isTrue);
      expect(out.output, contains('summary of long text'));
      // A tool the turn never offered is still refused.
      final refused = await r.run(
        const ToolCall(id: 'm1', name: 'mcp_files', arguments: '{"path":"/"}'),
      );
      expect(refused.ok, isFalse);
    },
  );
}
