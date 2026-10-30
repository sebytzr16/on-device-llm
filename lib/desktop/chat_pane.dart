import '../core/platform/desktop_preferences.dart';
import 'model_visibility.dart';
import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/island/status_island.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/motion.dart';
import '../features/attachments/data/attachment_store.dart';
import '../features/attachments/domain/attachment.dart';
import '../features/attachments/presentation/attachment_chips.dart';
import '../features/attachments/presentation/attachment_picker.dart';
import '../features/chat/domain/entities/chat_message.dart';
import '../features/chat/domain/retrieval_plan.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import '../features/chat/presentation/widgets/chat_bubble.dart';
import '../features/chat/presentation/widgets/composer.dart';
import '../features/chat/presentation/widgets/send_button.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/models/presentation/providers/retired_model_names.dart';
import '../features/presets/presentation/providers/presets_provider.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../features/settings/presentation/providers/effective_settings_provider.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../features/settings/presentation/widgets/settings_labels.dart';
import '../features/shortcuts/domain/prompt_shortcut.dart';
import '../features/shortcuts/prompt_shortcuts_provider.dart';
import '../features/tools/presentation/tools_quick_panel.dart';
import '../features/voice/voice_service.dart';
import '../features/voice/conversation_screen.dart';
import 'desktop_theme.dart';
import 'focus_ring.dart';
import 'chat_tools.dart';
import 'inspector_panel.dart';
import 'load_progress.dart';
import 'model_preset_menu.dart';
import 'title_bar.dart';

/// The conversation in a centred reading column, the composer pinned under
/// it. Turns, answers, sources and maths render with the shared bubble.
class DesktopChatPane extends ConsumerStatefulWidget {
  final FocusNode composerFocus;
  const DesktopChatPane({super.key, required this.composerFocus});

  @override
  ConsumerState<DesktopChatPane> createState() => _DesktopChatPaneState();
}

class _DesktopChatPaneState extends ConsumerState<DesktopChatPane> {
  final _composer = GlobalKey<_ComposerState>();
  bool _dropping = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final count = state.messages.length + (state.showsLiveAnswer ? 1 : 0);
    return DropTarget(
      enable: !state.isGenerating,
      onDragEntered: (_) => setState(() => _dropping = true),
      onDragExited: (_) => setState(() => _dropping = false),
      onDragDone: (details) async {
        setState(() => _dropping = false);
        await _composer.currentState?._import([
          for (final file in details.files) (file.name, file.path, null),
        ]);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.desktopChatTitle,
                      style: context.text.headline,
                    ),
                    Text(
                      context.l10n.desktopChatExplanation,
                      style: context.text.small,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _conversation(context, ref, state, count)),
                    const DesktopInspectorSlot(),
                  ],
                ),
              ),
            ],
          ),
          if (_dropping)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.accent.fade(0.12),
                    borderRadius: AppDesign.radius(AppDesign.rLg),
                    border: Border.all(color: context.colors.accent, width: 2),
                  ),
                  child: Center(
                    child: Chip(label: Text(context.l10n.desktopChatDrop)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Deletes a turn and offers to bring it back from the island.
  Future<void> _deleteTurn(ChatMessage message, {required bool pair}) async {
    try {
      final notifier = ref.read(chatProvider.notifier);
      final deletion = await notifier.deleteTurn(message.id, pair: pair);
      if (!mounted || deletion == null) return;
      final toast = islandToastFor(context);
      final unavailable = context.l10n.undoUnavailable;
      toast(
        context.l10n.messageDeleted,
        icon: Icons.delete_outline,
        action: IslandAction(context.l10n.undo, () async {
          try {
            final ok = await notifier.undoDelete(deletion);
            if (!ok) toast(unavailable);
          } catch (e) {
            toast('$e', tone: IslandTone.error);
          }
        }),
      );
    } catch (e) {
      if (mounted) showIslandToast(context, '$e', tone: IslandTone.error);
    }
  }

  /// Answers the same question with another downloaded model, picked from
  /// a small dialog rather than the phone's sheet.
  Future<void> _compare(ChatMessage answer) async {
    final candidates = ref
        .read(modelManagerProvider)
        .catalog
        .where(
          (m) =>
              m.isDownloaded &&
              m.id != answer.modelId &&
              desktopModelVisible(
                m,
                advanced: ref.read(desktopPreferencesProvider).advanced,
              ),
        )
        .toList();
    final picked = await showAppDialog<ModelInfo>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(dialog.l10n.compareWithTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dialog.l10n.compareHint,
                style: dialog.text.small.copyWith(
                  color: dialog.colors.textMuted,
                ),
              ),
              const SizedBox(height: AppDesign.md),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in candidates)
                      ListTile(
                        key: Key('compare-${m.id}'),
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDesign.radius(AppDesign.rMd),
                        ),
                        leading: const Icon(Icons.memory, size: 18),
                        title: Text(m.displayName),
                        subtitle: Text(
                          '${m.quantLabel} · '
                          '${m.sizeLabel}',
                        ),
                        onTap: () => Navigator.pop(dialog, m),
                      ),
                  ],
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
        ],
      ),
    );
    if (picked != null && mounted) {
      await ref.read(chatProvider.notifier).compare(picked);
    }
  }

  Widget _conversation(
    BuildContext context,
    WidgetRef ref,
    ChatState state,
    int count,
  ) {
    final busy = state.isGenerating;
    final notifier = ref.read(chatProvider.notifier);
    final models = ref.watch(modelManagerProvider);
    final speakingId = ref.watch(voiceProvider.select((v) => v.speakingId));
    final messages = state.messages;
    final live = messages.where(ChatNotifier.isLive).toList();
    final lastAssistant = live
        .where((m) => m.role == ChatRole.assistant)
        .lastOrNull;
    final lastUser = live.where((m) => m.role == ChatRole.user).lastOrNull;
    // Edited questions keep their earlier versions under the same parent.
    final versionsByParent = <String?, List<ChatMessage>>{};
    for (final m in messages) {
      if (m.role == ChatRole.user && !m.isAlternative) {
        versionsByParent.putIfAbsent(m.parentId, () => []).add(m);
      }
    }
    final downloadedModelCount = models.catalog
        .where((m) => m.isDownloaded)
        .length;
    final remote = ref.watch(
      settingsProvider.select((s) => s.usesRemote ? s.remoteModel : null),
    );
    final remoteActive = remote != null;
    final webAllowed = ref.watch(
      settingsProvider.select(
        (s) => s.webSearchEnabled && (!s.usesRemote || s.remoteWebResearch),
      ),
    );
    // An answer from memory to a real question offers a web search.
    final memoryAnswerQuestion =
        webAllowed &&
            lastUser != null &&
            !RetrievalPlan.smallTalk(lastUser.content) &&
            !RetrievalPlan.localTask(lastUser.content)
        ? lastUser.content
        : null;
    final retired = ref.watch(retiredModelNamesProvider);
    String modelName(String? id) => modelLabel(
      id,
      catalog: models.catalog,
      retired: retired,
      removed: context.l10n.modelRemovedLabel,
      fallback: models.loadedModel?.displayName,
    );

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: MenuAnchor(
            menuChildren: [
              MenuItemButton(
                onPressed: state.chatId == null || state.temporary
                    ? null
                    : () => exportDesktopChat(context, ref),
                child: Text(context.l10n.desktopChatExport),
              ),
            ],
            builder: (context, controller, child) => IconButton(
              tooltip: context.l10n.desktopChatMenu,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ),
        Expanded(
          child: messages.isEmpty && !busy
              ? const _EmptyState()
              : SelectionArea(
                  // A right-click on a message with nothing selected opens
                  // that message's actions instead of the text menu.
                  contextMenuBuilder: (context, region) {
                    final pending = ChatBubble.takeRightClick();
                    final selected = region.contextMenuButtonItems.any(
                      (i) => i.type == ContextMenuButtonType.copy,
                    );
                    if (pending == null || selected) {
                      return AdaptiveTextSelectionToolbar.selectableRegion(
                        selectableRegionState: region,
                      );
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      region.hideToolbar();
                      pending();
                    });
                    return const SizedBox.shrink();
                  },
                  // Newest at the bottom; a reversed list stays pinned to
                  // the answer being written without scroll bookkeeping.
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    itemCount: count,
                    itemBuilder: (context, i) {
                      final index = count - 1 - i;
                      final Widget child;
                      if (index >= messages.length) {
                        child = state.isLoadingModel
                            ? const _LoadingRow()
                            : _LiveAnswer(
                                modelName: remoteActive
                                    ? modelName('remote:$remote')
                                    : models.loadedModel?.displayName,
                              );
                      } else {
                        final m = messages[index];
                        final lastAnswer = !busy && m.id == lastAssistant?.id;
                        child = ChatBubble(
                          key: ValueKey(m.id),
                          message: m,
                          modelName: m.role == ChatRole.assistant
                              ? modelName(m.modelId)
                              : null,
                          versions: m.role == ChatRole.user
                              ? versionsByParent[m.parentId] ?? const []
                              : const [],
                          onRestoreVersion: !busy && m.role == ChatRole.user
                              ? (branch) =>
                                    unawaited(notifier.restoreBranch(branch))
                              : null,
                          onRestore: !busy && m.branch != null
                              ? () => notifier.restoreBranch(m.branch!)
                              : null,
                          onDelete: !busy && !m.isSuperseded && !m.isAlternative
                              ? (pair) => _deleteTurn(m, pair: pair)
                              : null,
                          onSpeak: m.role == ChatRole.assistant
                              ? () => ref
                                    .read(voiceProvider.notifier)
                                    .speak(m.content, id: m.id)
                              : null,
                          speaking: speakingId == m.id,
                          onEdit: !busy && m.role == ChatRole.user
                              ? (text) => m.id == lastUser?.id
                                    ? notifier.editLast(text)
                                    : notifier.editTurn(m, text)
                              : null,
                          onRegenerate:
                              lastAnswer ||
                                  (!busy &&
                                      m.role == ChatRole.user &&
                                      m.id == live.lastOrNull?.id)
                              ? notifier.regenerate
                              : null,
                          onSearchWeb:
                              lastAnswer &&
                                  memoryAnswerQuestion != null &&
                                  m.responseStatus == 'complete' &&
                                  m.content.isNotEmpty
                              ? notifier.searchAgain
                              : null,
                          onCompare:
                              lastAnswer &&
                                  !remoteActive &&
                                  downloadedModelCount > 1
                              ? () => _compare(m)
                              : null,
                          onContinue:
                              lastAnswer &&
                                  m.content.isNotEmpty &&
                                  const {
                                    'stopped',
                                    'interrupted',
                                    'error',
                                  }.contains(m.status)
                              ? notifier.continueAnswer
                              : null,
                          // A branch copies the conversation up to here into
                          // a new chat.
                          onBranch:
                              !busy &&
                                  !state.temporary &&
                                  state.chatId != null &&
                                  ChatNotifier.isLive(m)
                              ? () => notifier.copyChat(
                                  state.chatId!,
                                  throughMessageId: m.id,
                                )
                              : null,
                        );
                      }
                      return _Column(child: child);
                    },
                  ),
                ),
        ),
        if (state.error != null || state.notice != null)
          _Column(
            child: _Notice(
              text: state.error ?? state.notice!,
              error: state.error != null,
            ),
          ),
        _Column(
          child: _Composer(key: _composer, focus: widget.composerFocus),
        ),
      ],
    );
  }
}

/// Everything in the pane shares one reading width.
class _Column extends StatelessWidget {
  final Widget child;
  const _Column({required this.child});

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: DesktopTheme.readingWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: child,
      ),
    ),
  );
}

class _LiveAnswer extends ConsumerWidget {
  final String? modelName;
  const _LiveAnswer({this.modelName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (answer, reasoning) = ref.watch(
      chatProvider.select((s) => (s.partialAnswer, s.reasoning?.content)),
    );
    return ChatBubble(
      streaming: true,
      modelName: modelName,
      message: ChatMessage(
        id: 'streaming',
        role: ChatRole.assistant,
        content: answer,
        reasoning: reasoning,
        timestamp: DateTime.now(),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppDesign.lg),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: const ModelLoadProgress(),
    ),
  );
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final hasModel = ref.watch(
      modelManagerProvider.select((m) => m.loadedModelId != null),
    );
    final loading = ref.watch(
      modelManagerProvider.select((m) => m.isLoadingModel),
    );
    return Center(
      child: SpringEntrance(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.desktopEmptyTitle,
                textAlign: TextAlign.center,
                style: context.text.display.copyWith(fontSize: 30),
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.desktopEmptyHint,
                textAlign: TextAlign.center,
                style: context.text.bodyMuted.copyWith(fontSize: 13.5),
              ),
              if (loading) ...[
                const SizedBox(height: 24),
                const SizedBox(width: 360, child: ModelLoadProgress()),
              ] else if (!hasModel) ...[
                const SizedBox(height: 20),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: c.hairline),
                    borderRadius: AppDesign.radius(AppDesign.rFull),
                  ),
                  child: const ModelPickerChip(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final bool error;
  const _Notice({required this.text, required this.error});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = error ? c.danger : c.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 15,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: context.text.small.copyWith(color: tone)),
          ),
        ],
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  final FocusNode focus;
  const _Composer({super.key, required this.focus});

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _text = TextEditingController();
  late final FocusNode _field = FocusNode(onKeyEvent: _onKey);

  @override
  void initState() {
    super.initState();
    // Ctrl+L and new chat focus the outer node; hand it to the field.
    widget.focus.addListener(_handFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _field.requestFocus());
  }

  void _handFocus() {
    if (widget.focus.hasPrimaryFocus) _field.requestFocus();
  }

  @override
  void dispose() {
    widget.focus.removeListener(_handFocus);
    _text.dispose();
    _field.dispose();
    super.dispose();
  }

  /// Enter sends, Shift+Enter is a new line (the field's own behaviour).
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      unawaited(_paste());
      return KeyEventResult.handled;
    }
    final enter =
        e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (enter && !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  final _pending = <Attachment>[];
  static bool _webExplained = false;

  Future<void> _send() async {
    if (ref.read(chatProvider).isGenerating) return;
    final text = _text.text;
    final attachments = List<Attachment>.of(_pending);
    if (text.trim().isEmpty && attachments.isEmpty) return;
    // "/summarize Ã¢â‚¬Â¦" goes out as the saved prompt with the text in it.
    final shortcut = PromptShortcut.apply(
      text,
      ref.read(promptShortcutsProvider),
      lang: Localizations.localeOf(context).languageCode,
    );
    _text.clear();
    setState(_pending.clear);
    final accepted = await ref
        .read(chatProvider.notifier)
        .send(
          shortcut?.$2 ?? text,
          attachments: attachments,
          learn: shortcut == null,
        );
    if (mounted && !accepted) {
      if (_text.text.isEmpty) _text.text = text;
      setState(() => _pending.addAll(attachments));
    }
  }

  /// Windows' file dialog straight away: no camera or gallery on a PC.
  Future<void> _attach() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !mounted) return;
    final sources = <(String, String?, Uint8List?)>[
      for (final f in files)
        (f.name, f.path, f.path == null ? await f.readAsBytes() : null),
    ];
    if (!mounted) return;
    await _import(sources);
  }

  Future<void> _import(List<(String, String?, Uint8List?)> sources) async {
    if (!mounted || ref.read(chatProvider).isGenerating) return;
    try {
      final picked = await importAttachments(context, sources);
      if (mounted) {
        setState(() => _pending.addAll(picked));
      } else {
        for (final attachment in picked) {
          await AttachmentStore.delete(attachment);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.desktopChatActionFailed)),
        );
      }
    }
  }

  Future<void> _paste() async {
    if (ref.read(chatProvider).isGenerating) return;
    try {
      final image = await Pasteboard.image;
      if (!mounted) return;
      if (image != null && image.isNotEmpty) {
        final directory = await Directory(
          (await getTemporaryDirectory()).path,
        ).createTemp('chat-paste-');
        try {
          final file = File('${directory.path}/image.png');
          await file.writeAsBytes(image, flush: true);
          if (mounted) {
            await _import([
              (context.l10n.desktopChatClipboardImage, file.path, null),
            ]);
          }
        } finally {
          await directory.delete(recursive: true);
        }
      } else {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (mounted && data?.text != null) {
          final selection = _text.selection;
          final start = selection.isValid ? selection.start : _text.text.length;
          final end = selection.isValid ? selection.end : start;
          final text = data!.text!;
          _text.value = TextEditingValue(
            text: _text.text.replaceRange(start, end, text),
            selection: TextSelection.collapsed(offset: start + text.length),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.desktopChatActionFailed)),
        );
      }
    }
  }

  void _remove(Attachment a) {
    setState(() => _pending.remove(a));
    unawaited(AttachmentStore.delete(a));
  }

  /// Local Ã¢â€ â€™ Auto Ã¢â€ â€™ Always Ã¢â€ â€™ Local; leaving Local asks once per run.
  Future<void> _cycleWeb() async {
    final settings = ref.read(settingsProvider);
    final next = switch (settings.webMode) {
      WebMode.off => WebMode.auto,
      WebMode.auto => WebMode.always,
      WebMode.always => WebMode.off,
    };
    if (settings.webMode == WebMode.off && !_webExplained) {
      final ok = await confirmAction(
        context,
        title: context.l10n.turnOnWebQuestion,
        message: context.l10n.turnOnWebHint,
        confirmLabel: context.l10n.turnOn,
        cancelLabel: context.l10n.stayLocal,
      );
      if (ok != true || !mounted) return;
      _webExplained = true;
    }
    await ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(webMode: next));
  }

  /// Off Ã¢â€ â€™ Low Ã¢â€ â€™ Medium Ã¢â€ â€™ High Ã¢â€ â€™ Off, for this chat only.
  void _cycleThinking(InferenceSettings settings) {
    final next = settings.thinkingLevel.next;
    final overrides = {...ref.read(chatOverridesProvider), ...next.overrides};
    if (next == ThinkingLevel.off) overrides.remove('thinkingBudgetTokens');
    unawaited(ref.read(chatProvider.notifier).setChatOverrides(overrides));
  }

  void _dictate(InferenceSettings settings, bool listening) {
    final n = ref.read(voiceProvider.notifier);
    if (listening) {
      n.stop();
      return;
    }
    final before = _text.text;
    n.listen(
      onDeviceOnly: settings.voiceOnDeviceOnly,
      onText: (t) {
        _text.text = before.isEmpty ? t : '$before $t';
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
      },
    );
  }

  Future<void> _openConversation() async {
    final chat = ref.read(chatProvider);
    if (!chat.isGenerating && chat.messages.isNotEmpty) {
      ref.read(chatProvider.notifier).newChat();
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const ConversationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final busy = ref.watch(chatProvider.select((s) => s.isGenerating));
    final rate = ref.watch(
      chatProvider.select(
        (s) => (s.metrics['tokensPerSecond'] as num?)?.toDouble(),
      ),
    );
    final settings = ref.watch(effectiveSettingsProvider).effective;
    final web = settings.webMode;
    final hasModel = ref.watch(
      modelManagerProvider.select((m) => m.loadedModelId != null),
    );
    final variantModelId = ref.watch(
      modelManagerProvider.select((m) => m.loadedModelId),
    );
    final presets = ref.watch(presetsProvider);
    final preset = presets.active;
    final voice = ref.watch(voiceProvider);
    final lang = Localizations.localeOf(context).languageCode;
    final shortcuts = [
      for (final s in ref.watch(promptShortcutsProvider)) s.localized(lang),
    ];
    final used = ref.watch(
      chatProvider.select(
        (s) =>
            ((s.metrics['promptTokens'] as num?) ?? 0) +
            ((s.metrics['tokens'] as num?) ?? 0),
      ),
    );
    return Focus(
      focusNode: widget.focus,
      skipTraversal: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The phone's message box: one rounded, raised surface whose
            // outline turns amber while you type, and the round send button.
            ListenableBuilder(
              listenable: _field,
              builder: (context, child) => AnimatedContainer(
                duration: DesktopTheme.medium,
                curve: DesktopTheme.curve,
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: AppDesign.radius(AppDesign.rXl),
                  border: Border.all(
                    color: _field.hasFocus
                        ? c.accent.fade(0.7)
                        : c.hairlineStrong,
                  ),
                ),
                child: child,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedSize(
                      duration: DesktopTheme.medium,
                      curve: DesktopTheme.curve,
                      alignment: Alignment.topCenter,
                      child: _pending.isEmpty
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 6, right: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AttachmentChips(
                                    attachments: _pending,
                                    onRemove: busy ? null : _remove,
                                  ),
                                  if (!busy) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final (label, prompt)
                                            in _pending.any((a) => a.isImage)
                                                ? ChatComposer.imageActionsIn(
                                                    l10n,
                                                  )
                                                : ChatComposer.documentActionsIn(
                                                    l10n,
                                                  ))
                                          ActionChip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(label),
                                            labelStyle: context.text.mono
                                                .copyWith(color: c.text),
                                            onPressed: () {
                                              _text.text = prompt;
                                              _send();
                                            },
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                    ),
                    // "/" + the start of a name: matching prompt shortcuts.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _text,
                      builder: (context, value, _) {
                        final matches = PromptShortcut.suggestions(
                          value.text,
                          shortcuts,
                        );
                        return AnimatedSize(
                          duration: DesktopTheme.medium,
                          curve: DesktopTheme.curve,
                          child: matches.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final m in matches)
                                        ActionChip(
                                          visualDensity: VisualDensity.compact,
                                          avatar: Icon(
                                            Icons.bolt_rounded,
                                            size: 14,
                                            color: c.accent,
                                          ),
                                          label: Text('/${m.name}'),
                                          labelStyle: context.text.mono
                                              .copyWith(color: c.text),
                                          onPressed: () {
                                            _text.text = '/${m.name} ';
                                            _text.selection =
                                                TextSelection.collapsed(
                                                  offset: _text.text.length,
                                                );
                                            _field.requestFocus();
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                        );
                      },
                    ),
                    TextField(
                      controller: _text,
                      focusNode: _field,
                      minLines: 1,
                      maxLines: 10,
                      keyboardType: TextInputType.multiline,
                      style: context.text.body,
                      decoration: InputDecoration(
                        hintText: voice.listening
                            ? l10n.listening
                            : l10n.messageHint,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    Row(
                      children: [
                        _IconPill(
                          icon: Icons.add_rounded,
                          tooltip: l10n.desktopAttachTooltip,
                          onTap: busy ? null : _attach,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              spacing: 6,
                              children: [
                                MenuAnchor(
                                  menuChildren: [
                                    for (final p in presets.presets)
                                      MenuItemButton(
                                        leadingIcon: Text(p.emoji),
                                        trailingIcon: p.id == preset.id
                                            ? Icon(
                                                Icons.check_rounded,
                                                size: 16,
                                                color: c.accent,
                                              )
                                            : null,
                                        onPressed: () => ref
                                            .read(presetsProvider.notifier)
                                            .activate(p.id),
                                        child: Text(p.name),
                                      ),
                                  ],
                                  builder: (context, menu, _) => _Pill(
                                    emoji: preset.emoji,
                                    label: preset.name,
                                    on: preset.id != 'general',
                                    onTap: busy
                                        ? null
                                        : () => menu.isOpen
                                              ? menu.close()
                                              : menu.open(),
                                  ),
                                ),
                                if (variantModelId != null)
                                  DesktopModelPresetMenu(
                                    modelId: variantModelId,
                                    pill: true,
                                  ),
                                _Pill(
                                  icon: Icons.psychology_outlined,
                                  label: settings.thinkingModeEnabled
                                      ? thinkingLevelLabel(
                                          settings.thinkingLevel,
                                          l10n,
                                        )
                                      : l10n.think,
                                  on: settings.thinkingModeEnabled,
                                  onTap: busy
                                      ? null
                                      : () => _cycleThinking(settings),
                                ),
                                _Pill(
                                  icon: web == WebMode.off
                                      ? Icons.public_off_rounded
                                      : Icons.public_rounded,
                                  label: switch (web) {
                                    WebMode.off => l10n.webLocal,
                                    WebMode.auto => l10n.webAuto,
                                    WebMode.always => l10n.webAlways,
                                  },
                                  on: web != WebMode.off,
                                  onTap: busy ? null : _cycleWeb,
                                ),
                                MenuAnchor(
                                  alignmentOffset: const Offset(0, 6),
                                  menuChildren: const [
                                    SizedBox(
                                      width: 380,
                                      child: ToolsQuickPanel(),
                                    ),
                                  ],
                                  builder: (context, menu, _) => _Pill(
                                    icon: Icons.build_outlined,
                                    label: l10n.uiToolsQuickPanelToolUse,
                                    on: settings.toolsEnabled,
                                    onTap: busy
                                        ? null
                                        : () => menu.isOpen
                                              ? menu.close()
                                              : menu.open(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _IconPill(
                          icon: voice.listening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          tooltip: voice.listening
                              ? l10n.stopDictation
                              : l10n.dictate,
                          danger: voice.listening,
                          onTap: busy
                              ? null
                              : () => _dictate(settings, voice.listening),
                        ),
                        _IconPill(
                          icon: Icons.record_voice_over_outlined,
                          tooltip: l10n.conversationTitle,
                          onTap: busy ? null : _openConversation,
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _text,
                          builder: (_, value, _) => SendButton(
                            tooltip: busy
                                ? '${l10n.stop} (Esc)'
                                : '${l10n.send} (Enter)',
                            busy: busy,
                            ready:
                                (value.text.trim().isNotEmpty ||
                                    _pending.isNotEmpty) &&
                                hasModel,
                            onSend: _send,
                            onStop: () =>
                                ref.read(chatProvider.notifier).cancel(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (voice.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: Text(
                  voice.error!,
                  style: context.text.mono.copyWith(
                    color: c.warning,
                    fontSize: 11.5,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Text(
                      l10n.desktopComposerHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.caption.copyWith(
                        color: c.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  if (rate != null && rate > 0)
                    Text(
                      l10n.desktopTokensPerSecond(rate.toStringAsFixed(1)),
                      style: context.text.mono.copyWith(fontSize: 11),
                    ),
                  // LM Studio's context meter: the last turn's share of n_ctx.
                  if (used > 0)
                    Tooltip(
                      message: l10n.desktopContextUsed(
                        used.round(),
                        settings.contextSize,
                      ),
                      child: SizedBox(
                        width: 64,
                        child: ClipRRect(
                          borderRadius: AppDesign.radius(AppDesign.rFull),
                          child: LinearProgressIndicator(
                            value: (used / settings.contextSize)
                                .clamp(0, 1)
                                .toDouble(),
                            minHeight: 4,
                            color: used / settings.contextSize > 0.85
                                ? c.warning
                                : c.accent,
                            backgroundColor: c.hairline,
                          ),
                        ),
                      ),
                    ),
                  ValueListenableBuilder<bool>(
                    valueListenable: desktopInspectorOpen,
                    builder: (_, open, _) => _IconPill(
                      icon: Icons.tune_rounded,
                      tooltip: '${l10n.desktopInspectorToggle} (Ctrl+I)',
                      small: true,
                      on: open,
                      onTap: () => desktopInspectorOpen.value = !open,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A stadium chip like the phone composer's: amber when on.
class _Pill extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final String label;
  final bool on;
  final VoidCallback? onTap;
  const _Pill({
    this.icon,
    this.emoji,
    required this.label,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(enabled: onTap != null, child: _chip(context, c));
  }

  Widget _chip(BuildContext context, AppColors c) {
    return Material(
      color: on ? c.accent.fade(0.12) : c.surface,
      shape: StadiumBorder(
        side: BorderSide(color: on ? c.accent.fade(0.5) : c.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: DesktopFocusRing(
        label: label,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emoji != null)
                  Text(emoji!, style: const TextStyle(fontSize: 12))
                else
                  Icon(icon, size: 15, color: on ? c.accent : c.textMuted),
                const SizedBox(width: 6),
                BlurSwitcher(
                  child: Text(
                    label,
                    key: ValueKey(label),
                    style: context.text.mono.copyWith(
                      fontSize: 12,
                      color: on ? c.accent : c.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round icon button in the pill style (attach, dictate, inspector).
class _IconPill extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool on, danger, small;
  const _IconPill({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.on = false,
    this.danger = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = danger ? c.danger : (on ? c.accent : c.textMuted);
    return Tooltip(
      message: tooltip,
      child: Pressable(
        enabled: onTap != null,
        child: Material(
          color: danger
              ? c.danger.fade(0.14)
              : (on ? c.accent.fade(0.12) : c.surface),
          shape: CircleBorder(
            side: BorderSide(
              color: danger
                  ? c.danger.fade(0.5)
                  : (on ? c.accent.fade(0.5) : c.hairline),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: DesktopFocusRing(
            label: tooltip,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.all(small ? 4 : 7),
                child: BlurSwitcher(
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    size: small ? 14 : 17,
                    color: tint,
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
