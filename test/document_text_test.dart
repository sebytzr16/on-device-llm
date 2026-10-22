import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
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
}
