import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import '../design/app_design.dart';
import 'motion.dart';

/// A spring as a [Curve], for duration-based animations such as routes: it
/// runs the spring for [seconds] and lands exactly on 1.
class SpringCurve extends Curve {
  final SpringDescription spring;
  final double seconds;
  const SpringCurve(this.spring, {this.seconds = 0.6});

  @override
  double transformInternal(double t) =>
      SpringSimulation(spring, 0, 1, 0).x(t * seconds);
}

/// Pages slide in on a calm spring while the page below sinks back a little
/// and dims: depth, without the rebound that suits small controls.
class SpringPageTransitionsBuilder extends PageTransitionsBuilder {
  const SpringPageTransitionsBuilder();

  /// Nearly critically damped: a full page never swings past its place.
  static final SpringDescription page = AppMotion.spring(
    dampingRatio: 0.86,
    response: 0.42,
  );

  @override
  Duration get transitionDuration => const Duration(milliseconds: 560);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _SpringPage(
    animation: animation,
    secondary: secondaryAnimation,
    child: child,
  );
}

class _SpringPage extends StatefulWidget {
  final Animation<double> animation, secondary;
  final Widget child;
  const _SpringPage({
    required this.animation,
    required this.secondary,
    required this.child,
  });

  @override
  State<_SpringPage> createState() => _SpringPageState();
}

class _SpringPageState extends State<_SpringPage> {
  late CurvedAnimation _enter, _below;

  void _curve() {
    _enter = CurvedAnimation(
      parent: widget.animation,
      curve: SpringCurve(SpringPageTransitionsBuilder.page),
      reverseCurve: Curves.easeInCubic,
    );
    _below = CurvedAnimation(
      parent: widget.secondary,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _curve();
  }

  @override
  void didUpdateWidget(covariant _SpringPage old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation ||
        old.secondary != widget.secondary) {
      _enter.dispose();
      _below.dispose();
      _curve();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _below.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (!context.motion.animates) return child;
    final enter = _enter, below = _below;
    return AnimatedBuilder(
      animation: Listenable.merge([enter, below]),
      builder: (context, child) {
        final t = enter.value, s = below.value;
        final width = MediaQuery.sizeOf(context).width;
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset((1 - t) * width, 0),
              child: Transform.scale(
                // Sinks back while the next page covers it.
                scale: 1 - 0.06 * s,
                child: DecoratedBox(
                  // A soft edge shadow while the page slides over another.
                  decoration: BoxDecoration(
                    boxShadow: t < 1
                        ? [
                            BoxShadow(
                              color: Colors.black.fade(0.45 * (1 - t)),
                              blurRadius: 24,
                            ),
                          ]
                        : const [],
                  ),
                  child: child,
                ),
              ),
            ),
            if (s > 0)
              IgnorePointer(
                child: ColoredBox(color: Colors.black.fade(0.4 * s)),
              ),
          ],
        );
      },
      child: child,
    );
  }
}

/// Opens a sheet that grows out of [from] (the pill or button tapped) and
/// shrinks back into it when it closes. Without [from] it rises from the
/// bottom on the same spring. The sheet sizes to its content, up to most
/// of the screen; content with its own scrolling (a
/// [DraggableScrollableSheet]) keeps working.
///
/// Takes the [showModalBottomSheet] options the app uses: like there, a
/// sheet that is not [isScrollControlled] is at most 9/16 of the screen;
/// the surface always keeps clear of the status bar and shows a handle.
Future<T?> showMorphSheet<T>({
  required BuildContext context,
  BuildContext? from,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = true,
  bool showDragHandle = true,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  AppHaptics.tick();
  Rect? source;
  final box = from?.findRenderObject();
  if (box is RenderBox && box.hasSize && box.attached) {
    source = box.localToGlobal(Offset.zero) & box.size;
  }
  return Navigator.of(context).push<T>(
    _MorphSheetRoute<T>(
      source: source,
      builder: builder,
      tall: isScrollControlled,
      dismissible: isDismissible,
      draggable: enableDrag,
      motion: context.motion,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _MorphSheetRoute<T> extends PopupRoute<T> {
  final Rect? source;
  final WidgetBuilder builder;
  final bool tall, dismissible, draggable;
  final Motion motion;
  @override
  final String? barrierLabel;
  _MorphSheetRoute({
    required this.source,
    required this.builder,
    required this.tall,
    required this.dismissible,
    required this.draggable,
    required this.motion,
    required this.barrierLabel,
  });

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Duration get transitionDuration => motion.fade(AppMotion.glide);

  @override
  Duration get reverseTransitionDuration => motion.fade(AppMotion.fadeOut);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Material(
    type: MaterialType.transparency,
    child: MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: Builder(builder: builder),
    ),
  );

  CurvedAnimation? _curved;

  @override
  void dispose() {
    _curved?.dispose();
    super.dispose();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final motion = context.motion;
    final c = context.colors;
    final media = MediaQuery.of(context);
    return _MorphSheetFrame(
      animation: motion.animates
          ? _curved ??= CurvedAnimation(
              parent: animation,
              curve: SpringCurve(motion.spring),
              reverseCurve: Curves.easeInCubic,
            )
          : const AlwaysStoppedAnimation(1),
      source: source,
      color: c.surfaceRaised,
      border: c.hairline,
      handle: c.hairlineStrong,
      topInset: media.viewPadding.top + AppDesign.sm,
      // AppSheet animates its keyboard padding, so the inset is applied once.
      bottomInset: 0,
      maxFactor: tall ? 1 : 9 / 16,
      draggable: draggable && dismissible,
      onDismiss: () => Navigator.of(context).maybePop(),
      child: child,
    );
  }
}

/// Draws the sheet surface at the rect between the source and the sheet's
/// place (the spring can overshoot a little), clips the content to it and
/// fades the content in; drags on the surface pull it down to dismiss.
class _MorphSheetFrame extends StatefulWidget {
  final Animation<double> animation;
  final Rect? source;
  final Color color, border, handle;
  final double topInset, bottomInset, maxFactor;
  final bool draggable;
  final VoidCallback onDismiss;
  final Widget child;
  const _MorphSheetFrame({
    required this.maxFactor,
    required this.draggable,
    required this.animation,
    required this.source,
    required this.color,
    required this.border,
    required this.handle,
    required this.topInset,
    required this.bottomInset,
    required this.onDismiss,
    required this.child,
  });

  @override
  State<_MorphSheetFrame> createState() => _MorphSheetFrameState();
}

class _MorphSheetFrameState extends State<_MorphSheetFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _dragged(DragUpdateDetails d) =>
      _drag.value = math.max(0, _drag.value + d.delta.dy);

  void _released(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    if (_drag.value > 120 || v > 700) {
      widget.onDismiss();
      return;
    }
    _drag.springTo(0, context.motion.spring, animate: context.motion.animates);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.animation, _drag]),
    builder: (context, child) => _MorphSheetLayout(
      t: widget.animation.value,
      drag: _drag.value,
      source: widget.source,
      color: widget.color,
      border: widget.border,
      topInset: widget.topInset,
      bottomInset: widget.bottomInset,
      maxFactor: widget.maxFactor,
      child: child!,
    ),
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: widget.draggable ? _dragged : null,
      onVerticalDragEnd: widget.draggable ? _released : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: widget.handle,
                borderRadius: AppDesign.radius(2),
              ),
            ),
          ),
          Flexible(child: widget.child),
        ],
      ),
    ),
  );
}

class _MorphSheetLayout extends SingleChildRenderObjectWidget {
  final double t, drag, topInset, bottomInset, maxFactor;
  final Rect? source;
  final Color color, border;
  const _MorphSheetLayout({
    required this.t,
    required this.drag,
    required this.source,
    required this.color,
    required this.border,
    required this.topInset,
    required this.bottomInset,
    required this.maxFactor,
    required super.child,
  });

  @override
  _RenderMorphSheet createRenderObject(BuildContext context) =>
      _RenderMorphSheet()..update(this);

  @override
  void updateRenderObject(BuildContext context, _RenderMorphSheet r) =>
      r.update(this);
}

class _RenderMorphSheet extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  double _t = 0, _drag = 0, _topInset = 0, _bottomInset = 0, _maxFactor = 1;
  Rect? _source;
  Color _color = const Color(0xFF000000), _border = const Color(0xFF000000);

  /// Where the sheet rests (content laid out at its final size).
  Rect _rest = Rect.zero;
  static const _radius = 26.0;

  void update(_MorphSheetLayout w) {
    final relayout =
        w.topInset != _topInset ||
        w.bottomInset != _bottomInset ||
        w.drag != _drag ||
        w.maxFactor != _maxFactor;
    _maxFactor = w.maxFactor;
    _t = w.t;
    _drag = w.drag;
    _source = w.source;
    _color = w.color;
    _border = w.border;
    _topInset = w.topInset;
    _bottomInset = w.bottomInset;
    relayout ? markNeedsLayout() : markNeedsPaint();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;
    child.layout(
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: math.max(
          0,
          math.min(
            size.height - _topInset - _bottomInset,
            size.height * _maxFactor,
          ),
        ),
      ),
      parentUsesSize: true,
    );
    _rest = Rect.fromLTWH(
      0,
      size.height - _bottomInset - child.size.height + _drag,
      size.width,
      child.size.height,
    );
  }

  /// The surface right now: from the source (or just below the screen) to
  /// the resting place; past it a little while the spring overshoots.
  Rect get _current {
    final from =
        _source ?? _rest.translate(0, _rest.height + _bottomInset + 24);
    final r = Rect.lerp(from, _rest, _t)!;
    // Overshoot grows the sheet upward; the bottom stays on the edge.
    return _t > 1 ? Rect.fromLTRB(r.left, r.top, r.right, _rest.bottom) : r;
  }

  double get _cornerRadius {
    final start = _source == null ? _radius : _source!.shortestSide / 2;
    return start + (_radius - start) * _t.clamp(0.0, 1.0);
  }

  RRect _shape(Rect r) {
    final radius = Radius.circular(math.min(_cornerRadius, r.shortestSide / 2));
    // Rounded top, square bottom once it sits on the edge.
    final bottom = Radius.circular(
      math.min(_cornerRadius, r.shortestSide / 2) * (1 - _t.clamp(0.0, 1.0)),
    );
    return RRect.fromRectAndCorners(
      r,
      topLeft: radius,
      topRight: radius,
      bottomLeft: bottom,
      bottomRight: bottom,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _t <= 0) return;
    final rect = _current.shift(offset);
    final shape = _shape(rect);
    final canvas = context.canvas;
    canvas.drawShadow(
      Path()..addRRect(shape),
      const Color(0xFF000000),
      12,
      false,
    );
    canvas.drawRRect(shape, Paint()..color = _color);
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _border,
    );
    // The content stays where it rests and is uncovered as the surface
    // grows; it fades in once the surface is past halfway.
    final alpha = ((_t - 0.35) / 0.45).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    context.pushClipRRect(
      needsCompositing,
      offset,
      shape.shift(-offset).outerRect,
      shape.shift(-offset),
      (context, offset) {
        context.pushOpacity(offset, (alpha * 255).round(), (context, offset) {
          context.paintChild(child, offset + _rest.topLeft);
        });
      },
    );
  }

  @override
  bool hitTestSelf(Offset position) => _current.contains(position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null || !_current.contains(position)) return false;
    return result.addWithPaintOffset(
      offset: _rest.topLeft,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(_rest.left, _rest.top, 0, 1);
}
