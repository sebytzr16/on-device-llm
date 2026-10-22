import '../../../data/network/web_search/search_models.dart';

/// Freshness policy is independent of title matching and transport. A live
/// read is tried first for changing facts; a saved archive stays a snapshot.
abstract final class WikipediaSources {
  static Future<SearchResult?> lookup({
    required bool onlineAllowed,
    required bool timely,
    required Future<SearchResult?> Function() online,
    required Future<SearchResult?> Function() offline,
  }) async {
    Future<SearchResult?> safely(Future<SearchResult?> Function() get) async {
      try {
        return await get();
      } catch (_) {
        return null;
      }
    }

    if (onlineAllowed && timely) {
      final fresh = await safely(online);
      if (fresh != null) return fresh;
    }
    final saved = await safely(offline);
    if (saved != null) return saved.withPage(stale: timely);
    return onlineAllowed && !timely ? safely(online) : null;
  }
}
