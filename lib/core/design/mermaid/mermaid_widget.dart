import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';
import '../app_design.dart';
import 'mermaid_layout.dart';
import 'mermaid_parser.dart';

class MermaidBlock extends StatefulWidget {
  final String source;
  final Widget codeBlock;
  const MermaidBlock({
    super.key,
    required this.source,
    required this.codeBlock,
  });

  @override
  State<MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<MermaidBlock> {
  bool code = false;
  String? parsedSource;
  MermaidDiagram? diagram;
  (String, double, TextStyle, ThemeData)? layoutKey;
  MermaidLayout? cachedLayout;

  @override
  Widget build(BuildContext context) {
    if (parsedSource != widget.source) {
      parsedSource = widget.source;
      diagram = parseMermaid(widget.source);
    }
    if (diagram == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.codeBlock,
          Text(context.l10n.mermaidUnsupported, style: context.text.caption),
        ],
      );
    }
    final c = context.colors;
    final baseStyle = context.text.small.copyWith(color: c.text);
    final fontSize = baseStyle.fontSize ?? 14;
    final style = baseStyle.copyWith(
      fontSize: MediaQuery.textScalerOf(context).scale(fontSize),
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppDesign.sm),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: c.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => code = false),
                child: Text(
                  context.l10n.mermaidDiagram,
                  style: TextStyle(color: code ? c.textMuted : c.accent),
                ),
              ),
              Text('|', style: context.text.caption),
              TextButton(
                onPressed: () => setState(() => code = true),
                child: Text(
                  context.l10n.mermaidCode,
                  style: TextStyle(color: code ? c.accent : c.textMuted),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: context.l10n.mermaidCopySource,
                iconSize: 16,
                icon: const Icon(Icons.copy_outlined),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: widget.source)),
              ),
            ],
          ),
          if (code)
            widget.codeBlock
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final key = (
                  widget.source,
                  constraints.maxWidth,
                  style,
                  Theme.of(context),
                );
                if (layoutKey != key) {
                  cachedLayout = layoutMermaid(diagram!, style);
                  layoutKey = key;
                }
                final layout = cachedLayout!;
                final width = math.min(layout.size.width, constraints.maxWidth);
                final height = math.min(layout.size.height, 520.0);
                return SizedBox(
                  height: height,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(width, layout.size.width),
                      height: height,
                      child: InteractiveViewer(
                        constrained: false,
                        minScale: .25,
                        maxScale: 4,
                        boundaryMargin: const EdgeInsets.all(24),
                        child: Semantics(
                          label: widget.source,
                          image: true,
                          child: CustomPaint(
                            key: const ValueKey('mermaid-diagram'),
                            size: layout.size,
                            painter: MermaidPainter(diagram!, layout, style, c),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class MermaidPainter extends CustomPainter {
  final MermaidDiagram diagram;
  final MermaidLayout layout;
  final TextStyle style;
  final AppColors colors;
  MermaidPainter(this.diagram, this.layout, this.style, this.colors);

  void text(Canvas canvas, String label, Rect rect, {bool center = true}) {
    final painter = mermaidText(label, style, math.max(1, rect.width));
    painter.paint(
      canvas,
      Offset(
        center ? rect.center.dx - painter.width / 2 : rect.left,
        center ? rect.center.dy - painter.height / 2 : rect.top,
      ),
    );
  }

  void line(
    Canvas canvas,
    List<Offset> points,
    Paint paint, {
    bool dashed = false,
  }) {
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (!dashed) {
        canvas.drawLine(a, b, paint);
        continue;
      }
      final length = (b - a).distance;
      if (length == 0) continue;
      for (var p = 0.0; p < length; p += 10) {
        canvas.drawLine(
          Offset.lerp(a, b, p / length)!,
          Offset.lerp(a, b, math.min(p + 5, length) / length)!,
          paint,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = colors.accent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = colors.surface;
    if (diagram.kind == MermaidKind.pie) {
      pie(canvas, size);
      return;
    }
    // Frames precede content, including nested sequence frames.
    for (final box in layout.boxes.where((b) => !b.note)) {
      canvas.drawRect(box.rect, stroke..color = colors.hairlineStrong);
      text(
        canvas,
        box.label,
        Rect.fromLTWH(
          box.rect.left + 8,
          box.rect.top + 4,
          box.rect.width - 16,
          24,
        ),
        center: false,
      );
    }
    for (final lifeline in layout.lifelines) {
      line(
        canvas,
        [lifeline.$1, lifeline.$2],
        stroke..color = colors.textFaint,
        dashed: true,
      );
    }
    for (final route in layout.routes) {
      stroke
        ..color = colors.accent
        ..strokeWidth = route.edge.stroke == '==>' ? 3.5 : 1.5;
      line(canvas, route.points, stroke, dashed: route.edge.dashed);
      final end = route.points.last;
      final delta = end - route.points[route.points.length - 2];
      final angle = math.atan2(delta.dy, delta.dx);
      if (route.edge.stroke == '-x') {
        canvas.drawLine(
          end - const Offset(5, 5),
          end + const Offset(5, 5),
          stroke,
        );
        canvas.drawLine(
          end - const Offset(5, -5),
          end + const Offset(5, -5),
          stroke,
        );
      } else if (route.edge.arrow) {
        final path = Path()..moveTo(end.dx, end.dy);
        final tips = <Offset>[];
        for (final sign in [-1, 1]) {
          final point =
              end -
              Offset(
                    math.cos(angle + sign * .45),
                    math.sin(angle + sign * .45),
                  ) *
                  10;
          tips.add(point);
          path.lineTo(point.dx, point.dy);
          path.moveTo(end.dx, end.dy);
        }
        if (!route.edge.sequence || route.edge.stroke.endsWith('>>')) {
          final head = Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(tips[0].dx, tips[0].dy)
            ..lineTo(tips[1].dx, tips[1].dy)
            ..close();
          canvas.drawPath(head, Paint()..color = colors.accent);
        } else {
          canvas.drawPath(path, stroke);
        }
      }
      if (route.edge.label.isNotEmpty) {
        canvas.drawRect(route.label, fill..color = colors.surfaceRaised);
        text(canvas, route.edge.label, route.label);
      }
    }
    for (final box in layout.boxes.where((b) => b.note)) {
      canvas.drawRect(box.rect, fill..color = colors.accent.fade(.15));
      canvas.drawRect(box.rect, stroke..color = colors.accent);
      text(canvas, box.label, box.rect.deflate(8));
    }
    for (final node in diagram.nodes.values) {
      final r = layout.nodes[node.id]!;
      final path = Path();
      switch (node.shape) {
        case MermaidShape.rect:
          path.addRect(r);
        case MermaidShape.round:
          path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(16)));
        case MermaidShape.circle:
          path.addOval(r);
        case MermaidShape.diamond:
          path
            ..moveTo(r.center.dx, r.top)
            ..lineTo(r.right, r.center.dy)
            ..lineTo(r.center.dx, r.bottom)
            ..lineTo(r.left, r.center.dy)
            ..close();
        case MermaidShape.flag:
          path
            ..moveTo(r.left, r.top)
            ..lineTo(r.right, r.top)
            ..lineTo(r.right, r.bottom)
            ..lineTo(r.left, r.bottom)
            ..lineTo(r.left + 16, r.center.dy)
            ..close();
        case MermaidShape.database:
          path
            ..moveTo(r.left, r.top + 10)
            ..cubicTo(
              r.left,
              r.top - 4,
              r.right,
              r.top - 4,
              r.right,
              r.top + 10,
            )
            ..lineTo(r.right, r.bottom - 10)
            ..cubicTo(
              r.right,
              r.bottom + 4,
              r.left,
              r.bottom + 4,
              r.left,
              r.bottom - 10,
            )
            ..close();
      }
      stroke
        ..color = colors.accent
        ..strokeWidth = 1.5;
      if (node.actor) {
        final head = Offset(r.center.dx, r.top + 10);
        canvas.drawCircle(head, 7, stroke);
        line(canvas, [
          head + const Offset(0, 7),
          head + const Offset(0, 28),
        ], stroke);
        line(canvas, [
          head + const Offset(-14, 17),
          head + const Offset(14, 17),
        ], stroke);
        line(canvas, [
          head + const Offset(-12, 40),
          head + const Offset(0, 28),
          head + const Offset(12, 40),
        ], stroke);
        text(
          canvas,
          node.label,
          Rect.fromLTRB(r.left, r.top + 52, r.right, r.bottom),
        );
        continue;
      }
      canvas.drawPath(path, fill..color = colors.surface);
      canvas.drawPath(path, stroke);
      if (node.shape == MermaidShape.database) {
        canvas.drawOval(Rect.fromLTWH(r.left, r.top, r.width, 20), stroke);
      }
      text(
        canvas,
        node.label,
        r.deflate(node.shape == MermaidShape.diamond ? 30 : 16),
      );
    }
  }

  void pie(Canvas canvas, Size size) {
    final palette = [
      colors.accent,
      colors.info,
      colors.success,
      colors.danger,
      colors.reasoning,
    ];
    text(canvas, diagram.title, Rect.fromLTWH(16, 12, size.width - 32, 32));
    final total = diagram.slices.fold(0.0, (sum, slice) => sum + slice.value);
    var start = -math.pi / 2;
    for (var i = 0; i < diagram.slices.length; i++) {
      final slice = diagram.slices[i];
      final sweep = slice.value / total * math.pi * 2;
      final color = palette[i % palette.length];
      canvas.drawArc(
        const Rect.fromLTWH(24, 64, 240, 240),
        start,
        sweep,
        true,
        Paint()..color = color,
      );
      canvas.drawArc(
        const Rect.fromLTWH(24, 64, 240, 240),
        start,
        sweep,
        true,
        Paint()
          ..color = colors.surfaceRaised
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      start += sweep;
      canvas.drawRect(
        Rect.fromLTWH(292, 72 + i * 42, 14, 14),
        Paint()..color = color,
      );
      final label = diagram.showData
          ? '${slice.label} (${slice.value})'
          : slice.label;
      text(
        canvas,
        label,
        Rect.fromLTWH(318, 66 + i * 42, size.width - 334, 34),
        center: false,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MermaidPainter oldDelegate) =>
      oldDelegate.diagram != diagram ||
      oldDelegate.layout != layout ||
      oldDelegate.style != style ||
      oldDelegate.colors != colors;
}
