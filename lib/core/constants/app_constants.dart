class AppConstants {
  static const appName = 'OnDevice LLM';

  /// Length follows the request: "concise" alone made small models answer
  /// research and news questions in two lines (report 2026-09-23).
  static const defaultSystemPrompt =
      'You are a helpful, knowledgeable and accurate assistant. Match the '
      'length to the request: brief for greetings, chat and simple questions; '
      'complete and well organised for explanations, research, news, '
      'comparisons and how-tos. Use Markdown when it helps reading: short '
      'paragraphs, bullet or numbered lists, **bold** key facts, a table for '
      'comparisons. Never repeat your answer.';

  /// The base prompt of a spoken turn (Conversation): the written one asks
  /// for Markdown and long, organised answers, which the spoken style then
  /// contradicts; Qwen3.5 0.8B followed neither (tester, 2026-10-08).
  static const spokenSystemPrompt =
      'You are a helpful, knowledgeable and accurate assistant.';

  static const ddgHtmlEndpoint = 'https://html.duckduckgo.com/html/';
  static const ddgLiteEndpoint = 'https://lite.duckduckgo.com/lite/';

  /// The page that issues the query token for DuckDuckGo's verticals.
  static const ddgHomeEndpoint = 'https://duckduckgo.com/';

  /// DuckDuckGo's keyless news vertical (JSON).
  static const ddgNewsEndpoint = 'https://duckduckgo.com/news.js';
}
