import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/motion/motion.dart';
import '../../../attachments/domain/attachment.dart';
import '../../../attachments/presentation/attachment_chips.dart';
import '../../../goals/goal_specialization.dart';
import '../../../share/reader_actions.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../../models/presentation/widgets/model_picker_sheet.dart';
import '../../../presets/presentation/preset_sheet.dart';
import '../../../presets/presentation/providers/presets_provider.dart';
import '../../../shortcuts/domain/prompt_shortcut.dart';
import '../../../shortcuts/presentation/shortcuts_page.dart';
import '../../../shortcuts/prompt_shortcuts_provider.dart';
import '../../../voice/voice_service.dart';
import '../../../settings/domain/entities/inference_settings.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/widgets/settings_labels.dart';
import 'send_button.dart';
import '../providers/chat_provider.dart';
import '../../../settings/presentation/providers/effective_settings_provider.dart';
import '../../../../core/design/app_dialog.dart';

/// Bottom composer: model, preset, Think and web-mode pills sharing one
/// row equally, the multiline input and a single send-or-stop button.
class ChatComposer extends ConsumerStatefulWidget {
  final TextEditingController controller;

  /// Lets the screen put the cursor in the box (widget, shared text).
  final FocusNode? focusNode;
  final bool busy, canSend;
  final VoidCallback onSend, onStop;

  /// Files waiting to go with the next message, and the attach/remove flows.
  /// [onAttach] gets the + button, for the sheet to grow out of.
  final List<Attachment> attachments;
  final ValueChanged<BuildContext>? onAttach;
  final ValueChanged<Attachment>? onRemoveAttachment;

  /// Sends a suggested question about the pending attachments (FX-08).
  final ValueChanged<String>? onQuickPrompt;

  /// Offered when the typed message reads like a research project: opens
  /// Goals with it as the objective.
  final ValueChanged<String>? onResearchGoal;
  const ChatComposer({
    super.key,
    required this.controller,
    this.focusNode,
    required this.busy,
    required this.canSend,
    required this.onSend,
    required this.onStop,
    this.attachments = const [],
    this.onAttach,
    this.onRemoveAttachment,
    this.onQuickPrompt,
    this.onResearchGoal,
  });

  /// One-tap questions once something is attached: photo actions from the
  /// AI Edge Gallery "Ask Image" pattern, document actions for files.
  /// One-tap questions (label, prompt) in the app's language, so the
  /// answer comes back in it too.
  static List<(String, String)> imageActionsIn(AppLocalizations t) => [
    (t.quickDescribe, t.quickDescribePrompt),
    (t.quickExtractText, t.quickExtractTextPrompt),
    (t.quickTranslate, t.quickTranslatePrompt),
    (t.quickSolve, t.quickSolvePrompt),
    (t.quickExplain, t.quickExplainPrompt),
    (t.quickIdentify, t.quickIdentifyPrompt),
  ];
  static List<(String, String)> documentActionsIn(AppLocalizations t) => [
    (t.quickSummarise, t.quickSummarisePrompt),
    (t.quickKeyPoints, t.quickKeyPointsPrompt),
    (t.quickExplainSimply, t.quickExplainSimplyPrompt),
    (t.quickActionItems, t.quickActionItemsPrompt),
    (t.quickQuestions, t.quickQuestionsPrompt),
  ];

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  // One explanation per app run: the point is informed consent, not nagging.
  static bool _webSearchExplained = false;

  /// Local → Auto → Always → Local. Leaving Local asks for consent once per run.
  Future<void> _cycleWeb() async {
    final settings = ref.read(settingsProvider);
    final next = switch (settings.webMode) {
      WebMode.off => WebMode.auto,
      WebMode.auto => WebMode.always,
      WebMode.always => WebMode.off,
    };
    // Consent is about leaving Local; auto -> always changes only how often.
    if (settings.webMode == WebMode.off && !_webSearchExplained) {
      final ok = await confirmAction(
        context,
        title: context.l10n.turnOnWebQuestion,
        message: context.l10n.turnOnWebHint,
        confirmLabel: context.l10n.turnOn,
        cancelLabel: context.l10n.stayLocal,
      );
      if (ok != true || !mounted) return;
      _webSearchExplained = true;
    }
    AppHaptics.tick();
    await ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(webMode: next));
    if (mounted) {
      showIslandToast(
        context,
        webModeLabel(next, context.l10n),
        icon: next == WebMode.off ? Icons.public_off : Icons.public,
      );
    }
  }

  /// Off → Low → Medium → High → Off, for this chat only (review
  /// 2026-09-28: every chat starts without thinking unless the user's
  /// default says otherwise).
  void _cycleThinking(InferenceSettings settings) {
    final next = settings.thinkingLevel.next;
    AppHaptics.tick();
    final overrides = {...ref.read(chatOverridesProvider), ...next.overrides};
    if (next == ThinkingLevel.off) overrides.remove('thinkingBudgetTokens');
    unawaited(ref.read(chatProvider.notifier).setChatOverrides(overrides));
    final t = context.l10n;
    showIslandToast(
      context,
      next == ThinkingLevel.off
          ? t.thinkOffToast
          : t.thinkLevelToast(thinkingLevelLabel(next, t)),
      icon: Icons.psychology_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = ref.watch(effectiveSettingsProvider).effective;
    final loaded = ref.watch(modelManagerProvider.select((m) => m.loadedModel));
    final preset = ref.watch(presetsProvider.select((s) => s.active));
    final voice = ref.watch(voiceProvider);
    final lang = Localizations.localeOf(context).languageCode;
    final shortcuts = [
      for (final s in ref.watch(promptShortcutsProvider)) s.localized(lang),
    ];
    final busy = widget.busy;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDesign.md,
          AppDesign.xs,
          AppDesign.md,
          AppDesign.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Four controls share the row equally so nothing scrolls off
            // the right edge: model, preset, Think, web mode.
            Row(
              children: [
                Expanded(
                  child: _Pill(
                    key: const Key('model-pill'),
                    onTap: busy
                        ? null
                        : (from) => showModelPickerSheet(context, from: from),
                    child: Builder(
                      builder: (context) {
                        final name = settings.usesRemote
                            ? (settings.remoteModel.isEmpty
                                  ? settings.remoteUri!.host
                                  : settings.remoteModel)
                            : loaded?.displayName ?? context.l10n.modelPill;
                        return BlurSwitcher(
                          child: Text(
                            name,
                            key: ValueKey(name),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.caption.copyWith(
                              color: loaded == null && !settings.usesRemote
                                  ? c.accent
                                  : c.text,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Pill(
                    key: const Key('preset-pill'),
                    selected: preset.id != 'general',
                    onTap: busy
                        ? null
                        : (from) => showPresetSheet(context, from: from),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          preset.emoji,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: AppDesign.xs),
                        Flexible(
                          child: Text(
                            preset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.caption.copyWith(
                              color: preset.id != 'general' ? c.accent : c.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Pill(
                    key: const Key('think-pill'),
                    selected: settings.thinkingModeEnabled,
                    onTap: busy ? null : (_) => _cycleThinking(settings),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 15,
                          color: settings.thinkingModeEnabled
                              ? c.accent
                              : c.textMuted,
                        ),
                        const SizedBox(width: AppDesign.xs),
                        Flexible(
                          child: BlurSwitcher(
                            child: Text(
                              settings.thinkingModeEnabled
                                  ? thinkingLevelLabel(
                                      settings.thinkingLevel,
                                      context.l10n,
                                    )
                                  : context.l10n.think,
                              key: ValueKey(settings.thinkingLevel),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.caption.copyWith(
                                color: settings.thinkingModeEnabled
                                    ? c.accent
                                    : c.text,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Pill(
                    key: const Key('web-pill'),
                    onTap: busy ? null : (_) => _cycleWeb(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.public,
                          size: 14,
                          color: settings.webSearchEnabled
                              ? c.info
                              : c.textMuted,
                        ),
                        const SizedBox(width: AppDesign.xs),
                        Flexible(
                          child: BlurSwitcher(
                            child: Text(
                              switch (settings.webMode) {
                                WebMode.off => context.l10n.webLocal,
                                WebMode.auto => context.l10n.webAuto,
                                WebMode.always => context.l10n.webAlways,
                              },
                              key: ValueKey(settings.webMode),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.caption.copyWith(
                                color: settings.webSearchEnabled
                                    ? c.info
                                    : c.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _Grows(
              child: voice.error == null
                  ? null
                  : Padding(
                      key: ValueKey(voice.error),
                      padding: const EdgeInsets.only(top: AppDesign.xs),
                      child: Text(
                        voice.error!,
                        style: context.text.mono.copyWith(color: c.warning),
                      ),
                    ),
            ),
            _Grows(
              child: widget.attachments.isEmpty
                  ? null
                  : Column(
                      key: const ValueKey('attachments'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppDesign.sm),
                        AttachmentChips(
                          attachments: widget.attachments,
                          onRemove: busy ? null : widget.onRemoveAttachment,
                        ),
                        if (!busy && widget.onQuickPrompt != null) ...[
                          const SizedBox(height: AppDesign.sm),
                          SizedBox(
                            height: 32,
                            child: ListView(
                              key: const Key('quick-actions'),
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              children: [
                                for (final (i, (label, prompt))
                                    in (widget.attachments.any((a) => a.isImage)
                                            ? ChatComposer.imageActionsIn(
                                                context.l10n,
                                              )
                                            : ChatComposer.documentActionsIn(
                                                context.l10n,
                                              ))
                                        .indexed)
                                  _Cascade(
                                    index: i,
                                    child: ActionChip(
                                      key: Key('quick-$label'),
                                      visualDensity: VisualDensity.compact,
                                      label: Text(label),
                                      labelStyle: context.text.mono.copyWith(
                                        color: c.text,
                                      ),
                                      onPressed: () =>
                                          widget.onQuickPrompt!(prompt),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            // "/" + the start of a name: matching prompt shortcuts.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) =>
                  _Grows(child: _suggestions(context, value, shortcuts, busy)),
            ),
            const SizedBox(height: AppDesign.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Pressable(
                    enabled: !busy && widget.onAttach != null,
                    child: Builder(
                      builder: (button) => IconButton(
                        key: const Key('attach'),
                        tooltip: context.l10n.attachTooltip,
                        onPressed: busy || widget.onAttach == null
                            ? null
                            : () => widget.onAttach!(button),
                        color: c.textMuted,
                        icon: const Icon(Icons.add_circle_outline, size: 24),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('message-input'),
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    style: context.text.body,
                    decoration: InputDecoration(
                      hintMaxLines: 1,
                      hintText: voice.listening
                          ? context.l10n.listening
                          : context.l10n.messageHint,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Pressable(
                    enabled: !busy,
                    child: IconButton(
                      key: const Key('dictate'),
                      tooltip: voice.listening
                          ? context.l10n.stopDictation
                          : context.l10n.dictate,
                      onPressed: busy
                          ? null
                          : () {
                              final n = ref.read(voiceProvider.notifier);
                              if (voice.listening) {
                                n.stop();
                                return;
                              }
                              final before = widget.controller.text;
                              n.listen(
                                onDeviceOnly: settings.voiceOnDeviceOnly,
                                onText: (t) {
                                  widget.controller.text = before.isEmpty
                                      ? t
                                      : '$before $t';
                                  widget.controller.selection =
                                      TextSelection.collapsed(
                                        offset: widget.controller.text.length,
                                      );
                                },
                              );
                            },
                      color: voice.listening ? c.danger : c.textMuted,
                      icon: BlurSwitcher(
                        child: Icon(
                          voice.listening ? Icons.mic : Icons.mic_none,
                          key: ValueKey(voice.listening),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDesign.sm),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (_, value, _) {
                    final hasText =
                        value.text.trim().isNotEmpty ||
                        widget.attachments.isNotEmpty;
                    return Padding(
                      // Sits on the input's baseline row even when it grows.
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SendButton(
                        busy: busy,
                        ready: hasText && widget.canSend,
                        onSend: widget.onSend,
                        onStop: widget.onStop,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The row under the message box, if any: reader actions for a pasted
  /// link, "research this as a goal", or matching /shortcuts.
  Widget? _suggestions(
    BuildContext context,
    TextEditingValue value,
    List<PromptShortcut> shortcuts,
    bool busy,
  ) {
    final c = context.colors;
    final settings = ref.read(settingsProvider);
    final matches = PromptShortcut.suggestions(value.text, shortcuts);
    // One shared or pasted link: reader actions.
    final link = ReaderActions.linkIn(value.text);
    if (!busy &&
        matches.isEmpty &&
        link != null &&
        widget.onQuickPrompt != null) {
      final t = context.l10n;
      final actions = [
        (t.readerSummarize, t.readerSummarizePrompt(link)),
        (t.readerKeyPoints, t.readerKeyPointsPrompt(link)),
        (t.readerExplain, t.readerExplainPrompt(link)),
      ];
      return Padding(
        key: const ValueKey('reader'),
        padding: const EdgeInsets.only(top: AppDesign.sm),
        child: SizedBox(
          height: 32,
          child: ListView(
            key: const Key('reader-actions'),
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            children: [
              for (final (i, (label, prompt)) in actions.indexed)
                _Cascade(
                  index: i,
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.article_outlined,
                      size: 14,
                      color: c.accent,
                    ),
                    label: Text(label),
                    labelStyle: context.text.mono.copyWith(color: c.text),
                    // Reading the page is a network request:
                    // only with web research on.
                    onPressed: settings.webSearchEnabled
                        ? () => widget.onQuickPrompt!(prompt)
                        : () => showIslandToast(
                            context,
                            t.readerNeedsWeb,
                            tone: IslandTone.warning,
                            icon: Icons.public_off,
                          ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (!busy &&
        matches.isEmpty &&
        widget.onResearchGoal != null &&
        GoalSpecialization.looksLikeGoal(value.text)) {
      return Padding(
        key: const ValueKey('goal'),
        padding: const EdgeInsets.only(top: AppDesign.sm),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            key: const Key('research-as-goal'),
            visualDensity: VisualDensity.compact,
            avatar: Icon(Icons.flag_outlined, size: 14, color: c.accent),
            label: Text(context.l10n.composerResearchGoal),
            labelStyle: context.text.mono.copyWith(color: c.accent),
            onPressed: () => widget.onResearchGoal!(value.text),
          ),
        ),
      );
    }
    if (busy || matches.isEmpty) return null;
    return Padding(
      key: const ValueKey('shortcuts'),
      padding: const EdgeInsets.only(top: AppDesign.sm),
      child: SizedBox(
        height: 32,
        child: ListView(
          key: const Key('shortcut-suggestions'),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          children: [
            for (final (i, s) in matches.indexed)
              _Cascade(
                index: i,
                child: Tooltip(
                  message: s.description,
                  child: ActionChip(
                    key: Key('shortcut-${s.name}'),
                    visualDensity: VisualDensity.compact,
                    label: Text('/${s.name}'),
                    labelStyle: context.text.mono.copyWith(color: c.accent),
                    onPressed: () {
                      widget.controller.value = TextEditingValue(
                        text: '/${s.name} ',
                        selection: TextSelection.collapsed(
                          offset: s.name.length + 2,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ActionChip(
              key: const Key('shortcut-manage'),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.tune, size: 14),
              label: Text(context.l10n.composerManageShortcuts),
              labelStyle: context.text.mono.copyWith(color: c.textMuted),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ShortcutsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget child;

  /// Gets the pill itself, for a sheet to grow out of.
  final ValueChanged<BuildContext>? onTap;
  final bool selected;
  const _Pill({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = context.motion;
    return Pressable(
      enabled: onTap != null,
      child: AnimatedContainer(
        duration: motion.fade(AppMotion.fadeIn),
        curve: AppMotion.ease,
        decoration: ShapeDecoration(
          color: selected ? c.accent.fade(0.12) : c.surfaceRaised,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? c.accent.fade(0.5) : c.hairline),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
              child: AnimatedOpacity(
                opacity: onTap == null ? 0.6 : 1,
                duration: motion.fade(AppMotion.fadeIn),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that opens by growing: its height springs open while the content
/// blurs in, and it closes the same way. A null child is the closed row.
class _Grows extends StatelessWidget {
  final Widget? child;
  const _Grows({this.child});

  @override
  Widget build(BuildContext context) => ClipRect(
    child: SpringSize(
      alignment: Alignment.topCenter,
      child: BlurSwitcher(
        alignment: Alignment.topCenter,
        child:
            child ??
            const SizedBox(key: ValueKey('closed'), width: double.infinity),
      ),
    ),
  );
}

/// A chip in a row of chips; the row cascades in from left to right.
class _Cascade extends StatelessWidget {
  final int index;
  final Widget child;
  const _Cascade({required this.index, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: AppDesign.xs),
    child: SpringEntrance(
      delay: SpringEntrance.cascade(index),
      from: const Offset(0, 8),
      child: child,
    ),
  );
}
