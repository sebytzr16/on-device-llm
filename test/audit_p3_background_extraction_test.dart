import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/attachments/domain/document_text.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'document_text_test.dart' show zip;

void main() {
  test(
    'small compressed Office files yield while their large contents inflate',
    () async {
      final bytes = zip({
        'word/document.xml':
            '<w:document><w:p><w:t>${'word ' * 200000}</w:t></w:p></w:document>',
      });
      expect(bytes.length, lessThan(DocumentText.isolateThreshold));
      var yielded = false;
      Timer.run(() => yielded = true);
      final doc = await DocumentText.extract(bytes, 'large.docx');
      expect(doc.text, startsWith('word word'));
      expect(yielded, isTrue);
    },
  );
  test('background hashing and HTML extraction preserve their results', () async {
    expect(
      await KnowledgeStore.contentHash(Uint8List.fromList([97, 98, 99])),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    const body =
        '<html><head><title>Example</title></head><body><article><p>A readable paragraph.</p></article></body></html>';
    final expected = WebPageReader.extractPage(body);
    final actual = await WebPageReader.extractPageInBackground(body);
    expect(actual.title, expected.title);
    expect(actual.text, expected.text);
  });
}
