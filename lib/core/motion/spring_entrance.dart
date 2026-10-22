import 'dart:async';

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Plays once when it first appears: fades in, rises a few pixels and
/// settles on the house spring. [delay] staggers rows into a cascade.
/// Rebuilding it never replays; a new key does.
class SpringEntrance extends StatefulWidget {
  final Widget child;

  /// False shows the child at rest at once (content that was already there).
  final bool animate;
  final Duration delay;

  /// Where the child starts, relative to where it ends.
  final Offset from;
  final double fromScale;
  final Alignment scaleAlignment;
  const SpringEntrance({
    super.key,
    required this.child,
    this.animate = true,
    this.delay = Duration.zero,
    this.from = const Offset(0, 14),
    this.fromScale = 0.97,
    this.scaleAlignment = Alignment.center,
  });

  /// The delay of row [index] in a cascade, capped so long lists do not
  /// keep the last rows waiting.
  static Duration cascade(int index, {int stepMs = 35, int maxSteps = 8}) =>
      Duration(milliseconds: stepMs * (index < maxSteps ? index : maxSteps));

  @override
  State<SpringEntrance> createState() => _SpringEntranceState();
}

class _SpringEntranceState extends State<SpringEntrance>
    with SingleTickerProviderStateMixin {
  /// Decided once: rebuilding with a different [SpringEntrance.animate]
  /// must not cut an entrance short or restart one.
  late final bool _animates = widget.animate;
  late final AnimationController _t = AnimationController.unbounded(
    vsync: this,
    value: _animates ? 0 : 1,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !_animates) return;
    _started = true;
    final motion = context.motion;
    if (!motion.animates) {
      _t.value = 1;
      return;
    }
    unawaited(
      _t
          .animateWith(
            DelayedSimulation(
              widget.delay.inMicroseconds / Duration.microsecondsPerSecond,
              SpringSimulation(motion.spring, 0, 1, 0),
            ),
          )
          .then((_) => _t.value = 1),
    );
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animates) return widget.child;
    // One structure from start to rest (identity transforms cost nothing),
    // so the child keeps its state when the entrance ends.
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final t = _t.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: widget.from * (1 - t),
            child: Transform.scale(
              scale: widget.fromScale + (1 - widget.fromScale) * t,
              alignment: widget.scaleAlignment,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
