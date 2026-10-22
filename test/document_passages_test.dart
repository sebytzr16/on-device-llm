import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/attachments/domain/document_passages.dart';

void main() {
  final longDocument = [
    for (var i = 0; i < 24; i++)
      i == 19
          ? 'Section $i. The warranty expires on 30 June 2028. '
                '${'Warranty coverage and replacement terms. ' * 15}'
          : 'Section $i. ${'Unrelated background and general notes. ' * 18}',
  ].join('\n');

  test('focused question selects a late passage from a long document', () {
    final result = DocumentPassages.select(
      longDocument,
      'When does the warranty expire?',
    );
    expect(result, contains('30 June 2028'));
    expect(result, contains('Selected passages'));
    expect(result.length, lessThan(longDocument.length));
  });

  test('summary keeps the complete document', () {
    expect(
      DocumentPassages.select(longDocument, 'Summarize the document'),
      longDocument,
    );
  });

  test('no lexical match keeps the complete document', () {
    expect(
      DocumentPassages.select(longDocument, 'What is the aperture?'),
      longDocument,
    );
  });
}
