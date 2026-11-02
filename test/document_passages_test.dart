import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/attachments/domain/document_passages.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_embedder.dart';

/// Puts a passage close to the query when it names the warranty.
class _Embedder extends TextEmbedder {
  int documents = 0;
  @override
  String get modelId => 'fake';
  Float32List _v(String t) => Float32List.fromList(
    RegExp('warrant|guarantee').hasMatch(t.toLowerCase()) ? [1, 0] : [0, 1],
  );
  @override
  Future<List<Float32List>?> embedQueries(List<String> texts) async => [
    for (final t in texts) _v(t),
  ];
  @override
  Future<List<Float32List>?> embedDocuments(List<String> texts) async {
    documents++;
    return [for (final t in texts) _v(t)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  test('a file longer than the context keeps the closest passages, not '
      'its start', () async {
    final fitted = await DocumentPassages.fit(
      longDocument,
      'Analyse the coverage terms',
      3000,
    );
    expect(fitted.text, contains('Section 0.'));
    expect(fitted.text, contains('30 June 2028'));
    expect(fitted.text.length, lessThanOrEqualTo(3200));
    expect(fitted.kept, lessThan(fitted.total));
  });

  test('EmbeddingGemma ranks by meaning and embeds a file once', () async {
    final embedder = _Embedder();
    for (final q in ['What does the guarantee cover?', 'warranty?']) {
      final fitted = await DocumentPassages.fit(
        longDocument,
        q,
        3000,
        embedder: embedder,
      );
      expect(fitted.text, contains('30 June 2028'));
    }
    expect(embedder.documents, 1);
  });
}
