import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../data/local/database/app_database.dart';
import '../providers/chat_provider.dart';
import '../../../../core/design/app_design.dart';

/// A bounded view makes a source-message jump reliable even when the original
/// chat is too long for its lazy list to have built the target row. The rows
/// are loaded once per chat and deliberately frozen: a page opened while a
/// turn is still streaming shows the source as it was at that moment rather
/// than swapping the list under the reader on every turn event.
class MessageSourcePage extends ConsumerStatefulWidget {
  final String chatId, messageId;
  const MessageSourcePage({
    super.key,
    required this.chatId,
    required this.messageId,
  });
  @override
  ConsumerState<MessageSourcePage> createState() => _MessageSourcePageState();
}

class _MessageSourcePageState extends ConsumerState<MessageSourcePage> {
  /// Queried once per chat, not once per build: the page rebuilds whenever a
  /// turn starts or stops (it watches `isGenerating`), so a per-build future
  /// would run one full message query for every such event.
  late Future<List<Message>> _messages;

  @override
  void initState() {
    super.initState();
    _messages = ref.read(appDatabaseProvider).getMessages(widget.chatId);
  }

  @override
  void didUpdateWidget(MessageSourcePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _messages = ref.read(appDatabaseProvider).getMessages(widget.chatId);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.sourceMessage)),
    body: FutureBuilder<List<Message>>(
      future: _messages,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        final at = rows.indexWhere((r) => r.id == widget.messageId);
        if (at < 0) {
          return Center(child: Text(context.l10n.sourceMessageMissing));
        }
        return ListView(
          padding: const EdgeInsets.all(AppDesign.lg),
          children: [
            for (final row in rows.skip((at - 1).clamp(0, rows.length)).take(3))
              Card(
                color: row.id == widget.messageId
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
                      await ref
                          .read(chatProvider.notifier)
                          .openChat(widget.chatId);
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
