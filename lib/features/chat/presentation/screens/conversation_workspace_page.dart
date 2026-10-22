import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/design/app_design.dart';
import '../../domain/conversation_workspace.dart';
import '../providers/chat_provider.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

class ConversationWorkspacePage extends ConsumerStatefulWidget {
  const ConversationWorkspacePage({super.key});
  @override
  ConsumerState<ConversationWorkspacePage> createState() =>
      _WorkspacePageState();
}

class _WorkspacePageState extends ConsumerState<ConversationWorkspacePage> {
  String _state = 'active';
  String? _project;
  final _selected = <String>{};

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(_selected.clear);
    } catch (e) {
      if (mounted) showIslandToast(context, '$e', tone: IslandTone.error);
    }
  }

  Future<void> _editProject([ChatProject? project]) async {
    final name = TextEditingController(text: project?.name ?? '');
    final instructions = TextEditingController(
      text: project?.instructions ?? '',
    );
    final collection = TextEditingController(text: project?.collection ?? '');
    try {
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(dialog.l10n.project),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: AppDesign.md,
              children: [
                TextField(
                  controller: name,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: dialog.l10n.projectName,
                  ),
                ),
                TextField(
                  controller: instructions,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: InputDecoration(
                    labelText: dialog.l10n.projectInstructions,
                  ),
                ),
                TextField(
                  controller: collection,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: dialog.l10n.knowledgeCollectionName,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(dialog.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(dialog.l10n.save),
            ),
          ],
        ),
      );
      if (ok == true) {
        await _run(
          () => ref
              .read(conversationWorkspaceProvider.notifier)
              .saveProject(
                id: project?.id,
                name: name.text,
                instructions: instructions.text,
                collection: collection.text,
              ),
        );
      }
    } finally {
      // Text fields remain mounted during the route's closing animation.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      name.dispose();
      instructions.dispose();
      collection.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final workspace = ref.watch(conversationWorkspaceProvider);
    final notifier = ref.read(conversationWorkspaceProvider.notifier);
    final chats = ref.watch(chatsProvider);
    final busy = ref.watch(chatProvider.select((s) => s.isGenerating));
    return Scaffold(
      appBar: AppBar(
        title: Text(t.workspaceTitle),
        actions: [
          IconButton(
            key: const Key('create-project'),
            tooltip: t.project,
            onPressed: () => _editProject(),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in ['active', 'archived', 'trash'])
                  Padding(
                    padding: const EdgeInsets.all(AppDesign.xs),
                    child: ChoiceChip(
                      label: Text(
                        s == 'active'
                            ? t.conversations
                            : s == 'archived'
                            ? t.archivedChats
                            : t.trashChats,
                      ),
                      selected: _state == s,
                      onSelected: (_) => setState(() {
                        _state = s;
                        _selected.clear();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDesign.md),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _project ?? '',
                    items: [
                      DropdownMenuItem(value: '', child: Text(t.all)),
                      for (final p in workspace.projects)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (id) => setState(() {
                      _project = id == '' ? null : id;
                      _selected.clear();
                    }),
                  ),
                ),
                if (_project != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editProject(
                      workspace.projects.firstWhere((p) => p.id == _project),
                    ),
                  ),
                if (_project != null)
                  IconButton(
                    icon: const Icon(Icons.add_comment_outlined),
                    tooltip: t.newChat,
                    onPressed: busy
                        ? null
                        : () {
                            ref
                                .read(chatProvider.notifier)
                                .newChat(projectId: _project);
                            Navigator.pop(context);
                          },
                  ),
                if (_project != null)
                  IconButton(
                    tooltip: t.delete,
                    icon: const Icon(Icons.folder_delete_outlined),
                    onPressed: busy
                        ? null
                        : () async {
                            final id = _project!;
                            final confirmed = await confirmAction(
                              context,
                              title: t.project,
                              message: t.removeProjectHint,
                              confirmLabel: t.delete,
                              destructive: true,
                            );
                            if (!confirmed || !mounted) return;
                            setState(() => _project = null);
                            await _run(() => notifier.removeProject(id));
                          },
                  ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _run(
                          () => notifier.setState(
                            _selected.toList(),
                            _state == 'active' ? 'archived' : 'active',
                          ),
                        ),
                  child: Text(
                    _state == 'active' ? t.archiveChats : t.restoreChats,
                  ),
                ),
                if (_state != 'trash')
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _run(
                            () =>
                                notifier.setState(_selected.toList(), 'trash'),
                          ),
                    child: Text(t.moveToTrash),
                  ),
                PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: t.project,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: '', child: Text(t.noProject)),
                    for (final p in workspace.projects)
                      PopupMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onSelected: (id) => _run(
                    () => notifier.assign(
                      _selected.toList(),
                      id.isEmpty ? null : id,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppDesign.md),
                    child: Text(t.project),
                  ),
                ),
                if (_state == 'trash')
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final ids = _selected.toList();
                            final ok = await confirmAction(
                              context,
                              title: t.deleteConversationQuestion,
                              message: t.permanentDeleteHint,
                              confirmLabel: t.delete,
                              destructive: true,
                            );
                            if (ok) {
                              await _run(() async {
                                for (final id in ids) {
                                  await ref
                                      .read(chatProvider.notifier)
                                      .deleteChat(id);
                                }
                              });
                            }
                          },
                    child: Text(
                      t.delete,
                      style: TextStyle(color: context.colors.danger),
                    ),
                  ),
              ],
            ),
          Expanded(
            child: chats.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (rows) {
                final visible = rows
                    .where(
                      (c) =>
                          workspace.stateOf(c.id) == _state &&
                          (_project == null ||
                              workspace.memberships[c.id] == _project),
                    )
                    .toList();
                return ListView(
                  children: [
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppDesign.xl),
                        child: Text(t.noConversations),
                      ),
                    if (visible.isNotEmpty)
                      CheckboxListTile(
                        value: visible.every((c) => _selected.contains(c.id)),
                        title: Text(t.selectAllChats),
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _selected.addAll(visible.map((c) => c.id));
                                } else {
                                  _selected.clear();
                                }
                              }),
                      ),
                    for (final c in visible)
                      ListTile(
                        leading: Checkbox(
                          value: _selected.contains(c.id),
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(c.id);
                                  } else {
                                    _selected.remove(c.id);
                                  }
                                }),
                        ),
                        title: Text(
                          c.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: workspace.projectFor(c.id) == null
                            ? null
                            : Text(workspace.projectFor(c.id)!.name),
                        onTap: busy || _state == 'trash'
                            ? null
                            : () async {
                                await ref
                                    .read(chatProvider.notifier)
                                    .openChat(c.id);
                                if (context.mounted) Navigator.pop(context);
                              },
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
