import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../features/retrieval/domain/evidence.dart';
import 'search_models.dart';

/// The article Wikipedia has on a question's subject, as one more source in
/// a searched turn (report 2026-10-04). Wikipedia's public API is
/// free, keyless and answers plain clients; an encyclopedia article is the
/// reference a small model most needs next to vendor pages and forums. Two
/// requests: the search (three titles), then the chosen article's plain
/// text. Nothing is sent when web search is off.
class WikipediaClient {
  final Dio _dio;
  final Duration _timeout;

  WikipediaClient({Dio? dio, Duration timeout = const Duration(seconds: 6)})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: timeout,
              receiveTimeout: timeout,
              // Wikimedia asks API clients for a descriptive agent.
              headers: {
                'User-Agent':
                    'OnDeviceLLM/1.0 (on-device Android assistant; one lookup per question)',
                'Accept': 'application/json',
              },
            ),
          ),
      _timeout = timeout;

  /// Languages the app speaks; any other locale reads English Wikipedia.
  static const languages = {'en', 'fr', 'es'};

  /// Longest article text kept. Passages are ranked against the question
  /// afterwards, so this only bounds memory; the lead and the sections
  /// that follow it are what matter.
  static const maxChars = 40000;

  static const _ttl = Duration(hours: 1);
  final _recent = <String, (DateTime, SearchResult?)>{};

  /// The article that matches [query]'s subject, or null when the search
  /// finds none that does (a near-miss article is worse than none).
  Future<SearchResult?> lookup(
    String query, {
    String language = 'en',
    CancelToken? cancelToken,
  }) async {
    final lang = languages.contains(language) ? language : 'en';
    final key = '$lang|${query.trim().toLowerCase()}';
    final hit = _recent[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _ttl) return hit.$2;
    final api = 'https://$lang.wikipedia.org/w/api.php';
    var title = bestTitle(query, await _titles(api, query, cancelToken));
    // The whole question can bury the article ("Nikon Z30 weight and battery
    // life" finds no "Nikon Z30"); the product's name alone finds it.
    final product = title == null ? productName(query) : null;
    if (product != null) {
      title = bestTitle(query, await _titles(api, product, cancelToken));
    }
    // The subject's name alone: Wikipedia's search for "What is the capital
    // of Australia?" lists "Question", "Australian Capital Territory" and
    // "Canberra", none about the subject; "Australia" finds its article,
    // whose lead names the capital (phone probe round 8, 2026-10-18).
    final subject = title == null ? subjectName(query) : null;
    if (subject != null && subject != product) {
      title = bestTitle(query, await _titles(api, subject, cancelToken));
    }
    SearchResult? result;
    if (title != null) {
      final page = await _get(api, {
        'action': 'query',
        'prop': 'extracts|info|pageprops',
        'ppprop': 'disambiguation',
        'inprop': 'url',
        'explaintext': '1',
        'exsectionformat': 'wiki',
        'redirects': '1',
        'titles': title,
      }, cancelToken);
      result = parseArticle(page, lang);
    }
    if (_recent.length > 32) _recent.remove(_recent.keys.first);
    _recent[key] = (DateTime.now(), result);
    return result;
  }

  Future<List<String>> _titles(
    String api,
    String query,
    CancelToken? cancelToken,
  ) async {
    final search = await _get(api, {
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'srlimit': '3',
      'srprop': '',
    }, cancelToken);
    return [
      for (final row in (search['query']?['search'] as List? ?? const []))
        if (row is Map && row['title'] is String) row['title'] as String,
    ];
  }

  /// "Australia" from "What is the capital of Australia?": the longest run
  /// of capitalised words after the first word ("Marie Curie"), without a
  /// possessive; null without one.
  static String? subjectName(String query) {
    final words = query.trim().split(RegExp(r'\s+'));
    var best = <String>[];
    var run = <String>[];
    for (var i = 1; i <= words.length; i++) {
      final w = i == words.length
          ? ''
          : words[i]
                .replaceAll(
                  RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
                  '',
                )
                .replaceAll(RegExp(r"[’']s$"), '');
      if (w.length > 1 && RegExp(r'^\p{Lu}', unicode: true).hasMatch(w)) {
        run.add(w);
        continue;
      }
      if (run.length > best.length) best = run;
      run = [];
    }
    return best.isEmpty ? null : best.join(' ');
  }

  /// "Nikon Z30" from "What is the weight of the Nikon Z30?": the first
  /// model code and the word before it; null without a code.
  static String? productName(String query) {
    final words = [
      for (final w in query.split(RegExp(r'\s+')))
        if (w.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')
            case final clean when clean.isNotEmpty)
          clean,
    ];
    for (var i = 0; i < words.length; i++) {
      if (!_code.hasMatch(words[i].toLowerCase())) continue;
      final before = i > 0 && EvidenceRanker.terms(words[i - 1]).isNotEmpty
          ? '${words[i - 1]} '
          : '';
      return '$before${words[i]}';
    }
    return null;
  }

  Future<Map<String, dynamic>> _get(
    String url,
    Map<String, String> params,
    CancelToken? cancelToken,
  ) async {
    final res = await _dio
        .get<String>(
          url,
          queryParameters: {...params, 'format': 'json', 'formatversion': '2'},
          cancelToken: cancelToken,
          options: Options(responseType: ResponseType.plain),
        )
        .timeout(_timeout);
    final body = jsonDecode(res.data ?? '{}');
    return body is Map<String, dynamic> ? body : const {};
  }

  /// The first title whose words are words of the question: "Nikon Z30"
  /// for "nikon z30 sensor size", never "Nikon DX format". A title of four
  /// words or more may add one ("2022 FIFA World Cup"); a shorter one adds
  /// none: "Capital punishment in Canada" shares two words with "What is
  /// the capital of Canada?" and is not about it (phone probe round 7,
  /// 2026-10-18). A word counts when one starts the other ("Sinking" for
  /// "sink", "Australian" for "Australia"). A title with a model number
  /// must carry one the question has, and a question with a model code
  /// ("z30") needs a title that names it: "Nikon Z-mount" is the family,
  /// not the camera.
  static String? bestTitle(String query, List<String> titles) {
    final asked = EvidenceRanker.terms(query).toSet();
    if (asked.isEmpty) return null;
    final codes = asked.where(_code.hasMatch).toSet();
    for (final title in titles) {
      final words = EvidenceRanker.terms(
        title.replaceAll(RegExp(r'\s*\([^)]*\)'), ''),
      ).toSet();
      if (words.isEmpty) continue;
      final shared = words.where((w) => asked.any((a) => _same(w, a)));
      final numbered = words.where((w) => RegExp(r'\d').hasMatch(w));
      if (numbered.any((w) => !asked.contains(w))) continue;
      if (codes.isNotEmpty && codes.intersection(words).isEmpty) continue;
      final added = words.length - shared.length;
      if (shared.isNotEmpty && added <= (words.length >= 4 ? 1 : 0)) {
        return title;
      }
    }
    return null;
  }

  static bool _same(String a, String b) {
    if (a == b) return true;
    final (short, long) = a.length < b.length ? (a, b) : (b, a);
    return short.length >= 4 && long.startsWith(short);
  }

  /// A model code: letters and digits in one word ("z30", "s25", "a7iv").
  static final _code = RegExp(
    r'^(?=.*\p{L})(?=.*\d)[\p{L}\d]+$',
    unicode: true,
  );

  /// Section headings after which an article is references and links.
  static final _tail = RegExp(
    r'^==+\s*(See also|References|Notes|External links|Further reading|'
    r'Bibliography|Sources|Citations|Notes et références|Références|'
    r'Voir aussi|Liens externes|Bibliographie|Articles connexes|'
    r'Referencias|Notas|Véase también|Enlaces externos|Bibliografía)\s*==+\s*$',
    multiLine: true,
    caseSensitive: false,
  );

  /// The page of an extracts response as a read source; null for a missing
  /// page, a disambiguation page or an empty article.
  static SearchResult? parseArticle(Map<String, dynamic> body, String lang) {
    final pages = body['query']?['pages'];
    if (pages is! List || pages.isEmpty) return null;
    final page = pages.first;
    if (page is! Map || page['missing'] == true) return null;
    final props = page['pageprops'];
    if (props is Map && props.containsKey('disambiguation')) return null;
    final title = '${page['title'] ?? ''}';
    var text = '${page['extract'] ?? ''}';
    final tail = _tail.firstMatch(text);
    if (tail != null) text = text.substring(0, tail.start);
    text = text
        .replaceAllMapped(
          RegExp(r'^==+\s*(.*?)\s*==+\s*$', multiLine: true),
          (m) => '\n${m[1]}',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (title.isEmpty || text.length < 80) return null;
    if (text.length > maxChars) text = text.substring(0, maxChars);
    final url =
        '${page['fullurl'] ?? 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}'}';
    final lead = text.split('\n').first;
    return SearchResult(
      title: '$title — Wikipedia',
      url: url,
      snippet: lead.length > 300 ? '${lead.substring(0, 300)}…' : lead,
      source: '$lang.wikipedia.org',
      rank: 0,
      pageText: text,
      finalUrl: url,
      fetchedAt: DateTime.now(),
      outlet: 'Wikipedia',
    );
  }

  /// The Wikipedia to ask: the question's own language when its wording
  /// shows one (French or Spanish function words), else the app's.
  ///
  /// Another language than the app's needs two of its words, or one with
  /// its own spelling (an accent, "¿", "qu'"): "Explain le Chatelier
  /// principle" and "Tell me about Elle magazine" were read as French and
  /// answered in French (audit 2026-10-20). Code is not counted.
  static String languageFor(String query, String appLanguage) {
    final prose = query
        .replaceAll(RegExp(r'```[\s\S]*?(?:```|$)'), ' ')
        .replaceAll(RegExp(r'`[^`\n]*`'), ' ');
    final words = prose.toLowerCase().split(
      RegExp(r"[^\p{L}]+", unicode: true),
    );
    var fr = 0, es = 0, en = 0;
    for (final w in words) {
      if (_fr.contains(w)) fr++;
      if (_es.contains(w)) es++;
      if (_en.contains(w)) en++;
    }
    final app = appLanguage.toLowerCase().split(RegExp('[-_]')).first;
    final fallback = languages.contains(app) ? app : 'en';
    final best = [('fr', fr), ('es', es), ('en', en)]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final (lang, count) = best.first;
    if (count == 0 || count <= best[1].$2) return fallback;
    if (lang == fallback || count >= 2) return lang;
    final spelled = switch (lang) {
      'fr' => RegExp(
        r"[àâçéèêëîïôûùœ]|\b(?:qu|l|d|j|c|n|s)['’]\p{L}",
        unicode: true,
      ),
      'es' => RegExp(r'[¿¡ñáéíóú]', unicode: true),
      _ => RegExp(r'^\p{L}'),
    }.hasMatch(prose.toLowerCase());
    return spelled ? lang : fallback;
  }

  static const _fr = {
    'le',
    'les',
    'des',
    'du',
    'est',
    'sont',
    'quel',
    'quelle',
    'quels',
    'quelles',
    'comment',
    'combien',
    'pourquoi',
    'qui',
    'une',
    'pour',
    'avec',
    'dans',
    'sur',
    'au',
    'aux',
    'ce',
    'cette',
    'il',
    'elle',
    'et',
  };
  static const _es = {
    'el',
    'los',
    'las',
    'es',
    'qué',
    'cuál',
    'cuáles',
    'cuánto',
    'cuántos',
    'cómo',
    'por',
    'quién',
    'del',
    'una',
    'para',
    'con',
    'en',
    'y',
    'son',
    'está',
  };
  static const _en = {
    'the',
    'is',
    'are',
    'what',
    'which',
    'how',
    'who',
    'when',
    'why',
    'of',
    'and',
    'in',
    'does',
    'did',
    'was',
    'were',
    'with',
    'for',
    'a',
    'an',
  };

  void dispose() => _dio.close();
}
