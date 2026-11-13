import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/island/status_island.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/blur_switcher.dart';
import '../core/motion/pressable.dart';
import '../data/local/database/app_database.dart';
import '../features/chat/domain/conversation_workspace.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import 'desktop_app.dart';
import 'desktop_theme.dart';
import 'focus_ring.dart';
import 'developer_widgets.dart';

class DesktopProjectsPage extends ConsumerStatefulWidget {
  const DesktopProjectsPage({super.key});
  @override
  ConsumerState<DesktopProjectsPage> createState() =>
      _DesktopProjectsPageState();
}

class _DesktopProjectsPageState extends ConsumerState<DesktopProjectsPage> {
  String _state = 'active';
  String? _project;
  String _query = '';
  String? _anchor;
  final _selected = <String>{};
  final _focus = FocusNode();
  bool get _busy => ref.read(chatProvider).isGenerating;
  ConversationWorkspaceNotifier get _workspace =>
      ref.read(conversationWorkspaceProvider.notifier);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
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
    final folder = TextEditingController(text: project?.folder ?? '');
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
                  controller: folder,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: dialog.l10n.projectFolder,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: dialog.l10n.projectFolderClear,
                          onPressed: folder.clear,
                          icon: const Icon(Icons.clear),
                        ),
                        IconButton(
                          tooltip: dialog.l10n.projectFolderPick,
                          onPressed: () async {
                            final selected =
                                await FilePicker.getDirectoryPath();
                            if (selected != null) folder.text = selected;
                          },
                          icon: const Icon(Icons.folder_open),
                        ),
                      ],
                    ),
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
            // An empty name is refused by saveProject after the dialog
            // closed, losing what was typed (audit C07): Save waits for one.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: name,
              builder: (_, value, _) => FilledButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialog, true),
                child: Text(dialog.l10n.save),
              ),
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
                folder: folder.text.isEmpty ? null : folder.text,
              ),
        );
      }
    } finally {
      // Text fields remain mounted during the route's closing animation.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      name.dispose();
      instructions.dispose();
      collection.dispose();
      folder.dispose();
    }
  }

  void _navigate(String state, [String? project]) {
    setState(() {
      _state = state;
      _project = project;
      _selected.clear();
      _anchor = null;
    });
    _focus.requestFocus();
  }

  void _open(String id) {
    if (_busy || _state == 'trash') return;
    ref.read(desktopSectionProvider.notifier).show(DesktopSection.chat);
    _run(() => ref.read(chatProvider.notifier).openChat(id));
  }

  void _select(String id, List<Chat> rows) {
    _focus.requestFocus();
    if (_busy) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) {
      final start = rows.indexWhere((c) => c.id == _anchor);
      final end = rows.indexWhere((c) => c.id == id);
      setState(() {
        _selected.clear();
        final a = start < 0 ? end : start;
        _selected.addAll(
          rows
              .sublist(a < end ? a : end, (a > end ? a : end) + 1)
              .map((c) => c.id),
        );
        _anchor ??= id;
      });
    } else if (keys.isControlPressed) {
      setState(() {
        if (!_selected.remove(id)) _selected.add(id);
        _anchor = id;
      });
    } else {
      _anchor = id;
      _open(id);
    }
  }

  Future<void> _delete(List<String> ids) async {
    if (_busy || ids.isEmpty) return;
    final t = context.l10n;
    final permanent = _state == 'trash';
    final ok = await confirmAction(
      context,
      title: t.deleteConversationQuestion,
      message: permanent
          ? t.permanentDeleteHint
          : t.desktopProjectsTrashConfirm,
      confirmLabel: permanent ? t.delete : t.moveToTrash,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      if (permanent) {
        for (final id in ids) {
          await ref.read(chatProvider.notifier).deleteChat(id);
        }
      } else {
        await _workspace.setState(ids, 'trash');
      }
    });
  }

  List<Widget> _moveItems(List<String> ids) => [
    MenuItemButton(
      onPressed: _busy ? null : () => _run(() => _workspace.assign(ids, null)),
      child: Text(context.l10n.noProject),
    ),
    for (final p in ref.read(conversationWorkspaceProvider).projects)
      MenuItemButton(
        onPressed: _busy
            ? null
            : () => _run(() => _workspace.assign(ids, p.id)),
        child: Text(p.name),
      ),
  ];

  Widget _moveMenu(List<String> ids) => MenuBar(
    style: const MenuStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
      elevation: WidgetStatePropertyAll(0),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
    ),
    children: [
      SubmenuButton(
        menuChildren: _moveItems(ids),
        child: Text(context.l10n.desktopProjectsMove),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final workspace = ref.watch(conversationWorkspaceProvider);
    final chats = ref.watch(chatsProvider);
    final busy = ref.watch(chatProvider.select((s) => s.isGenerating));
    final all = chats.value ?? <Chat>[];
    final rows =
        all
            .where(
              (chat) =>
                  workspace.stateOf(chat.id) == _state &&
                  (_project == null ||
                      workspace.memberships[chat.id] == _project) &&
                  chat.title.toLowerCase().contains(_query),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // Keep selection restricted to the current, visible pane as providers update.
    _selected.retainAll(rows.map((c) => c.id));
    final project = workspace.projects
        .where((p) => p.id == _project)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.desktopPage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeveloperPageHeader(
            title: t.workspaceTitle,
            subtitle: t.desktopProjectsSubtitle,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView(
                          children: [
                            _place(
                              t.desktopProjectsAll,
                              Icons.forum_outlined,
                              'active',
                              null,
                              all
                                  .where(
                                    (c) => workspace.stateOf(c.id) == 'active',
                                  )
                                  .length,
                            ),
                            const SizedBox(height: AppSpace.row),
                            for (final p in workspace.projects)
                              _place(
                                p.name,
                                Icons.folder_outlined,
                                'active',
                                p.id,
                                all
                                    .where(
                                      (c) =>
                                          workspace.stateOf(c.id) == 'active' &&
                                          workspace.memberships[c.id] == p.id,
                                    )
                                    .length,
                              ),
                            const Divider(height: 24),
                            _place(
                              t.archivedChats,
                              Icons.archive_outlined,
                              'archived',
                              null,
                              all
                                  .where(
                                    (c) =>
                                        workspace.stateOf(c.id) == 'archived',
                                  )
                                  .length,
                            ),
                            _place(
                              t.trashChats,
                              Icons.delete_outline,
                              'trash',
                              null,
                              all
                                  .where(
                                    (c) => workspace.stateOf(c.id) == 'trash',
                                  )
                                  .length,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.row),
                      DeveloperButton(
                        label: t.desktopProjectsNew,
                        icon: Icons.create_new_folder_outlined,
                        onPressed: busy ? null : () => _editProject(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                VerticalDivider(width: 1, color: c.hairline),
                const SizedBox(width: 16),
                Expanded(
                  child: Focus(
                    focusNode: _focus,
                    autofocus: true,
                    onKeyEvent: (_, event) {
                      // Text editing keeps its normal selection and deletion shortcuts.
                      if (FocusManager.instance.primaryFocus != _focus ||
                          event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        setState(_selected.clear);
                      } else if (event.logicalKey == LogicalKeyboardKey.keyA &&
                          HardwareKeyboard.instance.isControlPressed &&
                          !busy) {
                        setState(() => _selected.addAll(rows.map((c) => c.id)));
                      } else if (event.logicalKey ==
                              LogicalKeyboardKey.delete &&
                          _selected.isNotEmpty) {
                        _delete(_selected.toList());
                      } else {
                        return KeyEventResult.ignored;
                      }
                      return KeyEventResult.handled;
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('projects-search'),
                                onChanged: (v) => setState(() {
                                  _query = v.trim().toLowerCase();
                                  _selected.clear();
                                  _anchor = null;
                                }),
                                decoration: InputDecoration(
                                  hintText: t.searchConversations,
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                            if (project != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: t.rename,
                                onPressed: busy
                                    ? null
                                    : () => _editProject(project),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                              IconButton(
                                tooltip: t.newChat,
                                onPressed: busy
                                    ? null
                                    : () {
                                        ref
                                            .read(chatProvider.notifier)
                                            .newChat(projectId: project.id);
                                        ref
                                            .read(
                                              desktopSectionProvider.notifier,
                                            )
                                            .show(DesktopSection.chat);
                                      },
                                icon: const Icon(
                                  Icons.add_comment_outlined,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                tooltip: t.delete,
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final ok = await confirmAction(
                                          context,
                                          title: t.project,
                                          message: t.removeProjectHint,
                                          confirmLabel: t.delete,
                                          destructive: true,
                                        );
                                        if (!ok || !mounted) return;
                                        await _run(
                                          () => ref
                                              .read(chatProvider.notifier)
                                              .deleteProject(project.id),
                                        );
                                        if (mounted) _navigate('active');
                                      },
                                icon: const Icon(
                                  Icons.folder_delete_outlined,
                                  size: 18,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpace.row),
                        BlurSwitcher(
                          alignment: Alignment.centerLeft,
                          child: _selected.isEmpty
                              ? const SizedBox.shrink(
                                  key: ValueKey('no-selection'),
                                )
                              : Wrap(
                                  key: const Key('projects-bulk-bar'),
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      t.desktopProjectsSelected(
                                        _selected.length,
                                      ),
                                      style: context.text.small,
                                    ),
                                    _moveMenu(_selected.toList()),
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => _run(
                                              () => _workspace.setState(
                                                _selected.toList(),
                                                _state == 'active'
                                                    ? 'archived'
                                                    : 'active',
                                              ),
                                            ),
                                      child: Text(
                                        _state == 'active'
                                            ? t.archiveChats
                                            : t.restoreChats,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => _delete(_selected.toList()),
                                      child: Text(
                                        t.delete,
                                        style: TextStyle(color: c.danger),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          setState(_selected.clear),
                                      child: Text(t.desktopProjectsClear),
                                    ),
                                  ],
                                ),
                        ),
                        SizedBox(
                          height: 32,
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  t.desktopProjectsTitle,
                                  style: context.text.small,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  t.project,
                                  style: context.text.small,
                                ),
                              ),
                              SizedBox(
                                width: 112,
                                child: Text(
                                  t.desktopProjectsUpdated,
                                  style: context.text.small,
                                ),
                              ),
                              const SizedBox(width: 136),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: c.hairline),
                        Expanded(
                          child: chats.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, _) => Center(
                              child: Text('$e', style: context.text.small),
                            ),
                            data: (_) => rows.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.forum_outlined,
                                          color: c.textFaint,
                                          size: 32,
                                        ),
                                        const SizedBox(height: AppSpace.row),
                                        Text(
                                          _query.isEmpty
                                              ? t.noConversations
                                              : t.desktopNoMatches,
                                          style: context.text.small,
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: rows.length,
                                    itemExtent: 44,
                                    itemBuilder: (context, index) {
                                      final chat = rows[index];
                                      final ids = _selected.contains(chat.id)
                                          ? _selected.toList()
                                          : [chat.id];
                                      final archive = _state == 'active'
                                          ? t.archiveChats
                                          : t.restoreChats;
                                      void changeState() => _run(
                                        () => _workspace.setState(
                                          ids,
                                          _state == 'active'
                                              ? 'archived'
                                              : 'active',
                                        ),
                                      );
                                      final menu = <Widget>[
                                        MenuItemButton(
                                          onPressed: busy || _state == 'trash'
                                              ? null
                                              : () => _open(chat.id),
                                          leadingIcon: const Icon(
                                            Icons.open_in_new,
                                            size: 16,
                                          ),
                                          child: Text(t.desktopProjectsOpen),
                                        ),
                                        SubmenuButton(
                                          menuChildren: _moveItems(ids),
                                          leadingIcon: const Icon(
                                            Icons.drive_file_move_outline,
                                            size: 16,
                                          ),
                                          child: Text(t.desktopProjectsMove),
                                        ),
                                        MenuItemButton(
                                          onPressed: busy ? null : changeState,
                                          leadingIcon: const Icon(
                                            Icons.archive_outlined,
                                            size: 16,
                                          ),
                                          child: Text(archive),
                                        ),
                                        const Divider(height: 9),
                                        MenuItemButton(
                                          onPressed: busy
                                              ? null
                                              : () => _delete(ids),
                                          leadingIcon: Icon(
                                            Icons.delete_outline,
                                            color: c.danger,
                                            size: 16,
                                          ),
                                          child: Text(
                                            _state == 'trash'
                                                ? t.desktopProjectsDeleteForever
                                                : t.moveToTrash,
                                            style: TextStyle(color: c.danger),
                                          ),
                                        ),
                                      ];
                                      return _ConversationRow(
                                        key: ValueKey(
                                          'project-chat-${chat.id}',
                                        ),
                                        chat: chat,
                                        project:
                                            workspace
                                                .projectFor(chat.id)
                                                ?.name ??
                                            t.noProject,
                                        selected: _selected.contains(chat.id),
                                        selecting: _selected.isNotEmpty,
                                        dragIds: ids,
                                        draggable: !busy,
                                        menu: menu,
                                        onTap: () => _select(chat.id, rows),
                                        onToggle: busy
                                            ? null
                                            : () {
                                                _focus.requestFocus();
                                                setState(() {
                                                  if (!_selected.remove(
                                                    chat.id,
                                                  )) {
                                                    _selected.add(chat.id);
                                                  }
                                                  _anchor = chat.id;
                                                });
                                              },
                                        actions: [
                                          IconButton(
                                            tooltip: t.desktopProjectsOpen,
                                            onPressed: busy || _state == 'trash'
                                                ? null
                                                : () => _open(chat.id),
                                            icon: const Icon(
                                              Icons.open_in_new,
                                              size: 16,
                                            ),
                                          ),
                                          MenuAnchor(
                                            menuChildren: _moveItems(ids),
                                            builder: (_, controller, _) =>
                                                IconButton(
                                                  tooltip:
                                                      t.desktopProjectsMove,
                                                  onPressed: busy
                                                      ? null
                                                      : () => controller.open(),
                                                  icon: const Icon(
                                                    Icons
                                                        .drive_file_move_outline,
                                                    size: 16,
                                                  ),
                                                ),
                                          ),
                                          IconButton(
                                            tooltip: archive,
                                            onPressed: busy
                                                ? null
                                                : changeState,
                                            icon: const Icon(
                                              Icons.archive_outlined,
                                              size: 16,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: t.delete,
                                            onPressed: busy
                                                ? null
                                                : () => _delete(ids),
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                              color: c.danger,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _place(
    String label,
    IconData icon,
    String state,
    String? project,
    int count,
  ) {
    final selected = _state == state && _project == project;
    return DragTarget<List<String>>(
      onWillAcceptWithDetails: (_) => !_busy && state == 'active',
      onAcceptWithDetails: (details) =>
          _run(() => _workspace.assign(details.data, project)),
      builder: (context, candidates, _) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Pressable(
          child: Material(
            color: candidates.isNotEmpty
                ? context.colors.accent.fade(0.2)
                : selected
                ? context.colors.text.fade(0.08)
                : Colors.transparent,
            borderRadius: AppDesign.radius(AppDesign.rMd),
            child: DesktopFocusRing(
              label: label,
              child: ListTile(
                key: ValueKey('project-place-${project ?? state}'),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? context.colors.accent
                      : context.colors.textMuted,
                ),
                title: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.body,
                ),
                trailing: Text('$count', style: context.text.small),
                onTap: () => _navigate(state, project),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatefulWidget {
  final Chat chat;
  final String project;
  final bool selected, selecting, draggable;
  final List<String> dragIds;
  final List<Widget> menu, actions;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  const _ConversationRow({
    super.key,
    required this.chat,
    required this.project,
    required this.selected,
    required this.selecting,
    required this.dragIds,
    required this.draggable,
    required this.menu,
    required this.actions,
    required this.onTap,
    required this.onToggle,
  });
  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow> {
  final _menu = MenuController();
  bool _hover = false;
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final date = widget.chat.updatedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateLabel = !date.isBefore(today)
        ? context.l10n.today
        : !date.isBefore(today.subtract(const Duration(days: 1)))
        ? context.l10n.yesterday
        : MaterialLocalizations.of(context).formatShortDate(date);
    final title = widget.chat.title.trim().isEmpty
        ? context.l10n.desktopUntitled
        : widget.chat.title;
    final row = MenuAnchor(
      controller: _menu,
      menuChildren: widget.menu,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onSecondaryTapDown: (d) => _menu.open(position: d.localPosition),
          child: Pressable(
            pressedScale: 0.995,
            child: DesktopFocusRing(
              label: title,
              onFocusChange: (value) => setState(() => _focused = value),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: AppDesign.radius(AppDesign.rMd),
                child: AnimatedContainer(
                  duration: DesktopTheme.fast,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? c.accent.fade(0.12)
                        : _hover
                        ? c.text.fade(0.045)
                        : Colors.transparent,
                    borderRadius: AppDesign.radius(AppDesign.rMd),
                  ),
                  child: Row(
                    children: [
                      if (widget.selecting)
                        SizedBox(
                          width: 32,
                          child: Checkbox(
                            value: widget.selected,
                            onChanged: widget.onToggle == null
                                ? null
                                : (_) => widget.onToggle!(),
                          ),
                        ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.body,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Text(
                          widget.project,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.small,
                        ),
                      ),
                      SizedBox(
                        width: 112,
                        child: Text(dateLabel, style: context.text.small),
                      ),
                      SizedBox(
                        width: 136,
                        child: _hover || _focused
                            ? Row(
                                children: [
                                  for (final action in widget.actions)
                                    SizedBox(width: 32, child: action),
                                ],
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Draggable<List<String>>(
      data: widget.dragIds,
      maxSimultaneousDrags: widget.draggable ? 1 : 0,
      feedback: Material(
        color: c.surfaceRaised,
        borderRadius: AppDesign.radius(AppDesign.rMd),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.dragIds.length > 1
                ? context.l10n.desktopProjectsSelected(widget.dragIds.length)
                : title,
            style: context.text.body,
          ),
        ),
      ),
      child: row,
    );
  }
}
