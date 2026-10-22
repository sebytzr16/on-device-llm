import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../data/local/database/app_database.dart';
import '../../../goals/goal_runner.dart';
import '../../../goals/presentation/goal_provider.dart';
import '../../../goals/presentation/goals_page.dart';
import '../providers/chat_provider.dart';
import '../../domain/conversation_workspace.dart';
import '../screens/conversation_workspace_page.dart';
import '../screens/message_source_page.dart';
import '../../../../core/motion/motion.dart';
import '../../../../core/design/app_dialog.dart';

/// Goals in the drawer's Workspace card: what a running or paused goal is
/// doing, or an invitation to start one.
class _GoalsRow extends ConsumerWidget {
  const _GoalsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(goalProvider);
    final past = ref.watch(goalHistoryProvider).length;
    final t = context.l10n;
    final subtitle = switch (goal?.status) {
      null => past == 0 ? t.drawerGoalsHint : t.drawerGoalsPast(past),
      GoalStatus.running => t.drawerGoalRunning(
        goal!.done + 1,
        goal.tasks.length.clamp(1, 99),
      ),
      GoalStatus.paused => '${t.goalPaused} · ${goal!.spec.objective}',
      GoalStatus.completed => t.drawerGoalReport(goal!.spec.objective),
      _ => goal!.spec.objective,
    };
    return _WorkspaceRow(
      key: const Key('drawer-goals'),
      icon: Icons.flag_outlined,
      title: t.goalsTitle,
      subtitle: subtitle,
      busy: goal?.status == GoalStatus.running,
      onTap: () {
        final navigator = Navigator.of(context);
        navigator.pop(); // the drawer
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const GoalsPage()),
        );
      },
    );
  }
}

/// One row of the Workspace card: an icon tile, a title and one line of
/// status.
class _WorkspaceRow extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool busy;
  final VoidCallback onTap;
  const _WorkspaceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.md,
          vertical: AppDesign.sm + 2,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.accent.fade(0.12),
                borderRadius: BorderRadius.circular(AppDesign.rSm),
              ),
              child: Icon(icon, size: 18, color: c.accent),
            ),
            const SizedBox(width: AppDesign.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.bodyMuted.copyWith(
                      color: context.colors.text,
                    ),
                  ),
                  MarqueeText(
                    subtitle,
                    style: context.text.label.copyWith(color: c.textFaint),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.chevron_right, size: 18, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}

/// A small upper-case header with a hairline, used for every drawer section
/// (request 2026-10-04: clear headers and dates).
class _SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  final EdgeInsets padding;
  const _SectionLabel(
    this.text, {
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppDesign.xl,
      AppDesign.lg,
      AppDesign.xl,
      AppDesign.sm,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = context.text.caption.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: c.textMuted,
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(text.toUpperCase(), style: style),
          if (trailing != null) ...[
            const SizedBox(width: AppDesign.sm),
            Text(trailing!, style: style.copyWith(color: c.textFaint)),
          ],
          const SizedBox(width: AppDesign.sm),
          Expanded(child: Divider(color: c.hairline, height: 1)),
        ],
      ),
    );
  }
}

/// Drawer body (request 2026-10-04): search; New chat and New
/// temporary chat side by side; a Workspace card with Goals and Projects;
/// conversations under date headers, each with a visible options button
/// (pin, rename, folder, tags, delete); the privacy footer.
class ConversationsSheet extends ConsumerStatefulWidget {
  const ConversationsSheet({super.key});
  @override
  ConsumerState<ConversationsSheet> createState() => _ConversationsSheetState();
}

class _ConversationsSheetState extends ConsumerState<ConversationsSheet> {
  final _search = TextEditingController();
  // Full-text results for the current query (FX-06); null = no query.
  Set<String>? _hits;

  /// Where each hit matched, shown under its title.
  Map<String, String> _snippets = const {};
  Map<String, String> _messageIds = const {};
  Timer? _debounce;
  String? _folder;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _hits = null;
        _snippets = const {};
        _messageIds = const {};
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final db = ref.read(appDatabaseProvider);
      final rows = await db.searchChats(q);
      final snippets = await db.searchSnippets(q);
      final ids = await db.searchMessageIds(q);
      if (mounted && _search.text == q) {
        setState(() {
          _hits = {for (final c in rows) c.id};
          _snippets = snippets;
          _messageIds = ids;
        });
      }
    });
    setState(() {});
  }

  /// Long-press menu: pin, rename, folder, tags, delete.
  Future<void> _organise(Chat chat) async {
    final db = ref.read(appDatabaseProvider);
    final action = await showMorphSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => AppSheet(
        title: chat.title,
        meta: [
          if (chat.folder != null) chat.folder!,
          ...AppDatabase.tagsOf(chat).map((t) => '#$t'),
        ].join(' · '),
        children: [
          ListTile(
            key: const Key('chat-pin'),
            leading: Icon(
              chat.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            title: Text(
              chat.pinned ? context.l10n.unpin : context.l10n.pinToTop,
            ),
            onTap: () => Navigator.pop(context, 'pin'),
          ),
          ListTile(
            key: const Key('chat-rename'),
            leading: const Icon(Icons.drive_file_rename_outline),
            title: Text(context.l10n.rename),
            onTap: () => Navigator.pop(context, 'rename'),
          ),
          ListTile(
            key: const Key('chat-folder'),
            leading: const Icon(Icons.folder_outlined),
            title: Text(context.l10n.moveToFolder),
            onTap: () => Navigator.pop(context, 'folder'),
          ),
          ListTile(
            key: const Key('chat-tags'),
            leading: const Icon(Icons.sell_outlined),
            title: Text(context.l10n.tags),
            onTap: () => Navigator.pop(context, 'tags'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: context.colors.danger),
            title: Text(context.l10n.moveToTrash),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'pin':
        await db.setPinned(chat.id, !chat.pinned);
      case 'rename':
        final t = await _ask(context.l10n.renameConversation, chat.title);
        if (t != null && t.trim().isNotEmpty) await db.renameChat(chat.id, t);
      case 'folder':
        final folders = await db.folders();
        if (!mounted) return;
        final f = await _pickFolder(folders, chat.folder);
        if (f != null) await db.setFolder(chat.id, f.isEmpty ? null : f);
      case 'tags':
        final t = await _ask(
          context.l10n.tagsCommaSeparated,
          AppDatabase.tagsOf(chat).join(', '),
        );
        if (t != null) {
          await db.setTags(chat.id, [
            for (final x in t.split(','))
              if (x.trim().isNotEmpty) x.trim().replaceFirst('#', ''),
          ]);
        }
      case 'delete':
        await _delete(chat);
    }
  }

  /// Empty is allowed: it clears the tags (rename ignores it).
  Future<String?> _ask(String title, String initial) => promptText(
    context,
    title: title,
    initial: initial,
    confirmLabel: context.l10n.save,
    allowEmpty: true,
    fieldKey: const Key('organise-input'),
  );

  /// Existing folders plus "New folder…" and "No folder"; '' clears.
  Future<String?> _pickFolder(List<String> folders, String? current) async {
    final choice = await showMorphSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => AppSheet(
        title: context.l10n.moveToFolder,
        children: [
          for (final f in folders)
            ListTile(
              leading: Icon(
                f == current ? Icons.folder : Icons.folder_outlined,
              ),
              title: Text(f),
              onTap: () => Navigator.pop(context, f),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(context.l10n.newFolder),
            onTap: () => Navigator.pop(context, '\u0000new'),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(context.l10n.removeFromFolder),
              onTap: () => Navigator.pop(context, ''),
            ),
        ],
      ),
    );
    if (choice == '\u0000new' && mounted) {
      return _ask(context.l10n.folderName, '');
    }
    return choice;
  }

  Future<void> _delete(Chat chat) async {
    try {
      // The toast can outlive this sheet: hold what Undo needs.
      final workspace = ref.read(conversationWorkspaceProvider.notifier);
      await workspace.setState([chat.id], 'trash');
      if (!mounted) return;
      final toast = islandToastFor(context);
      toast(
        context.l10n.moveToTrash,
        icon: Icons.delete_outline,
        action: IslandAction(context.l10n.undo, () async {
          try {
            await workspace.setState([chat.id], 'active');
          } catch (e) {
            toast('$e', tone: IslandTone.error);
          }
        }),
      );
    } catch (e) {
      if (mounted) {
        showIslandToast(
          context,
          context.l10n.couldNotDelete('$e'),
          tone: IslandTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (busy, currentChatId) = ref.watch(
      chatProvider.select((s) => (s.isGenerating, s.chatId)),
    );
    final notifier = ref.read(chatProvider.notifier);
    final workspace = ref.watch(conversationWorkspaceProvider);
    final projects = workspace.projects.length;
    final workspaceCard = Container(
      margin: const EdgeInsets.symmetric(horizontal: AppDesign.lg),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(AppDesign.rMd),
        border: Border.all(color: c.hairline),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            const _GoalsRow(),
            Divider(height: 1, indent: 56, color: c.hairline),
            _WorkspaceRow(
              key: const Key('drawer-workspace'),
              icon: Icons.folder_open_outlined,
              title: context.l10n.drawerProjects,
              subtitle: projects == 0
                  ? context.l10n.drawerProjectsCount(0)
                  : '${context.l10n.drawerProjectsCount(projects)} · ${context.l10n.drawerProjectsHint}',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ConversationWorkspacePage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDesign.lg,
              AppDesign.lg,
              AppDesign.lg,
              AppDesign.sm,
            ),
            child: TextField(
              key: const Key('chat-search'),
              controller: _search,
              onChanged: _onSearch,
              style: context.text.bodyMuted.copyWith(
                color: context.colors.text,
              ),
              decoration: InputDecoration(
                hintText: context.l10n.searchConversations,
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.l10n.clear,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _search.clear();
                          _onSearch('');
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDesign.lg),
            child: Row(
              children: [
                // Equal halves with tight padding, and labels that shrink
                // rather than cut (report 2026-10-04: "Temporary" was
                // cut off on the S25+ drawer).
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('drawer-new-chat'),
                    style: FilledButton.styleFrom(padding: _compactButton),
                    icon: const Icon(Icons.add, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(context.l10n.newChat, maxLines: 1),
                    ),
                    onPressed: busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            notifier.newChat();
                          },
                  ),
                ),
                const SizedBox(width: AppDesign.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('drawer-new-temporary'),
                    style: OutlinedButton.styleFrom(padding: _compactButton),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(context.l10n.drawerTemporary, maxLines: 1),
                    ),
                    onPressed: busy
                        ? null
                        : () {
                            final hint = context.l10n.temporaryChatHint;
                            final toast = islandToastFor(context);
                            Navigator.pop(context);
                            notifier.newChat(temporary: true);
                            toast(hint);
                          },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ref
                .watch(chatsProvider)
                .when(
                  loading: () => const Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (e, _) => _Empty(
                    icon: Icons.error_outline,
                    text: context.l10n.conversationsLoadFailed('$e'),
                  ),
                  data: (chats) {
                    chats = chats
                        .where((c) => workspace.stateOf(c.id) == 'active')
                        .toList();
                    final q = _search.text.trim().toLowerCase();
                    final hits = _hits;
                    var filtered = q.isEmpty
                        ? chats
                        : chats
                              .where(
                                (c) =>
                                    c.title.toLowerCase().contains(q) ||
                                    (hits?.contains(c.id) ?? false),
                              )
                              .toList();
                    final folders = {
                      for (final c in chats)
                        if (c.folder != null) c.folder!,
                    }.toList()..sort();
                    if (_folder != null) {
                      filtered = filtered
                          .where((c) => c.folder == _folder)
                          .toList();
                    }
                    final folderBar = folders.isEmpty
                        ? null
                        : SizedBox(
                            height: 36,
                            child: ListView(
                              key: const Key('folder-bar'),
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDesign.lg,
                              ),
                              children: [
                                for (final f in [null, ...folders])
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: AppDesign.xs,
                                    ),
                                    child: ChoiceChip(
                                      label: Text(f ?? context.l10n.all),
                                      selected: _folder == f,
                                      showCheckmark: false,
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) =>
                                          setState(() => _folder = f),
                                    ),
                                  ),
                              ],
                            ),
                          );
                    if (filtered.isEmpty) {
                      final empty = _Empty(
                        icon: q.isEmpty
                            ? Icons.forum_outlined
                            : Icons.search_off,
                        text: q.isEmpty
                            ? context.l10n.noConversations
                            : context.l10n.nothingMatches(_search.text.trim()),
                      );
                      if (q.isNotEmpty) return empty;
                      return ListView(
                        children: [
                          _SectionLabel(context.l10n.drawerWorkspace),
                          workspaceCard,
                          empty,
                        ],
                      );
                    }
                    final groups = _group(filtered, context.l10n);
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: AppDesign.lg),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              SliverList.list(
                                children: [
                                  if (q.isEmpty) ...[
                                    _SectionLabel(context.l10n.drawerWorkspace),
                                    workspaceCard,
                                  ],
                                  _SectionLabel(
                                    context.l10n.conversations,
                                    trailing: '${filtered.length}',
                                    padding: const EdgeInsets.fromLTRB(
                                      AppDesign.xl,
                                      AppDesign.xl,
                                      AppDesign.xl,
                                      AppDesign.sm,
                                    ),
                                  ),
                                  ?folderBar,
                                ],
                              ),
                              for (final g in groups) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppDesign.xl,
                                      AppDesign.md,
                                      AppDesign.xl,
                                      AppDesign.xs,
                                    ),
                                    child: Text(
                                      g.label,
                                      key: Key('drawer-group-${g.label}'),
                                      style: context.text.label.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: c.accent.fade(0.85),
                                      ),
                                    ),
                                  ),
                                ),
                                SliverList.separated(
                                  itemCount: g.chats.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: AppDesign.md),
                                  itemBuilder: (context, index) {
                                    final i = index;
                                    final chat = g.chats[index];
                                    return SpringEntrance(
                                      key: ValueKey('row-${chat.id}'),
                                      delay: SpringEntrance.cascade(
                                        i,
                                        stepMs: 25,
                                      ),
                                      from: const Offset(-12, 0),
                                      child: _ChatRow(
                                        chat: chat,
                                        snippet: _search.text.trim().isEmpty
                                            ? null
                                            : _snippets[chat.id],
                                        selected: currentChatId == chat.id,
                                        enabled: !busy,
                                        onOpen: () {
                                          final navigator = Navigator.of(
                                            context,
                                          );
                                          final target =
                                              _search.text.trim().isEmpty
                                              ? null
                                              : _messageIds[chat.id];
                                          navigator.pop();
                                          if (target == null) {
                                            unawaited(
                                              notifier.openChat(chat.id),
                                            );
                                          } else {
                                            navigator.push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    MessageSourcePage(
                                                      chatId: chat.id,
                                                      messageId: target,
                                                    ),
                                              ),
                                            );
                                          }
                                        },
                                        onDelete: () => _delete(chat),
                                        onOrganise: () => _organise(chat),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
          ),
          Divider(color: c.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesign.xl,
              vertical: AppDesign.md,
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: c.textFaint),
                const SizedBox(width: AppDesign.sm),
                Expanded(
                  child: Text(
                    context.l10n.storedOnDevice,
                    style: context.text.mono.copyWith(color: c.textFaint),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<_Group> _group(List<Chat> chats, AppLocalizations t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final week = today.subtract(const Duration(days: 7));
    final month = today.subtract(const Duration(days: 30));
    final buckets = {
      t.pinned: <Chat>[],
      t.today: <Chat>[],
      t.yesterday: <Chat>[],
      t.previous7Days: <Chat>[],
      t.previous30Days: <Chat>[],
      t.olderChats: <Chat>[],
    };
    for (final c in chats) {
      if (c.pinned) {
        buckets[t.pinned]!.add(c);
        continue;
      }
      final d = c.updatedAt.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      final key = !day.isBefore(today)
          ? t.today
          : day == yesterday
          ? t.yesterday
          : !day.isBefore(week)
          ? t.previous7Days
          : !day.isBefore(month)
          ? t.previous30Days
          : t.olderChats;
      buckets[key]!.add(c);
    }
    return [
      for (final e in buckets.entries)
        if (e.value.isNotEmpty) _Group(e.key, e.value),
    ];
  }
}

class _Group {
  final String label;
  final List<Chat> chats;
  const _Group(this.label, this.chats);
}

class _ChatRow extends StatelessWidget {
  final Chat chat;
  final bool selected, enabled;
  final VoidCallback onOpen, onDelete;
  final VoidCallback? onOrganise;

  /// The matching message excerpt while searching.
  final String? snippet;
  const _ChatRow({
    required this.chat,
    this.snippet,
    required this.selected,
    required this.enabled,
    required this.onOpen,
    required this.onDelete,
    this.onOrganise,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dismissible(
      key: ValueKey('chat-${chat.id}'),
      direction: enabled ? DismissDirection.endToStart : DismissDirection.none,
      // The dialog decides; the row itself never dismisses so the list stays
      // in sync with the database stream.
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppDesign.xl),
        color: c.danger.fade(0.15),
        child: Icon(Icons.delete_outline, color: c.danger),
      ),
      child: Material(
        color: selected ? c.surfaceRaised : Colors.transparent,
        child: InkWell(
          onTap: enabled ? onOpen : null,
          onLongPress: enabled ? (onOrganise ?? onDelete) : null,
          child: Container(
            padding: const EdgeInsets.only(
              left: AppDesign.xl,
              right: AppDesign.xs,
              top: AppDesign.sm,
              bottom: AppDesign.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? c.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (chat.pinned)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: AppDesign.xs,
                              ),
                              child: Icon(
                                Icons.push_pin,
                                size: 12,
                                color: c.accent,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyMuted.copyWith(
                                fontWeight: selected ? FontWeight.w600 : null,
                                color: enabled ? c.text : c.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (snippet != null) ...[
                        const SizedBox(height: 2),
                        _Snippet(snippet!),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        [
                          relativeTime(chat.updatedAt, l10n: context.l10n),
                          if (chat.folder != null) chat.folder!,
                          ...AppDatabase.tagsOf(chat).map((t) => '#$t'),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.mono.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
                // Delete and the rest used to need a long press (owner
                // report 2026-10-04); the options are one tap away now.
                IconButton(
                  key: Key('chat-options-${chat.id}'),
                  tooltip: context.l10n.chatOptions,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.more_horiz, size: 20, color: c.textFaint),
                  onPressed: enabled ? (onOrganise ?? onDelete) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: c.textFaint),
            const SizedBox(height: AppDesign.md),
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.text.bodyMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// "just now", "5 min ago", "3 h ago", "Yesterday", "12 Sep", "12 Sep 2025".
String relativeTime(DateTime t, {DateTime? now, AppLocalizations? l10n}) {
  now ??= DateTime.now();
  final local = t.toLocal();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return l10n?.justNow ?? 'just now';
  if (diff.inMinutes < 60) {
    return l10n?.minutesAgo(diff.inMinutes) ?? '${diff.inMinutes} min ago';
  }
  if (diff.inHours < 24 && now.day == local.day) {
    return l10n?.hoursAgo(diff.inHours) ?? '${diff.inHours} h ago';
  }
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today.subtract(const Duration(days: 1))) {
    return l10n?.yesterday ?? 'Yesterday';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final base = '${local.day} ${months[local.month - 1]}';
  return local.year == now.year ? base : '$base ${local.year}';
}

/// A search excerpt with the matched words in bold.
class _Snippet extends StatelessWidget {
  final String text;
  const _Snippet(this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = context.text.label.copyWith(color: c.textMuted);
    final spans = <TextSpan>[];
    final parts = text.split(AppDatabase.matchStart);
    for (var i = 0; i < parts.length; i++) {
      if (i == 0) {
        spans.add(TextSpan(text: parts[i]));
        continue;
      }
      final end = parts[i].indexOf(AppDatabase.matchEnd);
      if (end < 0) {
        spans.add(TextSpan(text: parts[i]));
        continue;
      }
      spans.add(
        TextSpan(
          text: parts[i].substring(0, end),
          style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
        ),
      );
      spans.add(TextSpan(text: parts[i].substring(end + 1)));
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      key: const Key('chat-snippet'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

const _compactButton = EdgeInsets.symmetric(
  horizontal: AppDesign.md,
  vertical: 10,
);
