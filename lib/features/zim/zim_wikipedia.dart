import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/network/web_search/search_models.dart';
import '../../data/network/web_search/web_page_reader.dart';
import '../../data/network/web_search/wikipedia_client.dart';
import '../retrieval/domain/evidence.dart';
import 'zim_archive.dart';

/// Offline Wikipedia from a Kiwix ZIM file the tester imported (tester
/// answers 2026-10-07, item 9). It answers the same question as
/// [WikipediaClient.lookup], the article on the question's subject, with
/// no network: the article is found by title in the file.
class ZimWikipedia {
  final String path;
  Future<ZimArchive>? _opening;
  bool _closed = false;
  String? _name;

  ZimWikipedia(this.path);

  /// Where an imported ZIM lives: one file, replaced on import.
  static String fileIn(String supportDir) =>
      p.join(supportDir, 'zim', 'wikipedia.zim');

  Future<ZimArchive> _open() {
    if (_closed) return Future.error(StateError('Offline Wikipedia is closed'));
    return _opening ??= ZimArchive.open(path);
  }

  Future<String?> archiveMetadata(String key) async =>
      (await _open()).metadata(key);
  Future<String> archiveIdentity() async => (await _open()).identity;

  /// The file's own title ("Wikipedia (English) top 50,000"), for Settings.
  Future<String> name() async {
    if (_name != null) return _name!;
    final title = (await (await _open()).metadata('Title'))?.trim() ?? '';
    return _name = title.isNotEmpty ? title : p.basename(path);
  }

  Future<void> close() async {
    _closed = true;
    try {
      await (await _opening)?.close();
    } catch (_) {}
  }

  Future<SearchResult?> article(String title) async {
    final zim = await _open();
    final e = await zim.findByTitle(title);
    if (e == null || !e.isArticle) return null;
    return toResult(
      e.title,
      utf8.decode(await zim.content(e), allowMalformed: true),
      await name(),
      archiveDate: await zim.metadata('Date'),
      archiveId: zim.identity,
      language: await zim.metadata('Language'),
    );
  }

  /// Titles the question could name, longest first: "Nikon Z30", "Eiffel
  /// Tower", "Paris". Each run of up to four words is tried as written, in
  /// Title Case and with only its first letter capitalised, which is how
  /// Wikipedia titles are written.
  static List<String> candidates(String query) {
    final words = [
      for (final w in query.split(RegExp(r'\s+')))
        if (w.replaceAll(
              RegExp(r"^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$", unicode: true),
              '',
            )
            case final clean when clean.isNotEmpty)
          clean,
    ];
    final out = <String>[];
    void add(String s) {
      if (!out.contains(s)) out.add(s);
    }

    String cap(String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);
    final product = WikipediaClient.productName(query);
    if (product != null) {
      add(product);
      add(product.split(' ').map(cap).join(' '));
    }
    for (var n = 4; n >= 1; n--) {
      for (var i = 0; i + n <= words.length; i++) {
        final run = words.sublist(i, i + n);
        // A run must start and end on a content word ("the Eiffel Tower"
        // is tried as "Eiffel Tower").
        if (EvidenceRanker.terms(run.first).isEmpty ||
            EvidenceRanker.terms(run.last).isEmpty) {
          continue;
        }
        final text = run.join(' ');
        add(text);
        add(run.map(cap).join(' '));
        final lower = text.toLowerCase();
        add(cap(lower));
      }
    }
    return out;
  }

  /// The article on [query]'s subject as a read source, or null when the
  /// file has none that [WikipediaClient.bestTitle] accepts.
  Future<SearchResult?> lookup(String query) async {
    final zim = await _open();
    final tried = <int>{};
    for (final title in candidates(query).take(60)) {
      final e = await zim.findByTitle(title);
      if (e == null || !e.isArticle || !tried.add(e.index)) continue;
      if (WikipediaClient.bestTitle(query, [e.title]) == null) continue;
      final html = utf8.decode(await zim.content(e), allowMalformed: true);
      final result = toResult(
        e.title,
        html,
        await name(),
        archiveDate: await zim.metadata('Date'),
        archiveId: zim.identity,
        language: await zim.metadata('Language'),
      );
      if (result != null) return result;
    }
    return null;
  }

  /// An article's HTML as a source; null for a short page (a stub or a
  /// disambiguation list is worse than nothing).
  static SearchResult? toResult(
    String title,
    String html,
    String file, {
    String? archiveDate,
    String? archiveId,
    String? language,
  }) {
    var (_, text) = WebPageReader.extract(html);
    text = text.trim();
    if (text.length < 80 || RegExp(r'may refer to:').hasMatch(text)) {
      return null;
    }
    if (text.length > WikipediaClient.maxChars) {
      text = text.substring(0, WikipediaClient.maxChars);
    }
    final lead = text
        .split('\n')
        .firstWhere(
          (l) => l.trim().length > 40,
          orElse: () => text.split('\n').first,
        );
    final url = 'zim://${Uri.encodeComponent(title.replaceAll(' ', '_'))}';
    return SearchResult(
      title: '$title — Wikipedia (offline)',
      url: url,
      snippet: lead.length > 300 ? '${lead.substring(0, 300)}…' : lead,
      source: file,
      rank: 0,
      pageText: text,
      finalUrl: url,
      fetchedAt: DateTime.now(),
      outlet: 'Wikipedia (offline)',
      archiveDate: archiveDate,
      archiveId: archiveId,
      archiveLanguage: language,
    );
  }

  /// Whether [path] is a ZIM file (checks the magic number).
  static Future<bool> isZim(String path) async {
    try {
      final f = await File(path).open();
      try {
        final b = await f.read(4);
        return b.length == 4 &&
            (b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24) == 72173914;
      } finally {
        await f.close();
      }
    } catch (_) {
      return false;
    }
  }
}
