import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/design/markdown_tables.dart';
import '../../../../core/design/markdown_math.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/motion/motion.dart';
import '../../../../core/utils/external_links.dart';
import '../../../attachments/presentation/attachment_chips.dart';
import '../../../knowledge/knowledge_store.dart';
import '../../../zim/zim_article_page.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/turn_run.dart';
import '../../../tools/phone_actions.dart';
import '../../../tools/presentation/phone_action_cards.dart';
import 'notice_sheet.dart';
import 'run_details_sheet.dart';
import 'code_block.dart';
import 'reasoning_accordion.dart';
import '../../../../core/design/app_dialog.dart';

/// One turn of the conversation. User turns sit in a raised bubble on the
/// right; assistant turns are set directly on the page like an article,
/// with a small mono caption above.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool streaming;

  /// Display name of the model that produced this turn, for the caption.
  final String? modelName;

  /// Turn actions (CHAT-02); only supplied for the last live turns.
  final VoidCallback? onRegenerate, onContinue;
  final ValueChanged<bool>? onDelete;
  final ValueChanged<String>? onEdit;

  /// Read-aloud (FX-01): tap to speak, tap again to stop; [speaking] marks
  /// the message currently being read.
  final VoidCallback? onSpeak;
  final bool speaking;

  /// FX-04: answer the same question with another model.
  final VoidCallback? onCompare;

  /// An answer from the model's memory: ask again with a web search.
  final VoidCallback? onSearchWeb;

  /// FX-05: bring this retained branch back in place of the current one.
  final VoidCallback? onRestore;
  final List<ChatMessage> versions;
  final ValueChanged<String>? onRestoreVersion;

  const ChatBubble({
    super.key,
    required this.message,
    this.streaming = false,
    this.modelName,
    this.onRegenerate,
    this.onContinue,
    this.onDelete,
    this.onEdit,
    this.onSpeak,
    this.speaking = false,
    this.onCompare,
    this.onSearchWeb,
    this.onRestore,
    this.versions = const [],
    this.onRestoreVersion,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    if (message.isSuperseded) {
      return _SupersededTurn(message, onRestore: onRestore);
    }
    // Appearance > compact bubbles halves the gap between turns.
    final compact = ChatBubbleDensity.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? AppDesign.xs : AppDesign.sm,
        horizontal: compact ? AppDesign.md : AppDesign.lg,
      ),
      child: GestureDetector(
        onLongPress: streaming ? null : () => showMessageActions(context),
        child: isUser
            ? _UserTurn(
                message,
                onMore: () => showMessageActions(context),
                onEdit: onEdit,
                onRegenerate: onRegenerate,
                versions: versions,
                onRestoreVersion: onRestoreVersion,
              )
            : _AssistantTurn(this),
      ),
    );
  }
}

/// One labelled row of the message sheet.
class _MessageAction {
  final String key;
  final IconData icon;
  final String label;
  final VoidCallback run;
  final bool danger;
  const _MessageAction(
    this.key,
    this.icon,
    this.label,
    this.run, {
    this.danger = false,
  });
}

extension on ChatBubble {
  /// Every action for this message with its name written out (report
  /// 2026-10-04: delete was hidden behind a long press, and the small icons
  /// had no labels). Opened by the ⋯ button or a long press.
  Future<void> showMessageActions(BuildContext context) async {
    final t = context.l10n;
    final isUser = message.role == ChatRole.user;
    AppHaptics.press();
    void copy() {
      AppHaptics.tick();
      Clipboard.setData(ClipboardData(text: message.content));
      showIslandToast(context, t.responseCopied, tone: IslandTone.done);
    }

    final actions = <_MessageAction>[
      if (message.content.isNotEmpty)
        _MessageAction(
          'copy',
          Icons.copy_outlined,
          isUser ? t.copyQuestion : t.copyResponse,
          copy,
        ),
      if (isUser && onEdit != null)
        _MessageAction(
          'edit',
          Icons.edit_outlined,
          t.editQuestion,
          () => _editQuestion(context, message, onEdit!),
        ),
      if (!isUser && message.content.isNotEmpty && onSpeak != null)
        _MessageAction(
          'speak',
          speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
          speaking ? t.stopReading : t.readAloud,
          onSpeak!,
        ),
      if (onRegenerate != null)
        _MessageAction(
          'regenerate',
          Icons.refresh,
          t.regenerate,
          onRegenerate!,
        ),
      if (!isUser && onContinue != null)
        _MessageAction(
          'continue',
          Icons.play_arrow_outlined,
          t.continueAnswer,
          onContinue!,
        ),
      if (!isUser && onCompare != null)
        _MessageAction(
          'compare',
          Icons.compare_arrows,
          t.compareWith,
          onCompare!,
        ),
      if (!isUser && message.runJson != null)
        _MessageAction('run', Icons.info_outline, t.runDetails, () {
          final run = TurnRun.decode(message.runJson);
          if (run != null) showRunDetailsSheet(context, run);
        }),
      if (onDelete != null && !isUser)
        _MessageAction(
          'delete-answer',
          Icons.delete_outline,
          t.deleteAnswer,
          () => onDelete!(false),
          danger: true,
        ),
      if (onDelete != null)
        _MessageAction(
          'delete-pair',
          Icons.delete_sweep_outlined,
          t.deleteQuestionAnswer,
          () => onDelete!(true),
          danger: true,
        ),
    ];
    if (actions.isEmpty) return;
    final picked = await showMorphSheet<_MessageAction>(
      context: context,
      useSafeArea: true,
      builder: (sheet) {
        final c = sheet.colors;
        return AppSheet(
          title: sheet.l10n.more,
          children: [
            for (final (i, a) in actions.indexed) ...[
              if (a.danger && (i == 0 || !actions[i - 1].danger))
                Divider(height: 1, color: c.hairline),
              ListTile(
                key: Key('message-action-${a.key}'),
                leading: Icon(a.icon, color: a.danger ? c.danger : null),
                title: Text(
                  a.label,
                  style: a.danger ? TextStyle(color: c.danger) : null,
                ),
                onTap: () => Navigator.pop(sheet, a),
              ),
            ],
          ],
        );
      },
    );
    if (picked != null && context.mounted) picked.run();
  }
}

Future<void> _editQuestion(
  BuildContext context,
  ChatMessage message,
  ValueChanged<String> onEdit,
) async {
  final text = await promptText(
    context,
    title: context.l10n.editQuestion,
    initial: message.content,
    confirmLabel: context.l10n.askAgain,
    maxLines: 8,
    selectAll: false,
  );
  if (text != null && text.trim().isNotEmpty) onEdit(text);
}

/// A 40 dp action under a message: a clear glyph with a tooltip.
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  const _ActionIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    iconSize: 18,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    color: color ?? context.colors.textMuted,
    icon: Icon(icon),
    onPressed: onPressed,
  );
}

/// A retained earlier version of a turn: out of the model's context,
/// collapsed until tapped, never deleted.
class _SupersededTurn extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onRestore;
  const _SupersededTurn(this.message, {this.onRestore});
  @override
  State<_SupersededTurn> createState() => _SupersededTurnState();
}

class _SupersededTurnState extends State<_SupersededTurn> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = widget.message;
    final label = m.role == ChatRole.user
        ? context.l10n.earlierQuestion
        : context.l10n.earlierAnswer;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppDesign.xs,
        horizontal: AppDesign.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: Key('superseded-${m.id}'),
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_less : Icons.history,
                  size: 14,
                  color: c.textFaint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _open
                        ? label
                        : '$label · ${m.content.replaceAll('\n', ' ').substring(0, m.content.length.clamp(0, 60))}${m.content.length > 60 ? '…' : ''}',
                    style: context.text.mono.copyWith(color: c.textFaint),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: AppDesign.sm),
              child: SelectableText(m.content, style: context.text.bodyMuted),
            ),
          if (_open && widget.onRestore != null && m.role == ChatRole.user)
            Padding(
              padding: const EdgeInsets.only(top: AppDesign.sm),
              child: OutlinedButton.icon(
                key: Key('restore-${m.id}'),
                onPressed: widget.onRestore,
                icon: const Icon(Icons.undo, size: 16),
                label: Text(context.l10n.restoreBranch),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserTurn extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRegenerate, onMore;
  final ValueChanged<String>? onEdit;
  final List<ChatMessage> versions;
  final ValueChanged<String>? onRestoreVersion;
  const _UserTurn(
    this.message, {
    this.onMore,
    this.onEdit,
    this.onRegenerate,
    this.versions = const [],
    this.onRestoreVersion,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onRegenerate != null)
            IconButton(
              key: const Key('regenerate-missing-answer'),
              tooltip: context.l10n.regenerate,
              onPressed: onRegenerate,
              icon: const Icon(Icons.refresh),
            ),
          if (onMore != null)
            _ActionIcon(
              key: Key('question-more-${message.id}'),
              tooltip: context.l10n.more,
              icon: Icons.more_horiz,
              color: c.textFaint,
              onPressed: onMore,
            ),
          if (onEdit != null)
            _ActionIcon(
              key: const Key('edit-question'),
              tooltip: context.l10n.editQuestion,
              icon: Icons.edit_outlined,
              color: c.textFaint,
              onPressed: () => _editQuestion(context, message, onEdit!),
            ),
          Flexible(child: _bubble(context, c)),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, AppColors c) => Container(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.8,
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AppDesign.lg,
      vertical: AppDesign.md,
    ),
    decoration: BoxDecoration(
      color: c.surfaceRaised,
      border: Border.all(color: c.hairline),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(AppDesign.rLg),
        topRight: Radius.circular(AppDesign.rLg),
        bottomLeft: Radius.circular(AppDesign.rLg),
        bottomRight: Radius.circular(AppDesign.xs),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.attachments.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              bottom: message.content.isEmpty ? 0 : AppDesign.sm,
            ),
            child: AttachmentChips(attachments: message.attachments),
          ),
        if (message.content.isNotEmpty)
          SelectableText(message.content, style: context.text.body),
        if (versions.length > 1)
          _VersionSwitcher(
            current: message,
            versions: versions,
            onPick: onRestoreVersion,
          ),
      ],
    ),
  );
}

/// ‹ 2/3 › under an edited question: the arrows bring back the previous or
/// next version of the turn (its question and answers), the label lists
/// them all. Disabled while an answer is being written.
class _VersionSwitcher extends StatelessWidget {
  final ChatMessage current;
  final List<ChatMessage> versions;
  final ValueChanged<String>? onPick;
  const _VersionSwitcher({
    required this.current,
    required this.versions,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = versions.indexWhere((m) => m.id == current.id);
    VoidCallback? go(int i) {
      if (onPick == null || i < 0 || i >= versions.length) return null;
      final branch = versions[i].branch;
      return branch == null || i == at ? null : () => onPick!(branch);
    }

    // 48 dp targets (Android's minimum) around small glyphs.
    Widget arrow(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      iconSize: 18,
      color: c.textMuted,
      icon: Icon(icon),
      onPressed: onTap,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.chevron_left, context.l10n.versionPrevious, go(at - 1)),
        PopupMenuButton<int>(
          key: const Key('question-versions'),
          tooltip: context.l10n.uiChatBubbleChooseQuestionVersion,
          enabled: onPick != null,
          onSelected: (i) => go(i)?.call(),
          itemBuilder: (_) => [
            for (var i = 0; i < versions.length; i++)
              PopupMenuItem(
                value: i,
                enabled: go(i) != null,
                child: Text(
                  '${i + 1}. ${versions[i].content.replaceAll('\n', ' ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppDesign.xs),
            child: Text(
              '${at + 1}/${versions.length}',
              style: context.text.mono.copyWith(color: c.textMuted),
            ),
          ),
        ),
        arrow(Icons.chevron_right, context.l10n.versionNext, go(at + 1)),
      ],
    );
  }
}

class _AssistantTurn extends StatelessWidget {
  final ChatBubble bubble;
  const _AssistantTurn(this.bubble);

  ChatMessage get message => bubble.message;
  bool get streaming => bubble.streaming;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context);
    final reasoning = message.reasoning;
    final sources = (jsonDecode(message.sourcesJson) as List)
        .cast<Map<String, dynamic>>();
    final time = message.timestamp.toLocal();
    final alternative = message.isAlternative;
    final caption = [
      if (alternative) 'compare',
      bubble.modelName ?? message.modelId ?? 'model',
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 14,
              height: 1.5,
              color: alternative ? c.info : c.accent,
            ),
            const SizedBox(width: AppDesign.sm),
            Expanded(
              child: Text(
                streaming ? context.l10n.generating : caption,
                style: context.text.mono.copyWith(color: c.textFaint),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesign.sm),
        if (reasoning != null && reasoning.isNotEmpty)
          ReasoningAccordion(content: reasoning, isComplete: !streaming),
        if (message.content.isNotEmpty)
          // While it streams, new words fade in behind a soft trailing edge
          // (not inside an open code block, which sits on its own panel).
          StreamingReveal(
            active:
                streaming && '```'.allMatches(message.content).length.isEven,
            revision: message.content.length,
            background: t.scaffoldBackgroundColor,
            child: MarkdownBody(
              data: message.content,
              selectable: !streaming,
              builders: {'pre': CodeBlockBuilder(), 'math': MathBuilder()},
              inlineSyntaxes: [MathSyntax()],
              imageBuilder: (uri, title, alt) => Text(alt ?? '[Image omitted]'),
              onTapLink: (_, href, _) async {
                if (href != null) {
                  try {
                    await openExternalLink(href);
                  } catch (_) {}
                }
              },
              styleSheet: _styleSheet(context, t, c),
            ),
          ),
        if (streaming)
          Padding(
            padding: EdgeInsets.only(
              top: message.content.isEmpty ? AppDesign.xs : AppDesign.sm,
            ),
            child: const _StreamingDots(),
          ),
        if (!streaming && message.responseStatus != 'complete')
          Padding(
            padding: const EdgeInsets.only(top: AppDesign.sm),
            child: Text(
              switch (message.responseStatus) {
                'stopped' => context.l10n.stoppedPartial,
                'interrupted' => context.l10n.interruptedClosed,
                'generating' => context.l10n.interruptedPartial,
                _ => context.l10n.interruptedError,
              },
              style: context.text.mono.copyWith(
                color: message.responseStatus == 'error' ? c.danger : c.warning,
              ),
            ),
          ),
        if (!streaming && PhoneActions.mayHave(message.runJson))
          Builder(
            builder: (context) {
              final actions = PhoneActions.fromTrace(
                TurnRun.decode(message.runJson)?.toolTrace ?? const [],
              );
              return actions.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: AppDesign.md),
                      child: PhoneActionCards(actions: actions),
                    );
            },
          ),
        if (!streaming && sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppDesign.md),
            child: _SourcesBubble(sources: sources),
          ),
        if (!streaming && sources.isEmpty && bubble.onSearchWeb != null)
          Padding(
            padding: const EdgeInsets.only(top: AppDesign.sm),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppDesign.sm,
              children: [
                Text(
                  context.l10n.answerFromMemory,
                  style: context.text.mono.copyWith(color: c.textFaint),
                ),
                TextButton.icon(
                  key: const Key('search-web-answer'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesign.sm,
                    ),
                  ),
                  onPressed: bubble.onSearchWeb,
                  icon: const Icon(Icons.travel_explore, size: 16),
                  label: Text(context.l10n.searchTheWeb),
                ),
              ],
            ),
          ),
        if (!streaming) _actionBar(context, c),
      ],
    );
  }

  /// Under every finished answer (request 2026-10-04): copy, read
  /// aloud, regenerate, continue when cut short, how it was made, and ⋯ for
  /// the rest with labels, delete included.
  Widget _actionBar(BuildContext context, AppColors c) {
    final t = context.l10n;
    final warning = message.runJson?.contains('"warning"') == true
        ? TurnRun.decode(message.runJson)?.warning
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesign.xs),
      child: Row(
        children: [
          if (message.content.isNotEmpty)
            _ActionIcon(
              key: Key('copy-${message.id}'),
              tooltip: t.copyResponse,
              icon: Icons.copy_outlined,
              onPressed: () {
                AppHaptics.tick();
                Clipboard.setData(ClipboardData(text: message.content));
                showIslandToast(
                  context,
                  t.responseCopied,
                  tone: IslandTone.done,
                );
              },
            ),
          if (message.content.isNotEmpty && bubble.onSpeak != null)
            _ActionIcon(
              key: Key('speak-${message.id}'),
              tooltip: bubble.speaking ? t.stopReading : t.readAloud,
              color: bubble.speaking ? c.accent : null,
              icon: bubble.speaking
                  ? Icons.stop_circle_outlined
                  : Icons.volume_up_outlined,
              onPressed: bubble.onSpeak,
            ),
          if (bubble.onRegenerate != null)
            _ActionIcon(
              key: const Key('regenerate-answer'),
              tooltip: t.regenerate,
              icon: Icons.refresh,
              onPressed: bubble.onRegenerate,
            ),
          if (bubble.onContinue != null)
            _ActionIcon(
              key: const Key('continue-answer'),
              tooltip: t.continueAnswer,
              icon: Icons.play_arrow_outlined,
              color: c.accent,
              onPressed: bubble.onContinue,
            ),
          if (message.runJson != null)
            _ActionIcon(
              key: Key('run-${message.id}'),
              tooltip: t.runDetails,
              icon: Icons.info_outline,
              onPressed: () {
                final run = TurnRun.decode(message.runJson);
                if (run != null) showRunDetailsSheet(context, run);
              },
            ),
          // Beside "how this was made": what the source check doubted, in
          // full (tester, 2026-10-19).
          if (warning != null)
            _ActionIcon(
              key: Key('warning-${message.id}'),
              tooltip: t.answerWarning,
              icon: Icons.warning_amber_rounded,
              color: c.warning,
              onPressed: () => showNoticeSheet(context, warning, warning: true),
            ),
          _ActionIcon(
            key: Key('answer-more-${message.id}'),
            tooltip: t.more,
            icon: Icons.more_horiz,
            onPressed: () => bubble.showMessageActions(context),
          ),
        ],
      ),
    );
  }

  /// Markdown `##` sits between the headline and title roles.
  static const _h2Size = 19.0;

  MarkdownStyleSheet _styleSheet(
    BuildContext context,
    ThemeData t,
    AppColors c,
  ) {
    final code = context.text.mono.copyWith(color: c.text);
    return MarkdownStyleSheet.fromTheme(t).copyWith(
      p: context.text.body,
      h1: context.text.headline,
      h2: context.text.headline.copyWith(fontSize: _h2Size),
      h3: context.text.title,
      h4: context.text.title,
      h5: context.text.title,
      h6: context.text.title,
      a: context.text.body.copyWith(
        color: c.info,
        decoration: TextDecoration.underline,
        decorationColor: c.info.fade(0.5),
      ),
      code: code.copyWith(backgroundColor: c.surfaceRaised),
      // The 'pre' builder paints its own panel.
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
      blockquote: context.text.body.copyWith(color: c.textMuted),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.accent.fade(0.6), width: 2)),
      ),
      blockquotePadding: const EdgeInsets.only(left: AppDesign.md),
      listBullet: context.text.body.copyWith(color: c.textMuted),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      tableBorder: TableBorder.all(color: c.hairline),
      tableColumnWidth: markdownTableColumns(context),
      tableHead: context.text.body.copyWith(fontWeight: FontWeight.w600),
      tableBody: context.text.body,
      blockSpacing: AppDesign.md,
    );
  }
}

/// One compact disclosure at the end of an answer. Expanding it reveals all
/// cited sources; each row opens the provenance and passage inspector.
class _SourcesBubble extends StatelessWidget {
  final List<Map<String, dynamic>> sources;
  const _SourcesBubble({required this.sources});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final evidence = sources.where((s) => s['sponsored'] != true).toList();
    final sponsored = sources.where((s) => s['sponsored'] == true).toList();
    final border = RoundedRectangleBorder(
      borderRadius: AppDesign.radius(AppDesign.rMd),
      side: BorderSide(color: c.hairline),
    );
    return ClipRRect(
      borderRadius: AppDesign.radius(AppDesign.rMd),
      child: Material(
        color: c.surfaceRaised,
        child: ExpansionTile(
          key: const Key('sources-bubble'),
          dense: true,
          initiallyExpanded: false,
          shape: border,
          collapsedShape: border,
          leading: Icon(Icons.source_outlined, size: 18, color: c.textMuted),
          title: Text(
            '${evidence.length} ${context.l10n.uiChatBubbleSources.toLowerCase()} · '
            '${evidence.map((s) => Uri.tryParse(s['url'] as String? ?? '')?.host ?? '').where((h) => h.isNotEmpty).toSet().take(2).join(', ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.monoStrong.copyWith(color: c.text),
          ),
          children: [
            if (sponsored.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(AppDesign.sm),
                child: Text(
                  '${evidence.length} reference${evidence.length == 1 ? '' : 's'} · ${sponsored.length} sponsored',
                  style: context.text.mono.copyWith(color: c.textMuted),
                ),
              ),
            for (final s in evidence)
              ListTile(
                key: Key('source-${s['number']}'),
                dense: true,
                leading: Icon(
                  KnowledgeStore.isKnowledgeUrl(s['url'] as String)
                      ? Icons.local_library_outlined
                      : s['retrievalStatus'] == 'news_story'
                      ? Icons.newspaper_outlined
                      : s['retrievalStatus'] == 'page_read'
                      ? Icons.article_outlined
                      : Icons.short_text,
                  size: 17,
                  color: c.textMuted,
                ),
                title: Text(
                  '[${s['number']}] ${s['title'] ?? context.l10n.sourceFallbackTitle}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.small.copyWith(color: c.text),
                ),
                subtitle: KnowledgeStore.isKnowledgeUrl(s['url'] as String)
                    ? Text(context.l10n.uiChatBubbleKnowledgeLibrary)
                    : Text(
                        [
                          (s['outlet'] as String?) ??
                              Uri.tryParse(s['url'] as String)?.host ??
                              s['url'] as String,
                          if (s['retrievalStatus'] == 'news_story' &&
                              DateTime.tryParse(
                                    s['publishedAt'] as String? ?? '',
                                  ) !=
                                  null)
                            _age(
                              context.l10n,
                              DateTime.parse(s['publishedAt'] as String),
                            )
                          else if (s['retrievalStatus'] == 'page_read' &&
                              s['updatedAt'] is String &&
                              (s['updatedAt'] as String).length >= 10 &&
                              DateTime.tryParse(s['updatedAt'] as String) !=
                                  null)
                            context.l10n.sourceUpdated(
                              (s['updatedAt'] as String).substring(0, 10),
                            )
                          else if (s['retrievalStatus'] == 'page_read' &&
                              s['publishedAt'] is String &&
                              (s['publishedAt'] as String).length >= 10 &&
                              DateTime.tryParse(s['publishedAt'] as String) !=
                                  null)
                            context.l10n.sourcePublished(
                              (s['publishedAt'] as String).substring(0, 10),
                            ),
                          if (s['remembered'] == true)
                            context.l10n.sourceReadEarlier,
                          if (s['stale'] == true)
                            context.l10n.sourceMayBeOutdated,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.mono.copyWith(color: c.textFaint),
                      ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showSourceSheet(context, s),
              ),
            if (sponsored.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDesign.md,
                  AppDesign.sm,
                  AppDesign.md,
                  AppDesign.xs,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.uiChatBubbleSponsoredNotUsed,
                    style: context.text.monoStrong.copyWith(color: c.textMuted),
                  ),
                ),
              ),
            for (var i = 0; i < sponsored.length; i++)
              ListTile(
                key: Key('sponsored-source-$i'),
                dense: true,
                leading: Icon(
                  Icons.ads_click_outlined,
                  size: 17,
                  color: c.textMuted,
                ),
                title: Text(
                  sponsored[i]['title'] as String? ??
                      context.l10n.sourceSponsored,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.small.copyWith(color: c.text),
                ),
                subtitle: Text(
                  Uri.tryParse(sponsored[i]['url'] as String)?.host ??
                      sponsored[i]['url'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.mono.copyWith(color: c.textFaint),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showSourceSheet(context, sponsored[i]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Three dots breathing in sequence: the model is still writing.
class _StreamingDots extends StatefulWidget {
  const _StreamingDots();
  @override
  State<_StreamingDots> createState() => _StreamingDotsState();
}

class _StreamingDotsState extends State<_StreamingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    duration: AppMotion.ambient,
    vsync: this,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.loopAmbient(animate: context.motion.animates);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.fade(
                    0.25 + 0.75 * _pulse((_c.value * 2 - i * 0.18) % 1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static double _pulse(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;
}

/// "3 h ago", "yesterday" or the date, for a news story's publish time.
String _age(AppLocalizations t, DateTime published) {
  final d = DateTime.now().toUtc().difference(published.toUtc());
  if (d.inMinutes < 60) return t.minutesAgo(d.inMinutes.clamp(1, 59));
  if (d.inHours < 24) return t.hoursAgo(d.inHours);
  if (d.inHours < 48) return t.yesterday.toLowerCase();
  final local = published.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

/// Source inspector (roadmap WEB-08): what was fetched, when, and exactly
/// which passages the model was given — so a citation can be checked, not
/// just followed.
Future<void> showSourceSheet(
  BuildContext context,
  Map<String, dynamic> s,
) => showMorphSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) {
    final c = context.colors;
    final news = s['retrievalStatus'] == 'news_story';
    final read = s['retrievalStatus'] == 'page_read' || news;
    final excerpt = s['excerpt'] as String?;
    final fetched = s['fetchedAt'] as String?;
    final published = s['publishedAt'] as String?;
    final updated = s['updatedAt'] as String?;
    final stale = s['stale'] == true;
    final sponsored = s['sponsored'] == true;
    final url = (s['finalUrl'] ?? s['url']) as String;
    final t = context.l10n;
    final host = Uri.tryParse(url)?.host ?? '';
    final knowledge = KnowledgeStore.isKnowledgeUrl(url);
    final zim = url.startsWith('zim://');
    String cap(String v) =>
        v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
    String? stamp(String? iso) {
      final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
      if (d == null) return null;
      String two(int v) => v.toString().padLeft(2, '0');
      return '${d.year}-${two(d.month)}-${two(d.day)} '
          '${two(d.hour)}:${two(d.minute)}';
    }

    // One line per fact, each with an icon; the first says how the page
    // was used.
    final readAt = stamp(fetched);
    final status = <(IconData, String, Color)>[
      if (zim)
        (
          Icons.offline_pin_outlined,
          t.sourceArchiveSnapshot(
            '${s['archiveDate'] ?? '—'}',
            '${s['archiveLanguage'] ?? '—'}',
          ),
          c.warning,
        ),
      if (zim) (Icons.info_outline, t.sourceOfflineLimitation, c.warning),
      if (s['coverage'] == 'headline_only')
        (Icons.short_text, t.sourceHeadlineOnly, c.warning),
      if (s['coverage'] == 'extracted_section')
        (Icons.notes, t.sourceExtractedSection, c.textMuted),
      if (sponsored)
        (Icons.campaign_outlined, t.sourceSponsoredDetail, c.warning)
      else if (knowledge)
        (
          Icons.menu_book_outlined,
          t.sourceFromKnowledge('${s['title']}'),
          c.success,
        )
      else if (news)
        (
          Icons.newspaper_outlined,
          t.sourceNewsStory('${s['outlet'] ?? host}'),
          c.success,
        )
      else if (read)
        (Icons.check_circle_outline, t.sourcePageRead, c.success)
      else if (s['readError'] != null)
        (
          Icons.error_outline,
          t.sourceReadFailed('${s['readError']}'),
          c.warning,
        )
      else
        (Icons.short_text, t.sourceSnippetOnly, c.warning),
      if (!sponsored && read && readAt != null)
        (Icons.schedule, t.sourceReadAt(readAt), c.textMuted),
      if (!sponsored &&
          published != null &&
          DateTime.tryParse(published) != null)
        (
          Icons.event_outlined,
          cap(
            t.sourcePublished(
              news
                  ? _age(t, DateTime.parse(published))
                  : published.substring(0, published.length.clamp(0, 10)),
            ),
          ),
          c.textMuted,
        ),
      if (!sponsored && updated != null && DateTime.tryParse(updated) != null)
        (
          Icons.update,
          cap(t.sourceUpdated(updated.substring(0, 10))),
          c.textMuted,
        ),
      if (!sponsored && read && stale)
        (Icons.history, cap(t.sourceKeptCopy), c.warning),
    ];
    final passages = read && excerpt != null && excerpt.isNotEmpty
        ? excerpt.split('\n[…]\n')
        : [
            (s['snippet'] as String?)?.isNotEmpty == true
                ? s['snippet'] as String
                : t.sourceNoText,
          ];

    Widget statusRow((IconData, String, Color) row) {
      final parts = row.$2.split(' · ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDesign.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(row.$1, size: 18, color: row.$3),
            const SizedBox(width: AppDesign.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parts.first,
                    style: context.text.body.copyWith(color: row.$3),
                  ),
                  if (parts.length > 1)
                    Text(
                      cap(parts.skip(1).join(', ')),
                      style: context.text.small,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) => AppSheet(
        title:
            '${s['title'] ?? (sponsored ? t.sourceSponsored : t.sourceFallbackTitle)}',
        meta: host.isNotEmpty && !knowledge
            ? host.replaceFirst(RegExp(r'^www\.'), '')
            : null,
        scrollable: false,
        primary: knowledge
            ? null
            : FilledButton.icon(
                onPressed: () async {
                  if (zim) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ZimArticlePage(
                          url: url,
                          title: '${s['title']}',
                          excerpt: excerpt ?? '',
                          archiveDate: s['archiveDate'] as String?,
                          archiveId: s['archiveId'] as String?,
                        ),
                      ),
                    );
                    return;
                  }
                  try {
                    await openExternalLink(url);
                  } catch (_) {}
                },
                icon: Icon(
                  zim ? Icons.menu_book_outlined : Icons.open_in_new,
                  size: 16,
                ),
                label: Text(
                  zim ? t.sourceOpenArchived : t.uiChatBubbleOpenInBrowser,
                ),
              ),
        secondary: knowledge || zim
            ? null
            : TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  showIslandToast(
                    context,
                    t.sourceLinkCopied,
                    tone: IslandTone.done,
                  );
                },
                icon: const Icon(Icons.link, size: 16),
                label: Text(t.sourceCopyLink),
              ),
        leading: SizedBox.square(
          dimension: AppDesign.iconTile,
          child: Center(
            child: sponsored
                ? Icon(Icons.campaign_outlined, color: c.accent)
                : Text(
                    '${s['number'] ?? ''}',
                    style: context.text.monoStrong.copyWith(color: c.accent),
                  ),
          ),
        ),
        children: [
          ListView(
            controller: scroll,
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesign.md,
                  vertical: AppDesign.sm,
                ),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  border: Border.all(color: c.hairline),
                  borderRadius: AppDesign.radius(AppDesign.rMd),
                ),
                child: Column(children: [for (final r in status) statusRow(r)]),
              ),
              const SizedBox(height: AppDesign.xl),
              if (!sponsored)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppDesign.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.sourceGivenHeading,
                          style: context.text.title,
                        ),
                      ),
                      Text(
                        t.sourcePassageCount(passages.length),
                        style: context.text.mono.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
              for (final passage in passages) ...[
                ClipRRect(
                  borderRadius: AppDesign.radius(AppDesign.rSm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppDesign.md),
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      border: Border(
                        left: BorderSide(
                          color: sponsored ? c.hairlineStrong : c.accent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: SelectableText(
                      passage.trim(),
                      style: passage == t.sourceNoText
                          ? context.text.bodyMuted
                          : context.text.body.copyWith(height: 1.45),
                    ),
                  ),
                ),
                const SizedBox(height: AppDesign.sm),
              ],
              if (!knowledge) ...[
                const SizedBox(height: AppDesign.md),
                const SizedBox.shrink(),
                if (!zim) ...[
                  const SizedBox(height: AppDesign.lg),
                  Text(
                    t.sourceAddress,
                    style: context.text.label.copyWith(color: c.textFaint),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    url,
                    maxLines: 3,
                    style: context.text.mono.copyWith(color: c.textFaint),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  },
);

/// Inherited density flag set by the chat screen from Settings > Appearance.
class ChatBubbleDensity extends InheritedWidget {
  final bool compact;
  const ChatBubbleDensity({
    super.key,
    required this.compact,
    required super.child,
  });

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ChatBubbleDensity>()
          ?.compact ??
      false;

  @override
  bool updateShouldNotify(ChatBubbleDensity old) => old.compact != compact;
}
