import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../entities/chat_message.dart';
import 'document_blocks.dart';
import '../../../attachments/domain/attachment.dart';
import '../../../retrieval/domain/evidence_audit.dart';

/// A single selection rendered to all supported document formats.
class ChatDocument {
  final String title;
  final String? chatId;
  final List<ChatMessage> messages;
  final bool includeReasoning;

  ChatDocument({
    required this.title,
    required this.messages,
    this.chatId,
    this.includeReasoning = false,
  });

  /// Combine turns without binding their local [1] citations to each other.
  /// Distinct snapshots of the same URL retain separate source identities.
  ChatDocument normalizedCitations() {
    final global = <Map<String, dynamic>>[];
    final rewritten = <ChatMessage>[];
    for (final message in messages) {
      final numbers = <int, int>{};
      final local = <Map<String, dynamic>>[];
      for (final source in _sources(message)) {
        final original = source['number'];
        if (original is! int) continue;
        var index = global.indexWhere(
          (existing) =>
              existing['url'] == source['url'] &&
              existing['excerpt'] == source['excerpt'],
        );
        if (index < 0) {
          index = global.length;
          global.add({...source, 'number': index + 1});
        }
        numbers[original] = index + 1;
        local.add(global[index]);
      }
      final content = message.content.replaceAllMapped(EvidenceAudit.marker, (
        match,
      ) {
        final old = match[1]!.split(',').map((n) => int.parse(n.trim()));
        if (old.any((n) => !numbers.containsKey(n))) {
          return '[unverified source]';
        }
        return '[${old.map((n) => numbers[n]).join(', ')}]';
      });
      rewritten.add(
        message.copyWith(content: content, sourcesJson: jsonEncode(local)),
      );
    }
    return ChatDocument(
      title: title,
      chatId: chatId,
      messages: rewritten,
      includeReasoning: includeReasoning,
    );
  }

  factory ChatDocument.select({
    required List<ChatMessage> messages,
    String title = 'OnDevice LLM conversation',
    String? chatId,
    Set<String>? selectedIds,
    bool includeBranches = false,
    bool includeReasoning = false,
  }) => ChatDocument(
    title: title,
    chatId: chatId,
    messages: [
      for (final message in messages)
        if ((includeBranches ||
                (!message.isSuperseded && !message.isAlternative)) &&
            (selectedIds == null || selectedIds.contains(message.id)))
          message,
    ],
    includeReasoning: includeReasoning,
  );

  /// Redacts user-supplied terms in message text, reasoning, attachment names,
  /// source titles and source URLs before any format is rendered.
  ChatDocument redacted(Iterable<String> terms) {
    final patterns = [
      for (final term in terms.map((value) => value.trim()))
        if (term.isNotEmpty) RegExp(RegExp.escape(term), caseSensitive: false),
    ];
    if (patterns.isEmpty) return this;
    String mask(String value) {
      var result = value;
      for (final pattern in patterns) {
        result = result.replaceAll(pattern, '[redacted]');
      }
      return result;
    }

    Object? maskValue(Object? value) {
      if (value is String) return mask(value);
      if (value is List) return value.map(maskValue).toList();
      if (value is Map) {
        return {
          for (final entry in value.entries) entry.key: maskValue(entry.value),
        };
      }
      return value;
    }

    return ChatDocument(
      title: mask(title),
      chatId: chatId == null ? null : mask(chatId!),
      includeReasoning: includeReasoning,
      messages: [
        for (final message in messages)
          ChatMessage(
            id: mask(message.id),
            role: message.role,
            content: mask(message.content),
            reasoning: message.reasoning == null
                ? null
                : mask(message.reasoning!),
            timestamp: message.timestamp,
            modelId: message.modelId == null ? null : mask(message.modelId!),
            tokenCount: message.tokenCount,
            status: mask(message.status),
            sourcesJson: jsonEncode(maskValue(_sources(message))),
            attachments: [
              for (final attachment in message.attachments)
                Attachment(
                  id: mask(attachment.id),
                  kind: attachment.kind,
                  name: mask(attachment.name),
                  mime: mask(attachment.mime),
                  path: mask(attachment.path),
                  sizeBytes: attachment.sizeBytes,
                ),
            ],
            parentId: message.parentId == null ? null : mask(message.parentId!),
            runJson: message.runJson == null ? null : mask(message.runJson!),
          ),
      ],
    );
  }

  String get text {
    final out = StringBuffer()..writeln(title);
    for (final message in messages) {
      out
        ..writeln()
        ..writeln('${_label(message)}:');
      _writeAttachments(out, message);
      out.writeln(message.content.trim());
      if (includeReasoning && message.reasoning?.trim().isNotEmpty == true) {
        out
          ..writeln('Model reasoning:')
          ..writeln(message.reasoning!.trim());
      }
      _writeSources(out, message);
    }
    return '${out.toString().trimRight()}\n';
  }

  String get markdown {
    final out = StringBuffer()
      ..writeln('# ${title.replaceAll('\n', ' ')}')
      ..writeln();
    for (final message in messages) {
      out
        ..writeln('## ${_label(message)}')
        ..writeln();
      _writeAttachments(out, message);
      out
        ..writeln(message.content.trim())
        ..writeln();
      if (includeReasoning && message.reasoning?.trim().isNotEmpty == true) {
        out
          ..writeln('### Model reasoning')
          ..writeln()
          ..writeln(message.reasoning!.trim())
          ..writeln();
      }
      _writeSources(out, message);
      out.writeln();
    }
    return '${out.toString().trimRight()}\n';
  }

  String get html {
    final body = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    return '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${const HtmlEscape().convert(title)}</title><style>body{font:16px/1.55 system-ui,sans-serif;max-width:48rem;margin:2rem auto;padding:0 1rem;color:#171717}pre{overflow:auto;padding:1rem;background:#f4f4f4}code{font-family:monospace}table{border-collapse:collapse}td,th{border:1px solid #bbb;padding:.4rem}</style></head><body>$body</body></html>';
  }

  String get json => const JsonEncoder.withIndent('  ').convert({
    'version': 2,
    'chatId': chatId,
    'messages': [
      for (final message in messages)
        {
          'id': message.id,
          'role': message.role.name,
          'content': message.content,
          if (includeReasoning) 'reasoning': message.reasoning,
          'timestamp': message.timestamp.toIso8601String(),
          'modelId': message.modelId,
          'status': message.status,
          'sources': _sources(message),
          if (message.attachments.isNotEmpty)
            'attachments': [
              for (final attachment in message.attachments)
                {
                  'name': attachment.name,
                  'kind': attachment.kind.name,
                  'mime': attachment.mime,
                },
            ],
        },
    ],
  });

  Uint8List get docx {
    final xml = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/'
      'wordprocessingml/2006/main"><w:body>',
    );
    void paragraph(
      String value, {
      bool heading = false,
      bool bullet = false,
      bool code = false,
    }) {
      xml.write('<w:p>');
      if (bullet || code) {
        xml.write('<w:pPr><w:ind w:left="720"/></w:pPr>');
      }
      xml.write('<w:r>');
      if (heading) xml.write('<w:rPr><w:b/><w:sz w:val="32"/></w:rPr>');
      if (code) {
        xml.write(
          '<w:rPr><w:rFonts w:ascii="Courier New" '
          'w:hAnsi="Courier New"/><w:shd w:fill="EFEFEF"/></w:rPr>',
        );
      }
      xml.write('<w:t xml:space="preserve">');
      xml.write(_xml((bullet ? '• ' : '') + value));
      xml.write('</w:t></w:r></w:p>');
    }

    void table(List<List<String>> rows) {
      xml.write(
        '<w:tbl><w:tblPr><w:tblBorders>'
        '<w:bottom w:val="single" w:sz="4"/>'
        '<w:insideH w:val="single" w:sz="4"/>'
        '<w:insideV w:val="single" w:sz="4"/>'
        '</w:tblBorders></w:tblPr>',
      );
      for (final row in rows) {
        xml.write('<w:tr>');
        for (final cell in row) {
          xml.write('<w:tc><w:p><w:r><w:t xml:space="preserve">');
          xml.write(_xml(cell));
          xml.write('</w:t></w:r></w:p></w:tc>');
        }
        xml.write('</w:tr>');
      }
      xml.write('</w:tbl>');
    }

    paragraph(title, heading: true);
    for (final message in messages) {
      paragraph(_label(message), heading: true);
      for (final attachment in message.attachments) {
        paragraph('Attachment: ${attachment.name}');
      }
      for (final block in DocumentBlocks.parse(message.content)) {
        switch (block.kind) {
          case DocumentBlockKind.heading:
            paragraph(block.text, heading: true);
          case DocumentBlockKind.bullet:
            paragraph(block.text, bullet: true);
          case DocumentBlockKind.numbered:
            paragraph(block.text, bullet: true);
          case DocumentBlockKind.code:
            for (final line in block.text.split('\n')) {
              paragraph(line, code: true);
            }
          case DocumentBlockKind.table:
            table(block.rows);
          case DocumentBlockKind.paragraph:
            paragraph(block.text);
        }
      }
      if (includeReasoning && message.reasoning?.trim().isNotEmpty == true) {
        paragraph('Model reasoning', heading: true);
        for (final line in message.reasoning!.split('\n')) {
          paragraph(line);
        }
      }
      for (final source in _sources(message)) {
        paragraph(_sourceLine(source));
      }
    }
    xml.write('<w:sectPr/></w:body></w:document>');
    final archive = Archive();
    void add(String name, String value) {
      archive.addFile(ArchiveFile.bytes(name, utf8.encode(value)));
    }

    add(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
          'content-types"><Default Extension="rels" ContentType="application/'
          'vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '</Types>',
    );
    add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
          '2006/relationships"><Relationship Id="rId1" Type="http://schemas.'
          'openxmlformats.org/officeDocument/2006/relationships/officeDocument"'
          ' Target="word/document.xml"/></Relationships>',
    );
    add('word/document.xml', xml.toString());
    return ZipEncoder().encodeBytes(archive);
  }

  Future<Uint8List> pdf() async {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
    final mono = pw.Font.ttf(
      await rootBundle.load('assets/fonts/JetBrainsMono.ttf'),
    );
    final document = pw.Document();
    final body = <pw.Widget>[
      pw.Text(title, style: pw.TextStyle(font: font, fontSize: 22)),
      pw.SizedBox(height: 12),
    ];
    for (final message in messages) {
      body.add(
        pw.Header(
          level: 1,
          text: _label(message),
          textStyle: pw.TextStyle(font: font, fontSize: 16),
        ),
      );
      for (final attachment in message.attachments) {
        body.add(
          pw.Text(
            'Attachment: ${attachment.name}',
            style: pw.TextStyle(font: font, fontSize: 9),
          ),
        );
      }
      for (final block in DocumentBlocks.parse(message.content)) {
        switch (block.kind) {
          case DocumentBlockKind.heading:
            body.add(
              pw.Header(
                level: block.level.clamp(1, 3),
                text: block.text,
                textStyle: pw.TextStyle(
                  font: font,
                  fontSize: (17 - block.level).clamp(11, 16).toDouble(),
                ),
              ),
            );
          case DocumentBlockKind.bullet:
            body.add(
              pw.Bullet(
                text: block.text,
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
            );
          case DocumentBlockKind.numbered:
            body.add(
              pw.Text(
                block.text,
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
            );
          case DocumentBlockKind.code:
            for (final line in block.text.split('\n')) {
              body.add(
                pw.Container(
                  width: double.infinity,
                  color: PdfColors.grey200,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: pw.Text(
                    line,
                    style: pw.TextStyle(font: mono, fontSize: 8),
                  ),
                ),
              );
            }
          case DocumentBlockKind.table:
            if (block.rows.isNotEmpty) {
              body.add(
                pw.TableHelper.fromTextArray(
                  data: block.rows,
                  headerCount: 1,
                  headerStyle: pw.TextStyle(font: font, fontSize: 9),
                  cellStyle: pw.TextStyle(font: font, fontSize: 8),
                ),
              );
            }
          case DocumentBlockKind.paragraph:
            body.add(
              pw.Text(
                block.text,
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
            );
        }
        body.add(pw.SizedBox(height: 5));
      }
      if (includeReasoning && message.reasoning?.trim().isNotEmpty == true) {
        body.add(
          pw.Text(
            'Model reasoning',
            style: pw.TextStyle(font: font, fontSize: 12),
          ),
        );
        body.add(
          pw.Text(
            message.reasoning!,
            style: pw.TextStyle(font: font, fontSize: 9),
          ),
        );
      }
      for (final source in _sources(message)) {
        body.add(
          pw.Text(
            _sourceLine(source),
            style: pw.TextStyle(font: font, fontSize: 8),
          ),
        );
      }
      body.add(pw.SizedBox(height: 12));
    }
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => body,
      ),
    );
    return document.save();
  }

  static String _label(ChatMessage message) => switch (message.role) {
    ChatRole.user => 'You',
    ChatRole.assistant => 'Assistant',
    ChatRole.system => 'System',
  };

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static List<Map<String, dynamic>> _sources(ChatMessage message) {
    try {
      return [
        for (final source in jsonDecode(message.sourcesJson) as List)
          if (source is Map) Map<String, dynamic>.from(source),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _sourceLine(Map<String, dynamic> source) {
    final number = source['number']?.toString() ?? '?';
    final title = source['title']?.toString() ?? 'Source';
    final url = source['url']?.toString() ?? '';
    return '[$number] $title: $url';
  }

  static void _writeAttachments(StringBuffer out, ChatMessage message) {
    for (final attachment in message.attachments) {
      out.writeln('Attachment: ${attachment.name}');
    }
  }

  static void _writeSources(StringBuffer out, ChatMessage message) {
    for (final source in _sources(message)) {
      out.writeln(_sourceLine(source));
    }
  }
}
