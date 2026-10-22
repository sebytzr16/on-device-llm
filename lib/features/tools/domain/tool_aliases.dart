import 'dart:convert';

import 'tool_spec.dart';

/// The names and argument names small models use for our tools when they
/// do not copy the offered ones exactly: `web_search`, `google`, `open_url`,
/// `calculate`, an argument called `q` or `link`… Each is mapped to the tool
/// it clearly means, so a well-intended call is run instead of failing as
/// "tool not available". Unknown names stay as written (and are refused by
/// the runner as before).
class ToolAliases {
  static const _names = {
    // search_web
    'web_search': 'search_web', 'websearch': 'search_web',
    'searchweb': 'search_web', 'search': 'search_web',
    'search_internet': 'search_web', 'internet_search': 'search_web',
    'search_online': 'search_web', 'online_search': 'search_web',
    'google': 'search_web', 'google_search': 'search_web',
    'bing': 'search_web', 'bing_search': 'search_web',
    'duckduckgo': 'search_web', 'duckduckgo_search': 'search_web',
    'ddg_search': 'search_web', 'browse': 'search_web',
    'tavily_search': 'search_web', 'serper_search': 'search_web',
    'searx_search': 'search_web', 'exa_search': 'search_web',
    'browser_search': 'search_web', 'lookup': 'search_web',
    'look_up': 'search_web', 'find_online': 'search_web',
    'brave_search': 'search_web', 'search_the_web': 'search_web',
    // search_news
    'news': 'search_news', 'get_news': 'search_news',
    'news_search': 'search_news', 'search_headlines': 'search_news',
    'headlines': 'search_news', 'latest_news': 'search_news',
    'get_latest_news': 'search_news', 'fetch_news': 'search_news',
    'top_stories': 'search_news', 'current_events': 'search_news',
    // read_url
    'open_url': 'read_url', 'fetch_url': 'read_url', 'fetch': 'read_url',
    'browse_page': 'read_url', 'browse_webpage': 'read_url',
    'get_webpage': 'read_url', 'get_web_page': 'read_url',
    'fetch_webpage': 'read_url',
    'read_page': 'read_url', 'open_page': 'read_url',
    'read_webpage': 'read_url', 'read_web_page': 'read_url',
    'browse_url': 'read_url', 'get_url': 'read_url', 'visit': 'read_url',
    'visit_url': 'read_url', 'visit_page': 'read_url',
    'web_fetch': 'read_url', 'fetch_page': 'read_url',
    'get_page': 'read_url', 'scrape': 'read_url', 'scrape_url': 'read_url',
    'open_link': 'read_url', 'read_link': 'read_url', 'open': 'read_url',
    // find_in_page
    'find': 'find_in_page', 'search_page': 'find_in_page',
    'find_text': 'find_in_page', 'page_search': 'find_in_page',
    'search_in_page': 'find_in_page', 'find_on_page': 'find_in_page',
    // calculator
    'calc': 'calculator', 'calculate': 'calculator', 'math': 'calculator',
    'wolfram_alpha': 'calculator', 'wolframalpha': 'calculator',
    'compute': 'calculator', 'evaluate': 'calculator',
    'eval': 'calculator', 'arithmetic': 'calculator',
    'evaluate_expression': 'calculator', 'calculator_tool': 'calculator',
    // search_documents
    'search_docs': 'search_documents', 'document_search': 'search_documents',
    'search_files': 'search_documents', 'search_knowledge': 'search_documents',
    'knowledge_search': 'search_documents', 'retrieve': 'search_documents',
    'file_search': 'search_documents',
    'search_my_documents': 'search_documents',
    'search_collection': 'search_documents',
  };

  /// The argument each tool cannot do without, and the other names models
  /// give it. A lone string argument goes to the first key.
  static const _args = <String, Map<String, List<String>>>{
    'search_web': {
      'query': [
        'q',
        'search',
        'search_query',
        'searchquery',
        'keywords',
        'keyword',
        'text',
        'term',
        'terms',
        'question',
        'input',
        'topic',
        'prompt',
        'search_term',
        'search_terms',
        'string',
      ],
    },
    'search_news': {
      'topic': [
        'query',
        'q',
        'subject',
        'category',
        'about',
        'keywords',
        'search',
        'search_query',
        'news_topic',
        'input',
        'text',
      ],
    },
    'read_url': {
      'url': [
        'link',
        'href',
        'uri',
        'page',
        'website',
        'address',
        'site',
        'web_page',
        'webpage',
        'page_url',
        'source',
        'target',
      ],
    },
    'find_in_page': {
      'url': ['link', 'href', 'uri', 'page', 'website', 'page_url'],
      'query': ['q', 'text', 'search', 'term', 'find', 'question', 'input'],
    },
    'search_documents': {
      'query': ['q', 'search', 'text', 'question', 'keywords', 'input', 'term'],
    },
    'calculator': {
      'expression': [
        'expr',
        'formula',
        'equation',
        'calculation',
        'input',
        'query',
        'math',
        'code',
        'problem',
        'x',
      ],
    },
  };

  static const canonical = {
    'search_web',
    'search_news',
    'read_url',
    'find_in_page',
    'search_documents',
    'calculator',
  };

  /// The tool [raw] means: our own name, a known alias, or [raw] cleaned up
  /// ("functions.search_web", "Search Web" and "search-web" all work).
  static String name(String raw) {
    var n = raw.trim().toLowerCase();
    n = n.replaceFirst(RegExp(r'^(functions|function|tools|tool)\.'), '');
    n = n.replaceAll(RegExp(r'[\s\-]+'), '_');
    if (canonical.contains(n)) return n;
    return _names[n] ?? raw.trim();
  }

  static bool known(String raw) => canonical.contains(name(raw));

  /// [args] for [tool] with every required argument filled from its
  /// aliases; a single unnamed value (a string instead of an object) is the
  /// first required argument.
  static Map<String, dynamic> args(String tool, Object? args) {
    final wanted = _args[tool];
    if (args is String) {
      final s = args.trim();
      if (s.startsWith('{')) {
        try {
          return ToolAliases.args(tool, jsonDecode(s));
        } catch (_) {}
      }
      if (wanted == null || s.isEmpty) return const {};
      return {wanted.keys.first: s};
    }
    final out = args is Map
        ? {
            for (final e in args.entries)
              '${e.key}'.trim().toLowerCase().replaceAll(
                RegExp(r'[\s\-]+'),
                '_',
              ): e.value,
          }
        : <String, dynamic>{};
    if (wanted == null) return out;
    for (final entry in wanted.entries) {
      if (out[entry.key] != null && '${out[entry.key]}'.trim().isNotEmpty) {
        continue;
      }
      for (final alias in entry.value) {
        final v = out[alias];
        if (v != null && '$v'.trim().isNotEmpty) {
          out[entry.key] = v is List ? v.join(' ') : v;
          break;
        }
      }
    }
    // One argument under an unknown name: it is the one the tool needs.
    final first = wanted.keys.first;
    if (out[first] == null && out.length == 1) {
      out[first] = out.values.first;
    }
    return out;
  }

  /// [call] with its tool name and arguments mapped to ours.
  static ToolCall normalize(ToolCall call) {
    final tool = name(call.name);
    Object? raw;
    try {
      raw = jsonDecode(call.arguments);
    } catch (_) {
      raw = call.arguments;
    }
    final fixed = args(tool, raw);
    if (tool == call.name && jsonEncode(fixed) == jsonEncode(call.args)) {
      return call;
    }
    return ToolCall(id: call.id, name: tool, arguments: jsonEncode(fixed));
  }
}
