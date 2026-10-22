import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/motion/motion.dart';
import '../../domain/entities/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/turn_phase.dart';

/// The composer's round button, one surface through the whole turn: an
/// arrow when there is something to send, a ring while the model gets ready
/// and reads the prompt (filling as it reads), a stop square while it
/// writes, a check that pops when the answer is complete, then the arrow.
class SendButton extends ConsumerStatefulWidget {
  final bool busy;

  /// Something to send and a model able to take it.
  final bool ready;
  final VoidCallback? onSend, onStop;
  const SendButton({
    super.key,
    required this.busy,
    required this.ready,
    this.onSend,
    this.onStop,
  });

  @override
  ConsumerState<SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends ConsumerState<SendButton>
    with TickerProviderStateMixin {
  late final AnimationController _pop = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: AppMotion.ambient,
  );

  /// How long the check stays before the arrow comes back.
  late final AnimationController _doneHold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addStatusListener(_holdEnded);
  bool _done = false;

  @override
  void dispose() {
    _pop.dispose();
    _spin.dispose();
    _doneHold.dispose();
    super.dispose();
  }

  void _holdEnded(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _done = false);
    }
  }

  void _turnEnded() {
    final state = ref.read(chatProvider);
    final last = state.messages.lastOrNull;
    final complete =
        state.error == null &&
        last != null &&
        last.role == ChatRole.assistant &&
        last.responseStatus == 'complete';
    if (!complete || !mounted) return;
    setState(() => _done = true);
    final motion = context.motion;
    if (motion.animates) {
      _pop.animateWith(SpringSimulation(motion.pop, 1, 1, 4));
    }
    _doneHold.forward(from: 0);
    AppHaptics.success();
  }

  void _send() {
    AppHaptics.press();
    widget.onSend?.call();
  }

  void _stop() {
    AppHaptics.press();
    widget.onStop?.call();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider.select((s) => s.isGenerating), (was, now) {
      if (was == true && !now) _turnEnded();
      if (now && _done) {
        _doneHold.stop();
        setState(() => _done = false);
      }
    });
    final c = context.colors;
    final motion = context.motion;
    final activity = ref.watch(turnPhaseProvider);
    final busy = widget.busy;
    final ring =
        busy &&
        (activity.phase == TurnPhase.preparing ||
            activity.phase == TurnPhase.reading);
    final measured = activity.phase == TurnPhase.reading;
    // The spinner runs only while there is nothing to measure yet.
    if (ring && !measured) {
      _spin.loopAmbient(animate: motion.animates);
    } else if (_spin.isAnimating) {
      _spin.stop();
    }
    final live = busy || widget.ready || _done;
    final icon = _done
        ? Icons.check_rounded
        : busy
        ? Icons.stop_rounded
        : Icons.arrow_upward_rounded;
    return Pressable(
      enabled: busy || widget.ready,
      child: AnimatedBuilder(
        animation: _pop,
        builder: (context, child) =>
            Transform.scale(scale: _pop.value, child: child),
        child: AnimatedContainer(
          duration: motion.fade(AppMotion.fadeIn),
          curve: AppMotion.ease,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: live ? c.accent : c.surfaceRaised,
            border: Border.all(color: live ? c.accent : c.hairlineStrong),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: ring ? 1 : 0,
                    // Gone quickly when the answer lands, so the check
                    // pops on a clean disk.
                    duration: motion.fade(
                      ring ? AppMotion.fadeIn : AppMotion.fadeOut,
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: activity.progress ?? 0),
                      duration: motion.fade(AppMotion.track),
                      curve: AppMotion.ease,
                      builder: (context, progress, _) => AnimatedBuilder(
                        animation: _spin,
                        builder: (context, _) => CustomPaint(
                          painter: _RingPainter(
                            progress: measured ? progress : null,
                            // Two turns per breath.
                            turn: (_spin.value * 2) % 1,
                            color: c.onAccent.fade(0.8),
                            track: c.onAccent.fade(0.16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('send-stop'),
                tooltip: busy ? context.l10n.stop : context.l10n.send,
                onPressed: busy
                    ? (widget.onStop == null ? null : _stop)
                    : widget.ready && widget.onSend != null
                    ? _send
                    : null,
                color: live ? c.onAccent : c.textMuted,
                disabledColor: _done ? c.onAccent : c.textFaint,
                icon: BlurSwitcher(
                  child: Icon(
                    icon,
                    key: ValueKey((icon, ring)),
                    // Smaller inside the ring, so the ring stays readable.
                    size: ring ? 16 : 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ring inside the button: a spinning arc while nothing can be
/// measured, then an arc filling with the share of the prompt read.
class _RingPainter extends CustomPainter {
  final double? progress;
  final double turn;
  final Color color, track;
  const _RingPainter({
    required this.progress,
    required this.turn,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(5);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final progress = this.progress;
    if (progress == null) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + turn * 2 * math.pi,
        2 * math.pi * 0.28,
        false,
        stroke..color = color,
      );
      return;
    }
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.02, 1.0),
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.turn != turn ||
      old.color != color ||
      old.track != track;
}
