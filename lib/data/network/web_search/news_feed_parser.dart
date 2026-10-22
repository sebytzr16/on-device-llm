import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

/// One story from a publisher's RSS/Atom feed.
class FeedItem {
  final String title, link, summary;
  final DateTime? published;
  const FeedItem({
    required this.title,
    required this.link,
    required this.summary,
    this.published,
  });
}

/// RSS 2.0, RSS 1.0 (RDF) and Atom, namespace-agnostic. Feeds are small and
/// dated, and they link to the publisher's own article pages, which the
/// reader can open — unlike syndication mirrors.
class NewsFeedParser {
  static bool looksLikeFeed(String body) {
    final head = body.substring(0, body.length.clamp(0, 2000)).toLowerCase();
    return head.contains('<rss') ||
        head.contains('<feed') ||
        head.contains('<rdf:rdf') ||
        head.contains('<channel');
  }

  /// Items in feed order; [now] corrects feeds that stamp local time as UTC
  /// (seen 2026-09-23: two publishers' newest items were hours "in the
  /// future"): the whole feed is shifted back by that amount, which keeps
  /// the order of its stories.
  static List<FeedItem> parse(String body, {DateTime? now, int max = 60}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      return const [];
    }
    final out = <FeedItem>[];
    for (final e in doc.descendants.whereType<XmlElement>()) {
      if (out.length >= max) break;
      final name = e.name.local;
      if (name != 'item' && name != 'entry') continue;
      String child(List<String> names) {
        for (final n in names) {
          for (final c in e.childElements) {
            if (c.name.local == n) {
              final t = c.innerText.trim();
              if (t.isNotEmpty) return t;
            }
          }
        }
        return '';
      }

      final title = plain(child(const ['title']));
      var link = child(const ['link', 'guid']);
      if (!link.startsWith('http')) {
        // Atom: <link rel="alternate" href="…"/>.
        for (final c in e.childElements) {
          if (c.name.local != 'link') continue;
          final rel = c.getAttribute('rel');
          final href = c.getAttribute('href');
          if (href != null && (rel == null || rel == 'alternate')) {
            link = href;
            break;
          }
        }
      }
      if (title.isEmpty || !link.startsWith('http')) continue;
      final summary = plain(
        child(const ['description', 'summary', 'encoded', 'content']),
      );
      final date = parseDate(
        child(const ['pubDate', 'published', 'updated', 'date', 'issued']),
      );
      out.add(
        FeedItem(
          title: title,
          link: link.trim(),
          summary: summary == title ? '' : summary,
          published: date,
        ),
      );
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final newest = out
        .map((i) => i.published)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m);
    if (newest != null &&
        newest.isAfter(clock.add(const Duration(minutes: 10)))) {
      final skew = newest.difference(clock);
      return [
        for (final i in out)
          FeedItem(
            title: i.title,
            link: i.link,
            summary: i.summary,
            published: i.published?.subtract(skew),
          ),
      ];
    }
    return out;
  }

  /// Markup and entities out of feed text; long ledes are cut at a sentence.
  static String plain(String s, {int max = 600}) {
    var t = s;
    if (t.contains('<') || t.contains('&')) {
      t = html_parser.parseFragment(t).text ?? t;
    }
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= max) return t;
    final cut = t.substring(0, max);
    final end = cut.lastIndexOf(RegExp(r'[.!?]\s'));
    return end > max ~/ 2 ? cut.substring(0, end + 1) : '${cut.trimRight()}…';
  }

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static const _zones = {
    'gmt': 0,
    'ut': 0,
    'utc': 0,
    'z': 0,
    'est': -5,
    'edt': -4,
    'cst': -6,
    'cdt': -5,
    'mst': -7,
    'mdt': -6,
    'pst': -8,
    'pdt': -7,
    'bst': 1,
    'cet': 1,
    'cest': 2,
  };

  /// RFC 822 (`Wed, 23 Sep 2026 01:08:40 GMT`, `… -0400`, `… EDT`) or ISO
  /// 8601; null when neither parses.
  static DateTime? parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toUtc();
    final m = RegExp(
      r'^(?:[A-Za-z]{3},?\s*)?(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([A-Za-z]+|[+-]\d{2}:?\d{2})?',
    ).firstMatch(s);
    if (m == null) return null;
    final month = _months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    final utc = DateTime.utc(
      year,
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.tryParse(m.group(6) ?? '') ?? 0,
    );
    final zone = (m.group(7) ?? 'gmt').toLowerCase();
    Duration offset;
    final numeric = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(zone);
    if (numeric != null) {
      final minutes =
          int.parse(numeric.group(2)!) * 60 + int.parse(numeric.group(3)!);
      offset = Duration(minutes: numeric.group(1) == '-' ? -minutes : minutes);
    } else {
      offset = Duration(hours: _zones[zone] ?? 0);
    }
    return utc.subtract(offset);
  }

  /// A feed as readable lines, for a feed URL read like a page.
  static String asText(List<FeedItem> items) => [
    for (final i in items)
      '${i.title}${i.published == null ? '' : ' (${i.published!.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC)'}'
          '${i.summary.isEmpty ? '' : ' — ${i.summary}'} ${i.link}',
  ].join('\n');
}
