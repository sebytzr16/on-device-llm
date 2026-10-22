import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A table column as wide as its text, up to [cap]. A markdown table with
/// intrinsic columns scrolls sideways (flutter_markdown_plus), so its cells
/// wrap between words instead of being squeezed to the screen's width and
/// broken letter by letter (review, 2026-09-28). A word longer than
/// [cap] keeps its own width.
class CappedColumnWidth extends IntrinsicColumnWidth {
  final double cap;
  const CappedColumnWidth(this.cap);

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      math.max(
        minIntrinsicWidth(cells, containerWidth),
        math.min(cap, super.maxIntrinsicWidth(cells, containerWidth)),
      );
}

/// The column width for markdown tables on this screen: a column holds
/// about half the screen before its text wraps.
TableColumnWidth markdownTableColumns(BuildContext context) => FixedColumnWidth(
  math.max(140, math.min(280, MediaQuery.sizeOf(context).width * 0.5)),
);
