part of 'chat_provider.dart';

/// The open chat as plain text or Markdown.
mixin _ChatExport on _ChatBase {
  /// The conversation as plain text for the share sheet: who said what,
  /// attachments by name, sources as a footnote list. No reasoning.
  String plainText({String? modelName}) {
    final b = StringBuffer();
    for (final m in state.messages) {
      if (m.isSuperseded || m.isAlternative) continue;
      final who = m.role == ChatRole.user ? 'You' : (modelName ?? 'Assistant');
      b.writeln('$who:');
      if (m.attachments.isNotEmpty) {
        b.writeln(
          '[${m.attachments.map((a) => a.isImage ? 'Photo: ${a.name}' : 'File: ${a.name}').join(', ')}]',
        );
      }
      b.writeln(m.content.trim());
      final sources = (jsonDecode(m.sourcesJson) as List).cast<Map>();
      for (final s in sources) {
        b.writeln(ChatNotifier._sharedSourceLine(s, separator: ' — '));
      }
      if (m.status != 'complete') b.writeln('(${m.status})');
      b.writeln();
    }
    return b.toString().trimRight();
  }

  String export({bool markdown = false}) {
    final document = ChatDocument.select(
      messages: state.messages,
      chatId: state.chatId,
    );
    return markdown ? document.markdown : document.json;
  }
}
