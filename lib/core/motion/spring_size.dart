import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Like [AnimatedSize], on a spring: the box follows its child's size with
/// the house overshoot, so a pill growing into a card swells a little past
/// its size and settles. The child keeps its own size and is aligned inside;
/// clip around it to hide overflow while the box catches up.
class SpringSize extends StatefulWidget {
  final Widget child;
  final AlignmentGeometry alignment;

  /// Defaults to the motion level's spring.
  final SpringDescription? spring;
  const SpringSize({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.spring,
  });

  @override
  State<SpringSize> createState() => _SpringSizeState();
}

class _SpringSizeState extends State<SpringSize> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    return _SpringSizeBox(
      vsync: this,
      spring: widget.spring ?? motion.spring,
      animate: motion.animates,
      alignment: widget.alignment,
      textDirection: Directionality.maybeOf(context),
      child: widget.child,
    );
  }
}

class _SpringSizeBox extends SingleChildRenderObjectWidget {
  final TickerProvider vsync;
  final SpringDescription spring;
  final bool animate;
  final AlignmentGeometry alignment;
  final TextDirection? textDirection;
  const _SpringSizeBox({
    required this.vsync,
    required this.spring,
    required this.animate,
    required this.alignment,
    this.textDirection,
    super.child,
  });

  @override
  RenderSpringSize createRenderObject(BuildContext context) => RenderSpringSize(
    vsync: vsync,
    spring: spring,
    animate: animate,
    alignment: alignment,
    textDirection: textDirection,
  );

  @override
  void updateRenderObject(BuildContext context, RenderSpringSize renderObject) {
    renderObject
      ..vsync = vsync
      ..spring = spring
      ..animate = animate
      ..alignment = alignment
      ..textDirection = textDirection;
  }
}

/// The render box behind [SpringSize]: two unbounded controllers chase the
/// child's size, keeping their velocity when the target moves again.
class RenderSpringSize extends RenderAligningShiftedBox {
  RenderSpringSize({
    required TickerProvider vsync,
    required this.spring,
    required this.animate,
    super.alignment,
    super.textDirection,
  }) : _vsync = vsync {
    _width = AnimationController.unbounded(vsync: vsync)..addListener(_tick);
    _height = AnimationController.unbounded(vsync: vsync)..addListener(_tick);
  }

  late final AnimationController _width, _height;
  TickerProvider _vsync;
  SpringDescription spring;
  bool animate;
  Size? _target;
  bool _inLayout = false;

  set vsync(TickerProvider value) {
    if (value == _vsync) return;
    _vsync = value;
    _width.resync(value);
    _height.resync(value);
  }

  /// Whether the box is still moving toward its child's size.
  bool get isAnimating => _width.isAnimating || _height.isAnimating;

  void _tick() {
    if (!_inLayout) markNeedsLayout();
  }

  @override
  void performLayout() {
    _inLayout = true;
    try {
      final child = this.child;
      if (child == null) {
        size = constraints.smallest;
        _target = null;
        return;
      }
      child.layout(constraints.loosen(), parentUsesSize: true);
      final target = constraints.constrain(child.size);
      if (_target == null || !animate) {
        _width
          ..stop()
          ..value = target.width;
        _height
          ..stop()
          ..value = target.height;
      } else if (target != _target) {
        _width.springTo(target.width, spring);
        _height.springTo(target.height, spring);
      }
      _target = target;
      size = constraints.constrain(
        Size(math.max(0, _width.value), math.max(0, _height.value)),
      );
      alignChild();
    } finally {
      _inLayout = false;
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(child.getDryLayout(constraints.loosen()));
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }
}
