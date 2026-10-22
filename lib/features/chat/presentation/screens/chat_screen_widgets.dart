part of 'chat_screen.dart';

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: context.colors.textMuted),
      const SizedBox(width: AppDesign.md),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

/// The answer being written. The only part of the chat that follows the
/// stream frame by frame.
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

class _LoadingModelRow extends StatelessWidget {
  const _LoadingModelRow();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppDesign.lg,
      vertical: AppDesign.lg,
    ),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppDesign.md),
        Expanded(
          child: Text(
            context.l10n.loadingModel,
            style: context.text.mono.copyWith(color: context.colors.textMuted),
          ),
        ),
      ],
    ),
  );
}

/// Danger-tinted card; the text is selectable so it can be copied into a
/// bug report. Dismiss only hides it: the notifier clears it on next send.
class _ErrorBanner extends StatefulWidget {
  final String error;
  const _ErrorBanner(this.error, {super.key});
  @override
  State<_ErrorBanner> createState() => _ErrorBannerState();
}

class _ErrorBannerState extends State<_ErrorBanner> {
  String? _dismissed;

  @override
  Widget build(BuildContext context) {
    if (_dismissed == widget.error) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppDesign.lg,
        AppDesign.sm,
        AppDesign.lg,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppDesign.md,
        AppDesign.sm,
        AppDesign.xs,
        AppDesign.sm,
      ),
      decoration: BoxDecoration(
        color: c.danger.fade(0.10),
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: c.danger.fade(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline, size: 16, color: c.danger),
          ),
          const SizedBox(width: AppDesign.sm),
          Expanded(
            child: SelectableText(
              widget.error,
              style: context.text.small.copyWith(color: c.text),
            ),
          ),
          IconButton(
            tooltip: context.l10n.dismiss,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _dismissed = widget.error),
          ),
        ],
      ),
    );
  }
}

/// Overrides for the open chat: inherits from the model profile and preset
/// (everything below the chat layer of the cascade).
class _ChatOverridesPage extends ConsumerWidget {
  const _ChatOverridesPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides = ref.watch(chatOverridesProvider);
    final inherited = resolveSettings(
      global: ref.watch(settingsProvider),
      defaults: ref.read(settingsProvider.notifier).defaults,
      profiles: ref.watch(modelProfilesProvider),
      preset: ref.watch(presetsProvider).active,
      chat: const {},
      recommendations: ref.watch(modelRecommendationsProvider),
      model: ref.watch(modelManagerProvider).loadedModel,
    ).effective;
    return OverridesPage(
      title: context.l10n.chatSettingsMenu,
      scopeLabel: context.l10n.thisChatSection,
      overrides: overrides,
      inherited: inherited,
      onChanged: (o) => ref.read(chatProvider.notifier).setChatOverrides(o),
    );
  }
}

/// A strip above the composer (notice, memory, error, metrics) that opens by
/// growing while its content blurs in, and closes the same way. A null
/// child is closed.
class _GrowIn extends StatelessWidget {
  final Widget? child;
  const _GrowIn({this.child});

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

/// The round button over the bottom of the conversation once the reader
/// has scrolled up; it pops in and out on the house spring.
class _JumpToLatest extends StatefulWidget {
  final bool visible;
  final VoidCallback onTap;
  const _JumpToLatest({required this.visible, required this.onTap});

  @override
  State<_JumpToLatest> createState() => _JumpToLatestState();
}

class _JumpToLatestState extends State<_JumpToLatest>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController.unbounded(
    vsync: this,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _JumpToLatest old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) {
      final motion = context.motion;
      _shown.springTo(
        widget.visible ? 1 : 0,
        widget.visible ? motion.pop : motion.snappy,
        animate: motion.animates,
      );
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedBuilder(
        animation: _shown,
        builder: (context, child) {
          final t = _shown.value;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.5 + 0.5 * t, child: child),
          );
        },
        child: Pressable(
          child: Tooltip(
            message: context.l10n.jumpToLatest,
            child: Material(
              key: const Key('jump-to-latest'),
              color: c.surfaceOverlay,
              elevation: 3,
              shadowColor: Colors.black,
              shape: CircleBorder(side: BorderSide(color: c.hairlineStrong)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                child: SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 20,
                    color: c.text,
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

/// The turn notice as a pop-up over the bottom of the chat (tester,
/// 2026-10-19): it slides up, stays three seconds, then slides away. It
/// shows two lines; a tap opens the whole notice. A warning also stays
/// under its answer as a triangle.
class _NoticeToast extends StatefulWidget {
  final String? notice;

  /// Changes with each turn, so the same text from a new turn pops again.
  final Object id;
  final bool warning;
  const _NoticeToast({
    required this.notice,
    required this.id,
    this.warning = false,
  });

  static const shown = Duration(seconds: 3);

  @override
  State<_NoticeToast> createState() => _NoticeToastState();
}

class _NoticeToastState extends State<_NoticeToast> {
  bool _up = false;
  String _text = '';
  bool _warning = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.notice != null) _show();
  }

  @override
  void didUpdateWidget(covariant _NoticeToast old) {
    super.didUpdateWidget(old);
    if (widget.id == old.id) return;
    if (widget.notice != null) {
      _show();
    } else {
      _hide();
    }
  }

  void _show() {
    _text = widget.notice!;
    _warning = widget.warning;
    _up = true;
    _timer?.cancel();
    _timer = Timer(_NoticeToast.shown, _hide);
  }

  void _hide() {
    _timer?.cancel();
    if (mounted && _up) setState(() => _up = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = context.motion;
    final tone = _warning ? c.warning : c.textFaint;
    return IgnorePointer(
      ignoring: !_up,
      child: AnimatedSlide(
        offset: _up ? Offset.zero : const Offset(0, 1.3),
        duration: motion.fade(AppMotion.glide),
        curve: _up
            ? SpringCurve(
                motion.spring,
                seconds: AppMotion.glide.inMilliseconds / 1000,
              )
            : Curves.easeInCubic,
        child: AnimatedOpacity(
          opacity: _up ? 1 : 0,
          duration: motion.fade(AppMotion.fadeIn),
          child: Material(
            color: c.surfaceRaised,
            elevation: 6,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(
              borderRadius: AppDesign.radius(AppDesign.rMd),
              side: BorderSide(color: _warning ? tone.fade(0.45) : c.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('turn-notice'),
              onTap: () {
                _hide();
                unawaited(showNoticeSheet(context, _text, warning: _warning));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesign.md,
                  vertical: AppDesign.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      _warning
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 16,
                      color: tone,
                    ),
                    const SizedBox(width: AppDesign.sm),
                    Expanded(
                      child: Text(
                        _text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.mono.copyWith(color: c.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
