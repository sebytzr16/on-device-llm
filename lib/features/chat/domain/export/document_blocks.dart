enum DocumentBlockKind { paragraph, heading, bullet, numbered, code, table }

class DocumentBlock {
  final DocumentBlockKind kind;
  final String text;
  final int level;
  final List<List<String>> rows;
  const DocumentBlock(
    this.kind, {
    this.text = '',
    this.level = 1,
    this.rows = const [],
  });
}

/// Small Markdown block parser for portable PDF/DOCX layout. The HTML export
/// uses the full GitHub-flavored parser.
class DocumentBlocks {
  static List<DocumentBlock> parse(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final out = <DocumentBlock>[];
    final paragraph = <String>[];
    final code = <String>[];
    var fenced = false;

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      out.add(
        DocumentBlock(
          DocumentBlockKind.paragraph,
          text: paragraph.join(' ').trim(),
        ),
      );
      paragraph.clear();
    }

    void flushCode() {
      out.add(DocumentBlock(DocumentBlockKind.code, text: code.join('\n')));
      code.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        flushParagraph();
        if (fenced) flushCode();
        fenced = !fenced;
        continue;
      }
      if (fenced) {
        code.add(line);
        continue;
      }
      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }
      final heading = RegExp(r'^\s*(#{1,6})\s+(.+)$').firstMatch(line);
      if (heading != null) {
        flushParagraph();
        out.add(
          DocumentBlock(
            DocumentBlockKind.heading,
            text: heading[2]!.trim(),
            level: heading[1]!.length,
          ),
        );
        continue;
      }
      final bullet = RegExp(r'^\s*[-*+]\s+(.+)$').firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        out.add(
          DocumentBlock(DocumentBlockKind.bullet, text: bullet[1]!.trim()),
        );
        continue;
      }
      final numbered = RegExp(r'^\s*(\d+)[.)]\s+(.+)$').firstMatch(line);
      if (numbered != null) {
        flushParagraph();
        out.add(
          DocumentBlock(
            DocumentBlockKind.numbered,
            text: '${numbered[1]}. ${numbered[2]!.trim()}',
          ),
        );
        continue;
      }
      if (line.contains('|') &&
          i + 1 < lines.length &&
          RegExp(r'^\s*\|?\s*:?-{3,}').hasMatch(lines[i + 1])) {
        flushParagraph();
        final rows = <List<String>>[_cells(line)];
        i += 2;
        while (i < lines.length &&
            lines[i].contains('|') &&
            lines[i].trim().isNotEmpty) {
          rows.add(_cells(lines[i]));
          i++;
        }
        i--;
        out.add(DocumentBlock(DocumentBlockKind.table, rows: rows));
        continue;
      }
      paragraph.add(line.trim());
    }
    flushParagraph();
    if (code.isNotEmpty) flushCode();
    return out;
  }

  static List<String> _cells(String line) {
    var text = line.trim();
    if (text.startsWith('|')) text = text.substring(1);
    if (text.endsWith('|')) text = text.substring(0, text.length - 1);
    return text.split('|').map((cell) => cell.trim()).toList();
  }
}
