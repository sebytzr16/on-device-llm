import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'mermaid_parser.dart';

class MermaidRoute {
  final List<Offset> points;
  final MermaidEdge edge;
  final Rect label;
  const MermaidRoute(this.points, this.edge, this.label);
}

class MermaidBox {
  final Rect rect;
  final String label;
  final bool note;
  const MermaidBox(this.rect, this.label, {this.note = false});
}

class MermaidLayout {
  final Size size;
  final Map<String, Rect> nodes;
  final List<MermaidRoute> routes;
  final List<MermaidBox> boxes;
  final List<(Offset, Offset)> lifelines;
  const MermaidLayout(
    this.size,
    this.nodes,
    this.routes,
    this.boxes, [
    this.lifelines = const [],
  ]);
}

TextPainter mermaidText(String text, TextStyle style, [double width = 220]) =>
    TextPainter(
      text: TextSpan(
        text: text.replaceAll(RegExp(r'<br\s*/?>'), '\n'),
        style: style,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);

MermaidLayout layoutMermaid(MermaidDiagram diagram, TextStyle style) {
  if (diagram.kind == MermaidKind.sequence) return _sequence(diagram, style);
  if (diagram.kind == MermaidKind.pie) {
    final legendWidth = diagram.slices.fold(
      0.0,
      (width, slice) => math.max(
        width,
        mermaidText('${slice.label}  ${slice.value}', style).width,
      ),
    );
    return MermaidLayout(
      Size(
        math.max(400, 340 + legendWidth),
        math.max(320, 70 + diagram.slices.length * 42.0),
      ),
      {},
      [],
      [],
    );
  }
  return _flow(diagram, style);
}

MermaidLayout _flow(MermaidDiagram d, TextStyle style) {
  final horizontal = d.direction == 'LR' || d.direction == 'RL';
  final reverse = d.direction == 'RL' || d.direction == 'BT';
  final sizes = <String, Size>{};
  for (final n in d.nodes.values) {
    final text = mermaidText(n.label, style, 180);
    var width = math.max(100.0, text.width + 40);
    var height = math.max(54.0, text.height + 30);
    if (n.shape == MermaidShape.diamond) {
      width += 50;
      height += 40;
    }
    if (n.shape == MermaidShape.circle) {
      width = height = math.max(width, height);
    }
    sizes[n.id] = Size(width, height);
  }
  final outgoing = {for (final id in d.nodes.keys) id: <String>[]};
  final incoming = {for (final id in d.nodes.keys) id: <String>[]};
  final visited = <String>{}, active = <String>{};
  final order = <String>[];
  // Remove DFS back edges for ranking; retain all edges in the drawing.
  void visit(String id) {
    if (!visited.add(id)) return;
    active.add(id);
    for (final edge in d.edges.where((e) => e.from == id)) {
      if (active.contains(edge.to)) continue;
      outgoing[id]!.add(edge.to);
      incoming[edge.to]!.add(id);
      visit(edge.to);
    }
    active.remove(id);
    order.add(id);
  }

  for (final id in d.nodes.keys) {
    visit(id);
  }
  final rank = {for (final id in d.nodes.keys) id: 0};
  for (final id in order.reversed) {
    for (final to in outgoing[id]!) {
      rank[to] = math.max(rank[to]!, rank[id]! + 1);
    }
  }
  final layers = List.generate(
    rank.values.reduce(math.max) + 1,
    (_) => <String>[],
  );
  for (final id in d.nodes.keys) {
    layers[rank[id]!].add(id);
  }
  final positions = <String, double>{};
  for (var sweep = 0; sweep < 6; sweep++) {
    for (final layer in layers) {
      for (var i = 0; i < layer.length; i++) {
        positions[layer[i]] = i.toDouble();
      }
    }
    for (final layer in sweep.isEven ? layers : layers.reversed) {
      double barycenter(String id) {
        final neighbours = sweep.isEven ? incoming[id]! : outgoing[id]!;
        return neighbours.isEmpty
            ? positions[id]!
            : neighbours.fold(0.0, (v, n) => v + positions[n]!) /
                  neighbours.length;
      }

      layer.sort((a, b) {
        final result = barycenter(a).compareTo(barycenter(b));
        return result == 0 ? positions[a]!.compareTo(positions[b]!) : result;
      });
    }
  }
  // Each innermost subgraph occupies a lane. Nested frames enclose their lanes.
  int lane(String id) {
    for (var i = d.groups.length - 1; i >= 0; i--) {
      if (d.groups[i].nodes.contains(id)) return i;
    }
    return d.groups.length;
  }

  final laneWidths = List.filled(d.groups.length + 1, 0.0);
  final axisSizes = <double>[];
  for (final layer in layers) {
    axisSizes.add(
      layer.fold(
        0.0,
        (v, id) =>
            math.max(v, horizontal ? sizes[id]!.width : sizes[id]!.height),
      ),
    );
    for (var l = 0; l < laneWidths.length; l++) {
      final members = layer.where((id) => lane(id) == l);
      final width = members.fold(
        0.0,
        (v, id) => v + (horizontal ? sizes[id]!.height : sizes[id]!.width) + 40,
      );
      laneWidths[l] = math.max(laneWidths[l], width == 0 ? 0 : width + 60);
    }
  }
  final crossSize = laneWidths.fold(0.0, (a, b) => a + b) + 40;
  final mainSize = axisSizes.fold(0.0, (a, b) => a + b + 100) + 40;
  final size = horizontal
      ? Size(mainSize, crossSize)
      : Size(crossSize, mainSize);
  final nodes = <String, Rect>{};
  var main = 70.0;
  for (var r = 0; r < layers.length; r++) {
    var laneStart = 20.0;
    for (var l = 0; l < laneWidths.length; l++) {
      final members = layers[r].where((id) => lane(id) == l).toList();
      final used = members.fold(
        0.0,
        (v, id) => v + (horizontal ? sizes[id]!.height : sizes[id]!.width) + 40,
      );
      var cross = laneStart + (laneWidths[l] - used) / 2;
      for (final id in members) {
        final s = sizes[id]!;
        final extent = horizontal ? s.width : s.height;
        final axis = main + (axisSizes[r] - extent) / 2;
        final reflected = reverse ? mainSize - axis - extent : axis;
        nodes[id] = horizontal
            ? Rect.fromLTWH(reflected, cross, s.width, s.height)
            : Rect.fromLTWH(cross, reflected, s.width, s.height);
        cross += (horizontal ? s.height : s.width) + 40;
      }
      laneStart += laneWidths[l];
    }
    main += axisSizes[r] + 100;
  }
  final boxes = <MermaidBox>[];
  for (var i = 0; i < d.groups.length; i++) {
    final group = d.groups[i];
    if (group.nodes.isEmpty) continue;
    var rect = nodes[group.nodes.first]!;
    for (final id in group.nodes.skip(1)) {
      rect = rect.expandToInclude(nodes[id]!);
    }
    final nesting = d.groups
        .skip(i + 1)
        .where((g) => g.nodes.isNotEmpty && g.nodes.every(group.nodes.contains))
        .length;
    final pad = 18.0 + nesting * 8;
    boxes.add(
      MermaidBox(
        Rect.fromLTRB(
          rect.left - pad,
          rect.top - pad - 24,
          rect.right + pad,
          rect.bottom + pad,
        ),
        group.label,
      ),
    );
  }
  final routes = <MermaidRoute>[];
  for (final edge in d.edges) {
    final a = nodes[edge.from]!, b = nodes[edge.to]!;
    List<Offset> points;
    if (edge.from == edge.to) {
      points = [
        a.centerRight,
        a.centerRight + const Offset(30, 0),
        a.topRight + const Offset(30, -25),
        a.topCenter + const Offset(0, -25),
        a.topCenter,
      ];
    } else {
      points = [
        _boundary(a, b.center, d.nodes[edge.from]!.shape),
        _boundary(b, a.center, d.nodes[edge.to]!.shape),
      ];
    }
    final middle = Offset.lerp(points.first, points.last, .5)!;
    final text = mermaidText(edge.label, style, 180);
    routes.add(
      MermaidRoute(
        points,
        edge,
        Rect.fromCenter(
          center: middle,
          width: text.width + 8,
          height: text.height + 4,
        ),
      ),
    );
  }
  return MermaidLayout(size, nodes, routes, boxes);
}

Offset _boundary(Rect rect, Offset toward, MermaidShape shape) {
  final delta = toward - rect.center;
  if (delta.distance == 0) return rect.center;
  final x = delta.dx.abs() / (rect.width / 2),
      y = delta.dy.abs() / (rect.height / 2);
  final scale = switch (shape) {
    MermaidShape.diamond => 1 / (x + y),
    MermaidShape.circle => 1 / math.sqrt(x * x + y * y),
    _ => 1 / math.max(x, y),
  };
  return rect.center + delta * scale;
}

MermaidLayout _sequence(MermaidDiagram d, TextStyle style) {
  final nodes = <String, Rect>{};
  final boxes = <MermaidBox>[];
  final routes = <MermaidRoute>[];
  final lifelines = <(Offset, Offset)>[];
  var x = 260.0;
  for (final node in d.nodes.values) {
    final text = mermaidText(node.label, style, 180);
    nodes[node.id] = Rect.fromCenter(
      center: Offset(x, 50),
      width: math.max(100, text.width + 30),
      height: math.max(54, text.height + (node.actor ? 55 : 24)),
    );
    x += 280;
  }
  var y = 130.0, number = d.numberStart;
  final stack = <(double, String, int)>[];
  for (final event in d.events) {
    final measuredLabel =
        d.autonumber && event.from != null && event.kind != 'note'
        ? '$number. ${event.label}'
        : event.label;
    final text = mermaidText(measuredLabel, style, 200);
    final height = math.max(70.0, text.height + 42);
    if (event.kind == 'start') {
      stack.add((y, event.label, stack.length));
      y += height;
      continue;
    }
    if (event.kind == 'end') {
      final start = stack.removeLast();
      boxes.add(
        MermaidBox(
          Rect.fromLTRB(20 + start.$3 * 8, start.$1, x - 80 - start.$3 * 8, y),
          start.$2,
        ),
      );
      y += 25;
      continue;
    }
    if (event.kind == 'else') {
      boxes.add(MermaidBox(Rect.fromLTWH(28, y, x - 116, height), event.label));
      y += height;
      continue;
    }
    final from = nodes[event.from]!.center.dx;
    final to = nodes[event.to ?? event.from]!.center.dx;
    if (event.kind == 'note') {
      final center = event.position == 'right of'
          ? from + 135
          : event.position == 'left of'
          ? from - 135
          : (from + to) / 2;
      boxes.add(
        MermaidBox(
          Rect.fromCenter(
            center: Offset(center, y + height / 2),
            width: 220,
            height: height - 12,
          ),
          event.label,
          note: true,
        ),
      );
    } else {
      final label = d.autonumber ? '$number. ${event.label}' : event.label;
      number += d.numberStep;
      final points = from == to
          ? [
              Offset(from, y + 28),
              Offset(from + 60, y + 28),
              Offset(from + 60, y + 52),
              Offset(from, y + 52),
            ]
          : [Offset(from, y + height - 12), Offset(to, y + height - 12)];
      routes.add(
        MermaidRoute(
          points,
          MermaidEdge(event.from!, event.to!, event.kind, label, true),
          Rect.fromLTWH(
            math.min(from, to) + (from == to ? 65 : 8),
            y,
            from == to ? 200 : (from - to).abs() - 16,
            text.height + 8,
          ),
        ),
      );
    }
    y += height;
  }
  for (final rect in nodes.values) {
    lifelines.add((rect.bottomCenter, Offset(rect.center.dx, y + 20)));
  }
  return MermaidLayout(Size(x, y + 50), nodes, routes, boxes, lifelines);
}
