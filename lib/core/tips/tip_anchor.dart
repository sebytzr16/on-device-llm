import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_design.dart';
import '../l10n/l10n.dart';
import '../motion/spring_entrance.dart';
import 'tips_store.dart';

/// Which side of its target a tip opens on.
enum TipSide { below, above }

/// A one-time tip (owner 2026-11-16): a small speech bubble whose tail
/// points at [child], shown until the user taps "Got it", uses the control
/// it points at, or turns tips off. Only one tip is on screen at a time
/// ([TipsNotifier.claim]); a dialog or a pushed page covers it, and a
/// target that is not painted (another tab) hides it.
class TipAnchor extends ConsumerStatefulWidget {
  const TipAnchor({
    super.key,
    required this.id,
    required this.title,
    required this.body,
    required this.child,
    this.side = TipSide.below,
    this.active = true,
    this.actionLabel,
    this.onAction,
    this.dismissLabel,
    this.step,
    this.onSkipAll,
    this.onDismissed,
    this.dismissOnTargetTap = true,
  });

  final String id;
  final String title;
  final String body;
  final Widget child;
  final TipSide side;

  /// False keeps the tip waiting (a model is loading, the page is hidden).
  final bool active;

  /// A button that does the thing the tip suggests; it also dismisses.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Replaces "Got it" (an offer reads better with "Later").
  final String? dismissLabel;

  /// "2 of 5" in a tour.
  final (int, int)? step;
  final VoidCallback? onSkipAll;
  final VoidCallback? onDismissed;

  /// Using the control the tip points at counts as "Got it".
  final bool dismissOnTargetTap;

  @override
  ConsumerState<TipAnchor> createState() => _TipAnchorState();
}

class _TipAnchorState extends ConsumerState<TipAnchor> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _target = GlobalKey();
  bool _claimPending = false;
  // Kept so dispose never touches ref (Riverpod forbids it once unmounting).
  late final TipsNotifier _notifier = ref.read(tipsProvider.notifier);
  bool _holdsSlot = false;

  bool get _mine => ref.read(tipsProvider).showing == widget.id;

  @override
  void initState() {
    super.initState();
    _notifier;
  }

  void _sync() {
    if (!mounted) return;
    final tips = ref.read(tipsProvider);
    final mine = tips.showing == widget.id;
    _holdsSlot = mine;
    if (widget.active && !mine && tips.shouldShow(widget.id)) {
      if (_claimPending) return;
      _claimPending = true;
      // After the frame: claiming changes provider state, which must not
      // happen while widgets build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _claimPending = false;
        if (!mounted || !widget.active) return;
        ref.read(tipsProvider.notifier).claim(widget.id);
      });
      return;
    }
    if (mine && !widget.active) {
      // Waiting (a reply is streaming, a load started): give the slot back
      // so it is claimed again in order, and so other tips are not blocked.
      final notifier = ref.read(tipsProvider.notifier);
      scheduleMicrotask(() => notifier.release(widget.id));
      if (_portal.isShowing) _portal.hide();
      return;
    }
    final show = mine && widget.active && tips.enabled;
    if (show && !_portal.isShowing) _portal.show();
    if (!show && _portal.isShowing) _portal.hide();
  }

  void _dismiss() {
    if (!_mine) return;
    unawaited(ref.read(tipsProvider.notifier).dismiss(widget.id));
    widget.onDismissed?.call();
  }

  @override
  void didUpdateWidget(TipAnchor old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.id != widget.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void dispose() {
    // Leaving the page gives the slot back without marking the tip seen.
    if (_holdsSlot) {
      final notifier = _notifier;
      final id = widget.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          notifier.release(id);
        } catch (_) {
          // The whole scope went away with the page; nothing to give back.
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tipsProvider, (_, _) => _sync());
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    Widget target = CompositedTransformTarget(
      link: _link,
      child: KeyedSubtree(key: _target, child: widget.child),
    );
    if (widget.dismissOnTargetTap) {
      target = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => _dismiss(),
        child: target,
      );
    }
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: target,
    );
  }

  Widget _overlay(BuildContext context) {
    final box = _target.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlay == null || !overlay.hasSize) {
      return const SizedBox.shrink();
    }
    const margin = 12.0;
    final ow = overlay.size.width;
    final width = math.min(300.0, ow - margin * 2);
    final centre = box
        .localToGlobal(box.size.center(Offset.zero), ancestor: overlay)
        .dx;
    // Keep the bubble on screen; the tail still points at the target.
    final left = (centre - width / 2).clamp(margin, ow - width - margin);
    final shift = left - (centre - width / 2);
    final below = widget.side == TipSide.below;
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: below ? Alignment.bottomCenter : Alignment.topCenter,
        followerAnchor: below ? Alignment.topCenter : Alignment.bottomCenter,
        offset: Offset(shift, below ? 6 : -6),
        child: SpringEntrance(
          from: Offset(0, below ? -8 : 8),
          fromScale: 0.9,
          scaleAlignment: Alignment(
            (-shift / (width / 2)).clamp(-1.0, 1.0),
            below ? -1 : 1,
          ),
          child: SizedBox(
            width: width,
            child: TipBubble(
              title: widget.title,
              body: widget.body,
              tailOffset: -shift,
              tailUp: below,
              step: widget.step,
              actionLabel: widget.actionLabel,
              dismissLabel: widget.dismissLabel,
              onAction: widget.onAction == null
                  ? null
                  : () {
                      _dismiss();
                      widget.onAction!();
                    },
              onGotIt: _dismiss,
              onSkipAll: widget.onSkipAll == null
                  ? null
                  : () {
                      _dismiss();
                      widget.onSkipAll!();
                    },
            ),
          ),
        ),
      ),
    );
  }
}

/// The bubble itself: raised surface, accent edge, a tail toward the
/// control it explains. Public for golden-free widget tests and previews.
class TipBubble extends StatelessWidget {
  const TipBubble({
    super.key,
    required this.title,
    required this.body,
    required this.onGotIt,
    this.tailOffset = 0,
    this.tailUp = true,
    this.step,
    this.actionLabel,
    this.onAction,
    this.dismissLabel,
    this.onSkipAll,
  });

  final String title;
  final String body;
  final VoidCallback onGotIt;

  /// Tail position from the bubble's centre, in pixels.
  final double tailOffset;
  final bool tailUp;
  final (int, int)? step;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? dismissLabel;
  final VoidCallback? onSkipAll;

  static const _tail = 7.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    final edge = c.accent.withValues(alpha: 0.55);
    final step = this.step;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: c.surfaceOverlay,
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: edge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: c.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: context.text.title.copyWith(fontSize: 14),
                  ),
                ),
                if (step != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      t.tipStep(step.$1, step.$2),
                      style: context.text.caption.copyWith(color: c.textFaint),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 23, right: 6),
            child: Text(body, style: context.text.small),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (onSkipAll != null)
                TextButton(
                  key: const Key('tip-skip-all'),
                  style: TextButton.styleFrom(
                    foregroundColor: c.textFaint,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onSkipAll,
                  child: Text(t.tipSkipAll),
                ),
              const Spacer(),
              TextButton(
                key: const Key('tip-got-it'),
                style: TextButton.styleFrom(
                  foregroundColor: actionLabel == null ? c.accent : c.textMuted,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onGotIt,
                child: Text(dismissLabel ?? t.tipGotIt),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: 2),
                FilledButton(
                  key: const Key('tip-action'),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: title,
      child: CustomPaint(
        foregroundPainter: _TailPainter(
          fill: c.surfaceOverlay,
          edge: edge,
          offset: tailOffset,
          up: tailUp,
          size: _tail,
        ),
        child: card,
      ),
    );
  }
}

/// The small triangle joining the bubble to its target, drawn over the
/// bubble's border so the two read as one shape.
class _TailPainter extends CustomPainter {
  _TailPainter({
    required this.fill,
    required this.edge,
    required this.offset,
    required this.up,
    required this.size,
  });

  final Color fill, edge;
  final double offset;
  final bool up;
  final double size;

  @override
  void paint(Canvas canvas, Size s) {
    final inset = AppDesign.rMd + size;
    final x = (s.width / 2 + offset).clamp(inset, s.width - inset);
    final base = up ? 0.0 : s.height;
    final apex = up ? -size : s.height + size;
    // The fill starts 1.5 px inside the card to cover its border there.
    final into = up ? 1.5 : -1.5;
    final body = Path()
      ..moveTo(x - size - 1, base + into)
      ..lineTo(x, apex)
      ..lineTo(x + size + 1, base + into)
      ..close();
    canvas.drawPath(body, Paint()..color = fill);
    final sides = Path()
      ..moveTo(x - size - 0.5, base)
      ..lineTo(x, apex)
      ..lineTo(x + size + 0.5, base);
    canvas.drawPath(
      sides,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.fill != fill ||
      old.edge != edge ||
      old.offset != offset ||
      old.up != up;
}
