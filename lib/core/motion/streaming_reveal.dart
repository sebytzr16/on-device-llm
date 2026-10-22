import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Streaming text that fades in instead of popping in: a soft edge trails
/// the end of the text by a few characters and glides after it on a
/// spring, so the bursts a model writes in read as one smooth motion.
///
/// It finds the last line of text inside [child] after layout and paints
/// the edge over it in [background], so it works with any rich text
/// (markdown included) as long as the text sits on that colour.
class StreamingReveal extends StatefulWidget {
  final Widget child;
  final bool active;

  /// Changes whenever the text grows; its length will do.
  final Object? revision;

  /// The colour behind the text, which the soft edge is painted in.
  final Color background;
  const StreamingReveal({
    super.key,
    required this.child,
    required this.active,
    required this.revision,
    required this.background,
  });

  @override
  State<StreamingReveal> createState() => _StreamingRevealState();
}

class _StreamingRevealState extends State<StreamingReveal>
    with SingleTickerProviderStateMixin {
  final _content = GlobalKey();
  final _edge = _RevealEdge();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  @override
  void didUpdateWidget(covariant StreamingReveal old) {
    super.didUpdateWidget(old);
    if (widget.active && widget.revision != old.revision) _wake();
  }

  void _wake() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 120
        : (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    final moving = _edge.step(dt.clamp(0.0, 0.05));
    _edge.changed();
    if (!moving) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _edge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.active && context.motion.animates;
    return Stack(
      children: [
        KeyedSubtree(key: _content, child: widget.child),
        if (on)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RevealPainter(
                    edge: _edge,
                    content: _content,
                    background: widget.background,
                    revision: widget.revision,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Where the revealed edge is on the line being written, and on the line
/// before it while the rest of that line sweeps in after the text wrapped.
class _RevealEdge extends ChangeNotifier {
  /// Width of the soft part of the edge.
  static const soft = 36.0;

  double x = 0, v = 0, target = 0;
  double lineTop = -1, lineHeight = 0, lineLeft = 0, lineRight = 0;

  /// The finished line's hidden rest: revealed left to right, fast, up to
  /// the line's end (text that arrived with the wrap included).
  double oldX = 0, oldRight = 0, oldTop = -1, oldHeight = 0;
  bool get oldActive => oldTop >= 0 && oldX - soft < oldRight;

  /// A critically damped spring with a 0.22 s response: the edge trails a
  /// steady stream by roughly a word and never overshoots it.
  bool step(double dt) {
    const w = 2 * math.pi / 0.22;
    final a = -w * w * (x - target) - 2 * w * v;
    v += a * dt;
    x += v * dt;
    if (oldActive) {
      // About a tenth of a second to finish the line, never crawling.
      oldX += math.max((oldRight + soft - oldX) * dt * 14, 900 * dt);
    }
    final moving = (x - target).abs() > 0.5 || v.abs() > 5 || oldActive;
    if (!moving) {
      x = target;
      v = 0;
    }
    return moving;
  }

  /// The text moved to a new line starting at [left]: the current line
  /// becomes the one sweeping to its end.
  void newLine(double top, double height, double left, double right) {
    if (lineTop >= 0 && x < lineRight) {
      oldX = x;
      oldRight = lineRight;
      oldTop = lineTop;
      oldHeight = lineHeight;
    }
    lineTop = top;
    lineHeight = height;
    lineLeft = left;
    lineRight = right;
    x = left;
    v = 0;
  }

  void changed() => notifyListeners();
}

class _RevealPainter extends CustomPainter {
  final _RevealEdge edge;
  final GlobalKey content;
  final Color background;
  final Object? revision;
  _RevealPainter({
    required this.edge,
    required this.content,
    required this.background,
    required this.revision,
  }) : super(repaint: edge);

  /// The paragraph holding the end of the text: the last one laid out.
  static RenderParagraph? _lastParagraph(RenderObject root) {
    RenderParagraph? last;
    void visit(RenderObject node) {
      if (node is RenderParagraph) last = node;
      node.visitChildren(visit);
    }

    visit(root);
    return last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final root = content.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.hasSize) return;
    final paragraph = _lastParagraph(root);
    if (paragraph == null || !paragraph.hasSize) return;
    final end = TextPosition(
      offset: paragraph.text.toPlainText(includeSemanticsLabels: false).length,
    );
    final toRoot = paragraph.getTransformTo(root);
    final caret = MatrixUtils.transformPoint(
      toRoot,
      paragraph.getOffsetForCaret(end, Rect.zero),
    );
    final left = MatrixUtils.transformPoint(toRoot, Offset.zero).dx;
    final right = MatrixUtils.transformPoint(
      toRoot,
      Offset(paragraph.size.width, 0),
    ).dx;
    final height = paragraph.getFullHeightForCaret(end);
    if ((caret.dy - edge.lineTop).abs() > 1) {
      // The text wrapped or a new block began: the rest of the old line
      // sweeps in, the new line reveals from its start.
      edge.newLine(caret.dy, height, left, right);
    }
    edge.target = caret.dx;
    _fog(canvas, edge.x, edge.lineLeft, edge.target + 3, caret.dy, height);
    if (edge.oldActive) {
      _fog(
        canvas,
        edge.oldX,
        edge.lineLeft,
        edge.oldRight,
        edge.oldTop,
        edge.oldHeight,
      );
    }
  }

  /// Hides a line from [x] to [right], with a soft edge just left of [x].
  void _fog(
    Canvas canvas,
    double x,
    double left,
    double right,
    double top,
    double height,
  ) {
    if (right <= x + 0.5) return;
    final rect = Rect.fromLTRB(
      math.max(left, x - _RevealEdge.soft),
      top,
      right,
      top + height,
    );
    final solidFrom = ((x - rect.left) / rect.width).clamp(0.0, 1.0);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [background.withValues(alpha: 0), background, background],
          stops: [0, solidFrom, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.revision != revision || old.background != background;
}
