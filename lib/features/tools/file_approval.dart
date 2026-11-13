import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/l10n/l10n.dart';
import '../../core/island/status_island.dart';
import 'project_file_tools.dart';

class ChatFileChange {
  final String chatId, scope;
  final FileChange change;
  ChatFileChange(this.chatId, this.scope, this.change);
}

final fileChangesProvider = StateProvider<List<ChatFileChange>>((ref) => []);
final fileApprovalProvider = Provider((ref) {
  final gate = FileApproval((changes) {
    ref.read(fileChangesProvider.notifier).state = List.of(changes);
  });
  ref.onDispose(gate.dispose);
  return gate;
});

/// Permissions are scoped to chat AND folder; the host persists opt-in decisions.
class FileApproval {
  final void Function(List<ChatFileChange>) changed;
  final changes = <ChatFileChange>[];
  final allowed = <String>{};
  bool _disposed = false;
  FileApproval(this.changed);
  Future<bool> request(
    String chatId,
    String folder,
    FileChange change,
    CancelToken? cancel, {
    Future<bool?> Function()? read,
    Future<void> Function()? save,
  }) async {
    if (_disposed || cancel?.isCancelled == true) return false;
    final stored = read == null ? null : await read();
    if (_disposed || cancel?.isCancelled == true) return false;
    final scope = '$chatId\u0000$folder';
    changes.add(ChatFileChange(chatId, scope, change));
    changed(changes);
    if (stored == true || allowed.contains(scope)) {
      change.answer.complete(true);
      return true;
    }
    try {
      final result = await Future.any([
        change.answer.future,
        if (cancel != null) cancel.whenCancel.then((_) => false),
      ]).timeout(const Duration(minutes: 10), onTimeout: () => false);
      if (result && allowed.contains(scope)) await save?.call();
      return result;
    } finally {
      if (!change.answer.isCompleted) change.answer.complete(false);
      if (!_disposed) changed(changes);
    }
  }

  void answer(ChatFileChange entry, bool allow, {bool allowChat = false}) {
    if (entry.change.answer.isCompleted) return;
    if (allow && allowChat) allowed.add(entry.scope);
    entry.change.answer.complete(allow);
    changed(changes);
  }

  void refresh() {
    if (!_disposed) changed(changes);
  }

  void dispose() {
    _disposed = true;
    for (final e in changes) {
      if (!e.change.answer.isCompleted) e.change.answer.complete(false);
    }
  }
}

class FileChangesPanel extends ConsumerWidget {
  final String? chatId;
  const FileChangesPanel({super.key, required this.chatId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref
        .watch(fileChangesProvider)
        .where((e) => e.chatId == chatId)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final t = context.l10n;
    final gate = ref.read(fileApprovalProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final e in entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.change.path,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ExpansionTile(
                      title: Text(t.projectFileDiff),
                      children: [
                        SizedBox(
                          height: 140,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              e.change.diff,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!e.change.answer.isCompleted && !e.change.applied)
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => gate.answer(e, false),
                            child: Text(t.projectFileReject),
                          ),
                          FilledButton(
                            onPressed: () => gate.answer(e, true),
                            child: Text(t.projectFileApprove),
                          ),
                          TextButton(
                            onPressed: () =>
                                gate.answer(e, true, allowChat: true),
                            child: Text(t.projectFileAllowChat),
                          ),
                        ],
                      ),
                    if (e.change.applied && !e.change.undone)
                      TextButton(
                        onPressed: () async {
                          try {
                            await e.change.undo!();
                          } catch (error) {
                            if (context.mounted) {
                              showIslandToast(
                                context,
                                '$error',
                                tone: IslandTone.error,
                              );
                            }
                          }
                        },
                        child: Text(t.projectFileUndo),
                      ),
                    if (e.change.undone) Text(t.projectFileUndone),
                    if (!e.change.applied && e.change.answer.isCompleted)
                      Text(t.projectFileFinished),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
