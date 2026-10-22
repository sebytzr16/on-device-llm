const _keepSearchValue = Object();

class SearchProviderHealth {
  final String provider, status;
  final int parsed, relevant, elapsedMs;
  const SearchProviderHealth(
    this.provider,
    this.status, {
    this.parsed = 0,
    this.relevant = 0,
    this.elapsedMs = 0,
  });
  Map<String, Object> toJson() => {
    'provider': provider,
    'status': status,
    'parsed': parsed,
    'relevant': relevant,
    'elapsedMs': elapsedMs,
  };
}

class SearchResult {
  final String title;
  final String url;
  final String snippet;
  final String? source;
  final int rank;
  final String? pageText, finalUrl, readError;
  final DateTime? fetchedAt;

  /// The page's own publication date, when it states one.
  final DateTime? publishedAt;

  /// The page's stated last update, when later than [publishedAt].
  final DateTime? updatedAt;

  /// The archive's snapshot, never the time it happened to be read.
  final String? archiveDate, archiveLanguage, archiveId;

  /// Conservative description of the text actually available to the model.
  String get coverage => url.startsWith('zim://')
      ? 'archive_snapshot'
      : newsItem
      ? 'headline_only'
      : pageText == null
      ? 'snippet_only'
      : 'extracted_section';

  /// [stale]: a saved copy (an offline archive or a saved article) used
  /// for a question about now, so it may be outdated.
  final bool stale, sponsored;

  /// The publisher's name ("BBC News", "The Canadian Press") when it is
  /// known, which is what the user recognises, unlike a syndication host.
  final String? outlet;

  /// A news listing (headline, publisher, time and lede from a news search
  /// or a publisher's feed) rather than a page that was read. Its [pageText]
  /// is the lede, and it is evidence in its own right: dated and attributed.
  final bool newsItem;

  /// Text that came from a page read earlier in the same chat rather than in
  /// this turn (follow-up questions look there first).
  final bool remembered;
  SearchResult withPage({
    Object? text = _keepSearchValue,
    Object? finalUrl = _keepSearchValue,
    Object? fetchedAt = _keepSearchValue,
    Object? error = _keepSearchValue,
    Object? publishedAt = _keepSearchValue,
    Object? updatedAt = _keepSearchValue,
    bool? stale,
    bool? remembered,
  }) => SearchResult(
    title: title,
    url: url,
    snippet: snippet,
    source: source,
    rank: rank,
    pageText: identical(text, _keepSearchValue) ? pageText : text as String?,
    finalUrl: identical(finalUrl, _keepSearchValue)
        ? this.finalUrl
        : finalUrl as String?,
    fetchedAt: identical(fetchedAt, _keepSearchValue)
        ? this.fetchedAt
        : fetchedAt as DateTime?,
    publishedAt: identical(publishedAt, _keepSearchValue)
        ? this.publishedAt
        : publishedAt as DateTime?,
    updatedAt: identical(updatedAt, _keepSearchValue)
        ? this.updatedAt
        : updatedAt as DateTime?,
    readError: identical(error, _keepSearchValue)
        ? readError
        : error as String?,
    stale: stale ?? this.stale,
    sponsored: sponsored,
    outlet: outlet,
    newsItem: newsItem,
    remembered: remembered ?? this.remembered,
    archiveDate: archiveDate,
    archiveLanguage: archiveLanguage,
    archiveId: archiveId,
  );

  /// The same result under another list position.
  SearchResult withRank(int rank) => SearchResult(
    title: title,
    url: url,
    snippet: snippet,
    source: source,
    rank: rank,
    pageText: pageText,
    finalUrl: finalUrl,
    fetchedAt: fetchedAt,
    publishedAt: publishedAt,
    updatedAt: updatedAt,
    readError: readError,
    stale: stale,
    sponsored: sponsored,
    outlet: outlet,
    newsItem: newsItem,
    remembered: remembered,
    archiveDate: archiveDate,
    archiveLanguage: archiveLanguage,
    archiveId: archiveId,
  );

  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    this.source,
    required this.rank,
    this.pageText,
    this.finalUrl,
    this.fetchedAt,
    this.publishedAt,
    this.updatedAt,
    this.readError,
    this.stale = false,
    this.sponsored = false,
    this.outlet,
    this.newsItem = false,
    this.remembered = false,
    this.archiveDate,
    this.archiveLanguage,
    this.archiveId,
  });
}
