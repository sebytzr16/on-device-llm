import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/features/attachments/domain/document_text.dart';

Uint8List zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, text) {
    final bytes = utf8.encode(text);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// [text] as UTF-16 code units in [endian] order, optionally prefixed with a
/// BOM that [DocumentText._decode] strips after decoding.
Uint8List utf16(String text, Endian endian, {bool bom = true}) {
  final data = ByteData.sublistView(Uint8List(2 + text.codeUnits.length * 2));
  var offset = 0;
  if (bom) {
    data.setUint8(0, endian == Endian.little ? 0xFF : 0xFE);
    data.setUint8(1, endian == Endian.little ? 0xFE : 0xFF);
    offset = 2;
  }
  for (final unit in text.codeUnits) {
    data.setUint16(offset, unit, endian);
    offset += 2;
  }
  return data.buffer.asUint8List();
}

void main() {
  test('forged-size DOCX is bounded by actual inflation', () async {
    final bomb = zip({
      'word/document.xml': 'x' * (DocumentText.maxArchiveEntryBytes + 1),
    });
    final data = ByteData.sublistView(bomb);
    for (var i = 0; i + 46 < bomb.length; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        data.setUint32(i + 24, 1024, Endian.little);
      }
      if (data.getUint32(i, Endian.little) == 0x04034b50) {
        data.setUint32(i + 22, 1024, Endian.little);
      }
    }
    await expectLater(
      DocumentText.extract(bomb, 'bomb.docx'),
      throwsFormatException,
    );
  });

  test('large files are read off the UI isolate (P3-27)', () async {
    final big = 'word ' * (DocumentText.isolateThreshold ~/ 4);
    final doc = await DocumentText.extract(bytes(big), 'big.txt');
    expect(doc.text, startsWith('word word'));
    await expectLater(
      DocumentText.extract(
        Uint8List(DocumentText.isolateThreshold + 1),
        'blob.xyz',
      ),
      throwsFormatException,
    );
  });

  test('archive expansion limits are checked before decompression', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.noData('word/document.xml')
          ..size = DocumentText.maxArchiveEntryBytes + 1,
      );
    expect(
      () => DocumentText.validateArchive(archive),
      throwsA(isA<FormatException>()),
    );
  });

  test('plain, code, csv and html files are read as text', () async {
    expect(
      (await DocumentText.extract(bytes('hello\r\nworld'), 'notes.txt')).text,
      'hello\nworld',
    );
    final code = await DocumentText.extract(
      bytes('void main() {}'),
      'main.dart',
    );
    expect(code.format, 'Dart source');
    final html = await DocumentText.extract(
      bytes('<html><title>T</title><body><p>Body text here.</p></body></html>'),
      'page.html',
    );
    expect(html.text, 'T\n\nBody text here.');
    // Unknown extension but printable content still counts as text.
    final sniffed = await DocumentText.extract(bytes('key=value'), 'file.xyz');
    expect(sniffed.format, 'Text file');
  });

  test('Word, PowerPoint, Excel and OpenDocument text is extracted', () async {
    final docx = await DocumentText.extract(
      zip({
        'word/document.xml':
            '<w:document><w:body><w:p><w:r><w:t>First &amp; para</w:t></w:r></w:p>'
            '<w:tbl><w:tr><w:tc><w:p><w:t>A1</w:t></w:p></w:tc><w:tc><w:p><w:t>B1</w:t></w:p></w:tc></w:tr></w:tbl>'
            '</w:body></w:document>',
      }),
      'report.docx',
    );
    expect(docx.format, 'Word document');
    expect(docx.text, contains('First & para'));
    expect(docx.text, contains('A1\tB1'));

    final pptx = await DocumentText.extract(
      zip({
        'ppt/slides/slide2.xml':
            '<p:sld><a:p><a:r><a:t>Second</a:t></a:r></a:p></p:sld>',
        'ppt/slides/slide1.xml':
            '<p:sld><a:p><a:r><a:t>Title</a:t></a:r></a:p></p:sld>',
      }),
      'deck.pptx',
    );
    expect(pptx.text, '--- Slide 1 ---\nTitle\n--- Slide 2 ---\nSecond');

    final xlsx = await DocumentText.extract(
      zip({
        'xl/sharedStrings.xml':
            '<sst><si><t>Name</t></si><si><r><t>Qty</t></r></si></sst>',
        'xl/worksheets/sheet1.xml':
            '<worksheet><sheetData>'
            '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
            '<row r="2"><c r="A2" t="inlineStr"><is><t>Bolt</t></is></c><c r="B2"><v>12</v></c></row>'
            '</sheetData></worksheet>',
      }),
      'stock.xlsx',
    );
    expect(xlsx.text, '--- Sheet 1 ---\nName\tQty\nBolt\t12');

    final odt = await DocumentText.extract(
      zip({
        'content.xml':
            '<office:document-content><office:body><text:h>Heading</text:h>'
            '<text:p>Para one.</text:p><text:p>Para<text:line-break/>two</text:p></office:body></office:document-content>',
      }),
      'letter.odt',
    );
    expect(odt.text, 'Heading\nPara one.\nPara\ntwo');
  });

  test('sparse XLSX rows keep cells under their own column (P1-14)', () {
    final text = DocumentText.sheetToText(
      '<worksheet><sheetData>'
      '<row r="1"><c r="A1" t="inlineStr"><is><t>Name</t></is></c>'
      '<c r="B1" t="inlineStr"><is><t>Size</t></is></c>'
      '<c r="C1" t="inlineStr"><is><t>Qty</t></is></c></row>'
      '<row r="2"><c r="A2" t="inlineStr"><is><t>Bolt</t></is></c>'
      '<c r="C2"><v>12</v></c></row>'
      '<row r="3"><c r="B3"><v>7</v></c></row>'
      '<row r="4"><c r="XFD4"><v>9</v></c></row>'
      '</sheetData></worksheet>',
      const [],
    );
    final lines = text.split('\n');
    expect(lines.take(3), ['Name\tSize\tQty', 'Bolt\t\t12', '\t7']);
    expect(
      lines[3].split('\t').length,
      lessThanOrEqualTo(DocumentText.maxSheetColumns + 1),
      reason: 'a far-right cell must not pad thousands of blank columns',
    );
    expect(lines[3], endsWith('9'));
  });

  test(
    'EPUB chapters and RTF prose come through; binaries are refused',
    () async {
      final epub = await DocumentText.extract(
        zip({
          'META-INF/container.xml': '<container/>',
          'OEBPS/ch1.xhtml':
              '<html><body><p>Chapter one text.</p></body></html>',
        }),
        'book.epub',
      );
      expect(epub.format, 'EPUB book');
      expect(epub.text, contains('Chapter one text.'));

      final rtf = await DocumentText.extract(
        bytes(
          r'{\rtf1\ansi{\fonttbl{\f0 Arial;}}\f0\fs24 Hello \b bold\b0  world.\par Second line\par}',
        ),
        'note.rtf',
      );
      expect(rtf.text, 'Hello bold world.\nSecond line');

      await expectLater(
        DocumentText.extract(
          Uint8List.fromList([0, 1, 2, 255, 0, 7]),
          'blob.bin',
        ),
        throwsFormatException,
      );
      await expectLater(
        DocumentText.extract(bytes('%PDF-1.4 ...'), 'file.pdf'),
        throwsFormatException,
        reason: 'no pdf backend in a pure Dart test',
      );
      final pdf = await DocumentText.extract(
        bytes('%PDF-1.4 ...'),
        'file.pdf',
        pdfText: (_) async => 'From pdfium',
      );
      expect(pdf.text, 'From pdfium');
    },
  );

  test(
    'deleted revisions are not extracted and inserted text is (A08)',
    () async {
      final docx = await DocumentText.extract(
        zip({
          'word/document.xml':
              '<w:document><w:body><w:p><w:r><w:t>keep this</w:t></w:r>'
              '<w:del><w:r><w:delText>remove me</w:delText></w:r></w:del>'
              '<w:ins><w:r><w:t> instead</w:t></w:r></w:ins></w:p>'
              '<w:p><w:r><w:t>separate paragraph</w:t></w:r></w:p>'
              '</w:body></w:document>',
        }),
        'report.docx',
      );
      expect(docx.text, 'keep this instead\nseparate paragraph');
      expect(docx.text, isNot(contains('remove me')));
    },
  );

  test('Word headers, footers, footnotes and embedded images (A08)', () async {
    final docx = await DocumentText.extract(
      zip({
        'word/document.xml':
            '<w:document><w:body><w:p><w:r><w:t>Body text.</w:t></w:r></w:p></w:body></w:document>',
        'word/_rels/document.xml.rels':
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>'
            '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
            '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>'
            '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>'
            '</Relationships>',
        'word/header1.xml':
            '<w:hdr><w:p><w:r><w:t>CONFIDENTIAL</w:t></w:r></w:p></w:hdr>',
        'word/footer1.xml':
            '<w:ftr><w:p><w:r><w:t>Page 1</w:t></w:r></w:p></w:ftr>',
        'word/footnotes.xml':
            '<w:footnotes><w:footnote w:id="0"><w:p><w:r><w:t>Note one.</w:t></w:r></w:p></w:footnote></w:footnotes>',
        'word/media/image1.png': 'not-a-png',
      }),
      'report.docx',
    );
    expect(docx.format, 'Word document');
    expect(docx.text, contains('Body text.'));
    expect(docx.text, contains('--- Header ---\nCONFIDENTIAL'));
    expect(docx.text, contains('--- Footer ---\nPage 1'));
    expect(docx.text, contains('--- Footnotes ---\nNote one.'));
    expect(docx.text, contains('not extracted'));
  });

  test('EPUB spine order overrides file order; navigation is excluded (A09)', () async {
    final epub = await DocumentText.extract(
      zip({
        'META-INF/container.xml':
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
            '</container>',
        'OEBPS/content.opf':
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
            '<manifest>'
            '<item id="c10" href="ch10.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            '</manifest>'
            '<spine><itemref idref="c10"/><itemref idref="c2"/></spine>'
            '</package>',
        'OEBPS/ch10.xhtml':
            '<html><head><title>Chapter Ten</title></head><body><p>Tenth text.</p></body></html>',
        'OEBPS/ch2.xhtml': '<html><body><p>Second text.</p></body></html>',
        'OEBPS/nav.xhtml': '<html><body><p>Navigation text.</p></body></html>',
      }),
      'book.epub',
    );
    expect(epub.format, 'EPUB book');
    expect(epub.text, startsWith('--- Chapter Ten ---\nTenth text.'));
    expect(epub.text, contains('\n--- ch2.xhtml ---\nSecond text.'));
    expect(epub.text, isNot(contains('Navigation text.')));
  });

  test(
    'truncated text keeps its limit warning instead of losing it (A07)',
    () async {
      final long = 'x' * (DocumentText.maxChars + 1000);
      final doc = await DocumentText.extract(bytes(long), 'long.txt');
      expect(doc.text.length, DocumentText.maxChars);
      expect(doc.text.substring(0, 500), 'x' * 500);
      expect(doc.text, endsWith(stringsFor('').documentScanTextLimit));
    },
  );

  test('PDF truncation warning survives bounding (A07)', () async {
    final long = 'page text\n' * (DocumentText.maxChars ~/ 10 + 10);
    final doc = await DocumentText.extract(
      bytes('%PDF-1.4 ...'),
      'file.pdf',
      pdfText: (_) async => long,
    );
    expect(doc.text.length, DocumentText.maxChars);
    expect(doc.text.startsWith('page text'), isTrue);
    expect(doc.text, endsWith(stringsFor('').documentScanTextLimit));
  });

  test(
    'UTF-16LE and UTF-16BE BOM files decode instead of Latin-1 (A10)',
    () async {
      final text = 'Café déjà — naïve ¿qué? ¡Hola! 😀';
      for (final endian in [Endian.little, Endian.big]) {
        final doc = await DocumentText.extract(
          utf16(text, endian),
          'notes.txt',
        );
        expect(doc.text, text);
      }
    },
  );

  test('BOM-less UTF-16 is detected from its NUL bytes (A10)', () async {
    final text = 'El arte de perder n\'est pas difficile à maîtriser.';
    for (final endian in [Endian.little, Endian.big]) {
      final doc = await DocumentText.extract(
        utf16(text, endian, bom: false),
        'notes.txt',
      );
      expect(doc.text, text);
    }
  });

  test('UTF-8 and Latin-1 decoding are unchanged (A10)', () async {
    expect(
      (await DocumentText.extract(bytes('café'), 'file.txt')).text,
      'café',
    );
    // Invalid UTF-8 still falls back to Latin-1 (0xE9 is é, 0xE8 is è).
    final latin = await DocumentText.extract(
      Uint8List.fromList([0xE9, 0x20, 0xE8]),
      'file.txt',
    );
    expect(latin.text, 'é è');
    // A UTF-8 BOM is still stripped after decoding.
    final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF] + utf8.encode('héllo'));
    expect((await DocumentText.extract(bom, 'file.txt')).text, 'héllo');
  });
}
