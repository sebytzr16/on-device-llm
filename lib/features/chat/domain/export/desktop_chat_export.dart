import 'dart:convert';

import '../entities/chat_message.dart';

/// Portable desktop export schema v1: title, model (nullable), date (UTC ISO
/// 8601), and messages in conversation order. Each message has role, content,
/// timestamp (UTC ISO 8601), model (nullable), thinking (nullable), attachment
/// names, and sources. No attachment file paths are exported.
class DesktopChatExport {
  final String title;
  final String? model;
  final DateTime date;
  final List<ChatMessage> messages;
  final String modelLabel, dateLabel, thinkingLabel;
  final Map<ChatRole, String> roleLabels;

  const DesktopChatExport({
    required this.title,
    required this.model,
    required this.date,
    required this.messages,
    this.modelLabel = 'Model',
    this.dateLabel = 'Date',
    this.thinkingLabel = 'Thinking',
    this.roleLabels = const {},
  });

  Iterable<ChatMessage> get liveMessages => messages.where(
    (message) => !message.isSuperseded && !message.isAlternative,
  );

  List<Map<String, dynamic>> _sources(ChatMessage message) {
    try {
      final value = jsonDecode(message.sourcesJson);
      return [
        if (value is List)
          for (final source in value)
            if (source is Map)
              {
                'title': source['title']?.toString() ?? '',
                'url': source['url']?.toString() ?? '',
              },
      ];
    } on FormatException {
      return [];
    }
  }

  String get json => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'title': title,
    'model': model,
    'date': date.toUtc().toIso8601String(),
    'messages': [
      for (final message in liveMessages)
        {
          'role': message.role.name,
          'content': message.content,
          'timestamp': message.timestamp.toUtc().toIso8601String(),
          'model': message.modelId,
          'thinking': message.reasoning,
          'attachments': [for (final a in message.attachments) a.name],
          'sources': _sources(message),
        },
    ],
  });

  static String _inline(String text) => text
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAllMapped(RegExp(r'[\\`*_{}\[\]<>#]'), (m) => '\\${m[0]}');

  String get markdown {
    final out = StringBuffer()
      ..writeln('# ${_inline(title)}')
      ..writeln()
      ..writeln('${_inline(modelLabel)}: ${_inline(model ?? "")}')
      ..writeln('${_inline(dateLabel)}: ${date.toUtc().toIso8601String()}');
    for (final message in liveMessages) {
      out
        ..writeln()
        ..writeln(
          '## ${_inline(roleLabels[message.role] ?? message.role.name)}',
        )
        ..writeln()
        ..writeln(message.content);
      if (message.reasoning?.isNotEmpty == true) {
        out
          ..writeln()
          ..writeln('<details>')
          ..writeln(
            '<summary>${const HtmlEscape().convert(thinkingLabel)}</summary>',
          )
          ..writeln()
          ..writeln(const HtmlEscape().convert(message.reasoning!))
          ..writeln()
          ..writeln('</details>');
      }
      for (final a in message.attachments) {
        out.writeln('\n- ${_inline(a.name)}');
      }
      for (final source in _sources(message)) {
        final url = Uri.tryParse(source['url'] as String);
        if (url != null && (url.scheme == 'https' || url.scheme == 'http')) {
          final destination = url
              .toString()
              .replaceAll('(', '%28')
              .replaceAll(')', '%29')
              .replaceAll('>', '%3E');
          out.writeln(
            '\n- [${_inline(source['title'] as String)}](<$destination>)',
          );
        }
      }
    }
    return out.toString();
  }
}
