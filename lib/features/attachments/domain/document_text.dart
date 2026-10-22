import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../data/network/web_search/web_page_reader.dart';

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
  static Future<ExtractedDocument> extract(
    Uint8List bytes,
    String name, {
    Future<String> Function(Uint8List bytes)? pdfText,
  }) async {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.pdf' || _startsWith(bytes, '%PDF')) {
      if (pdfText == null) {
        throw const FormatException('PDF text extraction is unavailable.');
      }
      return ExtractedDocument(_bounded(await pdfText(bytes)), 'PDF');
    }
    if (_htmlExtensions.contains(ext)) {
      final (title, text) = WebPageReader.extract(_decode(bytes));
      return ExtractedDocument(
        _bounded(title.isEmpty ? text : '$title\n\n$text'),
        'Web page',
      );
    }
    if (_plainExtensions.containsKey(ext)) {
      return ExtractedDocument(
        _bounded(_decode(bytes)),
        _plainExtensions[ext]!,
      );
    }
    if (ext == '.rtf' || _startsWith(bytes, '{\\rtf')) {
      return ExtractedDocument(_bounded(rtfToText(_decode(bytes))), 'RTF');
    }
    if (_isZip(bytes)) {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      validateArchive(archive);
      String? entry(String path) {
        final f = archive.findFile(path);
        return f == null ? null : _decode(f.content as List<int>);
      }

      final doc = entry('word/document.xml');
      if (doc != null) {
        return ExtractedDocument(
          _bounded(
            officeXmlToText(
              doc,
              paragraph: 'w:p',
              row: 'w:tr',
              cell: 'w:tc',
              tab: 'w:tab',
            ),
          ),
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
          out.writeln('--- Slide ${_slideNumber(s.name)} ---');
          out.writeln(
            officeXmlToText(_decode(s.content as List<int>), paragraph: 'a:p'),
          );
        }
        return ExtractedDocument(_bounded(out.toString()), 'Presentation');
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
          out.writeln('--- Sheet ${_slideNumber(s.name)} ---');
          out.writeln(sheetToText(_decode(s.content as List<int>), shared));
        }
        return ExtractedDocument(_bounded(out.toString()), 'Spreadsheet');
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
          ),
          switch (ext) {
            '.odp' => 'Presentation',
            '.ods' => 'Spreadsheet',
            _ => 'OpenDocument text',
          },
        );
      }
      final pages =
          archive.files
              .where(
                (f) => RegExp(
                  r'\.x?html?$',
                  caseSensitive: false,
                ).hasMatch(f.name),
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (pages.isNotEmpty) {
        final out = StringBuffer();
        for (final f in pages) {
          final (_, text) = WebPageReader.extract(
            _decode(f.content as List<int>),
          );
          if (text.isNotEmpty) out.writeln(text);
          if (out.length > maxChars) break;
        }
        return ExtractedDocument(_bounded(out.toString()), 'EPUB book');
      }
      throw const FormatException('This archive holds no readable document.');
    }
    if (looksLikeText(bytes)) {
      return ExtractedDocument(_bounded(_decode(bytes)), 'Text file');
    }
    throw FormatException(
      'Unsupported file type${ext.isEmpty ? '' : ' ($ext)'}. Supported: text, code, Markdown, CSV, JSON, HTML, PDF, Word, PowerPoint, Excel, OpenDocument, EPUB, RTF.',
    );
  }

  /// Rejects expansion bombs before any lazy ZIP entry is decompressed.
  static void validateArchive(Archive archive) {
    if (archive.files.length > maxArchiveEntries) {
      throw const FormatException('The archive contains too many files.');
    }
    var expanded = 0;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.size < 0 || file.size > maxArchiveEntryBytes) {
        throw const FormatException('An archived file is too large.');
      }
      expanded += file.size;
      if (expanded > maxExpandedArchiveBytes) {
        throw const FormatException(
          'The archive expands beyond the safe size limit.',
        );
      }
    }
  }

  static int _slideNumber(String name) =>
      int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(name)?.group(1) ?? '') ??
      0;

  static bool _startsWith(Uint8List b, String magic) =>
      b.length >= magic.length &&
      String.fromCharCodes(b.sublist(0, magic.length)) == magic;

  static bool _isZip(Uint8List b) =>
      b.length > 4 &&
      b[0] == 0x50 &&
      b[1] == 0x4B &&
      (b[2] == 3 || b[2] == 5 || b[2] == 7);

  /// UTF-8 first; a BOM-less Latin-1 file still comes through readable.
  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes).replaceFirst('\uFEFF', '');
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static String _bounded(String s) {
    final t = s.replaceAll('\r\n', '\n').trim();
    return t.length > maxChars ? t.substring(0, maxChars) : t;
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
        cells.add(_unescape(value));
      }
      if (cells.any((c) => c.trim().isNotEmpty)) out.writeln(cells.join('\t'));
    }
    return out.toString().trimRight();
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
