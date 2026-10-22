import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../app.dart';
import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/motion/motion.dart';
import '../../../attachments/data/attachment_store.dart';
import '../../../attachments/domain/attachment.dart';
import '../../../attachments/presentation/attachment_picker.dart';
import '../../../tools/presentation/tools_quick_panel.dart';
import '../../../goals/goal_specialization.dart';
import '../../../goals/presentation/goals_page.dart';
import '../../../knowledge/knowledge_store.dart';
import '../../../knowledge/knowledge_embedder.dart';
import '../../../models/domain/entities/model_info.dart';
import '../../../models/domain/model_config_card.dart';
import '../../../models/presentation/widgets/config_card_flow.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../../models/presentation/providers/model_recommendations_provider.dart';
import '../../../presets/presentation/providers/presets_provider.dart';
import '../../../settings/presentation/providers/effective_settings_provider.dart';
import '../../../shortcuts/domain/prompt_shortcut.dart';
import '../../../shortcuts/prompt_shortcuts_provider.dart';
import '../../../settings/presentation/providers/model_profiles_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/screens/overrides_page.dart';
import '../../../settings/presentation/widgets/metrics_sheet.dart';
import '../../../share/share_inbox.dart';
import '../../../voice/conversation_screen.dart';
import '../../../voice/voice_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/turn_run.dart';
import '../../domain/chat_draft_store.dart';
import '../../domain/temporary_files.dart';
import '../../domain/context_summary.dart';
import 'conversation_workspace_page.dart';
import '../../domain/export/chat_document.dart';
import '../../domain/export/document_draft_service.dart';
import '../../domain/export/document_draft_store.dart';
import '../../../../inference/engine/text_engine.dart';
import '../../../../core/providers/shared_providers.dart';
import '../providers/chat_model_pins.dart';
import '../../domain/retrieval_plan.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_title.dart';
import '../widgets/composer.dart';
import '../widgets/conversations_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/memory_banner.dart';
import '../widgets/notice_sheet.dart';
import '../../../../core/design/app_dialog.dart';

part 'chat_screen_actions.dart';
part 'chat_screen_widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _pending = <Attachment>[];
  final _drafts = ChatDraftStore();
  String _draftKey = 'new';
  Timer? _draftTimer;
  bool _restoringDraft = false;
  bool _temporaryDraft = false;
  int _draftRevision = 0;

  void _saveDraft() {
    if (_restoringDraft) return;
    if (_temporaryDraft || ref.read(chatProvider).temporary) {
      unawaited(
        TemporaryFiles.remember(
          _pending.map((a) => a.path),
        ).catchError((Object _) {}),
      );
      return;
    }
    _draftRevision++;
    _draftTimer?.cancel();
    final key = _draftKey;
    final draft = ChatDraft(text: _input.text, attachments: List.of(_pending));
    _draftTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        _drafts.save(key, draft).catchError((Object error) {
          if (mounted) {
            showIslandToast(context, '$error', tone: IslandTone.warning);
          }
        }),
      );
    });
  }

  Future<void> _switchDraft(String? chatId) async {
    final temporary = ref.read(chatProvider).temporary;
    final key = temporary ? 'temporary' : chatId ?? 'new';
    if (key == _draftKey) return;
    _draftTimer?.cancel();
    if (!_temporaryDraft) {
      unawaited(
        _drafts
            .save(
              _draftKey,
              ChatDraft(text: _input.text, attachments: List.of(_pending)),
            )
            .catchError((Object error) {
              if (mounted) {
                showIslandToast(context, '$error', tone: IslandTone.warning);
              }
            }),
      );
    }
    _draftKey = key;
    _temporaryDraft = temporary;
    _restoringDraft = true;
    _input.clear();
    _pending.clear();
    _restoringDraft = false;
    if (!temporary) await _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    if (ref.read(chatProvider).temporary) return;
    final key = _draftKey;
    final revision = _draftRevision;
    try {
      final draft = await _drafts.read(key);
      if (!mounted || key != _draftKey || revision != _draftRevision) return;
      _restoringDraft = true;
      setState(() {
        _input.text = draft.text;
        _pending
          ..clear()
          ..addAll(draft.attachments);
      });
      _restoringDraft = false;
    } catch (error) {
      if (mounted) showIslandToast(context, '$error', tone: IslandTone.warning);
    }
  }

  Future<void> _newChat() async {
    ref.read(chatProvider.notifier).newChat();
    await _switchDraft(null);
  }

  void _insertDraft(String text) {
    // Incoming shares never replace text the user has already written.
    final combined = _input.text.trim().isEmpty
        ? text
        : '${_input.text}\n\n$text';
    _input.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
    _saveDraft();
  }

  StreamSubscription<void>? _shares;

  /// Messages already shown. Only a question sent from the composer springs
  /// in; history, answers and restored chats appear as they are.
  final _seen = <String>{};

  /// A question was just sent: the next new question on screen springs in.
  bool _springNext = false;

  /// What the island showed while this turn got ready: 'load', 'research'
  /// or null. Decides the check it flashes when the answer starts.
  String? _islandKind;

  /// Far enough above the latest message to offer the jump button.
  bool _awayFromBottom = false;

  @override
  void initState() {
    super.initState();
    final initialChat = ref.read(chatProvider);
    _temporaryDraft = initialChat.temporary;
    _draftKey = _temporaryDraft ? 'temporary' : initialChat.chatId ?? 'new';
    _input.addListener(_saveDraft);
    unawaited(_restoreDraft());
    _scroll.addListener(_onScroll);
    // "Share to OnDevice LLM": the share that opened the app, then any
    // share that reaches it while it runs.
    _shares = ShareInbox.arrivals.listen((_) => _openShare());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openShare());
  }

  void _onScroll() {
    if (_scroll.hasClients) _atBottom = _scroll.position.extentAfter < 48;
    final away = _scroll.hasClients && _scroll.position.extentAfter > 400;
    if (away != _awayFromBottom) setState(() => _awayFromBottom = away);
  }

  bool _nearTop() => !_scroll.hasClients || _scroll.offset < 40;

  /// The list's height and whether the reader was at its end, last time
  /// they changed.
  double? _viewport;
  bool _atBottom = true;

  /// The list follows a streaming answer until the reader drags it; it
  /// follows again once they let go at the end, tap the jump button or
  /// send. Jumping on every repaint used to cancel the drag, so the reader
  /// could not scroll up during an answer (tester, 2026-10-20).
  bool _follow = true;

  /// A finger (or its fling) is moving the list.
  bool _userScrolling = false;

  bool _onUserScroll(UserScrollNotification n) {
    if (n.depth != 0) return false;
    _userScrolling = n.direction != ScrollDirection.idle;
    if (n.direction == ScrollDirection.forward) {
      // Towards older messages.
      _follow = false;
    } else if (!_userScrolling && n.metrics.extentAfter < 48) {
      _follow = true;
    }
    return false;
  }

  /// Keeps the end of the chat in view while the notice, memory and
  /// numbers strips grow in under it: the list shrank after the answer and
  /// cut off its sources card (the tester's phone chat, 2026-10-19).
  bool _keepBottom(ScrollMetricsNotification n) {
    if (n.depth != 0) return false;
    final m = n.metrics;
    final shrank = _viewport != null && m.viewportDimension < _viewport! - 0.5;
    _viewport = m.viewportDimension;
    if (shrank && _atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } else {
      _atBottom = m.extentAfter < 48;
    }
    return false;
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _follow = true;
    AppHaptics.tick();
    unawaited(
      _scroll.glideTo(_scroll.position.maxScrollExtent, context.motion),
    );
  }

  /// Whether [m] should spring in: a question just sent from the composer,
  /// the first time it is on screen.
  bool _springsIn(ChatMessage m) {
    if (!_seen.add(m.id)) return false;
    if (m.role != ChatRole.user || !_springNext) return false;
    _springNext = false;
    return true;
  }

  /// The island tells what the turn does before text streams: loading the
  /// model, searching, reading pages. It flashes a check when writing starts.
  void _syncIsland((bool, bool, String?, bool) next) {
    final island = ref.read(islandProvider.notifier);
    final t = context.l10n;
    final (busy, loading, notice, writing) = next;
    if (busy && !writing && loading) {
      _islandKind = 'load';
      final models = ref.read(modelManagerProvider);
      final name =
          ref
              .read(chatProvider.notifier)
              .pinnedModel(ref.read(chatProvider).chatId)
              ?.displayName ??
          models.loadedModel?.displayName ??
          models.catalog.where((m) => m.isDownloaded).firstOrNull?.displayName;
      island.activity(
        IslandMessage(
          name == null ? t.loadingModel : t.islandLoadingModel(name),
          tone: IslandTone.busy,
        ),
      );
      return;
    }
    if (busy && !writing && notice != null && notice.isNotEmpty) {
      // "Searching…" is under way; "3 pages read from 5 results." is a result.
      final underWay = notice.endsWith('…');
      if (underWay) _islandKind = 'research';
      island.activity(
        IslandMessage(
          notice,
          tone: underWay ? IslandTone.busy : IslandTone.info,
          icon: underWay ? null : Icons.travel_explore,
        ),
      );
      return;
    }
    final kind = _islandKind;
    _islandKind = null;
    island.activity(null);
    if (kind != null && ref.read(chatProvider).error == null) {
      island.toast(
        kind == 'load' ? t.islandModelReady : t.islandResearchDone,
        tone: IslandTone.done,
        duration: const Duration(milliseconds: 1100),
      );
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (!_temporaryDraft) {
      unawaited(
        _drafts
            .save(
              _draftKey,
              ChatDraft(text: _input.text, attachments: List.of(_pending)),
            )
            .catchError((Object _) {}),
      );
    }
    unawaited(_shares?.cancel());
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static Future<ModelConfigCard?> _configCardIn(SharedPayload share) async {
    final fromText = ModelConfigCard.decode(share.text);
    if (fromText != null) return fromText;
    // Any small file, whatever its name or type: messaging apps rename
    // `.odllm.json` cards or send them as generic files. The content decides.
    for (final f in share.files) {
      try {
        final file = File(f.path);
        if (await file.length() > 256 * 1024) continue;
        final card = ModelConfigCard.decode(await file.readAsString());
        if (card != null) return card;
      } catch (_) {}
    }
    return null;
  }

  /// Puts a shared item into a new chat: the text (a link, a quote) in the
  /// message box for the user to finish, the files attached, the attachment
  /// quick actions ready. Nothing is sent until the user sends it.
  bool _openingShare = false;
  bool _shareArrivalPending = false;

  Future<void> _openShare() async {
    if (_openingShare) {
      _shareArrivalPending = true;
      return;
    }
    _openingShare = true;
    try {
      SharedPayload? share;
      do {
        _shareArrivalPending = false;
        share = await ShareInbox.take();
        if (share != null && mounted) {
          try {
            await _handleShare(share);
          } finally {
            await ShareInbox.discardFiles(share);
          }
        }
      } while (mounted && (share != null || _shareArrivalPending));
    } finally {
      _openingShare = false;
    }
  }

  /// The choices for text selected in another app; null when dismissed.
  Future<String?> _pickSelectionAction() => showMorphSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final t = sheet.l10n;
      Widget option(String id, IconData icon, String label) => ListTile(
        key: Key('selection-$id'),
        leading: Icon(icon),
        title: Text(label),
        onTap: () => Navigator.pop(sheet, id),
      );
      return AppSheet(
        title: t.selectionTitle,
        children: [
          option('explain', Icons.lightbulb_outline, t.selectionExplain),
          option('summarize', Icons.notes, t.selectionSummarize),
          option('translate', Icons.translate, t.selectionTranslate),
          option('fix', Icons.spellcheck, t.selectionFix),
          option('ask', Icons.chat_bubble_outline, t.selectionAsk),
        ],
      );
    },
  );

  Future<void> _handleShare(SharedPayload share) async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    final toast = islandToastFor(context);
    if (share.error != null || share.isEmpty) {
      toast(share.error ?? context.l10n.shareNothing, tone: IslandTone.warning);
      return;
    }
    // The assistant gesture, the quick-settings tile or the widget.
    if (share.launch != null) {
      if (!ref.read(chatProvider).isGenerating) {
        await _newChat();
      }
      if (share.launch == 'voice') {
        unawaited(_openConversation());
      } else {
        _inputFocus.requestFocus();
      }
      return;
    }
    // Text selected in another app: the user picks what to do with it, and
    // the matching /shortcut goes in the box so they see what is sent.
    if (share.selection) {
      final text = share.text.trim();
      final action = await _pickSelectionAction();
      if (!mounted) return;
      if (!ref.read(chatProvider).isGenerating) {
        await _newChat();
      }
      if (!mounted) return;
      final lang = Localizations.localeOf(context).languageCode;
      final draft = switch (action) {
        'explain' || 'summarize' || 'fix' => '/$action $text',
        'translate' => '/translate $lang $text',
        _ => '$text\n\n',
      };
      _insertDraft(draft);
      if (action == null || action == 'ask') _inputFocus.requestFocus();
      return;
    }
    // A tapped scheduled prompt: asked at once (the tap is the request), or
    // opened as a goal. Mid-answer it waits in the box instead.
    if (share.scheduled != null) {
      if (share.scheduled == 'goal') {
        _openGoal(objective: share.text);
      } else if (ref.read(chatProvider).isGenerating) {
        _insertDraft(share.text);
        toast(context.l10n.scheduledWaiting, icon: Icons.schedule);
      } else {
        await _newChat();
        _insertDraft(share.text);
        await _send();
      }
      return;
    }
    // A shared model configuration opens its import preview, not a chat.
    final card = await _configCardIn(share);
    if (!mounted) return;
    if (card != null) {
      await showConfigCardPreview(context, ref, card);
      return;
    }
    // Mid-answer the current chat stays; the share waits in the box.
    if (!ref.read(chatProvider).isGenerating) {
      await _newChat();
    }
    if (!mounted) return;
    final files = share.files.isEmpty
        ? const <Attachment>[]
        : await importAttachments(context, [
            for (final f in share.files) (f.name, f.path, null),
          ]);
    if (!mounted) return;
    setState(() => _pending.addAll(files));
    final draft = share.draft;
    if (draft.isNotEmpty) {
      _insertDraft(draft);
    }
    if (share.skipped.isNotEmpty || share.more) {
      toast(
        [
          if (share.skipped.isNotEmpty)
            context.l10n.shareSkipped(share.skipped.join(', ')),
          if (share.more) context.l10n.shareMore,
        ].join('\n'),
        tone: IslandTone.warning,
      );
    }
  }

  /// Conversation mode: a full-screen voice chat in a new chat, saved like
  /// any other.
  Future<void> _openConversation() async {
    AppHaptics.tick();
    final chat = ref.read(chatProvider);
    if (!chat.isGenerating && chat.messages.isNotEmpty) await _newChat();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const ConversationScreen(),
      ),
    );
  }

  Future<void> _send() async {
    if (ref.read(chatProvider).isGenerating) return;
    final text = _input.text;
    final attachments = List<Attachment>.of(_pending);
    if (text.trim().isEmpty && attachments.isEmpty) return;
    // "/summarize …" goes out as the saved prompt with the text in it.
    final shortcut = PromptShortcut.apply(
      text,
      ref.read(promptShortcutsProvider),
      lang: Localizations.localeOf(context).languageCode,
    );
    _input.clear();
    setState(_pending.clear);
    _saveDraft();
    _springNext = true;
    _follow = true;
    final accepted = await ref
        .read(chatProvider.notifier)
        .send(
          shortcut?.$2 ?? text,
          attachments: attachments,
          learn: shortcut == null,
        );
    if (mounted && !accepted) {
      _springNext = false;
      if (_input.text.isEmpty) _input.text = text;
      setState(() => _pending.addAll(attachments));
      _saveDraft();
    }
  }

  Future<void> _attach({String? source, BuildContext? from}) async {
    final picked = await pickAttachments(
      context,
      source: source,
      from: from,
      more: [
        AttachTile(
          key: const Key('attach-goal'),
          icon: Icons.flag_outlined,
          label: context.l10n.attachGoalShort,
          tooltip: '${context.l10n.attachGoal}: ${context.l10n.attachGoalHint}',
          onTap: (sheet) {
            Navigator.pop(sheet);
            _openGoal(objective: _input.text);
          },
        ),
      ],
      below: const [ToolsQuickPanel()],
    );
    if (mounted && picked.isNotEmpty) {
      if (ref.read(chatProvider).temporary) {
        await TemporaryFiles.remember(picked.map((a) => a.path));
      }
      if (!mounted) return;
      setState(() => _pending.addAll(picked));
      _saveDraft();
    }
  }

  /// Goals, with [objective] (the message being typed) as the goal and the
  /// kind of research guessed from its wording. The message box keeps the
  /// text: backing out of Goals without starting must not lose it.
  void _openGoal({String? objective}) {
    final text = objective?.trim() ?? '';
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => GoalsPage(
            initialObjective: text.isEmpty ? null : text,
            initialSpecialization: text.isEmpty
                ? null
                : GoalSpecialization.guess(text),
          ),
        ),
      ),
    );
  }

  void _removeAttachment(Attachment a) {
    setState(() => _pending.remove(a));
    _saveDraft();
    unawaited(AttachmentStore.delete(a));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      chatProvider.select((s) => (s.chatId, s.temporary)),
      (_, value) => unawaited(_switchDraft(value.$1)),
    );
    final t = context.l10n;
    // Everything but the streamed text: the live answer repaints on its own
    // (_LiveAnswer), so a long chat is not rebuilt at every stream frame.
    ref.watch(
      chatProvider.select(
        (s) => (
          s.messages,
          s.isGenerating,
          s.isLoadingModel,
          s.error,
          s.chatId,
          s.notice,
          s.metrics,
          s.learned,
        ),
      ),
    );
    final state = ref.read(chatProvider);
    final islandUp = ref.watch(islandProvider.select((s) => s.showing != null));
    final models = ref.watch(modelManagerProvider);
    final speakingId = ref.watch(voiceProvider.select((v) => v.speakingId));
    final notifier = ref.read(chatProvider.notifier);
    final busy = state.isGenerating;
    // The notice pops up over the chat for a few seconds (tester,
    // 2026-10-19: no arrow to fold it any more).
    final noticeUp = state.notice?.isNotEmpty == true && !busy;
    final infoKey = '${state.notice}|${identityHashCode(state.metrics)}';
    final liveMessages = state.messages.where(ChatNotifier.isLive).toList();
    final versionsByParent = <String?, List<ChatMessage>>{};
    for (final message in state.messages) {
      if (message.role == ChatRole.user && !message.isAlternative) {
        versionsByParent.putIfAbsent(message.parentId, () => []).add(message);
      }
    }
    final lastUser = liveMessages
        .where((m) => m.role == ChatRole.user)
        .lastOrNull;
    final lastAssistant = liveMessages
        .where((m) => m.role == ChatRole.assistant)
        .lastOrNull;
    final downloadedModelCount = models.catalog
        .where((m) => m.isDownloaded)
        .length;
    ref.listen(
      chatProvider.select(
        (s) => (
          s.isGenerating,
          s.isLoadingModel,
          s.notice,
          s.partialAnswer.isNotEmpty || s.reasoning != null,
        ),
      ),
      (_, next) => _syncIsland(next),
    );
    ref.listen(chatProvider, (previous, next) {
      // Read the finished answer aloud when the setting asks for it.
      if (previous?.isGenerating == true &&
          !next.isGenerating &&
          next.error == null &&
          ref.read(settingsProvider).readAloud &&
          // The conversation screen speaks its own answers.
          !ConversationScreen.open) {
        final last = next.messages.lastOrNull;
        if (last != null &&
            last.role == ChatRole.assistant &&
            last.content.isNotEmpty) {
          unawaited(
            ref.read(voiceProvider.notifier).speak(last.content, id: last.id),
          );
        }
      }
      // A finished answer says so at the top (tester, 2026-10-20), with a
      // light tap.
      if (previous?.isGenerating == true &&
          !next.isGenerating &&
          next.error == null &&
          !ConversationScreen.open) {
        final last = next.messages.lastOrNull;
        if (last != null &&
            last.role == ChatRole.assistant &&
            (last.status == 'complete' || last.status == 'alternative')) {
          ref
              .read(islandProvider.notifier)
              .toast(context.l10n.islandAnswered, tone: IslandTone.done);
          AppHaptics.press();
        }
      }
      // Follow the stream while the reader stays at the end; a drag stops
      // it. Outside a turn, only when already near the bottom.
      if (!_follow || _userScrolling) return;
      if (!next.isGenerating &&
          _scroll.hasClients &&
          _scroll.position.extentAfter > 180) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _follow && !_userScrolling && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
    final remote = ref.watch(
      settingsProvider.select(
        (s) => s.usesRemote ? (s.remoteUri!.host, s.remoteModel) : null,
      ),
    );
    final remoteActive = remote != null;
    final webAllowed = ref.watch(
      settingsProvider.select(
        (s) => s.webSearchEnabled && (!s.usesRemote || s.remoteWebResearch),
      ),
    );
    // An answer from memory to a real question (not a greeting or writing
    // work) offers a one-tap web search.
    final memoryAnswerQuestion =
        webAllowed &&
            lastUser != null &&
            !RetrievalPlan.smallTalk(lastUser.content) &&
            !RetrievalPlan.localTask(lastUser.content)
        ? lastUser.content
        : null;
    ref.watch(chatModelPinsProvider);
    final pinned = ref.read(chatProvider.notifier).pinnedModel(state.chatId);
    String modelName(String? id) {
      if (id != null && id.startsWith('remote:')) {
        final m = id.substring(7);
        return '${m.isEmpty ? 'server model' : m} · remote';
      }
      return models.catalog.where((m) => m.id == id).firstOrNull?.displayName ??
          id ??
          'model';
    }

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: t.conversations,
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: ChatTitle(
          subtitle: state.temporary
              ? t.temporaryChat
              : remote != null
              ? '${remote.$2.isEmpty ? 'server model' : remote.$2} @ ${remote.$1}'
              : pinned != null
              ? t.chatPinned(pinned.displayName)
              : models.loadedModel?.displayName ?? t.noModelLoaded,
        ),
        actions: [
          IconButton(
            key: const Key('voice-conversation'),
            tooltip: t.voiceConversation,
            onPressed: () => unawaited(_openConversation()),
            icon: const Icon(Icons.record_voice_over_outlined),
          ),
          IconButton(
            tooltip: t.newChat,
            onPressed: busy ? null : _newChat,
            icon: const Icon(Icons.edit_square),
          ),
          PopupMenuButton<String>(
            tooltip: t.more,
            onSelected: _onMenu,
            // Request 2026-10-04: fifteen entries became seven. New
            // temporary chat, Projects and Goals live in the drawer; the
            // five ways to save a chat open one "Share or export" sheet.
            itemBuilder: (_) {
              final hasChat = state.messages.isNotEmpty && !busy;
              final overrides = ref.read(chatOverridesProvider).length;
              return [
                PopupMenuItem(
                  key: const Key('menu-chat-settings'),
                  value: 'chat-settings',
                  child: _MenuRow(
                    Icons.layers_outlined,
                    overrides == 0
                        ? t.chatSettingsMenu
                        : t.chatSettingsMenuCount(overrides),
                  ),
                ),
                if (state.chatId != null &&
                    !state.temporary &&
                    !busy &&
                    remote == null)
                  PopupMenuItem(
                    value: 'pin-model',
                    child: _MenuRow(Icons.push_pin_outlined, t.chatPinModel),
                  ),
                if (hasChat) ...[
                  PopupMenuItem(
                    key: const Key('menu-export'),
                    value: 'export',
                    child: _MenuRow(Icons.ios_share, t.shareOrExport),
                  ),
                  if (!state.temporary)
                    PopupMenuItem(
                      value: 'context-summary',
                      child: _MenuRow(
                        Icons.summarize_outlined,
                        t.contextSummary,
                      ),
                    ),
                ],
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'models',
                  child: _MenuRow(Icons.memory, t.models),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: _MenuRow(Icons.tune, t.settings),
                ),
                PopupMenuItem(
                  value: 'metrics',
                  child: _MenuRow(Icons.speed_outlined, t.metrics),
                ),
              ];
            },
          ),
        ],
      ),
      drawer: const Drawer(child: ConversationsSheet()),
      body: Column(
        children: [
          Expanded(
            // The welcome blurs away as the first question arrives, and
            // comes back the same way for a new chat.
            child: BlurSwitcher(
              child: state.messages.isEmpty && !busy
                  ? ChatEmptyState(
                      key: const ValueKey('empty'),
                      hasModel: models.catalog.any((m) => m.isDownloaded),
                      remoteHost: remote?.$1,
                      onAskPhoto: () => _attach(source: 'camera'),
                      onAskFile: () => _attach(source: 'file'),
                      onResearchGoal: _openGoal,
                    )
                  : Stack(
                      key: const ValueKey('conversation'),
                      children: [
                        // While the island shows over the top of a short
                        // conversation, the conversation eases down to make
                        // room (further down, it only covers older lines).
                        AnimatedPadding(
                          padding: EdgeInsets.only(
                            top: islandUp && _nearTop() ? 44 : 0,
                          ),
                          // In step with the island dropping in.
                          duration: context.motion.fade(AppMotion.glide),
                          curve: SpringCurve(
                            context.motion.snappy,
                            seconds: AppMotion.glide.inMilliseconds / 1000,
                          ),
                          child: ChatBubbleDensity(
                            compact: ref.watch(
                              settingsProvider.select((s) => s.compactBubbles),
                            ),
                            child: NotificationListener<UserScrollNotification>(
                              onNotification: _onUserScroll,
                              child: NotificationListener<ScrollMetricsNotification>(
                                onNotification: _keepBottom,
                                child: ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppDesign.lg,
                                  ),
                                  itemCount:
                                      state.messages.length + (busy ? 1 : 0),
                                  itemBuilder: (_, i) {
                                    if (i < state.messages.length) {
                                      final m = state.messages[i];
                                      // Turn actions apply to the last live question and
                                      // answer only (CHAT-02); earlier turns are history.
                                      final notifier = ref.read(
                                        chatProvider.notifier,
                                      );
                                      final isLastAnswer =
                                          !busy &&
                                          m.id == lastAssistant?.id &&
                                          m == liveMessages.last;
                                      final springs = _springsIn(m);
                                      return SpringEntrance(
                                        key: ValueKey('in-${m.id}'),
                                        animate: springs,
                                        from: const Offset(0, 22),
                                        fromScale: 0.94,
                                        scaleAlignment: Alignment.bottomRight,
                                        child: ChatBubble(
                                          message: m,
                                          onDelete:
                                              !busy &&
                                                  !m.isSuperseded &&
                                                  !m.isAlternative
                                              ? (pair) =>
                                                    _deleteTurn(m, pair: pair)
                                              : null,
                                          versions: m.role == ChatRole.user
                                              ? versionsByParent[m.parentId] ??
                                                    const []
                                              : const [],
                                          onRestoreVersion:
                                              !busy && m.role == ChatRole.user
                                              ? (branch) => unawaited(
                                                  notifier.restoreBranch(
                                                    branch,
                                                  ),
                                                )
                                              : null,
                                          modelName:
                                              m.role == ChatRole.assistant
                                              ? modelName(m.modelId)
                                              : null,
                                          onSpeak: m.role == ChatRole.assistant
                                              ? () => ref
                                                    .read(
                                                      voiceProvider.notifier,
                                                    )
                                                    .speak(m.content, id: m.id)
                                              : null,
                                          speaking: speakingId == m.id,
                                          onEdit:
                                              !busy && m.role == ChatRole.user
                                              ? (text) => m.id == lastUser?.id
                                                    ? notifier.editLast(text)
                                                    : notifier.editTurn(m, text)
                                              : null,
                                          onRestore: !busy && m.branch != null
                                              ? () => notifier.restoreBranch(
                                                  m.branch!,
                                                )
                                              : null,
                                          onRegenerate:
                                              isLastAnswer ||
                                                  (!busy &&
                                                      m.role == ChatRole.user &&
                                                      m == liveMessages.last)
                                              ? notifier.regenerate
                                              : null,
                                          onSearchWeb:
                                              isLastAnswer &&
                                                  memoryAnswerQuestion !=
                                                      null &&
                                                  m.responseStatus ==
                                                      'complete' &&
                                                  m.content.isNotEmpty
                                              ? notifier.searchAgain
                                              : null,
                                          onCompare:
                                              isLastAnswer &&
                                                  !remoteActive &&
                                                  downloadedModelCount > 1
                                              ? () => _compare(m)
                                              : null,
                                          onContinue:
                                              isLastAnswer &&
                                                  m.content.isNotEmpty &&
                                                  const {
                                                    'stopped',
                                                    'interrupted',
                                                    'error',
                                                  }.contains(m.status)
                                              ? notifier.continueAnswer
                                              : null,
                                        ),
                                      );
                                    }
                                    return SpringEntrance(
                                      key: const ValueKey('live-answer'),
                                      from: const Offset(0, 10),
                                      child: state.isLoadingModel
                                          ? const _LoadingModelRow()
                                          : _LiveAnswer(
                                              modelName: remote != null
                                                  ? modelName(
                                                      'remote:${remote.$2}',
                                                    )
                                                  : models
                                                        .loadedModel
                                                        ?.displayName,
                                            ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: AppDesign.sm,
                          left: AppDesign.lg,
                          right: AppDesign.lg,
                          child: _NoticeToast(
                            notice: noticeUp ? state.notice : null,
                            id: noticeUp ? infoKey : '',
                            warning:
                                noticeUp &&
                                lastAssistant?.runJson?.contains('"warning"') ==
                                    true &&
                                TurnRun.decode(
                                      lastAssistant!.runJson,
                                    )?.warning ==
                                    state.notice,
                          ),
                        ),
                        Positioned(
                          bottom: AppDesign.md,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _JumpToLatest(
                              visible: _awayFromBottom,
                              onTap: _jumpToLatest,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          _GrowIn(
            child: state.learned.isNotEmpty
                ? MemoryBanner(state.learned, key: const ValueKey('memory'))
                : null,
          ),
          _GrowIn(
            child: state.error != null
                ? _ErrorBanner(state.error!, key: ValueKey(state.error))
                : null,
          ),
          ChatComposer(
            controller: _input,
            focusNode: _inputFocus,
            busy: busy,
            canSend: !models.isLoadingModel,
            onSend: _send,
            onStop: notifier.cancel,
            attachments: _pending,
            onAttach: (from) => _attach(from: from),
            onRemoveAttachment: _removeAttachment,
            onQuickPrompt: (text) {
              _input.text = text;
              unawaited(_send());
            },
            onResearchGoal: (text) => _openGoal(objective: text),
          ),
        ],
      ),
    );
  }
}
