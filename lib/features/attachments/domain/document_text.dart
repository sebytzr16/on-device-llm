import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../data/bounded_zip.dart';
import 'scan_options.dart';
import 'package:path/path.dart' as p;

import '../../../data/network/web_search/web_page_reader.dart';
import '../../../core/l10n/l10n.dart';

/// Result of turning a file into text the model can read.
class ExtractedDocument {
  final String text;

  /// Human label of the format that was recognised ("Word document").
  final String format;
  const ExtractedDocument(this.text, this.format);
}

/// On-device text extraction for the file types a phone is likely to hold.
/// Pure Dart for everything but PDF (which goes through [pdfText], injected
/// by the caller so this class stays unit-testable). Nothing leaves the
/// device; unknown binary formats are refused rather than dumped as bytes.
class DocumentText {
  /// Per-document ceiling; the chat still fits the result to the context.
  static const maxChars = 400000;

  /// Blank columns a sheet row is padded to; a cell further right is kept
  /// after the last padded one instead of after thousands of tabs.
  static const maxSheetColumns = 256;
  static const maxArchiveEntries = 2048;
  static const maxExpandedArchiveBytes = 64 * 1024 * 1024;
  static const maxArchiveEntryBytes = 32 * 1024 * 1024;

  static const _plainExtensions = {
    '.txt': 'Plain text',
    '.text': 'Plain text',
    '.md': 'Markdown',
    '.markdown': 'Markdown',
    '.csv': 'CSV table',
    '.tsv': 'TSV table',
    '.json': 'JSON',
    '.jsonl': 'JSON lines',
    '.xml': 'XML',
    '.yaml': 'YAML',
    '.yml': 'YAML',
    '.toml': 'TOML',
    '.ini': 'Config file',
    '.cfg': 'Config file',
    '.conf': 'Config file',
    '.log': 'Log file',
    '.srt': 'Subtitles',
    '.vtt': 'Subtitles',
    '.tex': 'LaTeX',
    '.rst': 'reStructuredText',
    '.org': 'Org file',
    '.env': 'Environment file',
    '.properties': 'Properties file',
    '.gradle': 'Gradle script',
    '.dart': 'Dart source',
    '.py': 'Python source',
    '.js': 'JavaScript source',
    '.mjs': 'JavaScript source',
    '.ts': 'TypeScript source',
    '.tsx': 'TypeScript source',
    '.jsx': 'JavaScript source',
    '.java': 'Java source',
    '.kt': 'Kotlin source',
    '.kts': 'Kotlin script',
    '.c': 'C source',
    '.h': 'C header',
    '.cc': 'C++ source',
    '.cpp': 'C++ source',
    '.hpp': 'C++ header',
    '.cs': 'C# source',
    '.go': 'Go source',
    '.rs': 'Rust source',
    '.rb': 'Ruby source',
    '.php': 'PHP source',
    '.swift': 'Swift source',
    '.m': 'Objective-C source',
    '.sh': 'Shell script',
    '.bash': 'Shell script',
    '.zsh': 'Shell script',
    '.bat': 'Batch script',
    '.ps1': 'PowerShell script',
    '.sql': 'SQL',
    '.r': 'R source',
    '.lua': 'Lua source',
    '.css': 'Stylesheet',
    '.scss': 'Stylesheet',
    '.less': 'Stylesheet',
    '.cmake': 'CMake script',
    '.mk': 'Makefile',
    '.makefile': 'Makefile',
    '.dockerfile': 'Dockerfile',
    '.svg': 'SVG markup',
    '.ipynb': 'Notebook',
  };

  static const _htmlExtensions = {'.html', '.htm', '.xhtml', '.mhtml'};

  /// Extracts [bytes] named [name]. [pdfText] renders PDF pages to text on
  /// the platform; when null, PDFs are refused with a clear message.
  /// [cancelled] is checked before expensive operations and between pages.
  static Future<ExtractedDocument> extract(
    Uint8List bytes,
    String name, {
    Future<String> Function(Uint8List bytes)? pdfText,
    String localeCode = '',
    bool Function()? cancelled,
  }) async {
    final t = stringsFor(localeCode);
    final ext = p.extension(name).toLowerCase();
    if (ext == '.pdf' || _startsWith(bytes, '%PDF')) {
      if (pdfText == null) {
        throw FormatException(t.documentPdfUnavailable);
      }
      if (cancelled?.call() == true) throw const ScanCancelled();
      return ExtractedDocument(
        _bounded(await pdfText(bytes), t.documentScanTextLimit),
        'PDF',
      );
    }
    // ZIP inflate and Office/HTML scans of large files froze the UI for
    // seconds (audit P3-27); PDFs need the platform channel and stay here.
    if (_isZip(bytes) || bytes.length > isolateThreshold) {
      return Isolate.run(() => _extractOther(bytes, name, ext, t, cancelled));
    }
    return _extractOther(bytes, name, ext, t, cancelled);
  }

  /// Files above this size are extracted on a background isolate.
  static const isolateThreshold = 256 * 1024;

  static ExtractedDocument _extractOther(
    Uint8List bytes,
    String name,
    String ext,
    AppLocalizations t,
    bool Function()? cancelled,
  ) {
    if (_htmlExtensions.contains(ext)) {
      final (title, text) = WebPageReader.extract(_decode(bytes));
      return ExtractedDocument(
        _bounded(
          title.isEmpty ? text : '$title\n\n$text',
          t.documentScanTextLimit,
        ),
        'Web page',
      );
    }
    if (_plainExtensions.containsKey(ext)) {
      return ExtractedDocument(
        _bounded(_decode(bytes), t.documentScanTextLimit),
        _plainExtensions[ext]!,
      );
    }
    if (ext == '.rtf' || _startsWith(bytes, '{\\rtf')) {
      return ExtractedDocument(
        _bounded(rtfToText(_decode(bytes)), t.documentScanTextLimit),
        'RTF',
      );
    }
    if (_isZip(bytes)) {
      var archive = readZipMetadata(
        InputMemoryStream(bytes),
        maxEntries: maxArchiveEntries,
        strings: t,
      );
      validateArchive(archive, strings: t);
      var actual = 0;
      final inflated = Archive();
      for (final file in archive.files) {
        if (cancelled?.call() == true) throw const ScanCancelled();
        if (!file.isFile) continue;
        final out = BytesBuilder(copy: false);
        final remaining = maxExpandedArchiveBytes - actual;
        actual += inflateZipEntry(
          file,
          remaining < maxArchiveEntryBytes ? remaining : maxArchiveEntryBytes,
          out.add,
          strings: t,
        );
        inflated.addFile(ArchiveFile.bytes(file.name, out.takeBytes()));
      }
      archive = inflated;
      String? entry(String path) {
        final f = archive.findFile(path);
        return f == null ? null : _decode(f.content as List<int>);
      }

      final doc = entry('word/document.xml');
      if (doc != null) {
        final rels = entry('word/_rels/document.xml.rels');
        final relationships = rels == null
            ? <String, List<String>>{}
            : _officeRelationships(rels);
        final out = StringBuffer();
        out.writeln(
          officeXmlToText(
            doc,
            paragraph: 'w:p',
            row: 'w:tr',
            cell: 'w:tc',
            tab: 'w:tab',
          ),
        );
        for (final kind in ['header', 'footer']) {
          for (final target in relationships[kind] ?? const <String>[]) {
            final part = entry(target);
            if (part == null) continue;
            final partText = officeXmlToText(
              part,
              paragraph: 'w:p',
              row: 'w:tr',
              cell: 'w:tc',
              tab: 'w:tab',
            );
            if (partText.isNotEmpty) {
              out.writeln(
                '--- ${kind[0].toUpperCase()}${kind.substring(1)} ---',
              );
              out.writeln(partText);
            }
          }
        }
        for (final kind in ['footnotes', 'endnotes']) {
          final targets = relationships[kind];
          if (targets == null || targets.isEmpty) continue;
          final part = entry(targets.first);
          if (part == null) continue;
          final partText = officeXmlToText(
            part,
            paragraph: 'w:p',
            row: 'w:tr',
            cell: 'w:tc',
            tab: 'w:tab',
          );
          if (partText.isNotEmpty) {
            out.writeln('--- ${kind[0].toUpperCase()}${kind.substring(1)} ---');
            out.writeln(partText);
          }
        }
        final images = relationships['image'] ?? const <String>[];
        if (images.isNotEmpty) {
          out.writeln(t.documentImagesOmitted(images.length));
        }
        return ExtractedDocument(
          _bounded(out.toString(), t.documentScanTextLimit),
          'Word document',
        );
      }
      final slides =
          archive.files
              .where(
                (f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name),
              )
              .toList()
            ..sort(
              (a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)),
            );
      if (slides.isNotEmpty) {
        final out = StringBuffer();
        for (final s in slides) {
          if (cancelled?.call() == true) throw const ScanCancelled();
          out.writeln('--- Slide ${_slideNumber(s.name)} ---');
          out.writeln(
            officeXmlToText(_decode(s.content as List<int>), paragraph: 'a:p'),
          );
        }
        return ExtractedDocument(
          _bounded(out.toString(), t.documentScanTextLimit),
          'Presentation',
        );
      }
      final sheets =
          archive.files
              .where(
                (f) =>
                    RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name),
              )
              .toList()
            ..sort(
              (a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)),
            );
      if (sheets.isNotEmpty) {
        final shared = sharedStrings(entry('xl/sharedStrings.xml') ?? '');
        final out = StringBuffer();
        for (final s in sheets) {
          if (cancelled?.call() == true) throw const ScanCancelled();
          out.writeln('--- Sheet ${_slideNumber(s.name)} ---');
          out.writeln(sheetToText(_decode(s.content as List<int>), shared));
        }
        return ExtractedDocument(
          _bounded(out.toString(), t.documentScanTextLimit),
          'Spreadsheet',
        );
      }
      final content = entry('content.xml');
      if (content != null) {
        return ExtractedDocument(
          _bounded(
            officeXmlToText(
              content,
              paragraph: 'text:p',
              heading: 'text:h',
              row: 'table:table-row',
              cell: 'table:table-cell',
              tab: 'text:tab',
            ),
            t.documentScanTextLimit,
          ),
          switch (ext) {
            '.odp' => 'Presentation',
            '.ods' => 'Spreadsheet',
            _ => 'OpenDocument text',
          },
        );
      }
      String? opfPath;
      final container = entry('META-INF/container.xml');
      if (container != null) {
        opfPath = _opfRootfile(container);
      }
      List<String>? spine;
      if (opfPath != null) {
        final opf = entry(opfPath);
        if (opf != null) {
          spine = _spineOrder(opf, opfPath);
        }
      }

      if (spine != null && spine.isNotEmpty) {
        final out = StringBuffer();
        for (final href in spine) {
          if (cancelled?.call() == true) throw const ScanCancelled();
          // _spineOrder already resolved each href against the OPF folder.
          final part = entry(href);
          if (part == null) continue;
          final (title, text) = WebPageReader.extract(part);
          if (text.isNotEmpty) {
            out.writeln(
              '--- ${title.isNotEmpty ? title : p.basename(href)} ---',
            );
            out.writeln(text);
          }
          if (out.length > maxChars) break;
        }
        if (out.isNotEmpty) {
          return ExtractedDocument(
            _bounded(out.toString(), t.documentScanTextLimit),
            'EPUB book',
          );
        }
      }

      // Fallback: the package or its spine is missing or empty — chapters
      // are read in file order and navigation is not excluded.
      final members =
          archive.files
              .where(
                (f) => RegExp(
                  r'\.x?html?$',
                  caseSensitive: false,
                ).hasMatch(f.name),
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (members.isNotEmpty) {
        final out = StringBuffer();
        for (final f in members) {
          if (cancelled?.call() == true) throw const ScanCancelled();
          final (_, text) = WebPageReader.extract(
            _decode(f.content as List<int>),
          );
          if (text.isNotEmpty) out.writeln(text);
          if (out.length > maxChars) break;
        }
        out.writeln(t.documentEpubFallback);
        return ExtractedDocument(
          _bounded(out.toString(), t.documentScanTextLimit),
          'EPUB book',
        );
      }
      throw FormatException(t.documentArchiveEmpty);
    }
    if (looksLikeText(bytes)) {
      return ExtractedDocument(
        _bounded(_decode(bytes), t.documentScanTextLimit),
        'Text file',
      );
    }
    throw FormatException(t.documentUnsupported(ext.isEmpty ? '' : ' ($ext)'));
  }

  /// Rejects expansion bombs before any lazy ZIP entry is decompressed.
  static void validateArchive(Archive archive, {AppLocalizations? strings}) {
    final t = strings ?? stringsFor('');
    if (archive.files.length > maxArchiveEntries) {
      throw FormatException(t.documentArchiveManyFiles);
    }
    var expanded = 0;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.size < 0 || file.size > maxArchiveEntryBytes) {
        throw FormatException(t.documentArchiveEntryLarge);
      }
      expanded += file.size;
      if (expanded > maxExpandedArchiveBytes) {
        throw FormatException(t.documentArchiveExpandedLarge);
      }
    }
  }

  static int _slideNumber(String name) =>
      int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(name)?.group(1) ?? '') ??
      0;

  /// Relationship targets of `word/_rels/document.xml.rels`, grouped by
  /// relationship type suffix (header, footer, footnotes, endnotes, image).
  static Map<String, List<String>> _officeRelationships(String rels) {
    final out = <String, List<String>>{};
    for (final m in RegExp(
      r'<Relationship\b([^>]*)>',
      dotAll: true,
    ).allMatches(rels)) {
      final attrs = m.group(1)!;
      final type = _attribute(attrs, 'Type');
      final target = _attribute(attrs, 'Target');
      if (type.isEmpty ||
          target.isEmpty ||
          target.startsWith('/') ||
          RegExp(r'^[a-zA-Z]+:').hasMatch(target))
        continue;
      out.putIfAbsent(type.split('/').last, () => []).add('word/$target');
    }
    return out;
  }

  /// The value of [name] from an XML attribute string.
  static String _attribute(String attrs, String name) {
    final m = RegExp('\\b${RegExp.escape(name)}="([^"]*)"').firstMatch(attrs);
    return m == null ? '' : m.group(1)!;
  }

  /// The OPF package path declared by `META-INF/container.xml`.
  static String? _opfRootfile(String containerXml) {
    final m = RegExp(
      r'<rootfile\b[^>]*\bfull-path="([^"]*)"',
    ).firstMatch(containerXml);
    return m == null ? null : m.group(1)!;
  }

  /// Spine itemref targets in document order, navigation items excluded,
  /// resolved against the OPF file's directory.
  static List<String> _spineOrder(String opfXml, String opfPath) {
    final manifest = <String, String>{};
    for (final m in RegExp(
      r'<item\b([^>]*)>',
      dotAll: true,
    ).allMatches(opfXml)) {
      final attrs = m.group(1)!;
      final id = _attribute(attrs, 'id');
      final href = _attribute(attrs, 'href');
      final properties = _attribute(attrs, 'properties');
      if (id.isNotEmpty &&
          href.isNotEmpty &&
          !properties.split(RegExp(r'\s+')).contains('nav')) {
        manifest[id] = href;
      }
    }
    final spineXml =
        RegExp(
          r'<spine\b[^>]*>(.*?)</spine>',
          dotAll: true,
        ).firstMatch(opfXml)?.group(1) ??
        '';
    final order = <String>[];
    for (final m in RegExp(
      r'<itemref\b([^>]*)>',
      dotAll: true,
    ).allMatches(spineXml)) {
      final idref = _attribute(m.group(1)!, 'idref');
      final href = manifest[idref];
      if (href == null) continue;
      order.add(_resolveHref(opfPath, href));
    }
    return order;
  }

  /// An EPUB href resolved against its container file, rooted at the archive.
  static String _resolveHref(String opfPath, String href) {
    if (href.startsWith('/')) return href;
    final base = p.dirname(opfPath);
    var resolved = base == '.' ? href : '$base/$href';
    return resolved.replaceAll(RegExp(r'^\.\/'), '');
  }

  static bool _startsWith(Uint8List b, String magic) =>
      b.length >= magic.length &&
      String.fromCharCodes(b.sublist(0, magic.length)) == magic;

  static bool _isZip(Uint8List b) =>
      b.length > 4 &&
      b[0] == 0x50 &&
      b[1] == 0x4B &&
      (b[2] == 3 || b[2] == 5 || b[2] == 7);

  /// Share of NUL bytes (in the first 4 KB) that makes a BOM-less file look
  /// like UTF-16: ASCII text in UTF-16 has a NUL every second byte.
  static const _utf16NulRatio = 0.25;

  /// Byte-order marks pick UTF-16 endianness; a BOM-less file with many NUL
  /// bytes is decoded as UTF-16 too. UTF-8 and the Latin-1 fallback keep
  /// their previous behaviour. Normalisation (BOM removal) happens after
  /// decoding, never on raw bytes.
  static String _decode(List<int> bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _utf16Decode(bytes, 2, true).replaceFirst('\uFEFF', '');
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _utf16Decode(bytes, 2, false).replaceFirst('\uFEFF', '');
      }
      if (_nulRatio(bytes) > _utf16NulRatio) {
        return _utf16Decode(bytes, 0, _utf16LittleEndianFirst(bytes));
      }
    }
    try {
      return utf8.decode(bytes).replaceFirst('\uFEFF', '');
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// Decodes [bytes] from [start] as UTF-16 code units; surrogate pairs are
  /// kept as code units so round-tripping stays lossless.
  static String _utf16Decode(List<int> bytes, int start, bool littleEndian) {
    final codes = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      codes.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    while (codes.isNotEmpty && codes.last == 0) {
      codes.removeLast();
    }
    return String.fromCharCodes(codes);
  }

  /// NUL share of the first 4 KB of [bytes].
  static double _nulRatio(List<int> bytes) {
    final sample = bytes.sublist(0, bytes.length.clamp(0, 4096));
    if (sample.isEmpty) return 0;
    var nul = 0;
    for (final b in sample) {
      if (b == 0) nul++;
    }
    return nul / sample.length;
  }

  /// UTF-16LE ASCII puts NUL bytes at odd indexes, UTF-16BE at even indexes;
  /// the side with more NULs picks the byte order.
  static bool _utf16LittleEndianFirst(List<int> bytes) {
    var oddNul = 0, evenNul = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0) {
        if (i.isEven)
          evenNul++;
        else
          oddNul++;
      }
    }
    return oddNul >= evenNul;
  }

  /// Trims and bounds [s] to [maxChars], reserving room for [truncationNotice]
  /// and appending it after the cut so the limit notice is never removed by
  /// the truncation itself.
  static String _bounded(String s, String truncationNotice) {
    final t = s.replaceAll('\r\n', '\n').trim();
    if (t.length <= maxChars) return t;
    final room = maxChars - truncationNotice.length;
    return '${t.substring(0, room)}$truncationNotice';
  }

  /// A file with no NUL bytes and mostly printable characters is text even
  /// when its extension is unknown.
  static bool looksLikeText(Uint8List b) {
    if (b.isEmpty) return false;
    final sample = b.sublist(0, b.length.clamp(0, 4096));
    var printable = 0;
    for (final c in sample) {
      if (c == 0) return false;
      if (c >= 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) printable++;
    }
    return printable / sample.length > 0.95;
  }

  /// Office Open XML / OpenDocument text: paragraphs (and headings, table
  /// rows) become lines, cells are tab-separated, tags are dropped.
  static String officeXmlToText(
    String xml, {
    required String paragraph,
    String? heading,
    String? row,
    String? cell,
    String? tab,
  }) {
    var s = xml;
    // Deleted revision text is not part of the visible document; inserted
    // text is kept (its tags are stripped below).
    s = s.replaceAll(RegExp(r'<w:del\b[^>]*>.*?</w:del>', dotAll: true), '');
    if (tab != null) s = s.replaceAll(RegExp('<$tab\\b[^>]*/>'), '\t');
    s = s.replaceAll(
      RegExp(r'<w:br\b[^>]*/>|<text:line-break\b[^>]*/>|<a:br\b[^>]*/>'),
      '\n',
    );
    if (cell != null) {
      // A paragraph ending a cell ends the cell, not the row.
      s = s.replaceAll(RegExp('</$paragraph>\\s*</$cell>'), '\t');
      s = s.replaceAll(RegExp('</$cell>'), '\t');
    }
    for (final block in [paragraph, ?heading, ?row]) {
      s = s.replaceAll(RegExp('</$block>'), '\n');
    }
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    return _unescape(s)
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t]+$'), ''))
        .where((l) => l.trim().isNotEmpty)
        .join('\n');
  }

  /// `xl/sharedStrings.xml` → the strings by index.
  static List<String> sharedStrings(String xml) => [
    for (final m in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(xml))
      _unescape(m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '')),
  ];

  /// One worksheet: rows as lines, cells tab-separated, shared strings and
  /// inline strings resolved, formulas replaced by their cached value.
  /// Cells sit under the column their `r="C2"` reference names: the file
  /// omits empty cells, so file order alone shifts values left (audit P1-14).
  static String sheetToText(String xml, List<String> shared) {
    final out = StringBuffer();
    for (final row in RegExp(
      r'<row\b[^>]*>(.*?)</row>',
      dotAll: true,
    ).allMatches(xml)) {
      final cells = <String>[];
      for (final c in RegExp(
        r'<c\b([^>]*?)(?:/>|>(.*?)</c>)',
        dotAll: true,
      ).allMatches(row.group(1)!)) {
        final attrs = c.group(1) ?? '', body = c.group(2) ?? '';
        final type = RegExp(r'\bt="([^"]*)"').firstMatch(attrs)?.group(1);
        var value =
            RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ??
            '';
        if (type == 's') {
          final i = int.tryParse(value);
          value = i != null && i >= 0 && i < shared.length ? shared[i] : '';
        } else if (type == 'inlineStr') {
          value = body.replaceAll(RegExp(r'<[^>]+>'), '');
        } else if (type == 'b') {
          value = value == '1' ? 'TRUE' : 'FALSE';
        }
        final column = _columnIndex(attrs);
        if (column != null && column < maxSheetColumns) {
          while (cells.length < column) {
            cells.add('');
          }
        }
        cells.add(_unescape(value));
      }
      if (cells.any((c) => c.trim().isNotEmpty)) out.writeln(cells.join('\t'));
    }
    return out.toString().trimRight();
  }

  /// The zero-based column of a cell's `r="AB12"` reference, or null.
  static int? _columnIndex(String attrs) {
    final letters = RegExp(r'\br="([A-Z]{1,3})\d+"').firstMatch(attrs);
    if (letters == null) return null;
    var n = 0;
    for (final unit in letters.group(1)!.codeUnits) {
      n = n * 26 + unit - 64;
    }
    return n - 1;
  }

  /// RTF: control words and groups stripped, `\par` kept as line breaks,
  /// hex escapes decoded. Good enough for notes and exported documents.
  static String rtfToText(String rtf) {
    var s = rtf;
    // Destination groups (fonts, colours, metadata, pictures) carry no prose.
    s = s.replaceAll(
      RegExp(r'\{\\\*\\[a-z]+[^{}]*(\{[^{}]*\})*[^{}]*\}', dotAll: true),
      '',
    );
    s = s.replaceAll(
      RegExp(
        r'\{\\(?:fonttbl|colortbl|stylesheet|info|pict)[^{}]*(\{[^{}]*\})*[^{}]*\}',
        dotAll: true,
      ),
      '',
    );
    s = s.replaceAll(RegExp(r'\\(?:par|line)\b\s?'), '\n');
    s = s.replaceAll(RegExp(r'\\tab\b\s?'), '\t');
    s = s.replaceAllMapped(
      RegExp(r"\\'([0-9a-fA-F]{2})"),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    s = s.replaceAllMapped(
      RegExp(r'\\u(-?\d+)\s?\??'),
      (m) => String.fromCharCode((int.parse(m.group(1)!) + 65536) % 65536),
    );
    s = s.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
    s = s.replaceAll(RegExp(r'\\[^a-zA-Z]'), '');
    s = s.replaceAll(RegExp(r'[{}]'), '');
    return s
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(
        RegExp(r'&#(x?)([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(
          int.parse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16),
        ),
      )
      .replaceAll('&amp;', '&');
}
