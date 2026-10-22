import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_design.dart';

import 'motion.dart';

/// A toggle whose knob squishes under the finger, stretches as it travels
/// and lands with the house bounce, while the track fills with the accent.
class SpringSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SpringSwitch({super.key, required this.value, this.onChanged});

  @override
  State<SpringSwitch> createState() => _SpringSwitchState();
}

class _SpringSwitchState extends State<SpringSwitch>
    with TickerProviderStateMixin {
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.value ? 1 : 0,
  );
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void didUpdateWidget(covariant SpringSwitch old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      final motion = context.motion;
      _position.springTo(
        widget.value ? 1 : 0,
        motion.spring,
        animate: motion.animates,
      );
    }
  }

  @override
  void dispose() {
    _position.dispose();
    _press.dispose();
    super.dispose();
  }

  void _pressTo(double v) {
    final motion = context.motion;
    _press.springTo(v, motion.snappy, animate: motion.animates);
  }

  void _toggle() {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    AppHaptics.tick();
    onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onChanged != null;
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? _toggle : null,
        onTapDown: enabled ? (_) => _pressTo(1) : null,
        onTapUp: enabled ? (_) => _pressTo(0) : null,
        onTapCancel: enabled ? () => _pressTo(0) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: AnimatedBuilder(
            animation: Listenable.merge([_position, _press]),
            builder: (context, _) => CustomPaint(
              size: const Size(52, 32),
              painter: _SwitchPainter(
                position: _position.value,
                speed: _position.velocity,
                press: _press.value,
                onTrack: c.accent,
                offTrack: c.surfaceRaised,
                outline: c.hairlineStrong,
                onKnob: c.onAccent,
                offKnob: c.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchPainter extends CustomPainter {
  final double position, speed, press;
  final Color onTrack, offTrack, outline, onKnob, offKnob;
  const _SwitchPainter({
    required this.position,
    required this.speed,
    required this.press,
    required this.onTrack,
    required this.offTrack,
    required this.outline,
    required this.onKnob,
    required this.offKnob,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = position.clamp(0.0, 1.0);
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(track, Paint()..color = Color.lerp(offTrack, onTrack, t)!);
    canvas.drawRRect(
      track.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Color.lerp(outline, onTrack, t)!,
    );
    const pad = 4.0, knob = 24.0;
    // Wider while pressed and while moving fast: the knob stretches along
    // its path and settles round.
    final stretch = math.min(9.0, press * 6 + speed.abs() * 1.4);
    final travel = size.width - 2 * pad - knob;
    final center = pad + knob / 2 + position * travel;
    final width = knob + stretch;
    final left = (center - width / 2).clamp(
      pad - 1,
      size.width - pad + 1 - width,
    );
    final squash = press * 2;
    final rect = Rect.fromLTWH(left, pad + squash / 2, width, knob - squash);
    final shape = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(knob / 2),
    );
    canvas.drawShadow(
      Path()..addRRect(shape),
      const Color(0xFF000000),
      2,
      false,
    );
    canvas.drawRRect(shape, Paint()..color = Color.lerp(offKnob, onKnob, t)!);
  }

  @override
  bool shouldRepaint(_SwitchPainter old) =>
      old.position != position ||
      old.speed != speed ||
      old.press != press ||
      old.onTrack != onTrack ||
      old.offTrack != offTrack;
}

/// A [SwitchListTile] drawn with [SpringSwitch]: same constructor and the
/// same type for code (and tests) that look the tile up, the row toggles
/// when tapped anywhere.
class SpringSwitchTile extends SwitchListTile {
  const SpringSwitchTile({
    super.key,
    required super.value,
    required super.onChanged,
    super.title,
    super.subtitle,
    super.secondary,
    super.dense,
    super.contentPadding,
    super.isThreeLine,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: secondary,
    title: title,
    subtitle: subtitle,
    dense: dense,
    isThreeLine: isThreeLine,
    contentPadding: contentPadding,
    enabled: onChanged != null,
    trailing: SpringSwitch(value: value, onChanged: onChanged),
    onTap: onChanged == null
        ? null
        : () {
            AppHaptics.tick();
            onChanged!(!value);
          },
  );
}

/// Lets a slider be pulled past its ends: it stretches toward the finger,
/// squashes a little, and springs back when released.
class RubberBand extends StatefulWidget {
  final Widget child;
  const RubberBand({super.key, required this.child});

  @override
  State<RubberBand> createState() => _RubberBandState();
}

class _RubberBandState extends State<RubberBand>
    with SingleTickerProviderStateMixin {
  /// Negative past the start, positive past the end, in 0…1 of resistance.
  late final AnimationController _pull = AnimationController.unbounded(
    vsync: this,
  );
  bool _down = false;

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  void _move(PointerMoveEvent e) {
    if (!_down || !context.motion.animates) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final x = box.globalToLocal(e.position).dx;
    final over = x < 0
        ? x
        : x > box.size.width
        ? x - box.size.width
        : 0.0;
    // Resistance grows with the distance, like a rubber band.
    _pull.value = over.sign * (1 - math.exp(-over.abs() / 90));
  }

  void _release([PointerEvent? _]) {
    _down = false;
    final motion = context.motion;
    _pull.springTo(0, motion.pop, animate: motion.animates);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _down = true,
    onPointerMove: _move,
    onPointerUp: _release,
    onPointerCancel: _release,
    child: AnimatedBuilder(
      animation: _pull,
      builder: (context, child) {
        final p = _pull.value;
        return Transform(
          alignment: p < 0 ? Alignment.centerRight : Alignment.centerLeft,
          transform: Matrix4.diagonal3Values(
            1 + 0.06 * p.abs(),
            1 - 0.12 * p.abs(),
            1,
          ),
          child: child,
        );
      },
      child: widget.child,
    ),
  );
}
