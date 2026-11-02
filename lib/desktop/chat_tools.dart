import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../data/local/database/app_database.dart';
import '../features/attachments/domain/attachment.dart';
import '../features/chat/domain/entities/chat_message.dart';
import '../features/chat/domain/export/desktop_chat_export.dart';
import '../features/chat/presentation/providers/chat_provider.dart';

Future<void> exportDesktopChat(
  BuildContext context,
  WidgetRef ref, {
  String? chatId,
}) async {
  final l10n = context.l10n;
  final state = ref.read(chatProvider);
  final id = chatId ?? state.chatId;
  if (id == null) return;
  final format = await showDialog<bool>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.desktopChatExport),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.desktopChatMarkdown),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.desktopChatJson),
        ),
      ],
    ),
  );
  if (format == null || !context.mounted) return;
  try {
    final db = ref.read(appDatabaseProvider);
    if (state.temporary && chatId == null) return;
    final chat = await db.getChat(id);
    if (chat == null) return;
    final rows = await db.getMessages(id);
    final document = DesktopChatExport(
      title: chat.title,
      modelLabel: l10n.desktopChatModel,
      dateLabel: l10n.desktopChatDate,
      thinkingLabel: l10n.desktopChatThinking,
      roleLabels: {
        ChatRole.user: l10n.desktopChatUser,
        ChatRole.assistant: l10n.desktopChatAssistant,
        ChatRole.system: l10n.desktopChatSystem,
      },
      model: chat.modelId,
      date: chat.createdAt,
      messages: [
        for (final row in rows)
          ChatMessage(
            id: row.id,
            role: ChatRole.values.byName(row.role),
            content: row.content,
            timestamp: row.timestamp,
            modelId: row.modelId,
            reasoning: row.reasoning,
            status: row.status,
            parentId: row.parentId,
            runJson: row.runJson,
            sourcesJson: row.sourcesJson,
            attachments: Attachment.listFromJson(
              jsonDecode(row.attachmentsJson),
            ),
          ),
      ],
    );
    final extension = format ? 'json' : 'md';
    var name = chat.title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    name = name.replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) name = 'chat';
    if (name.length > 100) name = name.substring(0, 100);
    final result = await FilePicker.saveFile(
      fileName: '$name.$extension',
      dialogTitle: l10n.desktopChatExport,
      bytes: utf8.encode(format ? document.json : document.markdown),
      mimeType: format ? 'application/json' : 'text/markdown',
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.desktopChatExported)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.desktopChatActionFailed)));
    }
  }
}
