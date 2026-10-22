import 'dart:ui' show ImageFilter;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Swaps its child with the reference clips' crossfade: the old content
/// blurs and fades out while the new one comes in from a light blur and a
/// slightly smaller scale. Key the child by what it shows, so a new key
/// means new content. Only the incoming child sizes the switcher, so a
/// [SpringSize] around it heads straight for the new size.
class BlurSwitcher extends StatelessWidget {
  final Widget child;
  final AlignmentGeometry alignment;
  const BlurSwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    return AnimatedSwitcher(
      duration: motion.fade(AppMotion.fadeIn),
      reverseDuration: motion.fade(AppMotion.fadeOut),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => _CurrentSizedStack(
        alignment: alignment,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) =>
          BlurFade(animation: animation, blur: motion.blur, child: child),
      child: child,
    );
  }
}

/// Opacity, scale and blur from one animation value: 0 is gone (blurred,
/// transparent, 96 %), 1 is fully there.
class BlurFade extends AnimatedWidget {
  final bool blur;
  final Widget child;
  const BlurFade({
    super.key,
    required Animation<double> animation,
    required this.blur,
    required this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value.clamp(0.0, 1.0);
    final sigma = blur ? (1 - t) * AppMotion.blurSigma : 0.0;
    // The same structure every frame: the child's state must survive the
    // blur switching off at the end.
    return ImageFiltered(
      enabled: sigma > 0.05,
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: Transform.scale(
        scale: 0.96 + 0.04 * t,
        child: Opacity(opacity: t, child: child),
      ),
    );
  }
}

/// A stack sized by its last (incoming) child only; outgoing children keep
/// the constraints they had, so text does not re-wrap while it fades.
class _CurrentSizedStack extends MultiChildRenderObjectWidget {
  final AlignmentGeometry alignment;
  const _CurrentSizedStack({required this.alignment, super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCurrentSizedStack(
        alignment.resolve(Directionality.maybeOf(context)),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCurrentSizedStack renderObject,
  ) {
    renderObject.alignment = alignment.resolve(Directionality.maybeOf(context));
  }
}

class _StackSlot extends ContainerBoxParentData<RenderBox> {}

class _RenderCurrentSizedStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StackSlot>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StackSlot> {
  _RenderCurrentSizedStack(this._alignment);

  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StackSlot) child.parentData = _StackSlot();
  }

  @override
  void performLayout() {
    final current = lastChild;
    if (current == null) {
      size = constraints.smallest;
      return;
    }
    current.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(current.size);
    var child = firstChild;
    while (child != null) {
      if (child != current) child.layout(constraints, parentUsesSize: true);
      final slot = child.parentData! as _StackSlot;
      slot.offset = _alignment.alongOffset(size - child.size as Offset);
      child = slot.nextSibling;
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final current = lastChild;
    return current == null
        ? constraints.smallest
        : constraints.constrain(current.getDryLayout(constraints));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      lastChild?.getMinIntrinsicWidth(height) ?? 0;
  @override
  double computeMaxIntrinsicWidth(double height) =>
      lastChild?.getMaxIntrinsicWidth(height) ?? 0;
  @override
  double computeMinIntrinsicHeight(double width) =>
      lastChild?.getMinIntrinsicHeight(width) ?? 0;
  @override
  double computeMaxIntrinsicHeight(double width) =>
      lastChild?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final current = lastChild;
    if (current == null) return null;
    final offset = (current.parentData! as _StackSlot).offset;
    final distance = current.getDistanceToActualBaseline(baseline);
    return distance == null ? null : distance + offset.dy;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  // Only the incoming child takes taps; the outgoing one is on its way out.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final current = lastChild;
    if (current == null) return false;
    final slot = current.parentData! as _StackSlot;
    return result.addWithPaintOffset(
      offset: slot.offset,
      position: position,
      hitTest: (result, transformed) =>
          current.hitTest(result, position: transformed),
    );
  }
}
