import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../data/local/database/app_database.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import '../features/chat/domain/conversation_workspace.dart';
import '../core/motion/pressable.dart';
import '../core/motion/spring_entrance.dart';
import 'desktop_app.dart';
import '../core/platform/desktop_preferences.dart';
import 'advanced_toggle.dart';
import 'chat_tools.dart';
import 'chat_drafts.dart';
import 'desktop_theme.dart';
import 'focus_ring.dart';
import 'keyboard_shortcuts.dart';

/// Left column: new chat, search, the conversations grouped by date, and
/// the other places (Projects, Goals, Models, Settings).
class DesktopSidebar extends ConsumerStatefulWidget {
  final FocusNode searchFocus;
  final VoidCallback onNewChat;
  const DesktopSidebar({
    super.key,
    required this.searchFocus,
    required this.onNewChat,
  });

  @override
  ConsumerState<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends ConsumerState<DesktopSidebar> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final section = ref.watch(desktopSectionProvider);
    final advanced = ref.watch(desktopPreferencesProvider).advanced;
    final nav = ref.read(desktopSectionProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: desktopShortcutTooltip(context, l10n.newChat),
                  child: Pressable(
                    pressedScale: 0.97,
                    child: SizedBox(
                      height: 38,
                      child: OutlinedButton.icon(
                        onPressed: widget.onNewChat,
                        icon: Icon(
                          Icons.edit_square,
                          size: 16,
                          color: c.accent,
                        ),
                        label: Row(
                          children: [
                            Flexible(
                              child: Text(
                                l10n.newChat,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Ctrl+N',
                              style: context.text.mono.copyWith(
                                fontSize: 11,
                                color: c.textFaint,
                              ),
                            ),
                          ],
                        ),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          backgroundColor: c.text.fade(0.04),
                          side: BorderSide(color: c.hairline),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Temporary chat sits beside New chat, same surface, as on
              // the phone's app bar.
              Tooltip(
                message: '${l10n.temporaryChat} · ${l10n.temporaryChatHint}',
                child: Pressable(
                  pressedScale: 0.94,
                  child: SizedBox.square(
                    dimension: 38,
                    child: OutlinedButton(
                      key: const Key('desktop-new-temporary'),
                      onPressed: () {
                        ref
                            .read(chatProvider.notifier)
                            .newChat(temporary: true);
                        nav.show(DesktopSection.chat);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: c.text.fade(0.04),
                        side: BorderSide(color: c.hairline),
                      ),
                      child: Icon(
                        Icons.visibility_off_outlined,
                        size: 16,
                        color: c.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: TextField(
              controller: _query,
              focusNode: widget.searchFocus,
              onChanged: (_) => setState(() {}),
              textAlignVertical: TextAlignVertical.center,
              style: context.text.body.copyWith(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: l10n.searchConversations,
                hintStyle: context.text.body.copyWith(
                  fontSize: 13.5,
                  color: c.textFaint,
                ),
                fillColor: c.surfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: AppDesign.radius(AppDesign.rFull),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppDesign.radius(AppDesign.rFull),
                  borderSide: BorderSide(color: c.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppDesign.radius(AppDesign.rFull),
                  borderSide: BorderSide(color: c.accent.fade(0.7)),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 17),
                prefixIconConstraints: const BoxConstraints(minWidth: 34),
                suffixIcon: _query.text.isEmpty
                    ? Center(
                        widthFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            'Ctrl+K',
                            style: context.text.mono.copyWith(
                              fontSize: 11,
                              color: c.textFaint,
                            ),
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: l10n.clear,
                        icon: const Icon(Icons.close_rounded, size: 15),
                        onPressed: () => setState(_query.clear),
                      ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: _ChatList(query: _query.text.trim().toLowerCase())),
          const Divider(height: 13),
          DesktopSidebarSection(
            child: Column(
              children: [
                const SizedBox(height: 6),
                _NavRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: l10n.desktopChatTitle,
                  selected: section == DesktopSection.chat,
                  onTap: () => nav.show(DesktopSection.chat),
                ),
                if (advanced)
                  _NavRow(
                    icon: Icons.folder_outlined,
                    label: l10n.drawerProjects,
                    selected: section == DesktopSection.projects,
                    onTap: () => nav.show(DesktopSection.projects),
                  ),
                if (advanced)
                  _NavRow(
                    icon: Icons.flag_outlined,
                    label: l10n.goalsTitle,
                    selected: section == DesktopSection.goals,
                    onTap: () => nav.show(DesktopSection.goals),
                  ),
                _NavRow(
                  icon: Icons.memory_rounded,
                  label: l10n.models,
                  shortcut: 'Ctrl+M',
                  selected: section == DesktopSection.models,
                  onTap: () => nav.show(DesktopSection.models),
                ),
                _NavRow(
                  icon: Icons.auto_awesome_outlined,
                  label: l10n.desktopCreateTitle,
                  selected: section == DesktopSection.imageGen,
                  onTap: () => nav.show(DesktopSection.imageGen),
                ),
                _NavRow(
                  icon: Icons.compare_arrows_rounded,
                  label: l10n.desktopCompareTitle,
                  shortcut: 'Ctrl+Shift+D',
                  selected: section == DesktopSection.compare,
                  onTap: () => nav.show(DesktopSection.compare),
                ),
                _NavRow(
                  icon: Icons.dns_outlined,
                  label: l10n.desktopServerTitle,
                  shortcut: 'Ctrl+Shift+S',
                  selected: section == DesktopSection.server,
                  onTap: () => nav.show(DesktopSection.server),
                ),
                if (advanced)
                  _NavRow(
                    icon: Icons.extension_outlined,
                    label: l10n.mcpTitle,
                    selected: section == DesktopSection.mcp,
                    onTap: () => nav.show(DesktopSection.mcp),
                  ),
                if (advanced)
                  _NavRow(
                    icon: Icons.terminal_rounded,
                    label: l10n.desktopLogsTitle,
                    shortcut: 'Ctrl+Shift+L',
                    selected: section == DesktopSection.logs,
                    onTap: () => nav.show(DesktopSection.logs),
                  ),
                _NavRow(
                  icon: Icons.settings_outlined,
                  label: l10n.settings,
                  shortcut: 'Ctrl+,',
                  selected: section == DesktopSection.settings,
                  onTap: () => nav.show(DesktopSection.settings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatList extends ConsumerWidget {
  final String query;
  const _ChatList({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final chats = ref.watch(chatsProvider).value ?? const <Chat>[];
    final currentId = ref.watch(chatProvider.select((s) => s.chatId));
    final onChat = ref.watch(
      desktopSectionProvider.select((s) => s == DesktopSection.chat),
    );
    final workspace = ref.watch(conversationWorkspaceProvider);
    final shown = chats
        .where(
          (c) =>
              workspace.stateOf(c.id) == 'active' &&
              (query.isEmpty || c.title.toLowerCase().contains(query)),
        )
        .toList();
    if (shown.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty ? l10n.desktopNoChats : l10n.desktopNoMatches,
          style: context.text.small,
        ),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String group(Chat c) {
      if (c.pinned) return l10n.pinned;
      if (!c.updatedAt.isBefore(today)) return l10n.today;
      if (!c.updatedAt.isBefore(yesterday)) return l10n.yesterday;
      return l10n.earlier;
    }

    final sorted = [...shown]
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final rows = <Widget>[];
    String? last;
    for (final c in sorted) {
      final g = group(c);
      if (g != last) {
        rows.add(_GroupHeader(g));
        last = g;
      }
      // New conversations spring in; the list opens as a short cascade.
      rows.add(
        SpringEntrance(
          key: ValueKey(c.id),
          delay: SpringEntrance.cascade(rows.length),
          from: const Offset(0, 8),
          child: _ChatRow(chat: c, selected: onChat && c.id == currentId),
        ),
      );
    }
    return ListView(padding: EdgeInsets.zero, children: rows);
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 8, 4),
    child: Text(
      label,
      style: context.text.caption.copyWith(
        color: context.colors.textFaint,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ChatRow extends ConsumerStatefulWidget {
  final Chat chat;
  final bool selected;
  const _ChatRow({required this.chat, required this.selected});

  @override
  ConsumerState<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends ConsumerState<_ChatRow> {
  final _menu = MenuController();
  bool _hover = false, _focused = false;

  String get _title => widget.chat.title.trim().isEmpty
      ? context.l10n.desktopUntitled
      : widget.chat.title;

  void _open() {
    ref.read(desktopSectionProvider.notifier).show(DesktopSection.chat);
    if (!widget.selected) {
      ref.read(chatProvider.notifier).openChat(widget.chat.id);
    }
  }

  Future<void> _rename() async {
    final l10n = context.l10n;
    final title = await promptText(
      context,
      title: l10n.rename,
      initial: widget.chat.title,
      confirmLabel: l10n.rename,
    );
    if (title == null || title.trim().isEmpty) return;
    await ref
        .read(appDatabaseProvider)
        .renameChat(widget.chat.id, title.trim());
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await confirmAction(
      context,
      title: l10n.desktopDeleteChatTitle,
      message: l10n.desktopDeleteChatBody(_title),
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (ok && !ref.read(chatProvider).isGenerating) {
      final chat = ref.read(chatProvider.notifier);
      final drafts = ref.read(desktopChatDraftsProvider);
      await drafts.remove(widget.chat.id);
      await chat.deleteChat(widget.chat.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final bg = widget.selected
        ? c.text.fade(0.08)
        : _hover
        ? c.text.fade(0.045)
        : Colors.transparent;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _rename,
        const SingleActivator(LogicalKeyboardKey.delete): _delete,
      },
      child: MenuAnchor(
        controller: _menu,
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.file_download_outlined, size: 16),
            onPressed: () =>
                exportDesktopChat(context, ref, chatId: widget.chat.id),
            child: Text(l10n.desktopChatExport),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.copy_outlined, size: 16),
            onPressed: ref.watch(chatProvider).isGenerating
                ? null
                : () async {
                    final id = await ref
                        .read(chatProvider.notifier)
                        .copyChat(widget.chat.id);
                    if (id != null && mounted) {
                      ref
                          .read(desktopSectionProvider.notifier)
                          .show(DesktopSection.chat);
                    }
                  },
            child: Text(l10n.desktopChatDuplicate),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.drive_file_rename_outline, size: 16),
            shortcut: const SingleActivator(LogicalKeyboardKey.f2),
            onPressed: _rename,
            child: Text(l10n.rename),
          ),
          MenuItemButton(
            leadingIcon: Icon(
              widget.chat.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 16,
            ),
            onPressed: () => ref
                .read(appDatabaseProvider)
                .setPinned(widget.chat.id, !widget.chat.pinned),
            child: Text(l10n.pinToTop),
          ),
          const Divider(height: 9),
          MenuItemButton(
            leadingIcon: Icon(Icons.delete_outline, size: 16, color: c.danger),
            shortcut: const SingleActivator(LogicalKeyboardKey.delete),
            onPressed: _delete,
            child: Text(l10n.delete, style: TextStyle(color: c.danger)),
          ),
        ],
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onSecondaryTapDown: (d) => _menu.open(position: d.localPosition),
            child: Focus(
              skipTraversal: true,
              onFocusChange: (value) => setState(() => _focused = value),
              child: Builder(
                builder: (context) => Pressable(
                  pressedScale: 0.98,
                  child: DesktopFocusRing(
                    label: _title,
                    child: InkWell(
                      onTap: () {
                        Focus.of(context).requestFocus();
                        _open();
                      },
                      borderRadius: AppDesign.radius(AppDesign.rMd),
                      child: AnimatedContainer(
                        duration: DesktopTheme.fast,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: AppDesign.radius(AppDesign.rMd),
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: DesktopTheme.fast,
                              width: 3,
                              height: widget.selected ? 14 : 0,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: c.accent,
                                borderRadius: AppDesign.radius(2),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.body.copyWith(
                                  fontSize: 13.5,
                                  color: widget.selected ? c.text : c.textMuted,
                                ),
                              ),
                            ),
                            if (_hover || _focused)
                              Tooltip(
                                message: l10n.desktopChatMenu,
                                child: DesktopFocusRing(
                                  label: l10n.desktopChatMenu,
                                  child: InkWell(
                                    borderRadius: AppDesign.radius(4),
                                    onTap: () => _menu.open(),
                                    child: Icon(
                                      Icons.more_horiz,
                                      size: 16,
                                      color: c.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final bool selected;
  final VoidCallback onTap;
  const _NavRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.shortcut,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: shortcut == null ? label : '$label ($shortcut)',
      child: Pressable(
        pressedScale: 0.97,
        child: DesktopFocusRing(
          label: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppDesign.radius(AppDesign.rMd),
            child: AnimatedContainer(
              duration: DesktopTheme.fast,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected ? c.text.fade(0.08) : Colors.transparent,
                borderRadius: AppDesign.radius(AppDesign.rMd),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? c.accent : c.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.body.copyWith(
                        fontSize: 13.5,
                        color: selected ? c.text : c.textMuted,
                      ),
                    ),
                  ),
                  if (shortcut != null)
                    Text(
                      shortcut!,
                      style: context.text.mono.copyWith(
                        fontSize: 11,
                        color: c.textFaint,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
