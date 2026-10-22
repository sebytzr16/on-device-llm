import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../data/local/database/app_database.dart';
import '../providers/chat_provider.dart';
import '../../../../core/design/app_design.dart';

/// A bounded view makes a source-message jump reliable even when the original
/// chat is too long for its lazy list to have built the target row.
class MessageSourcePage extends ConsumerWidget {
  final String chatId, messageId;
  const MessageSourcePage({
    super.key,
    required this.chatId,
    required this.messageId,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.sourceMessage)),
    body: FutureBuilder<List<Message>>(
      future: ref.read(appDatabaseProvider).getMessages(chatId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        final at = rows.indexWhere((r) => r.id == messageId);
        if (at < 0) {
          return Center(child: Text(context.l10n.sourceMessageMissing));
        }
        return ListView(
          padding: const EdgeInsets.all(AppDesign.lg),
          children: [
            for (final row in rows.skip((at - 1).clamp(0, rows.length)).take(3))
              Card(
                color: row.id == messageId
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(AppDesign.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${row.role} · ${row.timestamp.toLocal()}'),
                      const SizedBox(height: AppDesign.sm),
                      SelectableText(row.content),
                    ],
                  ),
                ),
              ),
            FilledButton(
              onPressed: ref.watch(chatProvider.select((s) => s.isGenerating))
                  ? null
                  : () async {
                      await ref.read(chatProvider.notifier).openChat(chatId);
                      if (context.mounted) Navigator.pop(context);
                    },
              child: Text(context.l10n.openConversation),
            ),
          ],
        );
      },
    ),
  );
}
