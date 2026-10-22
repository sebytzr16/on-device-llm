import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/export/chat_document.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'exported PDF and DOCX reopen from device storage',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Document export test'))),
      );
      final document = ChatDocument.select(
        title: 'Device export check',
        messages: [
          ChatMessage(
            id: 'answer',
            role: ChatRole.assistant,
            content:
                '# Findings\nThe battery lasts all day.\n\n- Source checked',
            reasoning: 'private chain of thought',
            timestamp: DateTime.utc(2026, 9, 22),
            sourcesJson:
                '[{"number":1,"title":"Reference","url":"https://example.org/reference"}]',
          ),
        ],
      );
      final directory = await (await getTemporaryDirectory()).createTemp(
        'document-export-',
      );
      try {
        final pdfFile = File('${directory.path}/report.pdf');
        final docxFile = File('${directory.path}/report.docx');
        await pdfFile.writeAsBytes(await document.pdf(), flush: true);
        await docxFile.writeAsBytes(document.docx, flush: true);

        final pdf = await PdfDocument.openFile(pdfFile.path);
        try {
          expect(pdf.pages.length, greaterThan(0));
          final text = (await pdf.pages.first.loadText())?.fullText ?? '';
          expect(text, contains('battery lasts all day'));
          expect(text, isNot(contains('private chain of thought')));
        } finally {
          await pdf.dispose();
        }

        final docx = ZipDecoder().decodeBytes(await docxFile.readAsBytes());
        expect(docx.findFile('[Content_Types].xml'), isNotNull);
        final xml = utf8.decode(
          docx.findFile('word/document.xml')!.content as List<int>,
        );
        expect(xml, contains('battery lasts all day'));
        expect(xml, contains('https://example.org/reference'));
        expect(xml, isNot(contains('private chain of thought')));
      } finally {
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
