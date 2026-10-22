import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Squishes its child while a finger is down and springs it back on
/// release. It only listens: taps still reach the child's own handler.
class Pressable extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double pressedScale;
  const Pressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.94,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  Offset? _down;

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _press(PointerDownEvent event) {
    if (!widget.enabled) return;
    _down = event.position;
    final motion = context.motion;
    _scale.springTo(
      widget.pressedScale,
      motion.snappy,
      animate: motion.animates,
    );
  }

  void _release([PointerEvent? _]) {
    if (_down == null) return;
    _down = null;
    final motion = context.motion;
    _scale.springTo(1, motion.spring, animate: motion.animates);
  }

  void _move(PointerMoveEvent event) {
    // A drag is not a press: let go as soon as it turns into a scroll.
    final down = _down;
    if (down != null && (event.position - down).distance > kTouchSlop) {
      _release();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _press,
    onPointerMove: _move,
    onPointerUp: _release,
    onPointerCancel: _release,
    child: AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    ),
  );
}
